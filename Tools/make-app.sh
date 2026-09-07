#!/bin/bash
#
# Wraps a SwiftPM executable in a .app bundle and signs it.
#
# The bundle is not cosmetic. TCC decides what Accessibility permission an executable has
# by looking at its code signature and bundle identity, and it treats a loose binary run
# from a shell as part of the shell. Run the spike straight from Terminal and it borrows
# the Terminal's Accessibility grant, which looks exactly like success and proves nothing.
#
# Usage: Tools/make-app.sh [executable-name] [bundle-identifier]

set -euo pipefail

EXECUTABLE="${1:-ambit-spike-ax}"
BUNDLE_ID="${2:-com.zainnajamkhan.ambit.spike}"
CONFIGURATION="${CONFIGURATION:-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="$EXECUTABLE"
APP="build/${APP_NAME}.app"

echo "==> building $EXECUTABLE ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE"
BINARY="$(swift build -c "$CONFIGURATION" --product "$EXECUTABLE" --show-bin-path)/$EXECUTABLE"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Accessory: no Dock icon, no menu bar. The shape the real app will take. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Accessibility grant across rebuilds. Ad-hoc signing
# does not: TCC keys on the code directory hash, so every rebuild is a new stranger and the
# permission has to be granted again. Prefer any Apple Development certificate present.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"' || true)"

if [ -n "$IDENTITY" ]; then
    echo "==> signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --options runtime "$APP" 2>&1 | sed 's/^/    /'
else
    echo "==> signing ad-hoc (no Apple Development certificate found)"
    echo "    NOTE: the Accessibility grant will be dropped on every rebuild."
    codesign --force --sign - "$APP" 2>&1 | sed 's/^/    /'
fi

echo
echo "built: $APP"
echo
echo "run it:      open $APP"
echo "watch it:    tail -f ~/Library/Logs/Ambit/spike-ax.log"
echo "stop it:     pkill -INT -f $APP_NAME"
echo
echo "Launch with 'open', never by running the binary directly: a binary started from"
echo "the shell inherits the Terminal's Accessibility permission and will lie to you."
