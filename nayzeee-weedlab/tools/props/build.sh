#!/usr/bin/env bash
# Rebuilds every prop, the texture dictionary, the archetypes and the item images.
#
#   PY=<python with bpy + szio>  SOLLUMZ=<Sollumz checkout>  CODEWALKER=<CodeWalker checkout>  ./build.sh
#
# Needs: Python 3.13 venv with `pip install bpy==5.1.2 szio==1.4.0.dev2 numpy pillow`,
# a Sollumz checkout (github.com/Sollumz/Sollumz), a CodeWalker checkout
# (github.com/dexyfex/CodeWalker) and the .NET 8 SDK.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/../.." && pwd)"
BUILD="${BUILD:-$HERE/.build}"
PY="${PY:-python3}"
SAMPLES="${SAMPLES:-128}"

mkdir -p "$BUILD/scripts/addons"
ln -sfn "$SOLLUMZ" "$BUILD/scripts/addons/sollumz"
export BLENDER_USER_SCRIPTS="$BUILD/scripts"

echo "== textures";   "$PY" "$HERE/texgen.py" "$BUILD"
echo "== models";     "$PY" "$HERE/build_props.py" "$BUILD"
echo "== archetypes"; "$PY" "$HERE/make_ytyp.py" "$BUILD"
rm -rf "$BUILD/xml/nzw_weedlab" && cp -r "$BUILD/ytd/nzw_weedlab" "$BUILD/xml/nzw_weedlab"
echo "== binaries"
dotnet build "$HERE/xml2bin" -c Release -p:CodeWalkerCore="$CODEWALKER/CodeWalker.Core" -o "$BUILD/xml2bin" >/dev/null
rm -rf "$BUILD/stream" && dotnet "$BUILD/xml2bin/xml2bin.dll" "$BUILD/xml" "$BUILD/stream"
cp "$BUILD"/stream/*.ydr "$BUILD"/stream/*.ytd "$BUILD"/stream/*.ytyp "$RES/stream/"
cp "$BUILD/weedlab_props.blend" "$HERE/source/"
echo "== images"
"$PY" "$HERE/render_images.py" "$BUILD" "$RES/install/images" 512 "$SAMPLES"
"$PY" "$HERE/render_scenes.py" "$BUILD" "$RES/docs" 1280 "$SAMPLES"
echo "done"
