#!/bin/sh
# Builds this fork's unsigned, ad-hoc-signed Intel (x86_64) Hex.app and DMG
# on this Mac. Run from a checkout of `intel`:
#
#   scripts/build-intel-local.sh
#
# Output:
#   dist/hex-<version>-macos-x64.dmg   installable (drag Hex.app to Applications)
#   dist/hex-<version>-macos-x64.zip   zipped app
#
# Requirements:
#   - an Intel Mac (this fork's Intel build is x86_64 only);
#   - full Xcode 26 or newer (Hex builds against the macOS 26 SDK, which ships
#     SpeechAnalyzer/SpeechTranscriber and FoundationModels; Command Line Tools
#     alone are not enough), selected with `sudo xcode-select -s /Applications/Xcode.app`;
#   - a Rust toolchain (`rustup`).
#
# The app never checks for updates: upstream's release service only carries
# arm64 builds. To update, sync the fork and rebuild.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/scripts/macos-signing.sh"

fail() {
  echo "$*" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "This script builds a macOS app; run it on macOS."
[ "$(uname -m)" = x86_64 ] || fail "This script builds the Intel app; this Mac reports $(uname -m)."
command -v cargo >/dev/null 2>&1 || fail "Rust is not installed. Install it with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
command -v jq >/dev/null 2>&1 || fail "jq is required (brew install jq)."
command -v xcrun >/dev/null 2>&1 || fail "Xcode is not installed."

sdk=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)
[ -n "$sdk" ] || fail "No macOS SDK found. Install Xcode 26 or newer and run: sudo xcode-select -s /Applications/Xcode.app"
sdk_major=${sdk%%.*}
if [ "$sdk_major" -lt 26 ]; then
  fail "Hex builds against the macOS 26 SDK, but this Mac has SDK $sdk. Install Xcode 26 (the Universal build runs on Intel Macs) and run: sudo xcode-select -s /Applications/Xcode.app"
fi
if ! xcrun --sdk macosx actool --version >/dev/null 2>&1; then
  fail "actool is missing; install full Xcode 26 (Command Line Tools alone are not enough)."
fi

version=$(hex_version "$root")
build_number=$(hex_build_number "$version")
dist="$root/dist"
dmg="$dist/hex-$version-macos-x64.dmg"
zip="$dist/hex-$version-macos-x64.zip"

echo "Building Hex $version ($build_number) for Intel macOS with SDK $sdk" >&2
export HEX_VERSION="$version" HEX_BUILD_NUMBER="$build_number"
export HEX_INTEL_BUILD=1
export HEX_RELEASE_UNSIGNED=1

bundle=$("$root/scripts/build-app.sh")
archs=$(lipo -archs "$bundle/Contents/MacOS/hex")
[ "$archs" = x86_64 ] || fail "Built executable is $archs, not x86_64."
codesign --verify --deep --strict "$bundle" || fail "The built app does not verify."
# The bundled audio driver is universal and the Intel app only runs on macOS
# 15+, which the default deployment target and Info.plist already express.
plutil -extract LSMinimumSystemVersion raw "$bundle/Contents/Info.plist" >/dev/null || fail "Info.plist is missing LSMinimumSystemVersion."

stage=$(mktemp -d "${TMPDIR:-/tmp}/hex-intel-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT INT TERM
/usr/bin/ditto "$bundle" "$stage/Hex.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$dist"
rm -f "$dmg" "$zip"
hdiutil create -quiet -fs HFS+ -format UDZO -volname "Hex" -srcfolder "$stage" "$dmg" >/dev/null
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$bundle" "$zip"
# Relative names, so `shasum -a 256 -c SHA256SUMS` works from dist/.
( cd "$dist" && shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" >SHA256SUMS )

echo
echo "Built Intel Hex $version:"
echo "  $dmg"
echo "  $zip"
echo
echo "Install: open the DMG, drag Hex.app to Applications, then right-click"
echo "Hex.app -> Open the first time (the build is ad-hoc signed, not notarized)."
