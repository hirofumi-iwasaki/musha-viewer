# macOS Apple Silicon test artifact

The `macOS test build` GitHub Actions workflow builds the `release/0.1.0` branch or runs on manual dispatch, using the `xcode-27` Apple Silicon hosted runner, Flutter 3.47.4, and Rust 1.99.1. It builds an arm64 release-mode app for macOS 27, runs the native and Flutter tests, and checks the architecture, bundled C2PA library, ad-hoc signature, and release Sandbox entitlements. A failed check fails the workflow; no fallback debug artifact is labeled as a release build. The hosted runner and the resulting app still require real Mac device testing.

After a successful run, open its **Actions** page and download the `musha-viewer-macos-27-arm64-test` artifact. It contains a ZIP with `musha-viewer.app`, `SHA256SUMS.txt`, `BUILD-INFO.txt` with the commit and run URL, project notices, and a native dependency license inventory. In Terminal, from the extracted artifact directory, verify the checksum:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Expand the app ZIP in Finder, move the app to Applications if desired, and launch it. The build is **ad-hoc signed for testing**, with no Developer ID signature or notarization. macOS Gatekeeper may block it. Only after verifying the checksum and trusting the source, use the macOS Privacy & Security settings to allow the blocked app if offered. The app is restricted to macOS 27 or later on Apple Silicon; it does not target Intel Macs. This artifact is not a production or App Store release, and the provisional bundle identifier is not final.

Test file selection and Finder drag/drop with Sandbox enabled, image preview and metadata, valid and altered C2PA samples, settings persistence (including Quit and restart), and errors. See [the release and device checklist](RELEASE_0_1_0.md). Do not assume a successful build verifies those behaviors on a physical Mac. GitHub Actions artifacts expire after 14 days; the workflow does not create a GitHub Release or publish an app.
