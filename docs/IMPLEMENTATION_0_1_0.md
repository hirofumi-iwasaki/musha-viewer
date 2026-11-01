# 0.1.0 implementation notes

This is an image-viewer prototype; the broader design documents include future work. The Flutter UI uses a session counter to ignore results from an earlier selection. File information, image decoding, and EXIF extraction have separate error states. Reads are limited to 64 MiB; preview decoding is refused above 40 megapixels. EXIF parsing runs in an isolate. Neither limit guarantees a fixed memory ceiling, and EXIF parsing cannot currently be cancelled. The `exif` package returns a map, so the application cannot recover duplicate keys that the parser discards. Values and group labels are displayed as returned rather than asserting complete metadata coverage.

## Validation recorded 2026-11-01

- Flutter 3.47.4 (framework revision `9584c6713b`), Dart 3.13.3, Linux x64 container with GTK 3.24.49.
- `flutter analyze`: no issues. `flutter test`: three tests passed, including a generated JPEG with EXIF and decoded dimensions, a stale-result race with preview failure, and initial UI status.
- `flutter build linux --debug`: succeeded. The debug executable started under Xvfb and displayed its initial window. The native picker opened the generated JPEG and the inspector showed its dimensions and EXIF camera name. This does not establish Linux release or desktop integration support.
- macOS 27 build, Sandbox file selection, and native execution were not tested: the validation host is Linux. Signing, notarization, App Store distribution, and CPU-specific behavior remain unverified.

The fixture `test/fixtures/exif.jpg` is a generated 3 × 2 solid-color image containing a synthetic camera name. It contains no private image data.
