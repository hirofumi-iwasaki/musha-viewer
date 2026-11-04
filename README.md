# musha-viewer

## English

musha-viewer is a read-only Flutter image viewer for macOS 27. Open or drop one image to inspect a preview, file information, decoded dimensions, EXIF tags, and a C2PA verification result (offline by default). Use the inspector toggle and divider to change the layout, and the appearance menu for system, light, or dark theme. Window position, normal size, maximized state, inspector preferences, and theme are saved locally. DNG and NEF can show an embedded JPEG preview; select a folder to navigate supported images in natural filename order. Fit and 100% controls are available. Video, Finder “Open With”, and file history are not implemented.

Starting with version 1.0, versions distributed through app stores may be paid. The source code will remain publicly available.

C2PA verification uses c2pa-rs. Presence, parsing, asset and claim integrity, signature, trust and SDK validation are shown separately. A valid signature does not establish that depicted events are true. Unsupported files, remote credentials, errors and absent credentials are distinct states. Preview and metadata remain usable if verification fails or the native library is unavailable.

Offline verification is the default; online verification requires an explicit request and has not been verified on a physical Mac. The SDK may fetch remote manifests, CAWG identity resources and OCSP responses using bounded HTTPS GET requests. Plain HTTP is allowed only for a strict canonical OCSP GET to the exact host `ocsp.leica.systems`; other HTTP resources and OCSP endpoints are rejected. Private addresses and redirects are blocked, and proxies are unsupported. The budget is 20 seconds including DNS and at most 16 requests, with at most 16 MiB per response and 1 MiB for an HTTP OCSP response. Original image bytes are never uploaded. Requests disclose the client IP address and requested URLs or certificate identifiers to the contacted servers; a Leica OCSP request discloses the client IP and certificate identifiers to Leica. Because the request uses unencrypted HTTP, network intermediaries can also observe its certificate identifiers.

A locally patched, vendored c2pa-rs 0.91.10 validates the live response signature, CertID and EKU, requires the responder to be directly authorized by the actual signer certificate issuer, chains the responder to the bundled official Leica C2PA root, and requires a currently fresh response. It emits `org.musha.liveOcsp.good` or `org.musha.liveOcsp.revoked` as an informational marker for a definitive live Leica revocation result. Online completion requires a definitive live leaf OCSP result and a Good result for every required non-root issuer check. Missing AIA, a failed or unknown issuer response, or a truncated chain leaves the check incomplete even if the leaf is Good. A result without a marker does not confirm live Leica revocation status. Successful requests cover only resources attempted. No general C2PA trust list is configured: `verify_trust=false`, and the bundled Leica root is used only to authorize the Leica OCSP responder chain. Overall trust remains unknown, even after a successful live check.

The EXIF parser returns a map, so duplicate keys can be lost; XMP, IPTC, ICC, MakerNotes, and unknown tags are not comprehensively covered. An empty EXIF result does not prove that a file contains no metadata. Image decoding depends on Flutter and the OS. Ordinary files over 64 MiB are rejected. Large previews can require substantial memory when decoded. RAW previews are extracted separately; original-file metadata and verification require a RAW snapshot of at most 256 MiB and may use substantially more memory due to copying. The source file is opened read-only. Settings are stored as versioned JSON in macOS Application Support, Linux `$XDG_CONFIG_HOME/musha-viewer` (or `~/.config/musha-viewer`), and Windows LocalAppData. Corrupt or unknown-version settings are preserved instead of overwritten.

RAW previews are not full RAW development. BigTIFF and non-JPEG embedded previews are unsupported; camera-specific compatibility and real Leica DNG verification remain unverified. RAW TIFF orientation is applied unless the embedded JPEG has EXIF orientation; an extracted TIFF ICC profile is reported but not applied separately. Finder color and orientation comparisons and physical Mac testing remain outstanding. See [0.2.0 implementation notes](docs/IMPLEMENTATION_0_2_0.md) for scope and limitations.

### Build and validation

For Apple Silicon test builds and download instructions, see [macOS test artifacts](docs/MACOS_ARTIFACTS.md).

For isolated Linux development in the current managed workspace, see [viewer development runtime](docs/CLOUD_ENVIRONMENT.md).

