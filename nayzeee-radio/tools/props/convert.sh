#!/usr/bin/env bash
# =====================================================================================================
# NAYZEEE Radio - turn the prop sources into streamable GTA V binaries (nayzeee-radio-props/stream/)
#
# The repository carries every prop as CodeWalker XML + DDS (tools/props/xml/, written by build.py).
# Converting needs CodeWalker, which needs .NET 8 - two routes:
#
# 1) Any machine with the .NET 8 SDK + git (Linux / macOS / Windows WSL):
#
#        tools/props/convert.sh              convert the committed tools/props/xml as it is (no rebuild, ~1 min)
#        tools/props/convert.sh --rebuild    rebuild every prop first, then convert (15-25 min); the same as
#                                            cd nayzeee-radio && python3 tools/props/build.py --stream ../nayzeee-radio-props/stream
#
#    build.py clones CodeWalker into /tmp/nzr-work/props/CodeWalker, builds tools/props/cwtool against it,
#    converts every .ydr.xml + nzr_props.ytyp.xml, loads every binary back to validate it, refuses any
#    drawable above 16 MiB of memory pages and only then copies the .ydr files + nzr_props.ytyp into
#    ../nayzeee-radio-props/stream (stale nzr_*.ydr there are removed).
#
# 2) Windows without .NET - the CodeWalker GUI (https://github.com/dexyfex/CodeWalker, release build):
#      * start CodeWalker and pick the GTA V *Legacy* folder when it asks (NOT GTA V Enhanced - FiveM streams
#        legacy / gen8 resources; Enhanced writes gen9 files that FiveM cannot load)
#      * Tools -> RPF Explorer, switch on Edit mode, open (or create) a folder / .rpf to import into
#      * Import XML -> select every tools/props/xml/nzr_*.ydr.xml and nzr_props.ytyp.xml (each .ydr.xml needs
#        its texture folder tools/props/xml/<name>/ next to it - keep the layout as it is in the repository)
#      * select the imported nzr_*.ydr + nzr_props.ytyp -> right click -> Extract Raw... into
#        nayzeee-radio-props/stream/ (file list and checks: nayzeee-radio-props/stream/README.md)
#      * check: the stream folder holds one .ydr per nzr_*.ydr.xml + nzr_props.ytyp (+ its README.md), nothing else
# =====================================================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$(cd "$HERE/../.." && pwd)"          # nayzeee-radio/
cd "$RES"
STREAM="../nayzeee-radio-props/stream"

if ! command -v dotnet >/dev/null 2>&1; then
    echo "convert.sh: the .NET 8 SDK (dotnet) is not installed."
    echo "  Install it (https://dotnet.microsoft.com/download/dotnet/8.0) or use the CodeWalker GUI route"
    echo "  described at the top of tools/props/convert.sh."
    exit 1
fi

if [ "${1:-}" = "--rebuild" ]; then
    shift
    exec python3 tools/props/build.py --stream "$STREAM" "$@"
fi
exec python3 tools/props/build.py --convert-only --stream "$STREAM" "$@"
