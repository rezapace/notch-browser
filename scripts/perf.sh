#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Synthetic blank-page probe, not a website benchmark or total browser memory.
xcrun swiftc -Osize -whole-module-optimization -parse-as-library \
    Sources/NotchBrowser/Notch/WorkspaceWindow.swift \
    Sources/NotchBrowser/Vendor/DynamicNotch.swift \
    Sources/NotchBrowser/Browser/*.swift \
    Tests/NotchBrowserTests/LocalHTTPServer.swift \
    Tests/NotchBrowserTests/PerformanceProbe.swift \
    -o "$TMP/PerformanceProbe"
"$TMP/PerformanceProbe"
