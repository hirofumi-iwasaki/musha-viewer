#!/bin/bash
# Verify the built release app before producing an ad-hoc-signed test archive.
set -euo pipefail
app="build/macos/Build/Products/Release/Musha Viewer.app"
exe="$app/Contents/MacOS/Musha Viewer"
dylib="$app/Contents/Frameworks/libmusha_c2pa.dylib"
test -d "$app"
test -f "$exe"
test -f "$dylib"
for binary in "$exe" "$dylib"; do
  archs="$(lipo -archs "$binary")"
  echo "$binary: $archs"
  [[ "$archs" == arm64 ]]
done
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$dylib"
signature="$(codesign -dvv "$app" 2>&1)"
printf '%s\n' "$signature"
grep -q 'Signature=adhoc' <<< "$signature"
entitlements="$(mktemp "${TMPDIR:-/tmp}/musha-entitlements.XXXXXX")"
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
for entitlement in com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only com.apple.security.files.bookmarks.app-scope com.apple.security.network.client; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$entitlements")" == true ]]
done
# Stage the app and its required notices together. ditto preserves bundle
# permissions and symlinks, which artifact upload's normal ZIP does not.
staging="dist/macos-test"
archive="dist/musha-viewer-macos-27-arm64-test.zip"
rm -rf "$staging"
mkdir -p "$staging/Licenses"
ditto "$app" "$staging/Musha Viewer.app"
cp LICENSE THIRD_PARTY_NOTICES.md "$staging/Licenses/"
python3 scripts/collect-native-licenses.py --output "$staging/Licenses/THIRD_PARTY_LICENSES"
rm -f "$archive"
ditto -c -k --sequesterRsrc "$staging" "$archive"
# Check the archive itself, including the app signature after extraction.
inspection="$(mktemp -d "${TMPDIR:-/tmp}/musha-package.XXXXXX")"
trap 'rm -f "$entitlements"; rm -rf "$inspection"' EXIT
ditto -x -k "$archive" "$inspection"
test -f "$inspection/Musha Viewer.app/Contents/MacOS/Musha Viewer"
test -f "$inspection/Licenses/LICENSE"
test -f "$inspection/Licenses/THIRD_PARTY_NOTICES.md"
test -f "$inspection/Licenses/THIRD_PARTY_LICENSES/INDEX.md"
codesign --verify --deep --strict --verbose=2 "$inspection/Musha Viewer.app"
shasum -a 256 "$archive"
