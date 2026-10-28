#!/usr/bin/env bash
# Render every SVG master under art/src to PNGs under art/out, plus a contact sheet per folder.
set -euo pipefail
ART="$(cd "$(dirname "$0")/.." && pwd)"
SIZE="${SIZE:-256}"

for dir in "$ART"/src/*/; do
  group="$(basename "$dir")"
  out="$ART/out/$group"
  mkdir -p "$out"
  for svg in "$dir"*.svg; do
    [ -e "$svg" ] || continue
    name="$(basename "$svg" .svg)"
    rsvg-convert -w "$SIZE" -h "$SIZE" "$svg" -o "$out/$name.png"
    rsvg-convert -w 512 -h 512 "$svg" -o "$out/$name@2x.png"
  done
  magick montage -label '%t' "$out"/*@2x.png -tile 4x -geometry 256x256+12+12 \
    -background '#F6EFE2' -pointsize 22 "$ART/out/sheet-$group.png" 2>/dev/null || true
done
echo "rendered to $ART/out"
