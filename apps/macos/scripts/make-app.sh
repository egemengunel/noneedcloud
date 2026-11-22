#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG=debug
fi

swift build -c "$CONFIG"

APP=dist/NoNeedCloud.app
BIN=".build/$CONFIG/NoNeedCloud"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NoNeedCloud"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>NoNeedCloud</string>
	<key>CFBundleIdentifier</key>
	<string>com.parachuteclone.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>NoNeedCloud</string>
	<key>CFBundleDisplayName</key>
	<string>NoNeedCloud</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPhotosUsageDescription</key>
	<string>NoNeedCloud reads your iCloud Photos library to keep a full-quality backup copy on storage you own.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP"
