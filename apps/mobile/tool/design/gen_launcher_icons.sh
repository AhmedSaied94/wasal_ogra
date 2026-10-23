#!/usr/bin/env bash
# Writes the launcher icons from docs/design/brand/ (direction أ,
# specs/008.5-m21-design-refresh tasks.md T130), and the 512×512 store icon
# beside them. Needs rsvg-convert and ImageMagick.
#
# Usage, from apps/mobile:
#   tool/design/gen_launcher_icons.sh
#
# test/repo/launcher_icons_test.dart checks what it writes.
set -euo pipefail

cd "$(dirname "$0")/../.."
brand=../../docs/design/brand
res=android/app/src/main/res
ios=ios/Runner/Assets.xcassets/AppIcon.appiconset

for tool in rsvg-convert magick; do
  command -v "$tool" >/dev/null || { echo "needs $tool" >&2; exit 1; }
done

# svg size out: [out] rendered [size]×[size].
render() { rsvg-convert --width "$2" --height "$2" "$1" --output "$3"; }

# An opaque copy of [in] at [out]: iOS and the stores refuse an alpha channel.
opaque() {
  magick "$1" -background white -alpha remove -alpha off \
    -define png:color-type=2 "$2"
}

# Android: the legacy icon (48 dp) for API 24–25, and the adaptive icon's
# layers (108 dp) for API 26 on, per density.
declare -A scale=([mdpi]=1 [hdpi]=1.5 [xhdpi]=2 [xxhdpi]=3 [xxxhdpi]=4)
for density in "${!scale[@]}"; do
  dir=$res/mipmap-$density
  mkdir -p "$dir"
  legacy=$(awk "BEGIN { print 48 * ${scale[$density]} }")
  layer=$(awk "BEGIN { print 108 * ${scale[$density]} }")
  render "$brand/icon_master.svg" "$legacy" "$dir/ic_launcher.png"
  render "$brand/adaptive_background.svg" "$layer" \
    "$dir/ic_launcher_background.png"
  render "$brand/adaptive_foreground.svg" "$layer" \
    "$dir/ic_launcher_foreground.png"
  render "$brand/monochrome.svg" "$layer" "$dir/ic_launcher_monochrome.png"
done

mkdir -p "$res/mipmap-anydpi-v26"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- Direction أ (docs/design/brand/), written by tool/design/gen_launcher_icons.sh. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML

# iOS: every size Contents.json names, from the master, opaque.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$ios/Contents.json" <<'PY' | while read -r file px; do
import json, sys
for image in json.load(open(sys.argv[1]))["images"]:
    side = float(image["size"].split("x")[0])
    scale = int(image["scale"].rstrip("x"))
    print(image["filename"], round(side * scale))
PY
  render "$brand/icon_master.svg" "$px" "$tmp/$file"
  opaque "$tmp/$file" "$ios/$file"
done

# Google Play's listing icon.
render "$brand/icon_master.svg" 512 "$tmp/store.png"
opaque "$tmp/store.png" "$brand/store_icon_512.png"

echo "Wrote the launcher icons and $brand/store_icon_512.png."
