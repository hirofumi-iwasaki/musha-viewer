# macOS Apple Silicon test artifact

The `macOS test build` GitHub Actions workflow builds the `release/0.1.0` branch or runs on manual dispatch, using the `xcode-27` Apple Silicon hosted runner, Flutter 3.47.4, and Rust 1.99.1. It builds an arm64 release-mode app for macOS 27, runs the native and Flutter tests, and checks the architecture, bundled C2PA library, ad-hoc signature, and release Sandbox entitlements. A failed check fails the workflow; no fallback debug artifact is labeled as a release build. The hosted runner and the resulting app still require real Mac device testing.

After a successful run, open its **Actions** page and download the `musha-viewer-macos-27-arm64-test` artifact. It contains a ZIP with `musha-viewer.app`, `SHA256SUMS.txt`, `BUILD-INFO.txt` with the commit and run URL, project notices, and a native dependency license inventory. In Terminal, from the extracted artifact directory, verify the checksum:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Expand the app ZIP in Finder, move the app to Applications if desired, and launch it. The build is **ad-hoc signed for testing**, with no Developer ID signature or notarization. macOS Gatekeeper may block it. Only after verifying the checksum and trusting the source, use the macOS Privacy & Security settings to allow the blocked app if offered. The app is restricted to macOS 27 or later on Apple Silicon; it does not target Intel Macs. This artifact is not a production or App Store release, and the provisional bundle identifier is not final.

Test file selection and Finder drag/drop with Sandbox enabled, image preview and metadata, valid and altered C2PA samples, settings persistence (including Quit and restart), and errors. See [the release and device checklist](RELEASE_0_1_0.md). Do not assume a successful build verifies those behaviors on a physical Mac. GitHub Actions artifacts expire after 14 days.

## GitHub Release assets

Publishing a GitHub Release for a SemVer tag `v0.2.0` or later triggers the `macOS release asset` workflow. It checks out that tag, runs the same tests and packaging checks as the test build, and attaches `musha-viewer-macos-27-arm64-test-artifact.zip` to that release. The ZIP contains the test app ZIP, its SHA-256 checksum, build information, project notices, and native dependency license inventory. Prereleases earlier than `v0.2.0`, including `v0.2.0-rc.1`, are excluded. Later prereleases are accepted. The workflow does not create a release; publishing one is a separate operation.

To retry, run the workflow manually from the default branch with the existing published release tag. Draft releases and invalid or earlier tags are rejected. A successful retry replaces the asset of the same name. This is an ad-hoc-signed test build for macOS 27 or later on Apple Silicon: it is not Developer ID signed or notarized, and still requires physical Mac testing.

## 日本語

`v0.2.0` 以降の SemVer タグで GitHub Release を公開すると、`macOS release asset` ワークフローがそのタグをチェックアウトし、テストビルドと同じテスト・パッケージ検証を行って `musha-viewer-macos-27-arm64-test-artifact.zip` を添付します。ZIP にはアプリの ZIP、その SHA-256、ビルド情報、プロジェクトの通知とネイティブ依存ライセンス一覧が入ります。`v0.2.0-rc.1` のように `v0.2.0` より前のプレリリースは対象外で、それ以降のプレリリースは対象です。Release 自体の作成・公開は別途行います。

再実行する場合は、既定ブランチのワークフローを手動実行し、公開済み Release のタグを指定してください。ドラフト、無効なタグ、対象より前のタグは拒否されます。成功した再実行は同名の添付ファイルを置き換えます。成果物は macOS 27 以降の Apple Silicon 向けアドホック署名テストビルドで、Developer ID 署名と公証は行っておらず、Mac 実機での検証が必要です。
