#!/bin/zsh
# Builds the website's art: one-ink masks (dithered paintings and app screens) and real screenshots.
#   python3 tools/site/fetch-art.py        # once: public-domain paintings into build/site-art/
#   tools/site/build-media.sh [shots-dir]  # default shots: build/site-shots (from the review tour)
set -euo pipefail
cd "${0:A:h}/../.."
ART=build/site-art
SHOTS=${1:-build/site-shots}
OUT=site/assets/art
mkdir -p "$OUT" site/assets/shots build/tools
swiftc -O tools/site/dither.swift -o build/tools/dither
D=build/tools/dither

# Paintings
$D $ART/millet-sower.jpg $OUT/millet-sower.png --width 1800 --mode fs --block 2 --contrast 1.9 --brightness 0.12 --gamma 0.6 --crop 0,0.04,1,0.42
$D $ART/millet-sower.jpg $OUT/millet-sower-full.png --width 1000 --mode fs --block 2 --contrast 1.9 --brightness 0.12 --gamma 0.6
$D $ART/vangogh-sower.jpg $OUT/vangogh-sower.png --width 1600 --mode fs --block 2 --contrast 1.4
$D $ART/millet-gleaners.jpg $OUT/gleaners.png --width 1800 --mode fs --block 2 --contrast 1.7 --brightness 0.06 --gamma 0.75 --crop 0,0.28,1,0.62
$D $ART/vangogh-wheatfield.jpg $OUT/wheatfield.png --width 2000 --mode fs --block 2 --contrast 1.6
# The trading stage keeps the painting's color, printed in four flat inks with the same Bayer screen.
sips -s format jpeg --resampleWidth 1800 $ART/vangogh-sower-painting.jpg --out build/tools/vangogh-sower-1800.jpg >/dev/null
swift tools/site/palette.swift build/tools/vangogh-sower-1800.jpg site/assets/shots/vangogh-sower-inks.png --width 520 --inks 1B1640,4A1FF2,F0B92E,F4F4F1

# App screens: dithered landscape details for the feature rows (ink where the screen is light).
detail() { $D "$SHOTS/$1.png" "$OUT/ui-$2.png" --width 1100 --mode fs --block 1 --contrast 1.2 --ink light --crop "$3"; }
detail recording-sower recording 0,0.07,1,0.42
detail takeaways-sower takeaways 0,0.04,1,0.42
# The summary plate: a sermon page scrolled to Summary (-SermonSetScroll summary).
detail summary-sower summary 0,0.075,1,0.42
detail card-sower card 0,0.08,1,0.42

# Real screenshots
for f in library-sower library-riso library-rubric library-vespers library-lumen library-midnight offer-sower; do
  [ -f "$SHOTS/$f.png" ] && sips -s format jpeg -s formatOptions 80 --resampleWidth 640 "$SHOTS/$f.png" --out "site/assets/shots/$f.jpg" >/dev/null
done
ls -la $OUT site/assets/shots
