#!/bin/bash
# Verify the built release app before producing an ad-hoc-signed test archive.
set -euo pipefail
app="build/macos/Build/Products/Release/musha-viewer.app"
exe="$app/Contents/MacOS/musha-viewer"
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
mkdir -p dist/macos-test
cp LICENSE THIRD_PARTY_NOTICES.md docs/MACOS_ARTIFACTS.md dist/macos-test/
python3 scripts/collect-native-licenses.py
archive="musha-viewer-macos-27-arm64-test.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/macos-test/$archive"
(cd dist/macos-test && shasum -a 256 "$archive" > SHA256SUMS.txt)
cat > dist/macos-test/BUILD-INFO.txt <<INFO
macOS 27 Apple Silicon release-mode test build
Commit: ${BUILD_COMMIT:-unknown}
Workflow: ${BUILD_RUN_URL:-local}
Signed ad hoc; not Developer ID signed or notarized.
Minimum macOS version: 27.0.
INFO
