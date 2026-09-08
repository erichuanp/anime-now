#!/usr/bin/env bash
# Packs build/macos/.../Anime Now.app into dist/anime-now-<version>-macos.dmg,
# laid out as the usual "drag me into Applications" window.
#
# Needs `brew install create-dmg`. The window background is drawn by
# tools/dmg-background.swift so the DMG is reproducible from the repo alone.
set -euo pipefail

cd "$(dirname "$0")/.."
version=$(sed -n 's/^version: //p' pubspec.yaml | tr '+' '.')
app="build/macos/Build/Products/Release/Anime Now.app"
out="dist/anime-now-$version-macos.dmg"

[ -d "$app" ] || { echo "run: flutter build macos --release" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swift tools/dmg-background.swift "$work/background.png"
mkdir "$work/src"
cp -R "$app" "$work/src/"

mkdir -p dist
rm -f "$out"
create-dmg \
  --volname "Anime Now" \
  --background "$work/background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "Anime Now.app" 165 190 \
  --hide-extension "Anime Now.app" \
  --app-drop-link 495 190 \
  --no-internet-enable \
  "$out" "$work/src"

echo "$out"
