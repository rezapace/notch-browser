#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS." >&2; exit 1; }

swift build -c release -Xswiftc -Osize
APP="$PWD/dist/NotchBrowser.app"
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchBrowser" "$APP/Contents/MacOS/NotchBrowser"
# AppResources resolves this location explicitly; no development .build fallback in .app.
cp -R "$BIN_DIR/NotchBrowser_NotchBrowser.bundle" "$APP/Contents/Resources/"
cp licenses/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "${ICONSET:h}"' EXIT
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NotchBrowser</string>
<key>CFBundleIdentifier</key><string>dev.notchbrowser.app</string>
<key>CFBundleName</key><string>NotchBrowser</string>
<key>CFBundleDisplayName</key><string>NotchBrowser</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PLIST
strip -S -x "$APP/Contents/MacOS/NotchBrowser"
# A .gitignore does not prevent development paths from becoming binary strings.
if LC_ALL=C grep -aEq '/Users/|/home/' "$APP/Contents/MacOS/NotchBrowser" || \
   LC_ALL=C grep -aFq "$PWD" "$APP/Contents/MacOS/NotchBrowser"; then
    echo 'FAIL: build-machine path found in distribution executable' >&2
    exit 1
fi
echo 'PASS: distribution executable contains no build-machine home/project path'
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
"$APP/Contents/MacOS/NotchBrowser" --check-resources
echo "Built: $APP"
echo "Executable bytes: $(stat -f '%z' "$APP/Contents/MacOS/NotchBrowser")"
echo "Bundle file bytes: $(find "$APP" -type f -exec stat -f '%z' {} + | awk '{n += $1} END {printf "%.0f", n}')"
echo "Bundle disk usage (KiB): $(du -sk "$APP" | cut -f1)"
echo "Run: open '$APP'"
