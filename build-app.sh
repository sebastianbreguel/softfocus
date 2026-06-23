#!/bin/bash
# Build SoftFocus into a runnable .app bundle (menu-bar app, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=".build/release/SoftFocus"
APP="SoftFocus.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SoftFocus"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SoftFocus</string>
    <key>CFBundleDisplayName</key><string>SoftFocus</string>
    <key>CFBundleExecutable</key><string>SoftFocus</string>
    <key>CFBundleIdentifier</key><string>com.softfocus.SoftFocus</string>
    <key>CFBundleVersion</key><string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- LSUIElement: run as a menu-bar agent with no Dock icon. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Ad-hoc sign (free, no Developer ID): lets the unsigned app launch without the
# "damaged / unidentified developer" block once Homebrew strips the quarantine.
codesign --force --deep --sign - "$APP"

echo "Built $APP — run it with: open $APP"
