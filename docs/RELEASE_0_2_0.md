# 0.2.0 release and physical Mac checklist / 公開・Mac実機確認

## English

These checks are unverified until performed on a physical Mac. Record the commit, macOS version, Mac model and CPU, Flutter, Xcode and Rust versions, and the result and any issues for each check. Linux tests do not complete this checklist.

- [ ] Build and launch the release app with its native C2PA library. Confirm the downloaded Apple Silicon ZIP runs on a Mac without the development tools.
- [ ] Test permission-cleared Leica DNG files with Content Credentials and Nikon NEF files; record camera models, NEF compression settings, file sizes, preview availability and dimensions, and verification results. Include missing or invalid previews and RAW files above the original snapshot limit where available. Preserve the source files unchanged.
- [ ] Compare orientation and color with Finder using representative images, including embedded JPEG EXIF orientation and TIFF orientation and ICC profiles. Record differences and display configuration.
- [ ] In App Sandbox, select a file and authorize its folder, then navigate siblings; test denied access, Finder drag-and-drop, paths with spaces and non-ASCII characters, and external storage.
- [ ] Test physical arrow keys, trackpad horizontal gestures, zoom and pan conflicts, Fit and 100% on the physical display, boundaries and rapid navigation. Confirm filename and position display and absence of stale results.
- [ ] Verify C2PA offline, including signed and tampered fixtures, unavailable credentials and distinct integrity, signature and trust states. Confirm that the source remains read-only.
- [ ] Check settings and window restoration, including after display configuration changes.
- [ ] Review the bundle identifier, native library, third-party notices, signing, notarization and ZIP contents. Verify the actual distribution artifact and document its provenance before release.
- [ ] Record issues and outcomes in the implementation notes and update documented limitations before release.

## 日本語

以下はMac実機で実施するまで未確認です。コミット、macOSのバージョン、Macの機種とCPU、Flutter・Xcode・Rustのバージョン、各項目の結果と問題を記録してください。Linuxでのテストだけで完了にはできません。

- [ ] ネイティブC2PAライブラリを含むReleaseアプリをビルド・起動する。ダウンロードしたApple Silicon ZIPが開発ツールのないMacで起動することを確認する。
- [ ] 利用許諾のあるContent Credentials付きLeica DNGとNikon NEFを試し、機種、NEF圧縮設定、ファイルサイズ、プレビューの有無と寸法、検証結果を記録する。可能ならプレビューがない・壊れているファイルや元ファイルのスナップショット上限を超えるRAWも確認する。元ファイルは変更しない。
- [ ] JPEGのEXIFとTIFFの向き、ICCプロファイルを含む代表画像の色と向きをFinderと比較し、差異とディスプレイ設定を記録する。
- [ ] App Sandboxでファイルを選択してフォルダーを許可し、同じフォルダー内を移動する。許可拒否、Finderからのドラッグ＆ドロップ、空白・非ASCII文字を含むパス、外部ストレージも確認する。
- [ ] 物理左右キー、トラックパッドの横ジェスチャー、拡大・パンとの競合、実ディスプレイでの画面に合わせる表示と100%表示、端点、高速移動を確認する。ファイル名と位置の表示、古い結果が混入しないことも確認する。
- [ ] 署名済み・改変済みフィクスチャや取得できない認証情報を含め、C2PAをオフラインで検証し、整合性・署名・信頼の状態を区別できることを確認する。元ファイルが読み取り専用であることも確認する。
- [ ] ディスプレイ構成変更後を含め、設定とウィンドウの復元を確認する。
- [ ] Bundle ID、ネイティブライブラリ、第三者通知、署名、公証、ZIP内容を確認する。配布前に実際の配布成果物を検証し、由来を記録する。
- [ ] 結果と問題を実装メモに記録し、公開前に制限事項を更新する。
