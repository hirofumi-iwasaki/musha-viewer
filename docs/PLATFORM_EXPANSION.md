# Platform expansion assessment / プラットフォーム拡張の検討

## English

### Basis and limits

This assessment is based on checkout `b2e2cd8` (`release/0.2.0`) as inspected on 2026-11-04. It is a proposal, not a support announcement or a test report. Recheck the target release branch before implementation: later changes may alter these findings. The repository has Flutter Linux and macOS runners only. The Linux x86-64 development build and Xvfb startup are recorded in [the 0.2.0 implementation notes](IMPLEMENTATION_0_2_0.md); they do not establish a supported Linux distribution. The existing macOS workflow builds an ad-hoc-signed Apple Silicon test artifact for macOS 27; native-device validation, Developer ID signing and notarization are separate. No additional OS/CPU or camera model is certified here.

Shared prerequisites for every target: confirm Flutter/Dart, native Rust 1.96+ and plugin support for the **specific OS and architecture**, choose a minimum OS and distribution mechanism, build and package the locked C2PA library and its license notices, and test on the actual architecture. Preserve read-only input and offline verification; distinguish integrity, signature and unknown trust. CI builds and emulation alone do not prove device behavior. Estimates below are relative engineering effort, excluding unknown device availability, signing accounts, store review, and fixture acquisition.

### Suggested order and gaps

| Priority | Target | Relative effort | Main changes and unknowns |
| --- | --- | --- | --- |
| 1 | Linux x86-64 | Low–medium | Existing GTK runner and CMake bundle invoke `scripts/build-c2pa.sh` and install `libmusha_c2pa.so`. Define supported distributions, glibc/GTK baseline, packaging and portal/sandbox behavior; test X11 and Wayland, file chooser/drop, HiDPI and desktop integration. Existing x86-64 results are development evidence only. |
| 2 | Windows x64 | Medium | Generate/review a Windows runner and installer; add a Windows native build for Rust `cdylib`, C/C++/SDK prerequisites, DLL deployment and Windows-specific loading in `lib/c2pa.dart` (currently the non-macOS path assumes a Linux `.so`). Validate file picker/drop, path and Unicode behavior, window geometry, LocalAppData and atomic settings replacement. Decide code signing and distribution. |
| 3 | Intel macOS x86-64 | Medium, subject to toolchain availability | `scripts/build-c2pa.sh` names `x86_64-apple-darwin`, but the existing workflow and package validation explicitly require arm64. Check the selected Flutter/Xcode/macOS 27 SDK and runner/device combination actually supports the desired build and deployment; add a separate Intel or verified universal build, validate every executable and dylib architecture and signing. Never infer macOS 27 support on a particular Intel Mac from the Rust target alone. |
| 4 | Linux ARM64 | Medium–high | Verify Flutter engine, GTK and plugin availability on the chosen ARM64 distribution. Build native Cargo and Flutter artifacts for the same target; current Linux script builds for its host and fixed CMake output path, so cross-builds need explicit targets/sysroot and separate outputs. Test on native ARM64 hardware and chosen packaging baseline. Other Linux ARM variants are a separate investigation. |
| 5 | Windows ARM64 | High | Verify actual Flutter engine, all desktop plugins, Rust target, C/C++ toolchain and packaging support before promising a native build. Avoid mixing x64 and ARM64 DLLs; distinguish native execution from x64 emulation. Test on an ARM64 Windows device. If a dependency lacks native support, document the blocker and consider a separately labeled emulation experiment. |
| 6 | iOS / iPadOS | High | No iOS runner exists. Separate desktop-only window/display, drag/drop and shutdown assumptions from a mobile lifecycle and responsive touch UI; verify each plugin's platform support. Integrate Rust as an iOS-compatible library/framework and FFI with device/simulator architectures and signing. Use document-provider URLs and security-scoped access for their required lifetime rather than assuming a persistent local path; design folder navigation and permissions explicitly. Test real iPhone and iPad, provider access, low-memory behavior, lifecycle and release signing. |
| 7 | Android | High | No Android runner exists. Isolate desktop window/drop assumptions and provide responsive touch/lifecycle handling. Build/package Rust shared libraries per chosen Android ABI using an appropriate NDK and load them via Android-specific FFI; verify Flutter/plugin ABI support. Use the Storage Access Framework and content URIs, including transient/persisted grants and streaming/bounded snapshots, rather than treating a URI as a file path. Test actual devices, process recreation, memory limits and release packaging/signing. |

The exact order can change with user demand, hardware and SDK feasibility. In particular, ARM targets and Intel macOS must pass a toolchain feasibility check before scheduling implementation; no minimum OS or architecture support is inferred from this table. Mobile platforms require design work beyond adding a runner, and file-provider permissions must remain valid while asynchronous preview and verification run.

### Acceptance for each selected target

