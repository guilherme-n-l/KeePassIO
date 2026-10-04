#!/usr/bin/env bash
# Draws the app icon (light, dark and tinted variants) into the asset
# catalog with ImageMagick, so the artwork is reproducible from source.
set -euo pipefail

out="$(cd "$(dirname "$0")/.." && pwd)/keepassios/Assets.xcassets/AppIcon.appiconset"
shield="path 'M 512 176 L 780 276 L 780 520 C 780 690 664 806 512 860 C 360 806 244 690 244 520 L 244 276 Z'"

# draw BACKGROUND SHIELD_COLOR KEYHOLE_COLOR FILE
draw() {
    convert -size 1024x1024 "$1" \
        -fill "$2" -draw "$shield" \
        -fill "$3" -draw "circle 512,470 512,392" -draw "polygon 478,500 546,500 572,680 452,680" \
        -alpha off -depth 8 "$out/$4"
}

draw "gradient:#2F6BFF-#1636B8" white "#1E4BDB" AppIcon.png
draw "gradient:#101A3A-#05081A" "#5B8CFF" "#0A1230" AppIcon-Dark.png
draw "xc:black" "#E6E6E6" black AppIcon-Tinted.png
echo "Wrote $out"
