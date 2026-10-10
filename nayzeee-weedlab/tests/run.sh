#!/usr/bin/env bash
# Headless server test (needs lua5.4). Syntax-checks every file, then plays a character
# from finding Uncle Benson to a running weed operation.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
for f in $(find . -name '*.lua' -not -path './tests/*' -not -path './install/*' -not -path './tools/*'); do luac5.4 -p "$f"; done
node --check web/app.js && node --check web/preview.js && node --check web/icons.js
lua5.4 tests/run.lua .
