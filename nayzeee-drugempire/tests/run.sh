#!/usr/bin/env bash
# Headless server test (needs lua5.4). Plays a character from the first text to a running operation.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
for f in $(find . -name '*.lua' -not -path './tests/*' -not -path './install/*'); do luac5.4 -p "$f"; done
lua5.4 tests/run.lua .