- Record device model, OS version, architecture, toolchain, dependency versions, distribution format and whether execution is native or emulated. Build a Release artifact, inspect native library architecture, and launch it without development tools.
- Exercise picker/provider permission, cancellation, denial and revocation; desktop drop and directory access where offered; source hash before/after operations to verify read-only behavior. Test navigation and permissions against the actual target branch and granted folder model.
- Test supported image formats and limits, malformed/oversized files, orientation and color behavior, partial failures, rapid file switching and bounded memory. Compare platform behavior with a trusted reference; document unsupported codecs and profiles.
- Run native tests and Flutter analysis/tests on the target where feasible. Verify signed and tampered C2PA fixtures, absent/unsupported/error cases, offline behavior with network unavailable, and unknown trust; independently verify original-file bytes are used when RAW verification is supported.
- Test settings persistence and recovery, lifecycle/background and low-memory behavior, accessibility, input modalities, window/display restoration where applicable, and distribution installation/update/removal. Confirm notices, checksums, signing and platform-specific release requirements. Record remaining untested cases; do not silently mark them supported.

### Camera models and RAW are a separate dimension

OS/CPU portability does not establish camera-format compatibility. The 0.2.0 implementation extracts embedded JPEG previews from bounded classic TIFF structures in DNG/NEF and routes original DNG bytes to the C2PA TIFF handler. BigTIFF and non-JPEG previews are unsupported; original-file verification and EXIF are limited to 256 MiB. Only synthetic fixtures have been validated, not representative real-camera files. Obtain permission-cleared, representative original files with model, firmware, format/compression and expected orientation/color metadata; include signed and altered examples where lawful and relevant. Start with the user's actual Leica DNG and Nikon NEF models and their common settings, then expand only from measured results. For each, test bounded embedded-preview extraction, missing/corrupt/oversized preview handling, dimensions/orientation/ICC, independent verification of original DNG bytes and offline C2PA state. Do not equate an embedded preview with developed RAW or claim all models/compression modes work. Keep private originals and location/identity metadata out of public fixtures unless explicitly authorized.

## 日本語

### 調査の前提

この検討は 2026-11-04 に確認した `b2e2cd8`（`release/0.2.0`）のチェックアウトに基づく提案であり、対応表や試験報告ではありません。実装前に対象リリースブランチを再確認してください。現リポジトリの Flutter ランナーは Linux と macOS のみです。[0.2.0 実装記録](IMPLEMENTATION_0_2_0.md) に記録された Linux x86-64 の開発ビルドと Xvfb 起動は、特定ディストリビューションの正式対応を意味しません。既存 macOS ワークフローは macOS 27 向け Apple Silicon のアドホック署名テスト成果物を作ります。実機検証、Developer ID 署名、公証は別途必要です。ここでは追加の OS・CPU やカメラ機種の対応を保証しません。

全対象で、対象 OS・CPU ごとの Flutter/Dart、Rust 1.96 以降、プラグイン対応、最低 OS、配布方法、固定された C2PA ライブラリーとライセンス通知を確認し、実機で試験します。元データの読み取り専用とオフライン検証を守り、整合性・署名・不明な信頼状態を分けます。CI やエミュレーションだけでは実機動作を保証できません。以下は相対工数で、実機・署名アカウント・ストア審査・検証用画像の調達期間を含みません。

### 推奨順と差分

