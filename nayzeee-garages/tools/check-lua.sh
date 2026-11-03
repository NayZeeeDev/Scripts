#!/usr/bin/env bash
# Usage: tools/check-lua.sh [files...]   (default: every Lua file in the resource)
cd "$(dirname "$0")/.." || exit 1
if [ "$#" -eq 0 ]; then
  set -- $(find . -name '*.lua' -not -path './web/*' -not -path './tools/*' -not -name fxmanifest.lua | sort)
fi
status=0
for f in "$@"; do
  luac5.4 -p "$f" || status=1
done
python3 tools/lua_globals.py "$@" || status=1
luacheck --no-global --codes -q "$@" || status=1
exit $status
