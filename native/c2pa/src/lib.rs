use c2pa::{Context, Error, Reader, Settings};
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    io::Cursor,
    io::Read,
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    os::raw::c_char,
    panic::catch_unwind,
    slice,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
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

// All traffic is HTTPS GET without caller-supplied headers, body, redirects, or proxy.
// Resolve once and pin every connection to the checked addresses to prevent rebinding.
const RESPONSE_LIMIT: u64 = 16 * 1024 * 1024;
const REQUEST_LIMIT: usize = 16;
const TIMEOUT: Duration = Duration::from_secs(10);
const TOTAL_TIMEOUT: Duration = Duration::from_secs(20);
static DNS_WORKERS: AtomicUsize = AtomicUsize::new(0);

struct OnlineState {
    deadline: Instant,
    requests: AtomicUsize,
    hosts: Mutex<Vec<String>>,
    error: Mutex<Option<&'static str>>,
}
impl Default for OnlineState {
    fn default() -> Self {
        Self {
            deadline: Instant::now() + TOTAL_TIMEOUT,
            requests: AtomicUsize::new(0),
            hosts: Mutex::new(Vec::new()),
            error: Mutex::new(None),
        }
    }
}
impl OnlineState {
    fn record_host(&self, host: &str) {
        // URL parsing supplies ASCII DNS names or IP literals. Refuse unsafe display text.
        if host.is_empty()
            || host.len() > 253
            || !host
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b".-:[]".contains(&c))
        {
            return;
        }
        let mut hosts = self.hosts.lock().unwrap_or_else(|e| e.into_inner());
        if hosts.len() < REQUEST_LIMIT && !hosts.iter().any(|item| item == host) {
            hosts.push(host.to_owned());
        }
    }
    fn remaining(&self) -> std::result::Result<Duration, c2pa::http::HttpResolverError> {
        let remaining = self.deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            Err(self.fail("network deadline exceeded"))
        } else {
            Ok(remaining.min(TIMEOUT))
        }
    }
    fn fail(&self, reason: &'static str) -> c2pa::http::HttpResolverError {
        *self.error.lock().unwrap_or_else(|e| e.into_inner()) = Some(reason);
        c2pa::http::HttpResolverError::Io(std::io::Error::other(reason))
    }
}
fn public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => {
            let [a, b, c, _] = v.octets();
            !(a == 0
                || a == 10
                || a == 127
                || a >= 224
                || (a == 100 && (64..=127).contains(&b))
                || (a == 169 && b == 254)
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192 && (b == 168 || b == 0 || (b == 88 && c == 99)))
                || (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)))
                || (a == 203 && b == 0 && c == 113))
        }
        IpAddr::V6(v) => {
            // Only global unicast; mapped and special IPv6 ranges are rejected.
            let s = v.segments();
            (s[0] & 0xe000) == 0x2000
                && s[0] != 0x2002
                && s[0] != 0x3fff
                && !(s[0] == 0x2001 && (s[1] == 0xdb8 || s[1] < 0x200))
        }
    }
}
struct OnlineResolver(Arc<OnlineState>);
impl c2pa::http::SyncHttpResolver for OnlineResolver {
    fn http_resolve(
        &self,
        request: c2pa::http::http::Request<Vec<u8>>,
    ) -> std::result::Result<c2pa::http::http::Response<Box<dyn Read>>, c2pa::http::HttpResolverError>
    {
        use c2pa::http::http::{Method, Response};
        let state = &self.0;
        if state.requests.fetch_add(1, Ordering::Relaxed) >= REQUEST_LIMIT {
            return Err(state.fail("request limit exceeded"));
        }
        if request.method() != Method::GET || !request.body().is_empty() {
            return Err(state.fail("request rejected"));
        }
        let url = reqwest::Url::parse(&request.uri().to_string())
            .map_err(|_| state.fail("request rejected"))?;
        if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() {
            return Err(state.fail("request rejected"));
        }
        let host = url
            .host_str()
            .ok_or_else(|| state.fail("request rejected"))?
            .to_owned();
        state.record_host(&host);
        let port = url
            .port_or_known_default()
            .ok_or_else(|| state.fail("request rejected"))?;
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        let lookup_host = host.clone();
        let timeout = state.remaining()?;
        // fetch_update supports the minimum Rust 1.96 toolchain.
        #[allow(deprecated)]
        if DNS_WORKERS
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| {
                if n < 4 {
                    Some(n + 1)
                } else {
                    None
                }
            })
            .is_err()
        {
            return Err(state.fail("DNS lookup unavailable"));
        }
        if std::thread::Builder::new()
            .spawn(move || {
                struct Guard;
                impl Drop for Guard {
                    fn drop(&mut self) {
                        DNS_WORKERS.fetch_sub(1, Ordering::SeqCst);
                    }
                }
                let _guard = Guard;
                let _ = tx.send(
                    (lookup_host.as_str(), port)
                        .to_socket_addrs()
                        .map(|a| a.collect::<Vec<SocketAddr>>()),
                );
            })
            .is_err()
        {
            DNS_WORKERS.fetch_sub(1, Ordering::SeqCst);
            return Err(state.fail("DNS lookup unavailable"));
        }
        let addresses = rx
            .recv_timeout(timeout)
            .map_err(|_| state.fail("DNS lookup failed or timed out"))?
            .map_err(|_| state.fail("DNS lookup failed or timed out"))?;
        if addresses.is_empty() || addresses.iter().any(|a| !public_ip(a.ip())) {
            return Err(state.fail("network address rejected"));
        }
        let timeout = state.remaining()?;
        let client = reqwest::blocking::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(timeout)
            .connect_timeout(timeout)
            .resolve_to_addrs(&host, &addresses)
            .build()
            .map_err(|_| state.fail("network setup failed"))?;
        let mut response = client
            .get(url)
            .send()
            .map_err(|_| state.fail("network request failed or timed out"))?;
        if response.status().is_redirection() {
            return Err(state.fail("redirect rejected"));
        }
        if !response.status().is_success() {
            return Err(state.fail("remote server returned an error"));
        }
        if response
            .content_length()
            .is_some_and(|n| n > RESPONSE_LIMIT)
        {
            return Err(state.fail("response too large"));
        }
        let status = response.status().as_u16();
        let mut body = Vec::new();
        response
            .by_ref()
            .take(RESPONSE_LIMIT + 1)
            .read_to_end(&mut body)
            .map_err(|_| state.fail("network response failed or timed out"))?;
        if body.len() as u64 > RESPONSE_LIMIT {
            return Err(state.fail("response too large"));
        }
        Ok(Response::builder()
            .status(status)
            .body(Box::new(Cursor::new(body)) as Box<dyn Read>)?)
    }
}

