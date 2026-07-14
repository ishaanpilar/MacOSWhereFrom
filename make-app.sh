#!/bin/bash
# Build a release binary and wrap it in a proper .app bundle so it runs as a
# dockless menu-bar app (LSUIElement) and gets a clean Downloads-access prompt.
set -euo pipefail
cd "$(dirname "$0")"

APP="WhereFrom.app"
BIN_NAME="WhereFrom"

echo "Building release…"
swift build -c release

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Where From</string>
    <key>CFBundleDisplayName</key><string>Where From</string>
    <key>CFBundleIdentifier</key><string>com.local.wherefrom</string>
    <key>CFBundleExecutable</key><string>WhereFrom</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Where From reads each file's origin (WhereFroms) and download date to help you triage the folder.</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict><key>default</key><string>Open in Where From</string></dict>
            <key>NSMessage</key><string>openInWhereFrom</string>
            <key>NSPortName</key><string>Where From</string>
            <key>NSSendFileTypes</key>
            <array><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc sign so the TCC prompt shows a stable identity.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Register with Launch Services so the Finder right-click Service appears.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$PWD/$APP" || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "Done → $APP"
echo "Launch:  open $APP     (icon appears in the menu bar, not the Dock)"
echo "Finder:  right-click any folder → Open in Where From"
echo "         (first time, you may need to enable it in"
echo "          System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services)"
