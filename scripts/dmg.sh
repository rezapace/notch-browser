#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS." >&2; exit 1; }

./scripts/build.sh
TMP="$(mktemp -d)"
STAGE="$TMP/stage"
MOUNT="$TMP/mounted"
OUTPUT="$PWD/dist/NotchBrowser.dmg"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT" -quiet || return
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$STAGE" "$MOUNT"
ditto dist/NotchBrowser.app "$STAGE/NotchBrowser.app"
ln -s /Applications "$STAGE/Applications"
printf '%s\n' \
    'NotchBrowser — Instalasi' \
    '' \
    '1. Keluar dari versi lama dengan Command-Q.' \
    '2. Seret NotchBrowser.app ke Applications.' \
    '3. Eject disk image, lalu buka aplikasi dari Applications.' \
    '' \
    'Hover notch untuk membuka browser. Klik untuk mengetik.' \
    'Shift-Command-W: kecilkan ke notch. Command-Q: keluar.' \
    '' \
    'Build lokal menggunakan ad-hoc signing, belum notarized.' \
    'Jika Gatekeeper memblokir, gunakan System Settings > Privacy & Security > Open Anyway' \
    'hanya jika Anda mempercayai sumber aplikasi ini.' > "$STAGE/INSTALL.txt"

hdiutil create -volname NotchBrowser -fs HFS+ -srcfolder "$STAGE" \
    -format UDZO -imagekey zlib-level=9 "$TMP/NotchBrowser.dmg"
hdiutil verify "$TMP/NotchBrowser.dmg"
hdiutil attach "$TMP/NotchBrowser.dmg" -readonly -nobrowse -mountpoint "$MOUNT"
MOUNTED=1
codesign --verify --strict "$MOUNT/NotchBrowser.app"
"$MOUNT/NotchBrowser.app/Contents/MacOS/NotchBrowser" --check-resources
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]]
hdiutil detach "$MOUNT"
MOUNTED=0
mv -f "$TMP/NotchBrowser.dmg" "$OUTPUT"
(cd dist && shasum -a 256 NotchBrowser.dmg > SHA256SUMS)
shasum -a 256 "$OUTPUT"
echo "Checksum file: $PWD/dist/SHA256SUMS"
echo "DMG bytes: $(stat -f '%z' "$OUTPUT")"
echo "Created: $OUTPUT"
