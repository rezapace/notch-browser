#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun swiftc -parse-as-library \
    Sources/NotchBrowser/Notch/WorkspaceWindow.swift \
    Sources/NotchBrowser/Vendor/DynamicNotch.swift \
    Sources/NotchBrowser/Browser/*.swift \
    Tests/NotchBrowserTests/WorkspaceTests.swift \
    -o "$TMP/WorkspaceTests"
"$TMP/WorkspaceTests"

if [[ "${1:-}" == --bundle ]]; then
    ./scripts/build.sh
    # The negative test must fail even while the developer .build folder exists.
    cp -R dist/NotchBrowser.app "$TMP/NotchBrowser.app"
    APP="$TMP/NotchBrowser.app"
    OUTPUT="$("$APP/Contents/MacOS/NotchBrowser" --check-resources)"
    [[ "$OUTPUT" == *"$APP/Contents/Resources/"* ]] || { echo "FAIL: resource came from outside relocated app"; exit 1; }
    echo "PASS: relocated application resolves its own resource bundle"
    mkdir "$TMP/bare"
    cp "$APP/Contents/MacOS/NotchBrowser" "$TMP/bare/NotchBrowser"
    cp -R "$APP/Contents/Resources/NotchBrowser_NotchBrowser.bundle" "$TMP/bare/"
    OUTPUT="$("$TMP/bare/NotchBrowser" --check-resources)"
    [[ "$OUTPUT" == *"$TMP/bare/NotchBrowser_NotchBrowser.bundle/"* ]] || { echo "FAIL: bare resource is not relative to executable"; exit 1; }
    echo "PASS: relocated bare executable resolves adjacent resource bundle"
    rm -rf "$APP/Contents/Resources/NotchBrowser_NotchBrowser.bundle"
    if "$APP/Contents/MacOS/NotchBrowser" --check-resources >"$TMP/missing-resource.log" 2>&1; then
        echo "FAIL: missing app resource incorrectly used development fallback"; exit 1
    fi
    grep -q 'Missing icon.svg' "$TMP/missing-resource.log"
    echo "PASS: missing installed resource cannot fall back to .build"
fi
