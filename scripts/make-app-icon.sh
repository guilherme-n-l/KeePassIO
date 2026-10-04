#!/usr/bin/env bash
# Renders the app icon (light, dark and tinted variants) into the asset
# catalog from Design/AppIcon.svg, with rsvg-convert (librsvg) and
# ImageMagick.
#
# The SVG has a green square (#rect1) behind a white glyph. Each variant
# recolors those two and renders a fully opaque 1024x1024 PNG, as the App
# Store requires.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_svg="$root/Design/AppIcon.svg"
out="$root/keepassios/Assets.xcassets/AppIcon.appiconset"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for tool in rsvg-convert convert; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "make-app-icon: $tool not found (nix develop provides it)" >&2
    exit 1
  fi
done

# render BACKGROUND GLYPH FILE
render() {
  sed -e "s/opacity:0\.870246;fill:#4fa34f/opacity:1;fill:$1/" \
    -e "s/fill:#ffffff/fill:$2/g" \
    "$source_svg" >"$work/icon.svg"
  rsvg-convert --width 1024 --height 1024 "$work/icon.svg" -o "$work/icon.png"
  convert "$work/icon.png" -background "$1" -alpha remove -alpha off -depth 8 "$out/$3"
}

render "#4fa34f" "#ffffff" AppIcon.png
render "#0e1c0e" "#5fbf5f" AppIcon-Dark.png
render "#000000" "#ffffff" AppIcon-Tinted.png
echo "Wrote $out"
