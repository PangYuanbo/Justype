#!/bin/bash
# Build JustType.icns from a single source PNG.
# Usage: ./scripts/make-icon.sh <path-to-source.png>
#
# Pads the source image to a square (using the source's background color
# sampled from a corner pixel), resizes to 1024×1024, then generates every
# size macOS expects in an .iconset and packs them into Resources/JustType.icns.
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "Usage: $0 <source-image.png>" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/JustType.iconset"
OUT="$ROOT/Resources/JustType.icns"
BASE="$ROOT/build/JustType-1024.png"

mkdir -p "$ROOT/build" "$ROOT/Resources"
rm -rf "$ICONSET" "$BASE" "$OUT"
mkdir -p "$ICONSET"

# Pad to square with the corner pixel's color, then resize to 1024×1024.
python3 - "$SRC" "$BASE" <<'PY'
import sys, os
from PIL import Image

src_path, dst_path = sys.argv[1], sys.argv[2]
img = Image.open(src_path).convert("RGBA")
w, h = img.size
side = max(w, h)

# Sample top-left pixel for background fill.
bg = img.getpixel((0, 0))

square = Image.new("RGBA", (side, side), bg)
square.paste(img, ((side - w) // 2, (side - h) // 2), img)
square = square.resize((1024, 1024), Image.LANCZOS)
square.save(dst_path, "PNG")
print(f"Wrote {dst_path} 1024×1024 (bg={bg})")
PY

# Generate every size macOS expects in an iconset.
gen() {
    local size=$1 name=$2
    sips -z "$size" "$size" "$BASE" --out "$ICONSET/$name" >/dev/null
}

gen   16 icon_16x16.png
gen   32 icon_16x16@2x.png
gen   32 icon_32x32.png
gen   64 icon_32x32@2x.png
gen  128 icon_128x128.png
gen  256 icon_128x128@2x.png
gen  256 icon_256x256.png
gen  512 icon_256x256@2x.png
gen  512 icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
