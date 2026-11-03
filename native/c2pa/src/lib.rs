use c2pa::{Context, Error, Reader, Settings};
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    io::Cursor,
    io::Read,
    os::raw::c_char,
    panic::catch_unwind,
    slice,
};

// Refuse every HTTP request, including DID resolution, even if another build
// later enables an SDK HTTP feature through Cargo feature unification.
struct OfflineResolver;
impl c2pa::http::SyncHttpResolver for OfflineResolver {
    fn http_resolve(
        &self,
        _: c2pa::http::http::Request<Vec<u8>>,
    ) -> std::result::Result<c2pa::http::http::Response<Box<dyn Read>>, c2pa::http::HttpResolverError>
    {
        Err(c2pa::http::HttpResolverError::SyncHttpResolverNotImplemented)
    }
}

fn result(bytes: &[u8], mime: &str) -> Value {
    let settings = match Settings::new()
        .with_value("verify.verify_after_reading", true)
        .and_then(|s| s.with_value("verify.verify_trust", false))
        .and_then(|s| s.with_value("verify.verify_timestamp_trust", false))
        .and_then(|s| s.with_value("verify.ocsp_fetch", false))
        .and_then(|s| s.with_value("verify.remote_manifest_fetch", false))
    {
        Ok(s) => s,
        Err(e) => return json!({"status":"error", "error":e.to_string()}),
    };
    let context = match Context::new().with_settings(settings) {
        Ok(c) => c.with_resolver(OfflineResolver),
        Err(e) => return json!({"status":"error", "error":e.to_string()}),
    };
    match Reader::from_context(context).with_stream(mime, Cursor::new(bytes)) {
        Ok(reader) => {
            let report: Value = serde_json::from_str(&reader.json()).unwrap_or(Value::Null);
            let validation =
                serde_json::to_value(reader.validation_results()).unwrap_or(Value::Null);
            let active = &validation["activeManifest"];
            let codes = |kind: &str| -> Vec<&str> {
                active[kind]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v["code"].as_str()).collect())
                    .unwrap_or_default()
            };
            let successes = codes("success");
            let failures = codes("failure");
            let signature = if failures
                .iter()
                .any(|c| *c == "claimSignature.mismatch" || *c == "claimSignature.missing")
            {
                "invalid"
            } else if successes.contains(&"claimSignature.validated") {
                "valid"
            } else {
                "unknown"
            };
            let hash_failed = failures.iter().any(|c| {
                c.starts_with("assertion.dataHash.")
                    || c.starts_with("assertion.bmffHash.")
                    || c.starts_with("assertion.boxesHash.")
            });
            let hash_ok = successes.iter().any(|c| {
                *c == "assertion.dataHash.match"
                    || *c == "assertion.bmffHash.match"
                    || *c == "assertion.boxesHash.match"
            });
            let claim_integrity = if failures
                .iter()
                .any(|c| c.starts_with("assertion.hashedURI."))
            {
                "invalid"
            } else if successes.contains(&"assertion.hashedURI.match") {
                "valid"
            } else {
                "unknown"
            };
            let integrity = if hash_failed {
                "invalid"
            } else if hash_ok {
                "valid"
            } else {
                "unknown"
            };
            json!({"status":"present", "signature":signature, "integrity":integrity, "claim_integrity":claim_integrity, "trust":"unknown", "online":false, "trust_list":null, "verified_at_unix":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok().map(|d| d.as_secs()), "library":"c2pa-rs 0.91.7", "validation_state":format!("{:?}",reader.validation_state()), "validation_results":validation, "manifest":report})
        }
        Err(e) => {
            let status = match &e {
                Error::JumbfNotFound => "absent",
                Error::UnsupportedType => "unsupported",
                Error::RemoteManifestUrl(_) | Error::RemoteManifestFetch(_) => "remote",
                _ => "error",
            };
            json!({"status":status, "signature":"unknown", "integrity":"unknown", "trust":"unknown", "online":false, "trust_list":null, "library":"c2pa-rs 0.91.7", "error":e.to_string(), "error_code":format!("{:?}",e)})
        }
    }
}

/// Input pointers must remain valid for the call. The returned string is owned by Rust.
#[no_mangle]
pub unsafe extern "C" fn musha_c2pa_verify(
    bytes: *const u8,
    len: usize,
    mime: *const c_char,
) -> *mut c_char {
    let value = catch_unwind(|| {
        if bytes.is_null() || mime.is_null() || len > isize::MAX as usize {
            return json!({"status":"error", "error":"invalid input"});
        }
        let input = slice::from_raw_parts(bytes, len);
        match CStr::from_ptr(mime).to_str() {
            Ok(m) => result(input, m),
            Err(_) => json!({"status":"error", "error":"invalid UTF-8 format"}),
        }
    })
    .unwrap_or_else(|_| json!({"status":"error", "error":"native verifier panicked"}));
    CString::new(value.to_string())
        .expect("JSON contains no NUL")
        .into_raw()
}

/// Free exactly once the pointer returned by musha_c2pa_verify.
#[no_mangle]
pub unsafe extern "C" fn musha_c2pa_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signed_asset_and_tampering() {
        let signed = include_bytes!("../tests/fixtures/signed.jpg");
        let valid = result(signed, "image/jpeg");
        assert_eq!(valid["status"], "present");
        assert_eq!(valid["signature"], "valid");
        assert_eq!(valid["integrity"], "valid");
        assert_eq!(valid["claim_integrity"], "valid");
        assert_eq!(valid["trust"], "unknown");
        assert_eq!(valid["validation_state"], "Valid");
        let mut tampered = signed.to_vec();
        let position = tampered.len() - 10;
        tampered[position] ^= 1;
        let changed = result(&tampered, "image/jpeg");
        assert_eq!(changed["status"], "present");
        assert_eq!(changed["signature"], "valid");
        assert_eq!(changed["integrity"], "invalid");
        assert!(changed["validation_results"]
            .to_string()
            .contains("assertion.dataHash.mismatch"));
    }
    #[test]
    fn offline_identity_failure_is_preserved() {
        let report = result(
            include_bytes!("../tests/fixtures/cawg-offline.jpg"),
            "image/jpeg",
        );
        assert_eq!(report["validation_state"], "Invalid");
        assert!(report["validation_results"]
            .to_string()
            .contains("cawg.ica.did_unavailable"));
    }
    #[test]
    fn dng_uses_tiff_handler_on_original_bytes() {
        // Minimal little-endian TIFF with an empty first IFD and no manifest.
        let dng = b"II\x2a\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00";
        assert_eq!(result(dng, "image/x-adobe-dng")["status"], "absent");
        assert_eq!(result(b"not a DNG", "image/x-adobe-dng")["status"], "error");
    }
    #[test]
    fn absent_and_bad_inputs_are_distinct() {
        let unsigned = include_bytes!("../tests/fixtures/unsigned.jpg");
        assert_eq!(result(unsigned, "image/jpeg")["status"], "absent");
        assert_eq!(
            result(b"\xff\xd8\xff\xe1\x00\x32garbage", "image/jpeg")["status"],
            "error"
        );
        assert_eq!(
            result(b"not an asset", "application/x-unsupported")["status"],
            "unsupported"
        );
    }
}
