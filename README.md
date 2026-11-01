# musha-viewer

## English

musha-viewer is a planned open-source image and video viewer that displays embedded metadata and checks C2PA Content Credentials. It uses Dart and Flutter, initially targeting macOS 27, with Windows, Ubuntu, iOS, iPadOS, and Android planned for later releases.

The desktop interface combines a main preview with a resizable right inspector containing a two-column key/value metadata list and a C2PA verification summary. The application is read-only: it will not edit the opened media files.

**Status:** design stage. This repository does not yet contain a Flutter application, runnable builds, or a verified format-support matrix. The documentation records agreed direction separately from dependencies and capabilities that still require evaluation.

### Design documents

The initial detailed design documents are in Japanese:

- [Project policy and initial scope](docs/PROJECT_PLAN.md)
- [Architecture and candidate technologies](docs/ARCHITECTURE.md)
- [Metadata and C2PA behavior](docs/METADATA_AND_C2PA.md)
- [Settings and platform integration](docs/SETTINGS_AND_PLATFORMS.md)
- [Roadmap and acceptance criteria](docs/ROADMAP.md)

### License

Project materials are licensed under the [Apache License 2.0](LICENSE). Future third-party dependencies retain their own licenses; their versions, build options, and redistribution requirements must be reviewed before adoption. No media parser or playback dependency has been selected or bundled yet.

## 日本語

musha-viewerは、画像・動画のプレビュー、埋め込みメタデータの表示、C2PA Content Credentialsの確認を行うオープンソースアプリケーションです。DartとFlutterを基盤とし、初版はmacOS 27を対象とします。将来はWindows、Ubuntu、iOS、iPadOS、Androidへの対応を予定しています。

デスクトップでは、メインのプレビューと、幅を変更できる右側のインスペクターを配置します。インスペクターにはキー・値の2列でメタデータを表示し、C2PAの検証結果を示します。閲覧専用であり、開いたメディアファイルを編集しません。

**現在の状態：設計段階です。** Flutterアプリケーション、実行可能なビルド、検証済みの対応形式表はまだありません。文書では合意済みの方針と、調査・検証が必要な依存関係や機能を区別しています。

### 設計文書

- [プロジェクト方針・初版の範囲](docs/PROJECT_PLAN.md)
- [アーキテクチャー・技術候補](docs/ARCHITECTURE.md)
- [メタデータ・C2PAの仕様](docs/METADATA_AND_C2PA.md)
- [設定・プラットフォーム対応](docs/SETTINGS_AND_PLATFORMS.md)
- [開発順序・受け入れ条件](docs/ROADMAP.md)

### ライセンス

本プロジェクトの成果物は[Apache License 2.0](LICENSE)で公開します。将来採用する第三者ライブラリには各ライセンスが適用されます。採用前にバージョン、ビルドオプション、再配布条件を確認します。現時点ではメディア解析・再生ライブラリを選定・同梱していません。
