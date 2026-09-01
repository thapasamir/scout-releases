#!/usr/bin/env bash
# Scout – build, sign, package, notarize
# Usage: ./scripts/build-release.sh [--skip-notarize]
#
# Prerequisites:
#   - Xcode 15+, Command Line Tools
#   - Developer ID certificate installed in Keychain
#   - Fill in the four variables below

set -euo pipefail

# ── CONFIGURE THESE ──────────────────────────────────────────────────────────
TEAM_ID="YOUR_TEAM_ID"            # 10-char Apple Team ID (see developer.apple.com)
APPLE_ID="s.thapa@a5sync.com"     # Apple ID used for notarization
APP_PASSWORD="@keychain:AC_PASSWORD"   # app-specific password stored in Keychain:
                                       # xcrun notarytool store-credentials "AC_PASSWORD" \
                                       #   --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
INSTALLER_CERT="Developer ID Installer: Samir Thapa ($TEAM_ID)"
# ─────────────────────────────────────────────────────────────────────────────

SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
ARCHIVE="$ROOT_DIR/build/Scout.xcarchive"
EXPORT_DIR="$ROOT_DIR/build/export"
PKG_STAGE="$ROOT_DIR/build/pkg-stage"
PKG_COMPONENT="$ROOT_DIR/build/Scout-component.pkg"
PKG_FINAL="$ROOT_DIR/build/Scout.pkg"
RESOURCES_DIR="$SCRIPT_DIR/installer-resources"

echo "▶ Cleaning build directory..."
rm -rf "$ROOT_DIR/build"
mkdir -p "$ROOT_DIR/build"

echo "▶ Archiving Scout.xcodeproj..."
xcodebuild archive \
    -project "$ROOT_DIR/Scout.xcodeproj" \
    -scheme Scout \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \


echo "▶ Exporting Developer ID build..."
# Patch team ID into ExportOptions.plist at export time
EXPORT_OPTIONS="$ROOT_DIR/build/ExportOptions.plist"
sed "s/YOUR_TEAM_ID/$TEAM_ID/g" "$SCRIPT_DIR/ExportOptions.plist" > "$EXPORT_OPTIONS"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/Scout.app"
if [ ! -d "$APP_PATH" ]; then
    echo "✗ Export failed – Scout.app not found at $APP_PATH"
    exit 1
fi

echo "▶ Staging PKG payload..."
mkdir -p "$PKG_STAGE/Applications"
cp -R "$APP_PATH" "$PKG_STAGE/Applications/Scout.app"

echo "▶ Building component PKG..."
pkgbuild \
    --root "$PKG_STAGE" \
    --install-location "/" \
    --identifier "com.samirthapa.scout" \
    --version "1.0" \
    "$PKG_COMPONENT"

echo "▶ Building product PKG..."
productbuild \
    --distribution "$SCRIPT_DIR/Distribution.xml" \
    --resources "$RESOURCES_DIR" \
    --package-path "$(dirname "$PKG_COMPONENT")" \
    --sign "$INSTALLER_CERT" \
    "$PKG_FINAL"

echo "▶ PKG built: $PKG_FINAL"

if $SKIP_NOTARIZE; then
    echo "⏭  Skipping notarization (--skip-notarize)"
    echo "✓ Done. Distribute: $PKG_FINAL"
    exit 0
fi

echo "▶ Submitting for notarization (this takes a few minutes)..."
xcrun notarytool submit "$PKG_FINAL" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

echo "▶ Stapling notarization ticket..."
xcrun stapler staple "$PKG_FINAL"

echo "✓ Done. Distribute: $PKG_FINAL"