Use Flutter 3.47.4 / Dart 3.13.3 and Rust; build the native engine first as described in [C2PA build instructions](docs/C2PA_BUILD.md). On a Mac, use an Xcode SDK supporting the macOS 27 deployment target:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter build macos --release
```

The macOS runner enables App Sandbox and user-selected read-only access. `org.musha.mushaViewer` is a provisional bundle identifier; configure an appropriate identifier and signing before distribution. macOS build, sandbox selection and drag/drop, release execution, signing, notarization, and App Store distribution require verification on a Mac; follow the [release and device checklist](docs/RELEASE_0_2_0.md). The Linux runner is for development and does not establish release support.

## 日本語

musha-viewerはmacOS 27を対象とする閲覧専用Flutter画像ビューアーです。画像を選択または一つドロップすると、プレビュー、ファイル情報、デコード後の寸法、EXIF、C2PA検証結果（既定ではオフライン）を表示します。インスペクターの表示・幅、システム／ライト／ダークのテーマ、通常時のウィンドウ位置・大きさ、最大化状態は保存されます。DNG・NEFは埋め込みJPEGプレビューを表示でき、フォルダーを選ぶと対応画像をファイル名の自然順で移動できます。画面に合わせる表示と100%表示も利用できます。動画、Finderの「このアプリケーションで開く」、履歴は未実装です。

1.0以降は各ストア配布版については有料にする可能性があります。ソースコードは引き続き公開します。

C2PA は c2pa-rs で検証します。存在・解析、アセットとクレームの整合性、署名、信頼、SDK 検証状態を別々に表示します。有効な署名は撮影内容の真実性を保証しません。未対応、外部参照、エラー、未検出は区別します。検証やネイティブライブラリの読込が失敗してもプレビューとメタデータは利用できます。

既定はオフライン検証で、オンライン検証は明示的に要求した場合のみ行います。Mac 実機では未検証です。SDK は外部マニフェスト、CAWG 識別情報、OCSP 応答を上限付き HTTPS GET で取得する場合があります。平文 HTTP は正確なホスト `ocsp.leica.systems` への厳密な正規形式の OCSP GET に限り許可し、その他の HTTP リソースや OCSP エンドポイントは拒否します。プライベートアドレスとリダイレクトは遮断し、プロキシには対応しません。上限は DNS を含め合計20秒、最大16要求、応答ごとに16 MiB、HTTP OCSP 応答は1 MiBです。元画像のバイト列はアップロードしません。要求により接続先にクライアント IP アドレス、要求 URL や証明書の識別子が伝わります。Leica への OCSP 要求では、IP アドレスと証明書の識別子が Leica に伝わります。要求は暗号化されていない HTTP のため、ネットワークの中継者も証明書の識別子を見ることができます。

ローカルで修正し同梱した c2pa-rs 0.91.10 は、ライブ応答の署名、CertID、EKU を検証し、応答者が実際の署名者証明書の発行者に直接認可され、同梱の Leica 公式 C2PA ルートへ連鎖し、応答が現在有効な期間内であることを要求します。確定した Leica のライブ失効結果には、情報マーカー `org.musha.liveOcsp.good` または `org.musha.liveOcsp.revoked` が出力されます。オンライン確認の完了には、リーフ証明書の確定したライブ OCSP 結果と、必要なすべての非ルート発行者の確認結果が Good であることが必要です。AIA がない場合、発行者の応答が失敗または不明な場合、チェーンが途中で切れている場合は、リーフが Good でも確認は不完全です。マーカーがない場合、Leica のライブ失効状態は確認できません。要求の成功は試行したリソースに限られます。一般の C2PA 信頼リストは設定されず、`verify_trust=false` で、同梱 Leica ルートは Leica OCSP 応答者チェーンの認可にのみ使います。ライブ確認が成功しても全体の信頼状態は不明です。

EXIF解析器はマップを返すため同一キーが失われる場合があり、XMP、IPTC、ICC、MakerNote、未知タグを網羅しません。EXIFが空でも他のメタデータが存在しないとは限りません。画像の形式対応はFlutterとOSに依存します。通常の64 MiBを超える入力は拒否します。大きなプレビューのデコードには多くのメモリーが必要になる場合があります。RAWプレビューは別途抽出します。元ファイルのメタデータと検証には256 MiB以下のRAWスナップショットが必要で、データのコピーにより大幅に多いメモリーを使う場合があります。元ファイルは読み取り専用で開きます。設定JSONはmacOSのApplication Support、Linuxの`$XDG_CONFIG_HOME/musha-viewer`（未設定時`~/.config/musha-viewer`）、WindowsのLocalAppDataに保存します。破損または未知バージョンの設定は上書きせず保持します。

RAWプレビューはフルRAW現像ではありません。BigTIFFとJPEG以外の埋め込みプレビューは未対応で、機種別の互換性と実際のLeica DNGの検証は未確認です。埋め込みJPEGにEXIFの向きがない場合はRAWのTIFFの向きを適用し、抽出したTIFF ICCプロファイルは表示しますが個別には適用しません。Finderとの色・向きの比較とMac実機確認は残っています。詳細は[0.2.0実装メモ](docs/IMPLEMENTATION_0_2_0.md)を参照してください。

Apple Silicon向けテストビルドの取得方法は[macOSテスト成果物](docs/MACOS_ARTIFACTS.md)を参照してください。

管理ワークスペースでの分離したLinux開発環境は[ビューアー開発環境](docs/CLOUD_ENVIRONMENT.md)を参照してください。

ビルド前に[C2PAビルド手順](docs/C2PA_BUILD.md)に従ってネイティブエンジンを準備し、上記のFlutterコマンドを実行してください。macOSのビルド、Sandbox内でのファイル選択・ドロップ、Release起動、署名、公証、App Store配布は[リリース・実機確認リスト](docs/RELEASE_0_2_0.md)に沿った検証が必要です。Linuxランナーは開発用です。

## Design / 設計文書

The Japanese design documents describe the broader planned product. 設計文書には今後の目標を含みます。

- [Project policy / プロジェクト方針](docs/PROJECT_PLAN.md)
- [Architecture / アーキテクチャー](docs/ARCHITECTURE.md)
- [Metadata and C2PA / メタデータとC2PA](docs/METADATA_AND_C2PA.md)
- [Settings and platforms / 設定とプラットフォーム](docs/SETTINGS_AND_PLATFORMS.md)
- [Roadmap / ロードマップ](docs/ROADMAP.md)

## License / ライセンス

Project code is licensed under [Apache License 2.0](LICENSE). Third-party components retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md) and the locked dependency versions. 第三者依存関係にはそれぞれのライセンスが適用されます。
