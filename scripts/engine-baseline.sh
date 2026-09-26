#!/bin/zsh
# Developer-only interactive A/B probe; --smoke-test makes no external requests.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun swiftc -Osize -whole-module-optimization -parse-as-library \
    Sources/NotchBrowser/Notch/WorkspaceWindow.swift \
    Sources/NotchBrowser/Vendor/DynamicNotch.swift \
    Sources/NotchBrowser/Browser/*.swift \
    Tests/NotchBrowserTests/LocalHTTPServer.swift \
    Tests/NotchBrowserTests/EngineBaselineProbe.swift \
    -o "$TMP/EngineBaselineProbe"
"$TMP/EngineBaselineProbe" "$@"
