# 0.1.0 implementation notes

The viewer reads a bounded snapshot without writing to the source. Files over 64 MiB and preview images over 40 megapixels are rejected. The pixel limit does not guarantee a fixed memory ceiling. EXIF extraction and offline C2PA verification run independently of preview decoding; late results from an earlier selection are discarded. The EXIF parser returns a map, so duplicate keys lost by that parser cannot be recovered. Dropped files use the same pipeline; on macOS a security-scoped bookmark, when supplied by the drop plugin, remains active through processing. C2PA operations currently cannot be cancelled.

The settings store saves versioned JSON with a debounced serialized temporary-file replacement. Malformed and unrecognized-version files are retained and saving is disabled for the session. Restore checks display work areas and clamps the window onscreen. The settings implementation uses the OS Application Support directory on macOS, XDG config on Linux, and LocalAppData on Windows. See [C2PA build instructions](C2PA_BUILD.md) for the native engine and verification configuration.

## Validation and limits

Flutter 3.47.4 (framework `9584c6713b`) and Dart 3.13.3 were used on a Linux x64 development container. Tests cover settings round trips and preservation, drop validation, stale results, preview failure, a generated JPEG with EXIF, and initial UI. macOS 27 build, Sandbox selection and drag/drop, window restoration, native execution, signing, notarization, App Store distribution, and CPU-specific behavior require Mac device testing. Linux development checks are not release-platform validation. The generated `test/fixtures/exif.jpg` is a 3 × 2 solid-color image with synthetic EXIF and no private data.

Validation recorded 2026-11-01 for the integrated implementation:

- `flutter analyze`: no issues; `flutter test`: 10 tests passed, including the real native FFI signed/tampered fixtures and exit-time settings flush.
- `cargo test --locked --manifest-path native/c2pa/Cargo.toml`: 3 tests passed. These cover locally valid credentials, asset tampering, absent credentials, malformed/unsupported inputs, and an unresolved offline identity diagnostic.
- `flutter build linux --release`: succeeded with the native verifier included. In the running release app under Xvfb, the signed fixture showed SDK Valid with valid asset/claim integrity and signature; the tampered fixture showed SDK Invalid and invalid asset integrity.
- Dark theme was written to settings and restored after restarting the release app. Settings storage was isolated from other applications during this check.
- Actual OS drag-and-drop has not been exercised; the automated drop check covers input validation. macOS Sandbox access, window geometry/maximization restoration, and native drop delivery remain on the [device checklist](RELEASE_0_1_0.md).

The default verifier does not configure a trust list and does not fetch remote manifests, identity information or revocation information. Signer trust remains unknown. A local SDK Valid result is not a certification of signer trust or depicted content.