#[cfg(test)]
fn result(bytes: &[u8], mime: &str) -> Value {
    verify(bytes, mime, false)
}

fn verify(bytes: &[u8], mime: &str, online: bool) -> Value {
    verify_with_resolver(bytes, mime, online, Arc::new(OnlineState::default()), None)
}

fn verify_with_resolver(
    bytes: &[u8],
    mime: &str,
    online: bool,
    online_state: Arc<OnlineState>,
    resolver: Option<Arc<dyn c2pa::http::SyncHttpResolver>>,
) -> Value {
    let settings = match Settings::new()
        .with_value("verify.verify_after_reading", true)
        .and_then(|s| s.with_value("verify.verify_trust", false))
        .and_then(|s| s.with_value("verify.verify_timestamp_trust", false))
        .and_then(|s| s.with_value("verify.ocsp_fetch", online))
        .and_then(|s| s.with_value("verify.remote_manifest_fetch", online))
    {
        Ok(s) => s,
        Err(e) => return json!({"status":"error", "error":e.to_string()}),
    };
    let context = match Context::new().with_settings(settings) {
        Ok(c) => {
            if online {
                c.with_resolver(
                    resolver.unwrap_or_else(|| Arc::new(OnlineResolver(online_state.clone()))),
                )
            } else {
                c.with_resolver(OfflineResolver)
            }
        }
        Err(e) => return json!({"status":"error", "error":e.to_string()}),
    };
    let mut value = match Reader::from_context(context).with_stream(mime, Cursor::new(bytes)) {
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
            json!({"status":"present", "signature":signature, "integrity":integrity, "claim_integrity":claim_integrity, "trust":"unknown", "online":online, "trust_list":null, "verified_at_unix":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok().map(|d| d.as_secs()), "library":"c2pa-rs 0.91.7", "validation_state":format!("{:?}",reader.validation_state()), "validation_results":validation, "manifest":report})
        }
        Err(e) => {
            let status = match &e {
                Error::JumbfNotFound => "absent",
                Error::UnsupportedType => "unsupported",
                Error::RemoteManifestUrl(_) | Error::RemoteManifestFetch(_) => "remote",
                _ => "error",
            };
            json!({"status":status, "signature":"unknown", "integrity":"unknown", "trust":"unknown", "online":online, "trust_list":null, "library":"c2pa-rs 0.91.7", "error":e.to_string(), "error_code":format!("{:?}",e)})
        }
    };
    if online {
        let error = *online_state.error.lock().unwrap_or_else(|e| e.into_inner());
        let status_failure = value["status"] == "remote" || value["status"] == "error";
        let validation_text = value["validation_results"].to_string();
        let validation_unavailable = validation_text
            .contains("signingCredential.ocsp.inaccessible")
            || validation_text.contains("did_unavailable")
            || validation_text.contains("fetch_error")
            || validation_text.contains("fetchFailed");
        let attempted = online_state.requests.load(Ordering::Relaxed) > 0;
        value["online_complete"] =
            json!(attempted && error.is_none() && !status_failure && !validation_unavailable);
        value["online_error"] = json!(error.or(if status_failure || validation_unavailable {
            Some("online verification incomplete")
        } else if !attempted {
            Some("No network lookup was requested; revocation and trust are unconfirmed")
        } else {
            None
        }));
        value["online_requests_attempted"] = json!(attempted);
        value["online_request_count"] = json!(online_state.requests.load(Ordering::Relaxed));
        value["online_hosts"] =
            json!(*online_state.hosts.lock().unwrap_or_else(|e| e.into_inner()));
        // SDK errors may include the remote URL. Do not return it to the UI.
        if value["status"] == "remote" {
            value["error"] = json!("Online verification could not retrieve a remote resource");
            value["error_code"] = json!("RemoteManifestFetch");
        } else if value["status"] == "error" {
            value["error"] = json!("The asset could not be verified");
            // SDK Debug errors can contain URLs; retain the variant name only.
            if let Some(code) = value["error_code"].as_str() {
                value["error_code"] = json!(code.split(['(', ' ']).next().unwrap_or("Error"));
            }
        }
    }
    value
}

