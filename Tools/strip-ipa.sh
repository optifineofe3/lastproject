#!/usr/bin/env bash
# Strip Watch + every native .appex from IPA so sideload resigners
# and LiveContainer don't choke on entitlements they can't satisfy. Modifies in place.
#
# Usage: Tools/strip-ipa.sh path/to/app.ipa

set -euo pipefail

IPA="${1:-}"
[ -f "$IPA" ] || { echo "usage: $0 path/to/app.ipa" >&2; exit 1; }

IPA_ABS=$(cd "$(dirname "$IPA")" && pwd)/$(basename "$IPA")
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

echo ">>> Unpacking $IPA_ABS..."
( cd "$WORK" && unzip -q "$IPA_ABS" )

APP=$(find "$WORK/Payload" -maxdepth 2 -name '*.app' -type d | head -1)
[ -n "$APP" ] || { echo "::error::No .app directory found under Payload/" >&2; exit 1; }

echo ">>> Found app bundle: $APP"
echo ">>> Stripping Watch and all PlugIns/AppExtensions..."
rm -rf \
    "$APP/Watch" \
    "$APP/WatchKit" \
    "$APP/WatchKitSupport" \
    "$APP/com.apple.WatchPlaceholder" \
    "$APP/PlugIns" \
    "$APP/Extensions" \
    "$WORK/Payload/WatchKitSupport"

# Remove any nested .appex bundles
find "$APP" -name '*.appex' -type d -prune -exec rm -rf {} +

echo ">>> Rebuilding clean IPA..."
rm -f "$IPA_ABS"
( cd "$WORK" && zip -qry "$IPA_ABS" Payload )

echo ">>> Successfully stripped: $IPA_ABS"
