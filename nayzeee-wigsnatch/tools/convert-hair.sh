#!/usr/bin/env bash
# Turn freemode hairstyles into props for the wig head.
#   ./convert-hair.sh <hair.ydd> <hair_diff.ytd> <prop_name> [out_dir]
# Example:
#   ./convert-hair.sh hair_000_u.ydd hair_diff_000_a_uni.ytd nzw_m_150 ../../nzw_hairprops/stream
# Needs .NET 8 SDK and Python 3 with numpy + Pillow (>= 11). Run it once per hairstyle; every prop in
# the out folder ends up in one nzw_hair.ytyp.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
YDD="$1"; YTD="$2"; NAME="$3"; OUT="${4:-$HERE/../hairprops-out}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$OUT/../hair-source"   # working files, kept out of stream/
mkdir -p "$SRC" "$OUT"
dotnet build -c Release "$HERE/cwtool" -o "$HERE/cwtool/bin" >/dev/null
CW="dotnet $HERE/cwtool/bin/cwtool.dll"
$CW ydd2xml "$YDD" "$WORK" >/dev/null
$CW ytd2dds "$YTD" "$WORK"
# the diffuse is the texture that isn't a normal / spec map
DIFF="$(ls "$WORK"/*.dds | grep -v -i -E 'normal|spec' | head -n 1)"
python3 "$HERE/props/hair2prop.py" "$WORK"/*.ydd.xml "$DIFF" "$NAME" "$SRC"
$CW xml2ydr "$SRC/$NAME.ydr.xml" "$SRC" "$OUT/$NAME.ydr"
$CW xml2ytyp "$SRC/nzw_hair.ytyp.xml" "$OUT/nzw_hair.ytyp"
echo "done: $OUT/$NAME.ydr (+ nzw_hair.ytyp)"