/// Input pointers must remain valid for the call. The returned string is owned by Rust.
#[no_mangle]
pub unsafe extern "C" fn musha_c2pa_verify(
    bytes: *const u8,
    len: usize,
    mime: *const c_char,
) -> *mut c_char {
    verify_ffi(bytes, len, mime, false)
}

/// Explicit opt-in online verification. Input pointers must remain valid for the call.
#[no_mangle]
pub unsafe extern "C" fn musha_c2pa_verify_online(
    bytes: *const u8,
    len: usize,
    mime: *const c_char,
) -> *mut c_char {
    verify_ffi(bytes, len, mime, true)
}

unsafe fn verify_ffi(
    bytes: *const u8,
    len: usize,
    mime: *const c_char,
    online: bool,
) -> *mut c_char {
    let value = catch_unwind(|| {
        if bytes.is_null() || mime.is_null() || len > isize::MAX as usize {
            return json!({"status":"error", "error":"invalid input"});
        }
        let input = slice::from_raw_parts(bytes, len);
        match CStr::from_ptr(mime).to_str() {
            Ok(m) => verify(input, m, online),
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
    enum MockResult {
        Success(Vec<u8>),
        Timeout,
        Rejected,
    }
    struct MockResolver {
        state: Arc<OnlineState>,
        result: MockResult,
    }
    impl c2pa::http::SyncHttpResolver for MockResolver {
        fn http_resolve(
            &self,
            request: c2pa::http::http::Request<Vec<u8>>,
        ) -> std::result::Result<
            c2pa::http::http::Response<Box<dyn Read>>,
            c2pa::http::HttpResolverError,
        > {
            self.state.requests.fetch_add(1, Ordering::Relaxed);
            assert_eq!(request.method(), "GET");
            assert!(request.body().is_empty());
            let url = reqwest::Url::parse(&request.uri().to_string()).unwrap();
            self.state.record_host(url.host_str().unwrap());
            match &self.result {
                MockResult::Success(bytes) => Ok(c2pa::http::http::Response::builder()
                    .status(200)
                    .body(Box::new(Cursor::new(bytes.clone())) as Box<dyn Read>)
                    .unwrap()),
                MockResult::Timeout => Err(self.state.fail("network request failed or timed out")),
                MockResult::Rejected => Err(self.state.fail("network address rejected")),
            }
        }
    }
    fn remote_jpeg() -> Vec<u8> {
        let jpeg = include_bytes!("../tests/fixtures/unsigned.jpg");
        let xmp = br#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dcterms="http://purl.org/dc/terms/" dcterms:provenance="https://example.com/manifest.c2pa?secret=hidden"/></rdf:RDF></x:xmpmeta>"#;
        let mut payload = b"http://ns.adobe.com/xap/1.0/\0".to_vec();
        payload.extend_from_slice(xmp);
        let mut output = jpeg[..2].to_vec();
        output.extend_from_slice(&[0xff, 0xe1]);
        output.extend_from_slice(&((payload.len() + 2) as u16).to_be_bytes());
        output.extend_from_slice(&payload);
        output.extend_from_slice(&jpeg[2..]);
        output
    }
    #[test]
    fn remote_manifest_fetch_uses_injected_resolver_and_offline_never_calls_it() {
        let manifest = c2pa::jumbf_io::load_jumbf_from_memory(
            "image/jpeg",
            include_bytes!("../tests/fixtures/signed.jpg"),
        )
        .unwrap();
        let asset = remote_jpeg();
        let state = Arc::new(OnlineState::default());
        let mock = Arc::new(MockResolver {
            state: state.clone(),
            result: MockResult::Success(manifest),
        });
        let online = verify_with_resolver(
            &asset,
            "image/jpeg",
            true,
            state.clone(),
            Some(mock.clone()),
        );
        assert_eq!(online["status"], "present", "{online}");
        assert_eq!(online["signature"], "valid", "{online}");
        assert_eq!(online["online_requests_attempted"], true);
        assert_eq!(online["online_request_count"], 1);
        assert_eq!(online["online_hosts"], json!(["example.com"]));
        assert!(!online["online_hosts"].to_string().contains("secret"));
        // The fixture has no OCSP response; remote retrieval succeeds but verification remains incomplete.
        assert_eq!(online["online_complete"], false, "{online}");
        assert!(online["validation_results"]
            .to_string()
            .contains("signingCredential.ocsp.inaccessible"));
        assert!(state.requests.load(Ordering::Relaxed) > 0);
        let offline_state = Arc::new(OnlineState::default());
        let offline_mock = Arc::new(MockResolver {
            state: offline_state.clone(),
            result: MockResult::Timeout,
        });
        let offline = verify_with_resolver(
            &asset,
            "image/jpeg",
            false,
            offline_state.clone(),
            Some(offline_mock),
        );
        assert_eq!(offline["status"], "remote", "{offline}");
        assert_eq!(offline_state.requests.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn online_no_lookup_and_malformed_asset_are_distinct() {
        let state = Arc::new(OnlineState::default());
        let mock = Arc::new(MockResolver {
            state: state.clone(),
            result: MockResult::Timeout,
        });
        let unsigned = include_bytes!("../tests/fixtures/unsigned.jpg");
        let report = verify_with_resolver(
            unsigned,
            "image/jpeg",
            true,
            state.clone(),
            Some(mock.clone()),
        );
        assert_eq!(report["status"], "absent");
        assert_eq!(report["online_complete"], false);
        assert_eq!(report["online_request_count"], 0);
        assert_eq!(report["online_hosts"], json!([]));
        assert_eq!(
            report["online_error"],
            "No network lookup was requested; revocation and trust are unconfirmed"
        );
        assert_eq!(state.requests.load(Ordering::Relaxed), 0);
        let malformed = verify_with_resolver(
            b"\xff\xd8\xff\xe1\x00\x32garbage",
            "image/jpeg",
            true,
            state,
            Some(mock),
        );
        assert_eq!(malformed["status"], "error");
        assert_ne!(malformed["error_code"], "RemoteManifestFetch");
        assert_eq!(malformed["error"], "The asset could not be verified");
    }
    #[test]
    fn remote_manifest_failures_remain_incomplete() {
        let asset = remote_jpeg();
        for (mock_result, expected) in [
            (MockResult::Timeout, "network request failed or timed out"),
            (MockResult::Rejected, "network address rejected"),
        ] {
            let state = Arc::new(OnlineState::default());
            let mock = Arc::new(MockResolver {
                state: state.clone(),
                result: mock_result,
            });
            let report = verify_with_resolver(&asset, "image/jpeg", true, state, Some(mock));
            assert_eq!(report["status"], "remote", "{report}");
            assert_eq!(report["online_complete"], false);
            assert_eq!(report["online_error"], expected);
            assert!(!report.to_string().contains("secret"));
            assert_eq!(report["online_hosts"], json!(["example.com"]));
        }
    }
    #[test]
    fn rejects_non_public_addresses_and_unsafe_requests() {
        use c2pa::http::SyncHttpResolver;
        for address in [
            "127.0.0.1",
            "10.1.2.3",
            "169.254.169.254",
            "100.64.0.1",
            "192.0.2.1",
            "198.51.100.1",
            "203.0.113.1",
            "::1",
            "::ffff:127.0.0.1",
            "64:ff9b::a00:1",
            "2001:db8::1",
            "2002:7f00:1::1",
            "fc00::1",
            "fe80::1",
        ] {
            assert!(!public_ip(address.parse().unwrap()), "{address}");
        }
        assert!(public_ip("8.8.8.8".parse().unwrap()));
        assert!(public_ip("2606:4700:4700::1111".parse().unwrap()));
        let state = Arc::new(OnlineState::default());
        let resolver = OnlineResolver(state.clone());
        for request in [
            c2pa::http::http::Request::post("https://example.com/")
                .body(vec![1])
                .unwrap(),
            c2pa::http::http::Request::get("http://example.com/")
                .body(Vec::new())
                .unwrap(),
            c2pa::http::http::Request::get("https://example.com/")
                .body(vec![1])
                .unwrap(),
        ] {
            assert!(resolver.http_resolve(request).is_err());
        }
        assert_eq!(*state.error.lock().unwrap(), Some("request rejected"));
    }
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
        assert_eq!(result(dng, "image/x-nikon-nef")["status"], "absent");
        assert_eq!(result(b"not a NEF", "image/x-nikon-nef")["status"], "error");
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
