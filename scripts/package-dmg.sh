#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo 'Usage: bash scripts/package-dmg.sh /path/Disk\ Awake.app dist/Disk-Awake.dmg' >&2
    exit 1
fi
app="$1"
output="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$app/Contents" ]] || { echo "App not found: $app" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo 'Install create-dmg: brew install create-dmg' >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Output already exists: $output" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/staging"
ditto "$app" "$work/staging/Disk Awake.app"

# Empty uses the generated background; "none" disables it.
background="${DMG_BACKGROUND:-}"
options=()
if [[ "$background" != none ]]; then
    if [[ -z "$background" ]]; then
        background="$work/background.png"
        swift "$root/scripts/dmg-background.swift" "$background"
    fi
    [[ -f "$background" ]] || { echo "Background not found: $background" >&2; exit 1; }
    options+=(--background "$background")
fi

# Finder must run: skipping its AppleScript would discard the background/layout.
create-dmg --volname 'Disk Awake' \
    --window-pos 200 120 --window-size 660 440 \
    --icon-size 100 --text-size 14 \
    --icon 'Disk Awake.app' 170 205 \
    --hide-extension 'Disk Awake.app' \
    --app-drop-link 490 205 \
    "${options[@]}" "$output" "$work/staging"
hdiutil verify "$output"
shasum -a 256 "$output" > "$output.sha256"
