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

## RAW preview follow-up / RAWプレビューの追加修正

The 40-megapixel rejection was removed; decoding a large preview can use substantial memory. The controller validates a reduced 1 × 1 frame and reports original dimensions, while the displayed image can still require a full-resolution decode. Classic TIFF SubIFD type 13 pointers and single-strip JPEG with shared JPEGTables are handled within the existing bounds. JPEG end markers are located within the declared strip so trailing bytes are excluded; 8-bit baseline, extended sequential and progressive JPEG are accepted, while lossless JPEG RAW is not treated as a display preview. Tiled, multi-strip and non-JPEG previews remain unsupported.

A publicly downloadable [Photography Blog Leica M11 original](https://img.photographyblog.com/reviews/leica_m11/sample_images/leica_m11_01.dng) was inspected locally, without adding the image to this repository. Its four single-strip JPEG previews measured 160 × 120, 720 × 480, 2112 × 1408 and 9504 × 6320; each strip included nonzero data after its JPEG end marker. Pillow independently decoded all four. The Dart extractor selected the 9504 × 6320 JPEG (28,005,778 bytes) after removing 110 trailing strip bytes. The original CFA image was lossless JPEG. This is a Leica M11 sample, not the user's M11-D file: it does not prove M11-D compatibility. The user's screenshot showed successful original DNG C2PA integrity and signature validation with unknown trust; it does not establish preview extraction or identify the file's TIFF structure. Test the actual user files on macOS before claiming a fix for those files.

4000万画素での一律拒否を撤廃しました。大きなプレビューのデコードには多くのメモリーが必要になる場合があります。controller の検証では 1 × 1 に縮小したフレームを使い元の寸法を表示しますが、画面表示ではフル解像度のデコードが必要になることがあります。既存の上限内で classic TIFF の type 13 SubIFD と JPEGTables を共有する単一 JPEG strip に対応します。strip 内の JPEG 終端を探し、後続バイトを除外します。8-bit の baseline・extended sequential・progressive JPEG をプレビューとし、lossless JPEG の RAW 本体はプレビューとして扱いません。タイル、複数 strip、JPEG 以外のプレビューは引き続き未対応です。

公開されている [Photography Blog の Leica M11 原本](https://img.photographyblog.com/reviews/leica_m11/sample_images/leica_m11_01.dng)をローカルで調べました。画像自体はリポジトリに追加していません。4つの単一 strip JPEG プレビューは 160 × 120、720 × 480、2112 × 1408、9504 × 6320 で、いずれも JPEG 終端後にゼロ以外のバイトを含んでいました。4つとも Pillow で独立にデコードできました。Dart 抽出器は末尾の110バイトを除いた 9504 × 6320 の JPEG（28,005,778バイト）を選択しました。元の CFA 画像は lossless JPEG でした。これは M11 の別サンプルであり、ユーザーの M11-D 画像の互換性を証明しません。ユーザーのスクリーンショットでは元 DNG の C2PA 整合性と署名が有効、信頼は不明と表示されましたが、プレビュー抽出や TIFF 構造は確認できません。対象の実ファイルを macOS で再検証する必要があります。

On 2026-11-04, the viewer-only Linux container using Flutter 3.47.4 resolved locked packages, `flutter analyze` reported no issues, and 16 focused RAW parser, over-40-megapixel, and original-byte/stale-result tests passed. The public M11 extraction check above used Dart 3.13.3. These results do not validate the user's M11-D or Nikon Z8 files or macOS display behavior.

2026-11-04 に viewer 専用 Linux コンテナーと Flutter 3.47.4 でロック済み依存を解決し、`flutter analyze` は問題なし、RAW パーサー・4000万画素超・元データと古い結果に関する対象テスト16件が成功しました。上記の公開 M11 抽出は Dart 3.13.3 で確認しました。これらはユーザーの M11-D・Nikon Z8 ファイルや macOS での表示を検証したものではありません。

The user reported that the revised macOS test build displayed their Nikon Z8 NEF and Leica M11-D DNG successfully. This is a report for those particular files, not a compatibility guarantee for all camera models or compression settings.

ユーザーから、修正版の macOS テストビルドで手元の Nikon Z8 NEF と Leica M11-D DNG が正常に表示されたとの報告がありました。これは当該ファイルについての報告であり、全機種・全圧縮設定の互換性を保証するものではありません。

## Folder access and credential visibility / フォルダー許可と認証情報の表示

On macOS, when opening or dropping a file cannot establish access to its parent folder, the app requests the parent with the native folder picker; cancelling leaves the image open and does not grant access. The manual folder picker also starts at the current image's parent. The automatic fallback accepts the same absolute path; an equivalent path presented differently, such as through a symbolic link, may need a manual folder selection. Existing accessible folder navigation does not trigger this fallback. Actual macOS Sandbox permission and scope lifetime must still be checked on a Mac.

The inspector hides C2PA while a result is pending and for `absent` or `unsupported`, while showing present, remote-reference and error results. NEF now uses the SDK's supported Nikon TIFF MIME type. The SDK inspects the original container for embedded manifests and remote references and returns absence before signature/hash validation. It still reads the bounded original snapshot and copies it into the native verifier; there is no separate speculative EXIF-based absence probe. Malformed and uncertain inputs continue to the SDK rather than being classified absent. Verification remains offline.

macOS で画像の選択・ドロップ後に親フォルダーへアクセスできない場合は、親を初期位置にした OS のフォルダー選択画面を開きます。キャンセル時は画像を開いたまま、権限を取得しません。手動のフォルダー選択も現在の画像の親から開始します。自動処理は同一の絶対パスを受け付けるため、シンボリックリンクなど別表記で同じ場所を選んだ場合は手動選択が必要になることがあります。既にアクセスできるフォルダーでは自動確認画面を出しません。macOS Sandbox の権限とスコープの寿命は実機で確認が必要です。

インスペクターの C2PA 欄は結果待ち、および `absent`・`unsupported` の場合に非表示とし、存在・外部参照・エラーの場合は表示します。NEF は SDK がサポートする Nikon TIFF の MIME 型を使用します。SDK は元コンテナーのマニフェストと外部参照を調べ、存在しなければ署名・ハッシュ検証の前に不在を返します。上限付き元データの読み取りとネイティブ側へのコピーは引き続き行い、EXIF だけから不在を推測しません。破損や判定不能な入力は SDK へ渡し、検証はオフラインのままです。
