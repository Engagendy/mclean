#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="MClean"
APP_BUNDLE="MClean.app"
BUNDLE_ID="com.engagendy.MClean"
SCHEME="MClean"
XCODEPROJ="$PROJECT_ROOT/MClean.xcodeproj"
VERSION="1.0.0"
ARCH="$(uname -m)"

BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
DMG_DIR="$BUILD_DIR/dmg"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
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
echo "  MClean - Build & Package"
echo "  Version: $VERSION"
echo "  Architecture: $ARCH"
echo "==========================================================="

mkdir -p "$BUILD_DIR"

if [[ ! -d "$XCODEPROJ" ]]; then
    echo "ERROR: $XCODEPROJ not found. Run: xcodegen generate"
    exit 1
fi

echo "-> Building native SwiftUI app with Xcode"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
if ! xcodebuild -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -arch "$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
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

echo "-> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "-> Creating DMG"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

DMG_PATH="$BUILD_DIR/MClean-$VERSION-$DMG_ARCH.dmg"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1 | tail -2

echo "OK DMG created: $DMG_PATH"
