# musha-viewer

## English

musha-viewer is a read-only Flutter image viewer for macOS 27. Open or drop one image to inspect a preview, file information, decoded dimensions, EXIF tags, and an offline C2PA verification result. Use the inspector toggle and divider to change the layout, and the appearance menu for system, light, or dark theme. Window position, normal size, maximized state, inspector preferences, and theme are saved locally. DNG and NEF can show an embedded JPEG preview; select a folder to navigate supported images in natural filename order. Fit and 100% controls are available. Video, Finder “Open With”, and file history are not implemented.

C2PA verification is performed by c2pa-rs without network access. Presence, parsing, asset integrity, claim integrity, signature, trust and SDK validation are shown separately, with SDK details available in the inspector. The default configuration has no trust list; trust is unknown and a valid signature does not establish that depicted events are true. Unsupported files, remote credentials, errors, and absent credentials are distinct states. Preview and metadata remain usable if verification fails or the native library is unavailable.

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

musha-viewerはmacOS 27を対象とする閲覧専用Flutter画像ビューアーです。画像を選択または一つドロップすると、プレビュー、ファイル情報、デコード後の寸法、EXIF、オフラインのC2PA検証結果を表示します。インスペクターの表示・幅、システム／ライト／ダークのテーマ、通常時のウィンドウ位置・大きさ、最大化状態は保存されます。DNG・NEFは埋め込みJPEGプレビューを表示でき、フォルダーを選ぶと対応画像をファイル名の自然順で移動できます。画面に合わせる表示と100%表示も利用できます。動画、Finderの「このアプリケーションで開く」、履歴は未実装です。

C2PAはc2pa-rsでネットワーク接続せず検証します。存在・解析、アセットとクレームの整合性、署名、信頼、SDK検証状態を別々に表示し、詳細も確認できます。既定では信頼リストがなく信頼状態は不明です。有効な署名は撮影内容の真実性を保証しません。未対応、外部参照、エラー、未検出は区別します。検証やネイティブライブラリの読込が失敗してもプレビューとメタデータは利用できます。

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
