#!/usr/bin/env bash
# Headless engine test. Requires lua5.4 and python3.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../nayzeee-heistpack"
TMP="$(mktemp -d)"
python3 - "$ROOT/locales/en.json" "$TMP/strings.lua" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
out = ['return {']
for k, v in d.items():
    if isinstance(v, str): out.append(f'  [{q(k)}] = {q(v)},')
out.append('}')
open(sys.argv[2], 'w').write('\n'.join(out))
PY
lua5.4 "$HERE/run_heists.lua" "$ROOT" "$HERE" "$TMP/strings.lua"
