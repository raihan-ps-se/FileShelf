#!/bin/bash
set -e

APP_NAME="FileShelf"
VERSION="1.0.0"
BUILD="1"
DERIVED_DATA="build_release"

# ── Build Release ────────────────────────────────────────────────────────────
echo "🔨 Building $APP_NAME $VERSION (Release)..."

xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    2>&1 | tail -5

BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$BUNDLE" ]; then
    echo "❌ Build failed — $BUNDLE not found"
    exit 1
fi

echo "✅ Built $BUNDLE"
echo "   Binary arch: $(lipo -info "$BUNDLE/Contents/MacOS/$APP_NAME")"

# ── DMG ───────────────────────────────────────────────────────────────────────
echo "💿 Creating DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
VOL_NAME="$APP_NAME $VERSION"
DMG_TMP="dmg_staging"
DMG_RW="$APP_NAME-rw.dmg"

rm -rf "$DMG_TMP" "$DMG_NAME" "$DMG_RW"
mkdir -p "$DMG_TMP"
cp -R "$BUNDLE" "$DMG_TMP/"
ln -sf /Applications "$DMG_TMP/Applications"

# Create writable image (extra -size ensures hdiutil can mount it immediately)
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDRW \
    -size 10m \
    -quiet \
    "$DMG_RW"

# Mount it (no auto-open)
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil attach "$DMG_RW" -noautoopen -quiet
sleep 1

# Configure window: size, icon positions, hide toolbar/sidebar
osascript << APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 460}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 120
    set position of item "FileShelf.app" of container window to {150, 170}
    set position of item "Applications"  of container window to {390, 170}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

# Unmount and convert to compressed read-only
hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    -o "$DMG_NAME"

rm -rf "$DMG_TMP" "$DMG_RW"
echo "✅ $DMG_NAME ($(du -sh "$DMG_NAME" | cut -f1))"

echo ""
echo "   Install: open $DMG_NAME"
echo "   Release: gh release upload v$VERSION $DMG_NAME"
echo ""
if [ -t 0 ]; then
    read -p "Launch app now? [y/N] " launch
    if [[ "$launch" =~ ^[Yy]$ ]]; then
        open "$BUNDLE"
    fi
fi
