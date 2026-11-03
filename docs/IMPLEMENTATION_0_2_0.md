# 0.2.0 implementation notes / 実装メモ

## English

DNG and NEF viewing uses an embedded JPEG preview, not a developed RAW image. The classic TIFF reader searches IFDs and selects the largest valid JPEG candidate; BigTIFF, non-JPEG previews, and files without a usable embedded preview are unsupported. It reads ranges from the source and bounds TIFF traversal and limits each embedded preview to 64 MiB. These checks do not establish support for a particular camera or NEF compression setting. Preview dimensions describe the embedded image, not necessarily the RAW sensor dimensions.

DNG verification is directed at the original file bytes, independently of the displayed preview. The native verifier maps DNG to its TIFF handler. Synthetic inputs can establish basic routing, but successful verification of Leica credentials in real DNG files has not been established. The RAW original snapshot is limited to 256 MiB; files larger than that are unsupported for original-file verification and EXIF. RAW original-file work runs globally one at a time to limit concurrency, but snapshots and native verification may copy data and can require substantially more memory than the file size. If the original cannot be read within that limit, verification and original-file EXIF are unavailable even when a preview can be displayed. Verification remains offline, and presence, integrity, signature, and trust are separate states. The default configuration has no trust list; a valid signature does not establish the truth of depicted events. NEF credential verification is not claimed.

Directory navigation uses a snapshot of supported filenames in natural order, without recursion or wraparound. Opening a file attempts to discover its parent folder automatically; if access fails, the user can explicitly authorize the folder. macOS Sandbox behavior requires device validation. Arrow keys and horizontal gestures navigate when the preview is not zoomed; Fit and 100% controls change the view; 100% targets one image pixel per physical display pixel. The adjacent-preview cache holds at most two entries and 32 MiB, and only one prefetch runs at a time globally. Stale asynchronous results are discarded. Cache freshness uses file size and modification time, not a cryptographic fingerprint. RAW TIFF orientation is applied unless the embedded JPEG has EXIF orientation, avoiding a duplicate transform. An extracted TIFF ICC profile is reported but not applied separately; JPEG decoding and color behavior depend on Flutter and the platform. The viewer remains read-only. Full RAW development, editing, video, and release binaries for other operating systems are outside this scope.

## Validation and remaining work

Development validation: `flutter analyze` reported no issues; `flutter test` passed 31 tests, including C2PA integration, synthetic RAW, cache, and UI tests; `cargo test --locked --manifest-path native/c2pa/Cargo.toml` passed 4 tests. The final Linux Release build succeeded and its window opened under Xvfb.

Synthetic fixtures cannot represent all camera layouts, metadata, color profiles, or compression choices. Representative permission-cleared Leica DNG and Nikon NEF files, camera models, and NEF compression settings have not been supplied. Real-file compatibility and Leica credential verification require testing with those files. macOS build and execution, Sandbox folder selection and drag-and-drop, physical keyboard and trackpad behavior, and color/orientation comparisons with Finder require validation on a physical Mac. Linux development results do not establish macOS release behavior. See [the 0.2.0 plan](PLAN_0_2_0.md) and [the release checklist](RELEASE_0_2_0.md).

## 日本語

DNG・NEFの表示には埋め込みJPEGプレビューを使い、RAW現像は行いません。classic TIFFのIFDをたどって有効なJPEG候補のうち最大のものを選びます。BigTIFF、JPEG以外のプレビュー、利用可能な埋め込みプレビューのないファイルには対応しません。元ファイルは必要な範囲を読み取り、TIFF探索に上限を設け、埋め込みプレビューは各64 MiB以下に制限します。この処理は特定のカメラやNEF圧縮設定への対応を保証するものではありません。表示する寸法は埋め込み画像の寸法であり、RAWセンサーの寸法とは限りません。

DNGの検証は表示プレビューとは独立して元ファイルのバイト列に対して行います。ネイティブ検証器はDNGをTIFFハンドラーに渡します。合成入力では基本的な経路を確認できますが、実際のDNGでLeicaのContent Credentialsを検証できることは未確認です。RAW元ファイルのスナップショットには256 MiBの上限があり、それを超えるファイルの元ファイル検証とEXIF取得には対応しません。RAW元ファイル処理は同時に全体で1件に制限しますが、スナップショットやネイティブ検証ではデータがコピーされ、ファイルサイズより大幅に多いメモリーが必要になる場合があります。上限内で読み込めない場合はプレビューを表示できても検証と元ファイルのEXIFは利用できません。検証はオフラインで、存在・整合性・署名・信頼は別の状態です。既定では信頼リストがなく、有効な署名は撮影内容の真実性を保証しません。NEFの認証情報検証への対応は保証しません。

フォルダー内の対応ファイル名を自然順に並べた一覧で移動し、再帰検索や末尾から先頭への循環は行いません。ファイルを開くと親フォルダーの検出を試み、アクセスに失敗した場合はフォルダーを明示的に許可できます。macOS Sandboxでの動作は実機確認が必要です。拡大していないときは左右キーや横方向のジェスチャーで移動でき、画面に合わせる表示と100%表示を選べます。100%表示は画像の1ピクセルをディスプレイの物理1ピクセルに対応させることを目標とします。隣接プレビューのキャッシュは最大2件・32 MiBで、先読みは全体で同時に1件です。古い非同期結果は破棄します。キャッシュの鮮度確認にはファイルサイズと更新時刻を使い、暗号学的な照合ではありません。RAWのTIFFの向きは、埋め込みJPEGにEXIFの向きがある場合を除いて適用し、変換の重複を避けます。抽出したTIFF ICCプロファイルは表示しますが個別には適用しません。JPEGのデコードと色の扱いはFlutterとプラットフォームに依存します。ビューアーは読み取り専用です。フルRAW現像、編集、動画、他OS向け配布バイナリーは対象外です。

## 検証と残課題

開発環境での検証では、`flutter analyze`は問題なし、`flutter test`はC2PA統合・合成RAW・キャッシュ・UIのテストを含む31件すべてが成功し、`cargo test --locked --manifest-path native/c2pa/Cargo.toml`は4件すべてが成功しました。最終コードのLinux Releaseビルドが成功し、Xvfb上でウィンドウの表示を確認しました。

合成フィクスチャはすべてのカメラの構造、メタデータ、カラープロファイル、圧縮方式を再現できません。利用許諾のある代表的なLeica DNG・Nikon NEF、機種名、NEF圧縮設定は未提供です。実ファイルとの互換性とLeica認証情報の検証には、それらのファイルを使った確認が必要です。macOSでのビルド・実行、Sandboxのフォルダー選択とドラッグ＆ドロップ、物理キーボードとトラックパッド、Finderとの色・向きの比較は実機確認が必要です。Linuxでの開発検証はmacOSでのリリース動作を保証しません。[0.2.0計画](PLAN_0_2_0.md)と[リリース確認リスト](RELEASE_0_2_0.md)を参照してください。
