#!/usr/bin/env bash
# build-app.sh — produce a distributable DiaryInsight.app from the SPM executable.
#
# Usage:
#   ./build-app.sh           # release build → ./build/DiaryInsight.app
#   ./build-app.sh debug     # debug build
#
# The output bundle is self-contained: no SPM artifacts, no Xcode project, just
# the binary + Info.plist + a tiny Resources tree. Drag it into /Applications.

set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="ShiGuang"
BUNDLE_ID="com.diaryinsight.app"
DISPLAY_NAME="拾光"
BUNDLE_VERSION="0.1.0"
SHORT_VERSION="0.1.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
EXEC="$BIN_PATH/$APP_NAME"
if [[ ! -x "$EXEC" ]]; then
    echo "Executable not found at $EXEC" >&2
    exit 1
fi

OUT="$ROOT/build/$APP_NAME.app"
echo "==> assembling bundle at $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
mkdir -p "$OUT/Contents/Resources"
cp "$EXEC" "$OUT/Contents/MacOS/$APP_NAME"
chmod +x "$OUT/Contents/MacOS/$APP_NAME"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUNDLE_VERSION}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Markdown Diary Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# PkgInfo (helps Finder recognize the bundle)
printf "APPL????" > "$OUT/Contents/PkgInfo"

# App icon — drop the source PNG in. For a polished .icns, run
# `sips` + `iconutil` to generate multi-size .icns; the PNG works on most
# macOS versions as a fallback.
if [[ -f "$ROOT/Assets/icon.png" ]]; then
    cp "$ROOT/Assets/icon.png" "$OUT/Contents/Resources/AppIcon.png"
    echo "==> copied Assets/icon.png → Contents/Resources/AppIcon.png"
fi

# ad-hoc codesign so Gatekeeper lets the user double-click it on first run
echo "==> ad-hoc codesign"
codesign --force --sign - --timestamp=none "$OUT" 2>/dev/null || true

echo ""
echo "✅ Built $OUT"
echo "   Open with:  open '$OUT'"
echo "   Or drag to /Applications"
