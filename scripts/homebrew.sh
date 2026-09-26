#!/bin/zsh
# Emit a cask for the EXACT, already-built DMG. Do not rebuild after publishing it.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS.' >&2; exit 1; }
[[ -f dist/NotchBrowser.dmg && -f dist/SHA256SUMS ]] || {
    echo 'Run ./scripts/dmg.sh first.' >&2; exit 1
}
(cd dist && shasum -a 256 -c SHA256SUMS) >&2
SHA="$(shasum -a 256 dist/NotchBrowser.dmg | awk '{print $1}')"
TMP="$(mktemp -d)"
MOUNT="$TMP/mounted"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT" -quiet || return
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
mkdir "$MOUNT"
hdiutil attach "$PWD/dist/NotchBrowser.dmg" -readonly -nobrowse -quiet -mountpoint "$MOUNT"
MOUNTED=1
APP="$MOUNT/NotchBrowser.app"
codesign --verify --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/NotchBrowser")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a stable x.y.z version.' >&2; exit 1; }
[[ "$ARCH" == arm64 && "$MIN_OS" == 13.0 ]] || {
    echo 'Architecture/minimum macOS changed; update the cask generator requirements.' >&2; exit 1
}
if LC_ALL=C grep -aEq '/Users/|/home/' "$APP/Contents/MacOS/NotchBrowser"; then
    echo 'Refusing distribution binary containing a build-machine home path.' >&2; exit 1
fi
cat <<CASK
cask "notch-browser" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/rezapace/notch-browser/releases/download/v#{version}/NotchBrowser.dmg"
  name "NotchBrowser"
  desc "Minimal browser that expands from the notch"
  homepage "https://github.com/rezapace/notch-browser"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "NotchBrowser.app"

  caveats <<~EOS
    NotchBrowser is ad-hoc signed and is not notarized by Apple.
    If macOS blocks opening, use System Settings > Privacy & Security > Open Anyway
    only if you trust this release.
  EOS
end
CASK
