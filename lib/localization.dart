import 'package:flutter/material.dart';

/// Translate application-owned text; file paths, EXIF values and SDK diagnostics
/// are preserved as supplied by their source.
String tr(BuildContext context, String text) {
  if (Localizations.maybeLocaleOf(context)?.languageCode != 'ja') return text;
  const translations = <String, String>{
    'Invalid RAW TIFF offset or length.': 'RAW TIFFのオフセットまたは長さが無効です。',
    'Truncated RAW file.': 'RAWファイルが途中で切れています。',
    'Invalid RAW TIFF header.': 'RAW TIFFヘッダーが無効です。',
    'Unsupported RAW TIFF format.': '対応していないRAW TIFF形式です。',
    'RAW contains too many TIFF directories.': 'RAWに含まれるTIFFディレクトリが多すぎます。',
    'RAW TIFF directory is too large.': 'RAW TIFFディレクトリが大きすぎます。',
    'No valid embedded JPEG preview found in RAW file.':
        'RAWファイルに有効な埋め込みJPEGプレビューがありません。',
    'Some information was unavailable.': '一部の情報を取得できませんでした。',
    'Images': '画像',
    'Previous image': '前の画像',
    'Next image': '次の画像',
    'Authorize folder': 'フォルダーを許可',
    'Open image': '画像を開く',
    'Toggle inspector': 'インスペクターの表示切替',
    'Appearance': '外観',
    'system': 'システム設定',
    'light': 'ライト',
    'dark': 'ダーク',
    'Drop one image': '画像を1つドロップ',
    'Fit': '画面に合わせる',
    'Open an image to begin': '画像を開いてください',
    'Content Credentials (C2PA)': 'コンテンツ認証情報（C2PA）',
    'Metadata': 'メタデータ',
    'No image selected.': '画像が選択されていません。',
    'Online verification': 'オンライン検証',
    'Verify online': 'オンラインで検証',
    'Verifying online…': 'オンラインで検証中…',
    'Online verification incomplete': 'オンライン検証が完了していません',
    'Verification details': '検証の詳細',
    'Online verification details': 'オンライン検証の詳細',
    'Offline verification: no online lookup': 'オフライン検証：オンライン照会なし',
    'Select an image to verify.': '検証する画像を選択してください。',
    'Verifying…': '検証中…',
    'Offline verification': 'オフライン検証',
    'Offline verification of original file': '元ファイルのオフライン検証',
    'Reading EXIF…': 'EXIFを読み込み中…',
    'No EXIF tags returned by the parser.': 'EXIFタグが見つかりませんでした。',
    'EXIF unavailable because the file could not be read.':
        'ファイルを読み込めなかったためEXIFを取得できません。',
    'Verification unavailable because the file could not be read.':
        'ファイルを読み込めなかったため検証できません。',
    'Online verification in progress…': 'オンライン検証中…',
    'Live Leica revocation check: revoked; trust remains unknown':
        'Leicaの失効確認：失効済み。信頼性は不明です',
    'Live certificate revocation check passed; overall trust remains unknown':
        '証明書の失効確認に成功しました。全体の信頼性は不明です',
    'Requested network resources retrieved; trust and revocation remain unconfirmed':
        'ネットワークリソースを取得しました。信頼性と失効状態は未確認です',
    'No supported images in this folder.': 'このフォルダーに対応画像はありません。',
    'Folder access unavailable. Use Authorize folder to navigate adjacent images.':
        'フォルダーにアクセスできません。前後の画像を見るにはフォルダーを許可してください。',
    'Drop one image file; folders and multiple files are not supported.':
        '画像ファイルを1つドロップしてください。フォルダーや複数ファイルには対応していません。',
    'Settings version is unsupported; the original file will be preserved.':
        '設定のバージョンに対応していません。元のファイルは保持されます。',
    'Settings could not be read; the original file will be preserved.':
        '設定を読み込めませんでした。元のファイルは保持されます。',
    'File': 'ファイル',
    'Name': '名前',
    'Size': 'サイズ',
    'Modified': '更新日時',
    'Image': '画像',
    'Decoded dimensions': '画像の寸法',
    'Preview source': 'プレビューのソース',
    'Decoded preview dimensions': 'プレビューの寸法',
    'Platform preview (may be downsampled)': 'プラットフォームプレビュー（縮小される場合があります）',
    'Preview': 'プレビュー',
    'TIFF orientation': 'TIFFの向き',
    'TIFF ICC profile': 'TIFF ICCプロファイル',
    'Embedded RAW JPEG (not developed RAW)': 'RAWに埋め込まれたJPEG（現像済みRAWではありません）',
    'Not present or unsupported': 'なし、または非対応',
    'Present; not applied separately': 'あり（個別には適用されません）',
    'present': 'あり',
    'absent': 'なし',
    'not detected': '検出されませんでした',
    'remote reference': 'リモート参照',
    'completed': '完了',
    'no embedded manifest found': '埋め込みマニフェストなし',
    'remote manifest not fetched': 'リモートマニフェスト未取得',
    'unsupported format': '非対応の形式',
    'failed': '失敗',
    'unknown': '不明',
    'Valid': '有効',
    'Invalid': '無効',
    'valid': '有効',
    'invalid': '無効',
    'verified': '検証済み',
    'unverified': '未検証',
    'trusted': '信頼済み',
    'untrusted': '信頼されていません',
    'good': '正常',
    'revoked': '失効済み',
  };
  final exact = translations[text];
  if (exact != null) return exact;
  const prefixes = <String, String>{
    'Could not open folder: ': 'フォルダーを開けませんでした：',
    'Could not open dropped file: ': 'ドロップされたファイルを開けませんでした：',
    'Could not open file picker: ': 'ファイル選択画面を開けませんでした：',
    'Image display failed: ': '画像を表示できませんでした：',
    'Image preview unavailable: ': '画像プレビューを表示できません：',
    'Embedded RAW preview unavailable: ': '埋め込みRAWプレビューを表示できません：',
    'Could not read image: ': '画像を読み込めませんでした：',
    'File information unavailable: ': 'ファイル情報を取得できません：',
    'EXIF could not be read: ': 'EXIFを読み込めませんでした：',
    'EXIF unavailable: ': 'EXIFを取得できません：',
    'Verification unavailable: ': '検証できません：',
    'Original file verification unavailable: ': '元ファイルを検証できません：',
    'Online check unavailable: ': 'オンライン確認を実行できません：',
    'Online check incomplete: ': 'オンライン確認が完了していません：',
    'Settings are unavailable: ': '設定を利用できません：',
    'Window restoration unavailable: ': 'ウィンドウを復元できません：',
    'Window settings unavailable: ': 'ウィンドウ設定を利用できません：',
    'Could not save settings: ': '設定を保存できませんでした：',
    'Credentials: ': '認証情報：',
    'Parsing: ': '解析：',
    'Asset integrity: ': 'アセットの整合性：',
    'Claim integrity: ': 'クレームの整合性：',
    'SDK validation: ': 'SDKの検証：',
    'Signature: ': '署名：',
    'Trust: ': '信頼性：',
    'Online request attempts: ': 'オンラインリクエスト試行回数：',
    'Requested hosts (may not have been contacted): ':
        '要求したホスト（接続されていない場合があります）：',
    'Online credentials: ': 'オンライン認証情報：',
    'Online asset integrity: ': 'オンラインアセットの整合性：',
    'Online claim integrity: ': 'オンラインクレームの整合性：',
    'Embedded/local SDK validation: ': '埋め込み／ローカルSDKの検証：',
    'Online signature: ': 'オンライン署名：',
    'Online trust: ': 'オンライン信頼性：',
    'Online error: ': 'オンラインエラー：',
    'Online code: ': 'オンラインコード：',
    'Error: ': 'エラー：',
    'Code: ': 'コード：',
  };
  for (final entry in prefixes.entries) {
    if (text.startsWith(entry.key)) {
      final value = text.substring(entry.key.length);
      const trustSuffix = ' (no general C2PA trust list configured)';
      if (value.endsWith(trustSuffix)) {
        final status = value.substring(0, value.length - trustSuffix.length);
        return '${entry.value}${translations[status] ?? status}（一般的なC2PA信頼リストは未設定）';
      }
      return '${entry.value}${tr(context, value)}';
    }
  }
  if (text.endsWith(' bytes')) {
    return '${text.substring(0, text.length - 6)} バイト';
  }
  if (text.endsWith(' pixels')) {
    return '${text.substring(0, text.length - 7)} ピクセル';
  }
  return text;
}