| 順位 | 対象 | 相対工数 | 主な作業と未確定事項 |
| --- | --- | --- | --- |
| 1 | Linux x86-64 | 小〜中 | GTK ランナーと CMake バンドル、`scripts/build-c2pa.sh` による `libmusha_c2pa.so` 組み込みは存在します。対象ディストリビューション、glibc・GTK の基準、配布方式、ポータル・Sandboxを決め、X11/Wayland、選択・ドロップ、HiDPI、デスクトップ統合を検証します。既存結果は開発環境の証拠です。 |
| 2 | Windows x64 | 中 | Windows ランナーとインストーラーを整備し、Rust `cdylib` のビルド、C/C++・SDK、DLL 同梱と `lib/c2pa.dart` の Windows 用ロードを追加します（現状の macOS 以外の分岐は Linux の `.so` を前提）。選択・ドロップ、パスと Unicode、ウィンドウ、LocalAppData、設定の置換、署名と配布を検証します。 |
| 3 | Intel macOS x86-64 | 中。ただし SDK の成立が前提 | `scripts/build-c2pa.sh` に `x86_64-apple-darwin` の指定はありますが、既存ワークフローとパッケージ検査は arm64 専用です。選択する Flutter・Xcode・macOS 27 SDK と実機でビルド・実行が成立するか先に確認し、Intel 単体または検証済み universal ビルドの各実行ファイル・dylib・署名を調べます。Rust ターゲットの存在から特定 Intel Mac の macOS 27 対応を推定しません。 |
| 4 | Linux ARM64 | 中〜大 | 対象 ARM64 ディストリビューションで Flutter エンジン、GTK、プラグインの利用可否を確認します。Cargo と Flutter を同じターゲット向けにビルドします。現 Linux スクリプトはホスト向けビルドと固定出力先のため、クロスビルドにはターゲット・sysroot・出力分離が必要です。ARM64 実機と配布基準で検証します。他の ARM は別途調査します。 |
| 5 | Windows ARM64 | 大 | Flutter エンジン、全デスクトッププラグイン、Rust ターゲット、C/C++ ツールチェーン、パッケージングのネイティブ対応を先に確認します。x64 と ARM64 の DLL 混在を避け、ネイティブ実行と x64 エミュレーションを区別し、ARM64 実機で検証します。依存が未対応なら阻害要因を記録し、エミュレーションを試す場合は別物として表示します。 |
| 6 | iOS / iPadOS | 大 | iOS ランナーはありません。デスクトップ用ウィンドウ・画面・ドロップ・終了処理をモバイルのライフサイクルとタッチ UI から分離し、プラグイン対応を確認します。実機・シミュレーターの各アーキテクチャー向け Rust ライブラリー／framework、FFI と署名を整備します。ドキュメントプロバイダーの URL と必要期間の security-scoped access を使い、永続パスを前提にせず、フォルダー移動と権限を設計します。iPhone・iPad 実機、プロバイダー、メモリー不足、ライフサイクル、Release 署名を確認します。 |
| 7 | Android | 大 | Android ランナーはありません。デスクトップ依存を分離し、画面・タッチ・ライフサイクルに対応します。対象 ABI ごとに NDK で Rust 共有ライブラリーを作成・同梱し、Android 向け FFI ロードと Flutter・プラグイン対応を確認します。Storage Access Framework の content URI、権限の寿命と永続化、ストリーミング／上限付き読み取りを扱い、URI をローカルパスと見なしません。実機、プロセス再生成、メモリー制限、Release 配布と署名を確認します。 |

順序は需要、実機、SDK の成立性によって変わります。ARM と Intel macOS は実装前にツールチェーンの成立性を確認します。モバイルはランナー追加だけで完了せず、非同期プレビューと検証中もプロバイダー権限を維持する設計が必要です。

### 各対象の受け入れ条件

- 実機名、OS、CPU、ツールチェーン、依存バージョン、配布形式、ネイティブ／エミュレーションを記録する。Release 成果物とネイティブライブラリーのアーキテクチャーを調べ、開発ツールなしで起動する。
- 選択・プロバイダー権限、キャンセル、拒否、失効、対象となるデスクトップのドロップとフォルダーアクセスを確認する。操作前後の元ファイルハッシュを照合し、対象ブランチのナビゲーションと権限を試験する。
- 対応画像、サイズ制限、破損・巨大ファイル、向き・色、部分失敗、高速切り替え、メモリー上限を試す。信頼できる比較対象と照合し、未対応コーデックやプロファイルを記録する。
- 対象で可能なネイティブテスト、Flutter 解析・テストを実行する。署名済み・改変済み C2PA、未検出・未対応・エラー、ネットワークなし、信頼不明を確認する。RAW 検証対応時は元ファイルのバイトが使われることを独立に確認する。
- 設定の保存・復旧、ライフサイクル・低メモリー、アクセシビリティ、入力手段、必要なウィンドウ復元、インストール・更新・削除を試す。通知、チェックサム、署名、各 OS の配布要件を確認し、未試験項目を明記する。

### カメラ機種・RAW は別の検討軸

OS・CPU に移植できてもカメラ形式に対応したことにはなりません。0.2.0 は DNG/NEF の classic TIFF 構造から上限付きで埋め込み JPEG を抽出し、元 DNG のバイト列を C2PA の TIFF ハンドラーに渡します。BigTIFF と JPEG 以外のプレビューは未対応で、元ファイルの検証・EXIF は 256 MiB 以下に制限されます。合成データのみを検証しており、代表的な実機画像は未確認です。利用許諾のある代表的な元ファイルと、機種・ファームウェア・形式／圧縮・期待される向きと色の情報を用意します。適法かつ必要な範囲で署名済み・改変済み例も用意します。まずユーザーの Leica DNG・Nikon NEF の実機種と一般的な設定から調べ、実測に応じて拡大します。機種ごとに、上限付き埋め込みプレビュー抽出、欠落・破損・巨大プレビュー、寸法・向き・ICC、元 DNG の独立検証とオフライン C2PA 状態を確認します。埋め込みプレビューを RAW 現像と同一視せず、全機種・全圧縮方式の対応を保証しません。明示的な許可なく私有原本や位置・人物情報を公開テストデータに含めません。
