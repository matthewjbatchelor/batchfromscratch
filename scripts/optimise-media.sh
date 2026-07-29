#!/usr/bin/env bash
# Shrink the media library before it is imported.
#
# Run this on a COPY of wp-content/uploads, on your Mac:
#     ./scripts/optimise-media.sh ~/Downloads/wp-uploads
#
# Why bother: the originals average 1.75MB and the largest is 5MB — straight off a
# phone camera, never resized. Nothing on the site displays an image wider than
# about 1800px, so the extra pixels are pure download cost for every visitor and
# pure storage cost on the volume. Expect roughly an 85% reduction with no visible
# difference at the sizes the theme actually renders.
#
# Only originals are touched. WordPress's -WxH derivatives are left alone because
# they get regenerated from the originals anyway (wp media regenerate).
set -euo pipefail

SRC="${1:-}"
MAX_DIM="${MAX_DIM:-2400}"
QUALITY="${QUALITY:-82}"

if [ -z "${SRC}" ] || [ ! -d "${SRC}" ]; then
    echo "usage: $0 /path/to/uploads   (works on a copy — it rewrites in place)" >&2
    exit 64
fi

# macOS ships sips; ImageMagick is better but is not there by default.
if command -v magick >/dev/null 2>&1; then
    RESIZE() { magick "$1" -auto-orient -resize "${MAX_DIM}x${MAX_DIM}>" -quality "${QUALITY}" -strip "$1"; }
    echo "using ImageMagick"
elif command -v sips >/dev/null 2>&1; then
    RESIZE() { sips --resampleHeightWidthMax "${MAX_DIM}" -s formatOptions "${QUALITY}" "$1" --out "$1" >/dev/null; }
    echo "using sips (macOS built-in)"
else
    echo "need either ImageMagick (brew install imagemagick) or macOS sips" >&2
    exit 1
fi

before=$(du -sk "${SRC}" | cut -f1)
count=0

# Skip WordPress's generated sizes: -1024x768.jpg and friends.
while IFS= read -r -d '' f; do
    case "$(basename "$f")" in
        *-[0-9]*x[0-9]*.jpg|*-[0-9]*x[0-9]*.jpeg|*-[0-9]*x[0-9]*.png) continue ;;
    esac
    RESIZE "$f" || { echo "  skipped (failed): $f" >&2; continue; }
    count=$((count + 1))
    [ $((count % 25)) -eq 0 ] && echo "  ${count} done…"
done < <(find "${SRC}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

after=$(du -sk "${SRC}" | cut -f1)
printf '\n%s originals processed\n%.0fMB → %.0fMB (%.0f%% saved)\n' \
    "${count}" \
    "$(echo "${before}/1024" | bc -l)" \
    "$(echo "${after}/1024" | bc -l)" \
    "$(echo "(1 - ${after}/${before}) * 100" | bc -l)"
