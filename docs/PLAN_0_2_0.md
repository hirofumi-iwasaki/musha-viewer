# v0.2.0 plan / 作業計画

## English

Implement DNG/NEF viewing, Leica Content Credentials verification against the original DNG, and navigation between supported images in one directory. Prefer embedded RAW previews; do not promise full RAW development or camera-specific compatibility without fixtures. Keep source files read-only and verification offline. Preserve distinct integrity, signature, and trust states.

Scope:
- Bounded DNG/NEF embedded-preview extraction, clear preview provenance and dimensions, and graceful missing/invalid-preview errors.
- Evaluate c2pa-rs DNG support and verify original DNG bytes independently of extracted previews. Record unsupported cases and unknown trust honestly.
- Previous/next with physical arrow keys and horizontal trackpad/touch swipes, natural filename order, no recursion or wraparound, and explicit folder authorization when macOS Sandbox requires it.
- Fit and 100% zoom, with zoom/pan gestures separated from navigation.
- EXIF orientation and ICC handling; document measured behavior and remaining Finder comparisons.
- Bounded adjacent-preview prefetch/cache and stale-result protection during rapid navigation.
- Current filename and position (for example, 3 / 20).
- Preserve the v0.2.0+ macOS ARM ZIP release automation already implemented.

Acceptance: synthetic parser fixtures for valid/invalid/bounded RAW inputs; directory sorting and navigation boundaries; stale-result/cache limits; input-focus and zoom/navigation conflicts; regressions for settings and C2PA. Run analysis, Flutter/native tests, Linux Release build and startup in the dedicated container. macOS Sandbox, real trackpad gestures, color comparison with Finder, and actual Leica/Nikon files require device validation by the user. Camera models, NEF compression settings, and representative permission-cleared files are not yet supplied. Do not represent those checks as complete. Video, full RAW editing/development, and other-OS release binaries are outside scope.

## 日本語

DNG・NEF表示、元のDNGに対するLeica Content Credentials検証、同一フォルダー内の対応画像移動を実装する。RAWは埋め込みプレビューを優先し、実画像なしでフルRAW現像や機種別対応を保証しない。元ファイルは読み取り専用、C2PA検証はオフラインとし、整合性・署名・信頼を分ける。

対象：
- 上限を設けたDNG・NEF埋め込みプレビュー抽出、プレビューの由来・寸法表示、未収録・破損時の適切なエラー。
- c2pa-rsのDNG対応を調べ、抽出プレビューとは独立して元DNGを検証。未対応と信頼不明を正確に記録。
- 物理左右キーとトラックパッド／タッチの左右スワイプによる前後移動。ファイル名の自然順、再帰なし、末尾で停止。macOS Sandboxで必要な場合は明示的なフォルダー許可を取得。
- 画面に合わせる表示と100%表示。拡大・パンと画像移動の競合を防止。
- EXIF回転とICCの扱いを確認し、実測結果とFinder比較の残課題を記録。
- 隣接画像の先読みと容量制限付きキャッシュ、高速移動時の古い結果の破棄。
- ファイル名と現在位置（例：3 / 20）の表示。
- 実装済みのv0.2.0以降のmacOS ARM ZIP自動配布を維持。

受け入れ条件：正常・破損・上限超過の合成RAWフィクスチャ、自然順と移動端点、古い結果とキャッシュ上限、入力フォーカスと拡大／移動競合、設定・C2PA回帰を検証する。専用コンテナーで解析、Flutter／Rustテスト、Linux Releaseビルド・起動を確認する。macOS Sandbox、実トラックパッド、Finderとの色比較、実際のLeica／Nikonファイルはユーザーの実機確認が必要。機種名、NEF圧縮設定、利用許諾のある代表ファイルは未提供であり、確認済みとしない。動画、フルRAW編集・現像、他OSバイナリー配布は対象外。
