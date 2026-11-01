#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repo_dir/native/c2pa/Cargo.toml"
PATH="$HOME/.cargo/bin:$PATH"
export PATH
: "${CARGO:=cargo}"
case "$(uname -s)" in
  Linux)
    "$CARGO" build --locked --release --target-dir "$repo_dir/native/c2pa/target" --manifest-path "$manifest"
    ;;
  Darwin)
    # Xcode supplies ARCHS. Build each architecture explicitly for universal apps.
    architectures=${ARCHS:-$(uname -m)}
    set --
    for arch in $architectures; do
      case "$arch" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;;
      esac
      MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-27.0} "$CARGO" build --locked --release --target "$target" --target-dir "$repo_dir/native/c2pa/target" --manifest-path "$manifest"
      set -- "$@" "$repo_dir/native/c2pa/target/$target/release/libmusha_c2pa.dylib"
    done
    mkdir -p "$repo_dir/native/c2pa/target/macos"
    lipo -create "$@" -output "$repo_dir/native/c2pa/target/macos/libmusha_c2pa.dylib"
    install_name_tool -id @rpath/libmusha_c2pa.dylib "$repo_dir/native/c2pa/target/macos/libmusha_c2pa.dylib"
    ;;
  *) echo "Unsupported build host" >&2; exit 1 ;;
esac
