# musha-viewer

## English

musha-viewer is a read-only Flutter image viewer with a preview and a key/value metadata inspector. This first implementation targets macOS 27; the Linux runner is included for development. macOS build, sandbox access, and release execution have **not yet been verified on a Mac**.

Choose **Open image** to select a file, then use the trackpad or mouse to pan and zoom. **Fit** resets the view. The inspector displays filesystem information, decoded image dimensions, and EXIF tags returned by the parser. Preview, filesystem information, and EXIF report errors separately where possible. C2PA verification is not implemented and the inspector explicitly reports it as unavailable. Video, drag and drop, Finder opening, persistent settings, and inspector resizing are not implemented.

The picker offers common image extensions, but an extension is not a support guarantee: decoding depends on Flutter and the platform. The EXIF package returns a map, so tags with identical keys may be lost by that parser; it does not provide comprehensive XMP, IPTC, ICC, MakerNote, or unknown-tag coverage. An empty EXIF result does not establish that a file contains no metadata. Files over 64 MiB are rejected for preview and embedded metadata, though filesystem information can still appear. Images over 40 megapixels are also rejected before preview decoding; this limit does not strictly cap decoded memory. The app reads a snapshot without writing to the source file; it does not watch for changes while viewing.

### Build and test

With Flutter 3.47.4 and Dart 3.13.3, on a Mac with an Xcode version and SDK supporting the macOS 27 deployment target:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter build macos --release
```

The generated macOS runner enables App Sandbox and user-selected read-only file access. Its bundle identifier `org.musha.mushaViewer` is provisional; configure a suitable identifier and signing before distribution. No signed, notarized, or App Store build has been validated. Linux builds require Flutter's Linux desktop dependencies; Linux is a development runner, not a verified release target.

## 日本語

musha-viewerは、画像のプレビューとキー・値形式のメタデータ表示を行う閲覧専用のFlutterアプリです。この最初の実装はmacOS 27を対象とし、開発用にLinuxランナーも含みます。**macOSでのビルド、Sandbox権限、Release起動は実機未検証です。**

**Open image**でファイルを選択し、トラックパッドやマウスで移動・拡大縮小できます。**Fit**で表示を戻します。インスペクターはファイル情報、デコード後の画像寸法、解析器が返したEXIFタグを表示します。可能な範囲でプレビュー、ファイル情報、EXIFのエラーを個別に表示します。C2PA検証は未実装であり、画面に利用不可と表示します。動画、ドラッグ＆ドロップ、Finderから開く操作、設定保存、インスペクターの幅変更は未実装です。

選択画面には一般的な画像拡張子を表示しますが、対応は保証せず、デコードはFlutterとOSに依存します。EXIFパッケージはマップを返すため、同一キーのタグが解析時に失われる場合があります。XMP、IPTC、ICC、MakerNote、未知タグの網羅的な取得には対応していません。EXIFが空でも、他のメタデータが存在しないとは限りません。64 MiBを超えるファイルはプレビューと埋め込み情報の読込を拒否しますが、ファイル情報は表示できる場合があります。さらに、4000万画素を超える画像はプレビューのデコード前に拒否しますが、デコード後のメモリー使用量を厳密に制限するものではありません。元ファイルは書き換えず、読み込んだ時点の内容を表示します。

### ビルドとテスト

Flutter 3.47.4 / Dart 3.13.3と、macOS 27のデプロイメントターゲットをサポートするXcode・SDKを用意し、上記のコマンドを実行してください。macOSランナーではApp Sandboxとユーザーが選択したファイルの読み取り専用権限を有効にしています。Bundle ID `org.musha.mushaViewer` は仮の値です。配布前に適切なIDと署名を設定してください。署名、公証、App Store向けビルドはいずれも未検証です。Linuxランナーは開発用であり、リリース対象としての検証は行っていません。

## Design / 設計文書

The Japanese documents describe the broader planned product; features listed there are goals, not claims about the current implementation. 以下の設計文書は将来の目標を含み、実装済み機能の一覧ではありません。

- [Project policy / プロジェクト方針](docs/PROJECT_PLAN.md)
- [Architecture / アーキテクチャー](docs/ARCHITECTURE.md)
- [Metadata and C2PA / メタデータとC2PA](docs/METADATA_AND_C2PA.md)
- [Settings and platforms / 設定とプラットフォーム](docs/SETTINGS_AND_PLATFORMS.md)
- [Roadmap / ロードマップ](docs/ROADMAP.md)

## License / ライセンス

Project code is licensed under [Apache License 2.0](LICENSE). Direct runtime dependencies include `file_selector` 1.1.0 (BSD 3-Clause) and `exif` 3.3.0 (MIT); Flutter itself is BSD 3-Clause. Exact resolved versions are in [pubspec.lock](pubspec.lock). Flutter bundles dependency license texts in its license registry; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for further details. 第三者依存関係にはそれぞれのライセンスが適用されます。
