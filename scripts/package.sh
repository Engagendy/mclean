#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="theMClean"
APP_BUNDLE="theMClean.app"
BUNDLE_ID="com.engagendy.MClean"
SCHEME="MClean"
XCODEPROJ="$PROJECT_ROOT/MClean.xcodeproj"
VERSION="1.0.11"
ARCH="$(uname -m)"
SIGN_APP=0
NOTARIZE_DMG=0
SIGN_IDENTITY="${MCLEAN_CODE_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${MCLEAN_NOTARY_PROFILE:-}"
DIRECT_ENTITLEMENTS="$PROJECT_ROOT/MClean/Resources/MCleanDirect.entitlements"

BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
DMG_DIR="$BUILD_DIR/dmg"

usage() {
    cat <<EOF
Usage: ./scripts/package.sh [options]

Options:
  --arch arm64|x86_64          Build architecture. Defaults to current machine.
  --version X.Y.Z              Version written into the app and DMG name.
  --sign                       Sign the app with Developer ID Application.
  --identity NAME              Code signing identity. Defaults to
                               "Developer ID Application" or MCLEAN_CODE_SIGN_IDENTITY.
  --notarize                   Submit and staple the DMG with notarytool.
  --notary-profile NAME        notarytool keychain profile. Can also be set with
                               MCLEAN_NOTARY_PROFILE.
  -h, --help                   Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --sign) SIGN_APP=1; shift ;;
        --identity) SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize) SIGN_APP=1; NOTARIZE_DMG=1; shift ;;
        --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) DMG_ARCH="$ARCH" ;;
    aarch64) ARCH="arm64"; DMG_ARCH="arm64" ;;
    amd64) ARCH="x86_64"; DMG_ARCH="x86_64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "==========================================================="
echo "  theMClean - Build & Package"
echo "  Version: $VERSION"
echo "  Architecture: $ARCH"
if [[ "$SIGN_APP" -eq 1 ]]; then
    echo "  Signing: $SIGN_IDENTITY"
else
    echo "  Signing: ad-hoc"
fi
if [[ "$NOTARIZE_DMG" -eq 1 ]]; then
    echo "  Notarization profile: $NOTARY_PROFILE"
fi
echo "==========================================================="

mkdir -p "$BUILD_DIR"

if [[ ! -d "$XCODEPROJ" ]]; then
    echo "ERROR: $XCODEPROJ not found. Run: xcodegen generate"
    exit 1
fi

echo "-> Building native SwiftUI app with Xcode"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
XCODEBUILD_SIGNING_ARGS=(
    CODE_SIGN_IDENTITY="-"
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
)

if ! xcodebuild -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -arch "$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    "${XCODEBUILD_SIGNING_ARGS[@]}" \
    MARKETING_VERSION="$VERSION" \
    clean build >"$BUILD_LOG" 2>&1; then
    echo "xcodebuild failed. Matching error lines:"
    grep -nE "error:|SwiftCompile|CompileSwift" "$BUILD_LOG" | tail -80 || true
    echo ""
    tail -200 "$BUILD_LOG"
    exit 1
fi

APP_DIR="$(find "$DERIVED_DATA_DIR" -name "$APP_BUNDLE" -type d | head -1)"
if [[ -z "$APP_DIR" || ! -d "$APP_DIR" ]]; then
    echo "ERROR: $APP_BUNDLE not found in build output."
    exit 1
fi
CONTENTS_DIR="$APP_DIR/Contents"

echo "-> Writing bundle metadata"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION//./}" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"

echo "-> Creating DMG staging folder"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
DIST_APP_DIR="$DMG_DIR/$APP_BUNDLE"

if [[ "$SIGN_APP" -eq 1 ]]; then
    if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
        echo "ERROR: Code signing identity not found: $SIGN_IDENTITY"
        echo "Install a Developer ID Application certificate in Xcode, or pass --identity."
        exit 1
    fi

    echo "-> Developer ID signing"
    codesign \
        --force \
        --deep \
        --timestamp \
	        --options runtime \
	        --entitlements "$DIRECT_ENTITLEMENTS" \
	        --sign "$SIGN_IDENTITY" \
	        "$DIST_APP_DIR" >/dev/null
	    codesign --verify --deep --strict --verbose=2 "$DIST_APP_DIR"
	    spctl --assess --type execute --verbose=2 "$DIST_APP_DIR" || true
else
    echo "-> Ad-hoc signing"
    codesign --force --deep --sign - "$DIST_APP_DIR" >/dev/null
fi
echo "-> Creating DMG"
DMG_PATH="$BUILD_DIR/theMClean-$VERSION-$DMG_ARCH.dmg"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1 | tail -2

if [[ "$SIGN_APP" -eq 1 ]]; then
    echo "-> Signing DMG"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE_DMG" -eq 1 ]]; then
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "ERROR: --notary-profile or MCLEAN_NOTARY_PROFILE is required for notarization."
        echo "Create one with: xcrun notarytool store-credentials mclean-notary --apple-id EMAIL --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD"
        exit 1
    fi

    echo "-> Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "-> Stapling DMG"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo "OK DMG created: $DMG_PATH"
