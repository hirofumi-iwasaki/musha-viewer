# Local c2pa-rs patch

This directory contains the crates.io `c2pa` 0.91.10 package (upstream repository revision `1a605b826116e906ac479f707729e735c43d5881`). The independently verified SHA-256 of the crates.io archive is `1bef0ab19b01c227b0ffd637eaf50c856d8a9eea50a6e883b45a15ca56a6443a`. The local changes are:

- Fetched OCSP responses must be current, have a non-future `producedAt`, and contain exactly one matching certificate status. A missing `nextUpdate` uses a 24-hour limit from `producedAt`.
- Both stapled and fetched responder paths must use the queried certificate's verified issuer and that issuer's chain, ignoring response-provided alternate intermediates. Delegated responder EKU and signature/path validation remain required. Historical revocation-time behavior remains intact.
- Both response paths reject multiple matching statuses. Historical signing time is used only after the timestamp itself is verified against a TSA trust anchor; an untrusted caller-supplied or embedded timestamp cannot backdate revocation checks.
- Successful, definitive live validation emits `org.musha.liveOcsp.good` or `org.musha.liveOcsp.revoked`, allowing the caller to distinguish it from a stapled fallback. An internal OCSP request header identifies the request to the local resolver; the resolver does not forward it.
- A validated, good issuing-CA response also emits `org.musha.liveOcsp.issuerGood`; the caller compares the number of these markers to issuer lookup attempts.
- Missing or unusable issuer responses and a chain ending in a non-self-signed certificate emit `org.musha.liveOcsp.issuerIncomplete`. Online completion requires a definitive leaf response and no incomplete issuer check.
- A missing final root may be completed from the configured manifest anchors only after verifying that it signed the supplied chain tail.
- The `musha_ocsp_tests` feature exposes narrowly scoped test hooks only in test builds, used by the native verifier's deterministic security tests.
- A test-only absolute developer path in `src/crjson.rs` is replaced with a generic fixture path.

Review the source differences against the unmodified 0.91.10 crates.io archive before updating this dependency. The crate archive does not contain upstream's full test fixture tree; the native verifier's tests cover the local changes without relying on external network requests.
