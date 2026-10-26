#!/usr/bin/env bash
# Build the original nayzeee bags from code (tools/bagforge) into stream/.
#
#   tools/forge_bags.sh                 every bag in bagforge/catalog.py
#   tools/forge_bags.sh barrel dome     just these catalog keys
#
# Each model lands in stream/<model>/: <model>.ydr (shape + relief),
# one .ytd per colour (<model>, <model>_2 ...) and <model>.ytyp. Backpacks
# also get <model>_loose.ydr (straps flat) and a <colour>_loose archetype each.
#
# Needs: dotnet 8 SDK, python3 + Pillow + numpy, and CodeWalker's source
#   git clone --depth 1 https://github.com/dexyfex/CodeWalker
#   export CODEWALKER_CORE=/path/to/CodeWalker/CodeWalker.Core/CodeWalker.Core.csproj
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STREAM="$HERE/../stream"
WORK="$(mktemp -d)"
PROJ="$HERE/bagconv/bagconv.csproj"
: "${CODEWALKER_CORE:?set CODEWALKER_CORE to CodeWalker.Core.csproj}"

cw() { dotnet run --project "$PROJ" -p:CodeWalkerCore="$CODEWALKER_CORE" -c Release --no-build -- "$@" >/dev/null; }
dotnet build "$PROJ" -p:CodeWalkerCore="$CODEWALKER_CORE" -c Release -v q -nologo >/dev/null

KEYS=("$@")
[ ${#KEYS[@]} -eq 0 ] && mapfile -t KEYS < <(cd "$HERE/bagforge" && python3 -c 'from catalog import CATALOG; print("\n".join(CATALOG))')

for KEY in "${KEYS[@]}"; do
  python3 "$HERE/bagforge/build.py" "$KEY" "$WORK/$KEY"
  for DIR in "$WORK/$KEY"/*/; do
    MODEL="$(basename "$DIR")"; OUT="$STREAM/$MODEL"
    mkdir -p "$OUT"
    cw import "$DIR/$MODEL.ydr.xml" ydr "$OUT/$MODEL.ydr" "$DIR/$MODEL"
    LOOSE=()
    if [ -f "$DIR/${MODEL}_loose.ydr.xml" ]; then   # straps-flat twin for bags off the back
      cw import "$DIR/${MODEL}_loose.ydr.xml" ydr "$OUT/${MODEL}_loose.ydr" "$DIR/$MODEL"
      LOOSE=(--loose="$DIR/bounds_loose.json")
    fi
    n=0
    for T in $(ls -d "$DIR"/t*/ | sort -V); do
      n=$((n + 1)); NAME="$MODEL"; [ "$n" -gt 1 ] && NAME="${MODEL}_$n"
      cw import "$T/$NAME.ytd.xml" ytd "$OUT/$NAME.ytd" "$T/$NAME"
    done
    python3 "$HERE/conv.py" ytyp "$MODEL" "$n" "$DIR/bounds.json" "$DIR/$MODEL.ytyp.xml" ${LOOSE[@]+"${LOOSE[@]}"}
    cw import "$DIR/$MODEL.ytyp.xml" ytyp "$OUT/$MODEL.ytyp"
    echo "  stream/$MODEL: $n colours, $(du -sh "$OUT" | cut -f1)"
  done
done
rm -rf "$WORK"
