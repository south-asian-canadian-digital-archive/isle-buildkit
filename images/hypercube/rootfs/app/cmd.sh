#!/usr/bin/env bash
# hypercube: image on stdin, Tesseract text (or hOCR) on stdout.
#   cmd.sh <source-ext> [tesseract args...]
#
# Tesseract reads images through leptonica, which cannot open tiled TIFFs
# (so no pyramid TIFF), 16-bit JPEG 2000, float or LAB TIFFs, or HEIF/AVIF,
# and holds colour pages at 32 bits a pixel. So every image goes through
# libvips first: EXIF orientation applied, colour managed to sRGB, alpha
# flattened onto white, 8-bit greyscale, shrunk to at most
# HYPERCUBE_MAX_PIXELS. A multi-page TIFF keeps every page; a pyramid TIFF
# keeps its full-resolution page only. A page with a real resolution (above
# 72 dpi) is written as a strip TIFF carrying it, scaled if shrunk; any other
# as PGM, which has none, so Tesseract estimates it from the text as it does
# for a JPEG without one (libvips reports 72 dpi for those, 25 for JP2).
# If libvips cannot read the input, Tesseract gets it unchanged.

set -eou pipefail

SOURCE_EXT="$1"
ARGS=()
if [ "$#" -gt 1 ]; then
  ARGS=("${@:2}")
fi

# 50 MP is a 600 dpi letter page with room to spare. Larger pages are shrunk:
# Tesseract's memory grows with the page (a 245 MP JPEG was OOM-killed).
MAX_PIXELS="${HYPERCUBE_MAX_PIXELS:-50000000}"

TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# normalise <image> <dir>: writes <dir>/page-N.{tif,pgm} for each page worth
# reading and prints the Tesseract input: that page's path, or a list file
# naming every page (Tesseract reads a text file of paths as one job).
# Called from an `if`, where `set -e` is off: every step returns on failure.
normalise() {
  local in="$1" dir="$2" n i w h prev opt scale xres out
  local pages=(0)
  n=$(vipsheader -f n-pages "$in" 2>/dev/null || echo 1)
  if [ "$n" -gt 1 ]; then
    prev=$(vipsheader -f width "${in}[page=0]") || return 1
    for ((i = 1; i < n; i++)); do
      w=$(vipsheader -f width "${in}[page=$i]") || return 1
      # A page half as wide as the one before starts a pyramid's reduced
      # levels: read only the full-resolution page(s) before it.
      if [ $((w * 2 - prev)) -ge -1 ] && [ $((w * 2 - prev)) -le 1 ]; then
        break
      fi
      pages+=("$i")
      prev=$w
    done
  fi
  : > "$dir/pages.txt"
  for i in "${pages[@]}"; do
    opt=""
    if [ "$n" -gt 1 ]; then
      opt="[page=$i]"
    fi
    w=$(vipsheader -f width "$in$opt") || return 1
    h=$(vipsheader -f height "$in$opt") || return 1
    xres=$(vipsheader -f xres "$in$opt") || return 1
    scale=$(awk -v w="$w" -v h="$h" -v m="$MAX_PIXELS" \
      'BEGIN { print (w * h > m ? sqrt(m / (w * h)) : 1) }')
    vips thumbnail "$in$opt" "$dir/t.v" "$(awk -v w="$w" -v s="$scale" 'BEGIN { printf "%d", w * s }')" \
      --height "$(awk -v h="$h" -v s="$scale" 'BEGIN { printf "%d", h * s }')" --size down || return 1
    vips colourspace "$dir/t.v" "$dir/g.v" b-w || return 1
    vips flatten "$dir/g.v" "$dir/f.v" --background 255 || return 1
    # xres is in pixels per mm; 72 dpi is 2.835.
    if awk -v x="$xres" 'BEGIN { exit !(x > 2.84) }'; then
      out="$dir/page-$i.tif"
      xres=$(awk -v x="$xres" -v s="$scale" 'BEGIN { print x * s }')
      vips copy "$dir/f.v" "$out" --xres "$xres" --yres "$xres" || return 1
    else
      out="$dir/page-$i.pgm"
      vips copy "$dir/f.v" "$out" || return 1
    fi
    rm -f "$dir/t.v" "$dir/g.v" "$dir/f.v"
    echo "$out" >> "$dir/pages.txt"
  done
  if [ "${#pages[@]}" -eq 1 ]; then
    cat "$dir/pages.txt"
  else
    echo "$dir/pages.txt"
  fi
}

INPUT="$TMP_DIR/input.$SOURCE_EXT"
cat > "$INPUT"
mkdir "$TMP_DIR/norm"
if OCR_INPUT=$(normalise "$INPUT" "$TMP_DIR/norm" 2> "$TMP_DIR/vips.log"); then
  INPUT="$OCR_INPUT"
else
  echo "libvips could not read the $SOURCE_EXT input, passing it to Tesseract as is: $(head -c 300 "$TMP_DIR/vips.log")" >&2
fi

tesseract "$INPUT" stdout "${ARGS[@]}"
