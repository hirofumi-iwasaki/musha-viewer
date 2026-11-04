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
        atomic::{AtomicBool, AtomicUsize, Ordering},
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

// HTTPS GET is permitted generally; a strictly classified Leica OCSP GET may use HTTP.
// Resolve once and pin every connection to the checked addresses to prevent rebinding.
const RESPONSE_LIMIT: u64 = 16 * 1024 * 1024;
const OCSP_RESPONSE_LIMIT: u64 = 1024 * 1024;
const REQUEST_LIMIT: usize = 16;
const TIMEOUT: Duration = Duration::from_secs(10);
const TOTAL_TIMEOUT: Duration = Duration::from_secs(20);
static DNS_WORKERS: AtomicUsize = AtomicUsize::new(0);

struct OnlineState {
    deadline: Instant,
    requests: AtomicUsize,
    hosts: Mutex<Vec<String>>,
    error: Mutex<Option<&'static str>>,
    ocsp_attempted: AtomicBool,
    issuer_ocsp_attempts: AtomicUsize,
    leaf_ocsp_response: AtomicBool,
}
impl Default for OnlineState {
    fn default() -> Self {
        Self {
            deadline: Instant::now() + TOTAL_TIMEOUT,
            requests: AtomicUsize::new(0),
            hosts: Mutex::new(Vec::new()),
            error: Mutex::new(None),
            ocsp_attempted: AtomicBool::new(false),
            issuer_ocsp_attempts: AtomicUsize::new(0),
            leaf_ocsp_response: AtomicBool::new(false),
        }
    }
}
fn is_leica_ocsp_request(url: &reqwest::Url) -> bool {
    use base64::{engine::general_purpose::STANDARD, Engine};
    if url.scheme() != "http"
        || url.host_str() != Some("ocsp.leica.systems")
        || url.port_or_known_default() != Some(80)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return false;
    }
    let Some(encoded) = url.path().strip_prefix('/') else {
        return false;
    };
    if encoded.is_empty() || encoded.len() > 2048 {
        return false;
    }
    let Ok(der) = STANDARD.decode(encoded) else {
        return false;
    };
    if STANDARD.encode(&der) != encoded {
        return false;
    }
    let Ok(request) = rasn::der::decode::<rasn_ocsp::OcspRequest>(&der) else {
        return false;
    };
    if rasn::der::encode(&request).ok().as_deref() != Some(der.as_slice())
        || request.optional_signature.is_some()
        || request.tbs_request.version != 0u8.into()
        || request.tbs_request.requestor_name.is_some()
        || request.tbs_request.request_extensions.is_some()
        || request.tbs_request.request_list.len() != 1
    {
        return false;
    }
    let entry = &request.tbs_request.request_list[0];
    let id = &entry.req_cert;
    let serial = match rasn::der::encode(&id.serial_number) {
        Ok(s) => s,
        Err(_) => return false,
    };
    entry.single_request_extensions.is_none()
        && id.hash_algorithm.algorithm.to_string() == "1.3.14.3.2.26"
        && id
            .hash_algorithm
            .parameters
            .as_ref()
            .is_some_and(|p| p.as_bytes() == [0x05, 0x00])
        && id.issuer_name_hash.len() == 20
        && id.issuer_key_hash.len() == 20
        && serial.len() >= 3
        && serial[0] == 2
        && serial[1] > 0
        && serial[1] <= 21
        && serial[2] & 0x80 == 0
        && serial[2..].iter().any(|byte| *byte != 0)
        && (serial[1] <= 20 || (serial[2] == 0 && serial[3] & 0x80 != 0))
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
fn live_ocsp_status(validation: &Value) -> Option<&'static str> {
    let codes = ["success", "informational", "failure"]
        .iter()
        .filter_map(|kind| validation["activeManifest"][*kind].as_array())
        .flatten()
        .filter_map(|item| item["code"].as_str())
        .collect::<Vec<_>>();
    if codes.contains(&"org.musha.liveOcsp.revoked") {
        Some("revoked")
    } else if codes.contains(&"org.musha.liveOcsp.good") {
        Some("good")
    } else {
        None
    }
}
fn accepted_issuer_count(validation: &Value) -> usize {
    ["success", "informational", "failure"]
        .iter()
        .filter_map(|kind| validation["activeManifest"][*kind].as_array())
        .flatten()
        .filter(|item| item["code"].as_str() == Some("org.musha.liveOcsp.issuerGood"))
        .count()
}
fn issuer_checks_complete(validation: &Value, issuer_attempts: usize) -> bool {
    let incomplete = ["success", "informational", "failure"]
        .iter()
        .filter_map(|kind| validation["activeManifest"][*kind].as_array())
        .flatten()
        .any(|item| item["code"].as_str() == Some("org.musha.liveOcsp.issuerIncomplete"));
    !incomplete && accepted_issuer_count(validation) == issuer_attempts
}
impl c2pa::http::SyncHttpResolver for OnlineResolver {
    fn http_resolve(
        &self,
        request: c2pa::http::http::Request<Vec<u8>>,
    ) -> std::result::Result<c2pa::http::http::Response<Box<dyn Read>>, c2pa::http::HttpResolverError>
    {
        use c2pa::http::http::{Method, Response};
        let state = &self.0;
        let ocsp_kind = request
            .headers()
            .get("x-musha-ocsp")
            .and_then(|h| h.to_str().ok());
        let ocsp_request = matches!(ocsp_kind, Some("leaf" | "issuer"));
        if ocsp_request {
            state.ocsp_attempted.store(true, Ordering::Relaxed);
        }
        if ocsp_kind == Some("issuer") {
            state.issuer_ocsp_attempts.fetch_add(1, Ordering::Relaxed);
        }
        if state.requests.fetch_add(1, Ordering::Relaxed) >= REQUEST_LIMIT {
            return Err(state.fail("request limit exceeded"));
        }
        if request.method() != Method::GET {
            return Err(state.fail("request method rejected"));
        }
        if !request.body().is_empty() {
            return Err(state.fail("request body rejected"));
        }
        let url = reqwest::Url::parse(&request.uri().to_string())
            .map_err(|_| state.fail("invalid request URL"))?;
        if let Some(host) = url.host_str() {
            state.record_host(host);
        }
        let leica_ocsp = url.scheme() == "http" && url.host_str() == Some("ocsp.leica.systems");
        if url.scheme() == "http" && (!ocsp_request || !is_leica_ocsp_request(&url)) {
            return Err(state.fail("HTTP request rejected"));
        }
        if url.scheme() != "https" && !leica_ocsp {
            return Err(state.fail("request scheme rejected"));
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err(state.fail("request URL credentials rejected"));
        }
        let host = url
            .host_str()
            .ok_or_else(|| state.fail("request host missing"))?
            .to_owned();
        let port = url
            .port_or_known_default()
            .ok_or_else(|| state.fail("request port missing"))?;
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
        if leica_ocsp && response.status().as_u16() != 200 {
            return Err(state.fail("OCSP server returned an unexpected status"));
        }
        if leica_ocsp
            && !response
                .headers()
                .get(reqwest::header::CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .is_some_and(|value| {
                    value
                        .split(';')
                        .next()
                        .unwrap_or("")
                        .trim()
                        .eq_ignore_ascii_case("application/ocsp-response")
                })
        {
            return Err(state.fail("OCSP server returned an unexpected content type"));
        }
        let response_limit = if leica_ocsp {
            OCSP_RESPONSE_LIMIT
        } else {
            RESPONSE_LIMIT
        };
        if response
            .content_length()
            .is_some_and(|n| n > response_limit)
        {
            return Err(state.fail("response too large"));
        }
        let status = response.status().as_u16();
        let mut body = Vec::new();
        response
            .by_ref()
            .take(response_limit + 1)
            .read_to_end(&mut body)
            .map_err(|_| state.fail("network response failed or timed out"))?;
        if body.len() as u64 > response_limit {
            return Err(state.fail("response too large"));
        }
        if ocsp_kind == Some("leaf") {
            state.leaf_ocsp_response.store(true, Ordering::Relaxed);
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
        .with_value("trust.anchors", json!([{ "trust_anchors": include_str!("../trust/leica-c2pa-root.pem"), "trust_kind": "manifest", "trust_uri": "https://certs.leica.systems/cgi-bin/Leica_C2PA_Root_CA.crt" }]))
        .and_then(|s| s.with_value("verify.verify_after_reading", true))
        .and_then(|s| s.with_value("verify.verify_trust", false))
        .and_then(|s| s.with_value("verify.verify_timestamp_trust", false))
        .and_then(|s| s.with_value("verify.ocsp_fetch", online))
        .and_then(|s| s.with_value("verify.ocsp_fetch_should_override", online))
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
            json!({"status":"present", "signature":signature, "integrity":integrity, "claim_integrity":claim_integrity, "trust":"unknown", "online":online, "trust_list":null, "verified_at_unix":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok().map(|d| d.as_secs()), "library":"c2pa-rs 0.91.10", "validation_state":format!("{:?}",reader.validation_state()), "validation_results":validation, "manifest":report})
        }
        Err(e) => {
            let status = match &e {
                Error::JumbfNotFound => "absent",
                Error::UnsupportedType => "unsupported",
                Error::RemoteManifestUrl(_) | Error::RemoteManifestFetch(_) => "remote",
                _ => "error",
            };
            json!({"status":status, "signature":"unknown", "integrity":"unknown", "trust":"unknown", "online":online, "trust_list":null, "library":"c2pa-rs 0.91.10", "error":e.to_string(), "error_code":format!("{:?}",e)})
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
        let ocsp_attempted = online_state.ocsp_attempted.load(Ordering::Relaxed);
        let ocsp_status = if online_state.leaf_ocsp_response.load(Ordering::Relaxed) {
            live_ocsp_status(&value["validation_results"])
        } else {
            None
        };
        let ocsp_accepted = ocsp_attempted && ocsp_status.is_some();
        let issuer_attempts = online_state.issuer_ocsp_attempts.load(Ordering::Relaxed);
        let issuer_checks_complete =
            issuer_checks_complete(&value["validation_results"], issuer_attempts);
        value["online_complete"] = json!(
            attempted
                && error.is_none()
                && !status_failure
                && !validation_unavailable
                && ocsp_accepted
                && issuer_checks_complete
        );
        value["online_ocsp_attempted"] = json!(ocsp_attempted);
        value["online_ocsp_status"] = if ocsp_attempted {
            json!(ocsp_status.unwrap_or("unknown"))
        } else {
            Value::Null
        };
        value["online_error"] = json!(error.or(if !attempted && !status_failure {
            Some("No network lookup was requested; revocation and trust are unconfirmed")
        } else if status_failure
            || validation_unavailable
            || !ocsp_accepted
            || !issuer_checks_complete
        {
            Some("online verification incomplete")
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
    use base64::{engine::general_purpose::STANDARD, Engine};

    fn request_der(name_hash: u8) -> Vec<u8> {
        fn seq(bytes: &[u8]) -> Vec<u8> {
            let mut result = vec![0x30, bytes.len() as u8];
            result.extend_from_slice(bytes);
            result
        }
        let mut id = vec![0x30, 9, 6, 5, 0x2b, 0x0e, 3, 2, 0x1a, 5, 0, 4, 20];
        id.extend_from_slice(&[name_hash; 20]);
        id.extend_from_slice(&[4, 20]);
        id.extend_from_slice(&[0xff; 20]);
        id.extend_from_slice(&[2, 1, 42]);
        seq(&seq(&seq(&seq(&seq(&id)))))
    }

    #[test]
    fn leica_http_is_limited_to_canonical_single_cert_requests() {
        let valid = STANDARD.encode(request_der(0xab));
        let parse = |s: &str| reqwest::Url::parse(s).unwrap();
        assert!(valid.contains('/'));
        assert!(is_leica_ocsp_request(&parse(&format!(
            "http://ocsp.leica.systems/{valid}"
        ))));
        let state = Arc::new(OnlineState::default());
        let resolver = OnlineResolver(state.clone());
        use c2pa::http::SyncHttpResolver;
        let unmarked = c2pa::http::http::Request::get(format!("http://ocsp.leica.systems/{valid}"))
            .body(Vec::new())
            .unwrap();
        assert!(resolver.http_resolve(unmarked).is_err());
        assert_eq!(*state.error.lock().unwrap(), Some("HTTP request rejected"));
        // Intermediate issuers can have different hashes; all hashes are exactly 20 bytes.
        let other_issuer = STANDARD.encode(request_der(0x12));
        assert!(is_leica_ocsp_request(&parse(&format!(
            "http://ocsp.leica.systems/{other_issuer}"
        ))));
        for url in [
            format!("http://example.com/{valid}"),
            format!("http://ocsp.leica.systems.evil.example/{valid}"),
            format!("http://ocsp.leica.systems:81/{valid}"),
            format!("http://user@ocsp.leica.systems/{valid}"),
            format!("http://ocsp.leica.systems/{valid}?secret=hidden"),
            format!("http://ocsp.leica.systems/{valid}#fragment"),
            format!("http://ocsp.leica.systems/{valid}/extra"),
            format!("http://ocsp.leica.systems/{}", valid.trim_end_matches('=')),
        ] {
            assert!(!is_leica_ocsp_request(&parse(&url)), "{url}");
        }
        let mut malformed = request_der(1);
        malformed.push(0);
        assert!(!is_leica_ocsp_request(&parse(&format!(
            "http://ocsp.leica.systems/{}",
            STANDARD.encode(malformed)
        ))));
        assert!(!is_leica_ocsp_request(&parse(&format!(
            "http://ocsp.leica.systems/{}",
            "A".repeat(2049)
        ))));
        let mut zero_serial = request_der(1);
        *zero_serial.last_mut().unwrap() = 0;
        assert!(!is_leica_ocsp_request(&parse(&format!(
            "http://ocsp.leica.systems/{}",
            STANDARD.encode(zero_serial)
        ))));
    }

    #[test]
    fn stapled_status_alone_never_proves_live_response_accepted() {
        let fallback =
            json!({"activeManifest": {"success": [{"code": "signingCredential.ocsp.notRevoked"}]}});
        assert_eq!(live_ocsp_status(&fallback), None);
        assert_eq!(accepted_issuer_count(&fallback), 0);
        let two_issuers = json!({"activeManifest":{"informational":[{"code":"org.musha.liveOcsp.issuerGood"}, {"code":"org.musha.liveOcsp.issuerGood"}]}});
        assert_eq!(accepted_issuer_count(&two_issuers), 2);
        assert_ne!(accepted_issuer_count(&two_issuers), 3);
        assert!(issuer_checks_complete(&two_issuers, 2));
        assert!(!issuer_checks_complete(&two_issuers, 3));
        let missing_issuer = json!({"activeManifest":{"informational":[{"code":"org.musha.liveOcsp.good"}, {"code":"org.musha.liveOcsp.issuerIncomplete"}]}});
        assert_eq!(live_ocsp_status(&missing_issuer), Some("good"));
        assert!(!issuer_checks_complete(&missing_issuer, 0));
        assert_eq!(
            live_ocsp_status(
                &json!({"activeManifest":{"informational":[{"code":"different", "explanation":"org.musha.liveOcsp.good"}]}})
            ),
            None
        );
        assert_eq!(
            live_ocsp_status(
                &json!({"activeManifest":{"informational":[{"code":"org.musha.liveOcsp.good"}]}})
            ),
            Some("good")
        );
        assert_eq!(
            live_ocsp_status(
                &json!({"activeManifest":{"informational":[{"code":"org.musha.liveOcsp.revoked"}]}})
            ),
            Some("revoked")
        );
    }
    #[test]
    fn fetched_ocsp_requires_fresh_unique_status_and_direct_issuer() {
        let der = include_bytes!("../tests/fixtures/leica-root-ocsp.der");
        let root = include_bytes!("../tests/fixtures/leica-root.der").to_vec();
        let chain = vec![root.clone(), root.clone()];
        let mut outer: rasn_ocsp::OcspResponse = rasn::der::decode(der).unwrap();
        let response = outer.bytes.as_mut().unwrap();
        let basic: rasn_ocsp::BasicOcspResponse = rasn::der::decode(&response.response).unwrap();
        let now = basic.tbs_response_data.produced_at.to_utc().timestamp();
        assert!(c2pa::musha_ocsp_tests::fresh_at(der, &chain, now));
        assert_eq!(
            c2pa::musha_ocsp_tests::verify_fetched(
                der,
                &chain,
                include_bytes!("../trust/leica-c2pa-root.pem"),
                now
            ),
            (true, true)
        );
        assert_eq!(
            c2pa::musha_ocsp_tests::verify_fetched(
                der,
                &chain,
                include_bytes!("../trust/leica-c2pa-root.pem"),
                now + 3601
            ),
            (false, false)
        );
        assert!(!c2pa::musha_ocsp_tests::fresh_at(der, &chain, now - 1));
        assert!(!c2pa::musha_ocsp_tests::fresh_at(der, &chain, now + 3601));
        let encode = |mut basic: rasn_ocsp::BasicOcspResponse| {
            let mut outer = outer.clone();
            outer.bytes.as_mut().unwrap().response = rasn::der::encode(&basic).unwrap().into();
            // Keep the closure's input owned to make individual mutations independent.
            basic.tbs_response_data.responses.clear();
            rasn::der::encode(&outer).unwrap()
        };
        let mut no_next = basic.clone();
        no_next.tbs_response_data.responses[0].next_update = None;
        let no_next = encode(no_next);
        assert!(c2pa::musha_ocsp_tests::fresh_at(
            &no_next,
            &chain,
            now + 86400
        ));
        assert!(!c2pa::musha_ocsp_tests::fresh_at(
            &no_next,
            &chain,
            now + 86401
        ));
        let mut future_produced = basic.clone();
        future_produced.tbs_response_data.produced_at =
            basic.tbs_response_data.responses[0].next_update.unwrap();
        assert!(!c2pa::musha_ocsp_tests::fresh_at(
            &encode(future_produced),
            &chain,
            now
        ));
        for reverse in [false, true] {
            let mut duplicate = basic.clone();
            let mut revoked = duplicate.tbs_response_data.responses[0].clone();
            revoked.cert_status = rasn_ocsp::CertStatus::Revoked(rasn_ocsp::RevokedInfo {
                revocation_time: basic.tbs_response_data.produced_at,
                revocation_reason: None,
            });
            duplicate.tbs_response_data.responses.push(revoked);
            if reverse {
                duplicate.tbs_response_data.responses.reverse();
            }
            let duplicate = encode(duplicate);
            // The same count guard is used before processing a stapled response.
            assert_eq!(
                c2pa::musha_ocsp_tests::matching_count(&duplicate, &chain),
                2
            );
            assert!(!c2pa::musha_ocsp_tests::fresh_at(&duplicate, &chain, now));
        }
        let responder = rasn::der::encode(&basic.certs.as_ref().unwrap()[0]).unwrap();
        // A self-signed root needs no issuer check; a truncated non-root tail,
        // missing chain, and an issuer with no usable response remain incomplete.
        assert_eq!(c2pa::musha_ocsp_tests::issuer_plan(&chain), (vec![], false));
        assert_eq!(
            c2pa::musha_ocsp_tests::issuer_plan(&[root.clone(), responder.clone()]),
            (vec![], true)
        );
        let completed = c2pa::musha_ocsp_tests::complete_chain(
            vec![root.clone(), responder.clone()],
            include_bytes!("../trust/leica-c2pa-root.pem"),
        );
        assert_eq!(
            completed,
            vec![root.clone(), responder.clone(), root.clone()]
        );
        assert_eq!(
            c2pa::musha_ocsp_tests::issuer_plan(&completed),
            (vec![1], false)
        );
        assert_eq!(
            c2pa::musha_ocsp_tests::issuer_plan(&[root.clone()]),
            (vec![], true)
        );
        assert_eq!(
            c2pa::musha_ocsp_tests::issuer_plan(&[root.clone(), responder.clone(), root.clone()]),
            (vec![1], false)
        );
        assert_eq!(c2pa::musha_ocsp_tests::issuer_result(false), (false, true));
        assert_eq!(c2pa::musha_ocsp_tests::issuer_result(true), (true, false));
        assert_eq!(
            c2pa::musha_ocsp_tests::responder_chain(&responder, &chain),
            Some(vec![responder.clone(), root.clone()])
        );
        let mut substituted: rasn_pkix::Certificate = rasn::der::decode(&root).unwrap();
        let unrelated: rasn_pkix::Certificate = rasn::der::decode(&responder).unwrap();
        // Retain the target's serial and issuer name, but replace its key without
        // a corresponding issuer signature (a serial-substitution attack).
        substituted.tbs_certificate.subject_public_key_info =
            unrelated.tbs_certificate.subject_public_key_info.clone();
        let substituted = rasn::der::encode(&substituted).unwrap();
        assert!(
            c2pa::musha_ocsp_tests::responder_chain(&responder, &[substituted, root.clone()])
                .is_none()
        );
        let mut unrelated: rasn_pkix::Certificate = rasn::der::decode(&responder).unwrap();
        unrelated.tbs_certificate.issuer = unrelated.tbs_certificate.subject.clone();
        assert!(c2pa::musha_ocsp_tests::responder_chain(
            &rasn::der::encode(&unrelated).unwrap(),
            &chain
        )
        .is_none());
    }
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
        for (request, expected) in [
            (
                c2pa::http::http::Request::post("https://example.com/?secret=hidden")
                    .body(vec![1])
                    .unwrap(),
                "request method rejected",
            ),
            (
                c2pa::http::http::Request::get("http://example.com/?secret=hidden")
                    .body(Vec::new())
                    .unwrap(),
                "HTTP request rejected",
            ),
            (
                c2pa::http::http::Request::get("https://example.com/?secret=hidden")
                    .body(vec![1])
                    .unwrap(),
                "request body rejected",
            ),
            (
                c2pa::http::http::Request::get("https://user:password@example.com/?secret=hidden")
                    .body(Vec::new())
                    .unwrap(),
                "request URL credentials rejected",
            ),
        ] {
            assert!(resolver.http_resolve(request).is_err());
            let error = state.error.lock().unwrap();
            assert_eq!(*error, Some(expected));
            assert!(!error.unwrap().contains("secret"));
            assert!(!error.unwrap().contains("password"));
        }
        assert_eq!(*state.hosts.lock().unwrap(), vec!["example.com"]);
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
