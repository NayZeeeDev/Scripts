#!/usr/bin/env bash
# Turn a clothing bag (ped component .ydd + one .ytd per colour) into a
# prop for nayzeee-backpack: <model>.ydr, one .ytd per colour, <model>.ytyp.
#
#   tools/convert_bag.sh <model> <bag.ydd> <colour1.ytd> [colour2.ytd ...]
#
# Output lands in stream/<model>/. Colour n is <model>_n (colour 1 is just
# <model>): its own copy of the model (GTA ties a model to one texture set)
# plus its .ytd. The model is slimmed first (unused textures dropped, maps
# capped at 512, meshes over 45k triangles simplified). Colour textures
# bigger than 1024 are shrunk to 1024 DXT with mipmaps.
#
# Needs: dotnet 8 SDK, python3 + Pillow + numpy, and CodeWalker's source
#   git clone --depth 1 https://github.com/dexyfex/CodeWalker
#   export CODEWALKER_CORE=/path/to/CodeWalker/CodeWalker.Core/CodeWalker.Core.csproj
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MODEL="$1"; YDD="$2"; shift 2
OUT="$HERE/../stream/$MODEL"
WORK="$(mktemp -d)"
PROJ="$HERE/bagconv/bagconv.csproj"
: "${CODEWALKER_CORE:?set CODEWALKER_CORE to CodeWalker.Core.csproj}"

cw() { dotnet run --project "$PROJ" -p:CodeWalkerCore="$CODEWALKER_CORE" -c Release -- "$@"; }

dotnet build "$PROJ" -p:CodeWalkerCore="$CODEWALKER_CORE" -c Release -v q -nologo >/dev/null
mkdir -p "$OUT"

# model
cw export "$YDD" "$WORK/src" >/dev/null
python3 "$HERE/conv.py" drawable "$(ls "$WORK"/src/*.xml)" 0 "$MODEL" "$WORK/out"
python3 "$HERE/slim.py" "$WORK/out/$MODEL.ydr.xml" "$WORK/slim/$MODEL.ydr.xml" --max-tris=45000
cw import "$WORK/slim/$MODEL.ydr.xml" ydr "$OUT/$MODEL.ydr" "$WORK/slim/$MODEL" >/dev/null

# colours
n=0
for YTD in "$@"; do
  n=$((n + 1)); NAME="$MODEL"; [ "$n" -gt 1 ] && NAME="${MODEL}_$n"
  cw export "$YTD" "$WORK/tex$n" >/dev/null
  python3 "$HERE/conv.py" texture "$(ls "$WORK"/tex$n/*.xml)" "${MODEL}_d" "$WORK/t$n/$NAME.ytd.xml"
  python3 "$HERE/shrink.py" "$WORK/t$n/$NAME/${MODEL}_d.dds" "$WORK/t$n/$NAME/${MODEL}_d.dds" 1024 >/dev/null
  cw import "$WORK/t$n/$NAME.ytd.xml" ytd "$OUT/$NAME.ytd" "$WORK/t$n/$NAME" >/dev/null
  [ "$NAME" != "$MODEL" ] && cp "$OUT/$MODEL.ydr" "$OUT/$NAME.ydr"
done

# archetypes
python3 "$HERE/conv.py" ytyp "$MODEL" "$n" "$WORK/out/bounds.json" "$WORK/out/$MODEL.ytyp.xml"
cw import "$WORK/out/$MODEL.ytyp.xml" ytyp "$OUT/$MODEL.ytyp" >/dev/null

echo "done: stream/$MODEL ($n colours, $(du -sh "$OUT" | cut -f1))"
echo "add it to Config.Backpacks with variants { label, model = '$MODEL' / '${MODEL}_2' ... }"
rm -rf "$WORK"
