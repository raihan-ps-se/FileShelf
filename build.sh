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

echo "✅ $APP_NAME.app v$VERSION is ready"
echo ""
echo "   To run:    open $BUNDLE"
echo "   To install: cp -r $BUNDLE /Applications/"
echo ""
read -p "Launch now? [y/N] " launch
if [[ "$launch" =~ ^[Yy]$ ]]; then
    open "$BUNDLE"
fi
