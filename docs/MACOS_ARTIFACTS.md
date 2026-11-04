# macOS Apple Silicon test artifact

The `macOS test build` GitHub Actions workflow runs on `release/0.2.0` pushes or manual dispatch using the `xcode-27` Apple Silicon runner, Flutter 3.47.4, and Rust 1.99.1. It builds an arm64 release-mode app for macOS 27, runs the native and Flutter tests, and checks the architecture, bundled C2PA library, ad-hoc signature, and release Sandbox entitlements. The hosted runner and resulting app still require physical Mac testing.

After a successful run, download `musha-viewer-macos-27-arm64-test.zip` from the Actions page. The ZIP contains `Musha Viewer.app` and a `Licenses` directory. Expand it in Finder, move the app to Applications if desired, and launch it. The workflow log records the archive's SHA-256 checksum; compare it with `shasum -a 256 musha-viewer-macos-27-arm64-test.zip` before opening the archive.

The build is **ad-hoc signed for testing**, with no Developer ID signature or notarization. macOS Gatekeeper may block it. Only after verifying the checksum and trusting the source, use the macOS Privacy & Security settings to allow the blocked app if offered. The app requires macOS 27 or later on Apple Silicon; it does not target Intel Macs. This is not a production or App Store release, and the provisional bundle identifier is not final.

Test file selection and Finder drag/drop with Sandbox enabled, image preview and metadata, valid and altered C2PA samples, settings persistence (including Quit and restart), and errors. See [the release and device checklist](RELEASE_0_2_0.md). GitHub Actions artifacts expire after 14 days.

## GitHub Release assets

Publishing a GitHub Release for a SemVer tag `v0.2.0` or later triggers the `macOS release asset` workflow. It checks out that tag, runs the same tests and packaging checks as the test build, and attaches the same single ZIP containing the app and licenses. Prereleases earlier than `v0.2.0`, including `v0.2.0-rc.1`, are excluded. Later prereleases are accepted. The workflow does not create a release; publishing one is a separate operation.

To retry, run the workflow manually from the default branch with the existing published release tag. Draft releases and invalid or earlier tags are rejected. A successful retry replaces the asset of the same name. This is an ad-hoc-signed test build that still requires physical Mac testing.

## 日本語

`macOS test build` ワークフローは `release/0.2.0` へのプッシュまたは手動実行で Apple Silicon 向けテストビルドを作成します。成功後、Actions ページから `musha-viewer-macos-27-arm64-test.zip` をダウンロードしてください。ZIP には `Musha Viewer.app` と `Licenses` ディレクトリが含まれます。展開前に `shasum -a 256 musha-viewer-macos-27-arm64-test.zip` の結果をワークフローのログに記録された SHA-256 と比較してください。

このアプリは macOS 27 以降の Apple Silicon 向けで、アドホック署名されたテストビルドです。Developer ID 署名と公証は行っていないため、Gatekeeper にブロックされる場合があります。チェックサムと入手元を確認したうえで、必要に応じて macOS の「プライバシーとセキュリティ」で許可してください。Mac 実機での検証が必要です。手順は[リリース・実機確認チェックリスト](RELEASE_0_2_0.md)を参照してください。Actions の成果物は14日後に期限切れになります。

`v0.2.0` 以降の SemVer タグで GitHub Release を公開すると、`macOS release asset` ワークフローが同じ単一 ZIP を添付します。`v0.2.0-rc.1` のように `v0.2.0` より前のプレリリースは対象外です。Release 自体の作成・公開は別途行います。再実行する場合は、既定ブランチのワークフローを公開済み Release のタグで手動実行してください。成功すると同名の添付ファイルが置き換わります。

The checkout and artifact upload actions use Node.js 24 and require GitHub Actions runner version 2.327.1 or later. For a self-hosted `xcode-27` runner, update the runner before running these workflows.

チェックアウトと成果物アップロードのアクションは Node.js 24 を使用し、GitHub Actions ランナー 2.327.1 以降が必要です。セルフホストの `xcode-27` ランナーでは実行前に更新してください。
