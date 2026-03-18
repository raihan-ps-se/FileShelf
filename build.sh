#!/bin/bash
set -e

APP_NAME="FileShelf"
VERSION="1.0.0"
BUILD="1"
BUNDLE="$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# ── Build binary ─────────────────────────────────────────────────────────────
echo "🔨 Building $APP_NAME $VERSION..."
swift build -c release 2>&1
BINARY=".build/release/$APP_NAME"

# ── App icon ─────────────────────────────────────────────────────────────────
echo "🎨 Generating app icon..."
swift make_icon.swift

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z $size $size icon_1024.png --out "$ICONSET/icon_${size}x${size}.png"         > /dev/null
    dbl=$((size * 2))
    sips -z $dbl $dbl icon_1024.png   --out "$ICONSET/icon_${size}x${size}@2x.png"     > /dev/null
done

iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "✅ AppIcon.icns"

# ── App bundle ────────────────────────────────────────────────────────────────
echo "📦 Creating app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY"    "$MACOS/$APP_NAME"
cp AppIcon.icns "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FileShelf</string>
    <key>CFBundleIdentifier</key>
    <string>com.fileshelf.app</string>
    <key>CFBundleName</key>
    <string>FileShelf</string>
    <key>CFBundleDisplayName</key>
    <string>FileShelf</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 FileShelf. MIT License.</string>
</dict>
</plist>
EOF

# ── Cleanup temp files ────────────────────────────────────────────────────────
rm -rf "$ICONSET" icon_1024.png

# ── DMG ───────────────────────────────────────────────────────────────────────
echo "💿 Creating DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
VOL_NAME="$APP_NAME $VERSION"
DMG_TMP="dmg_staging"
DMG_RW="$APP_NAME-rw.dmg"

rm -rf "$DMG_TMP" "$DMG_NAME" "$DMG_RW"
mkdir -p "$DMG_TMP"
cp -r "$BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

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
echo "   Release: gh release upload vVERSION $DMG_NAME"
echo ""
if [ -t 0 ]; then
    read -p "Launch app now? [y/N] " launch
    if [[ "$launch" =~ ^[Yy]$ ]]; then
        open "$BUNDLE"
    fi
fi
