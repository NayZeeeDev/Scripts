#!/usr/bin/env python3
"""
Static cross-module contract checker for nayzeee-garages.

Checks (per side: client / server / shared, from fxmanifest.lua):
  1. NZ.<Module>.<member> used on a side but never defined on that side (or shared).
  2. Client lib.callback.await('nz:...') names that no server file registers.
  3. NUI callbacks declared in web/src/lib/types.ts (NuiCallbacks) that no client Lua registers,
     and forwarded NUI callbacks whose server callback 'nz:<name>' does not exist.
  4. NUI callback names used by the web code (request/fetchNui/mockNui) that are not declared.
  5. TriggerClientEvent('nz:client:...') without a client handler, and
     TriggerServerEvent('nz:...') without a server handler.
  6. NZ.NUI.open/send/close with an unknown app / action name.

Usage: python3 tools/contract_check.py   (exit 1 when problems are found)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# NUI callbacks handled on the client (never forwarded to the server).
CLIENT_ONLY_NUI = {
    'notify',
    'ready', 'close',
    'garage:drive', 'garage:spawner', 'garage:track', 'garage:goInside', 'garage:directions',
    'forSale:tour', 'forSale:buy',
    'impound:retrieve',
    'setup:livery', 'setup:extra', 'setup:drive',
    'interior:leave',
    'creator:pickEntry', 'creator:applyProfile', 'creator:addCameraPoint', 'creator:previewCutscene',
    'creator:placeSlot', 'creator:showSlots', 'creator:pickExit', 'creator:teleport', 'creator:walk',
    'creator:save', 'creator:cancel',
    'admin:location:teleport', 'admin:points', 'admin:pickPosition', 'admin:interior:create',
    'admin:interior:edit',
    'keys:refresh', 'keys:lock', 'keys:locate', 'keys:alarm', 'keys:players', 'keys:share', 'keys:holders',
    'keys:revoke', 'locksmith:refresh', 'locksmith:service',
}
# Client handlers that call a server callback under a different name.
CLIENT_TO_SERVER = {
    'garage:drive': 'nz:garage:retrieve', 'garage:spawner': 'nz:garage:spawner',
    'garage:track': 'nz:garage:track', 'garage:goInside': 'nz:garage:goInside',
    'garage:directions': 'nz:garage:nearestWithSpace', 'forSale:tour': 'nz:forSale:tour',
    'forSale:buy': 'nz:forSale:buy', 'impound:retrieve': 'nz:impound:retrieve',
    'creator:save': 'nz:creator:save',
    'keys:refresh': 'nz:carlock:tracker', 'keys:lock': 'nz:carlock:toggleLock', 'keys:locate': 'nz:carlock:tracker',
    'keys:alarm': 'nz:carlock:trackerAlarm', 'keys:players': 'nz:carlock:nearbyPlayers', 'keys:share': 'nz:carlock:share',
    'keys:holders': 'nz:carlock:keyHolders', 'keys:revoke': 'nz:carlock:keyRevoke',
    'locksmith:refresh': 'nz:carlock:locksmith:open', 'locksmith:service': 'nz:carlock:locksmith:service',
}
APPS = {'garage', 'impound', 'impoundForm', 'forSale', 'admin', 'creator', 'setup', 'interior', 'keys', 'locksmith', 'contract'}
ACTIONS = {'init', 'settings', 'open', 'update', 'close', 'hud', 'prompt', 'hint', 'notify'}


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def strip_lua_comments(src):
    src = re.sub(r'--\[(=*)\[.*?\]\1\]', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    return re.sub(r'--[^\n]*', '', src)


def manifest_files():
    text = read(os.path.join(ROOT, 'fxmanifest.lua'))
    sides = {}
    for block, side in (('shared_scripts', 'shared'), ('client_scripts', 'client'), ('server_scripts', 'server')):
        m = re.search(block + r'\s*\{(.*?)\}', text, re.S)
        if not m:
            continue
        for f in re.findall(r"'([^']+)'", m.group(1)):
            if f.startswith('@'):
                continue
            if '*' in f:
                d = os.path.dirname(f)
                for name in sorted(os.listdir(os.path.join(ROOT, d))):
                    if name.endswith('.lua'):
                        sides[os.path.join(d, name)] = side
            else:
                sides[f] = side
    return sides


def main():
    problems = []
    files = manifest_files()
    src = {}
    for f, side in files.items():
        p = os.path.join(ROOT, f)
        if not os.path.exists(p):
            problems.append(f'missing file listed in fxmanifest: {f}')
            continue
        src[f] = strip_lua_comments(read(p))

    defs = {'client': set(), 'server': set(), 'shared': set()}
    uses = []  # (side, file, member, line)
    for f, text in src.items():
        side = files[f]
        aliases = dict(re.findall(r'local\s+(\w+)\s*=\s*NZ\.(\w+)[ \t]*(?:--[^\n]*)?$', text, re.M))
        for alias, mod in aliases.items():
            for m in re.finditer(r'(?:function\s+' + re.escape(alias) + r'[.:](\w+)\s*\()|(?:^|[^\w.])' + re.escape(alias) + r'\.(\w+)\s*=(?!=)', text, re.M):
                defs[side].add(f'{mod}.{m.group(1) or m.group(2)}')
            for m in re.finditer(r'(?<![\w.])' + re.escape(alias) + r'[.:](\w+)', text):
                line = text.count('\n', 0, m.start()) + 1
                uses.append((side, f, f'{mod}.{m.group(1)}', line))
        for m in re.finditer(r'function\s+NZ\.(\w+)[.:](\w+)\s*\(', text):
            defs[side].add(f'{m.group(1)}.{m.group(2)}')
        for m in re.finditer(r'NZ\.(\w+)\.(\w+)\s*=(?!=)', text):
            defs[side].add(f'{m.group(1)}.{m.group(2)}')
        for m in re.finditer(r'NZ\.(\w+)[.:](\w+)', text):
            line = text.count('\n', 0, m.start()) + 1
            uses.append((side, f, f'{m.group(1)}.{m.group(2)}', line))
        # NZ.X = { a = ..., b = ... } style tables at top level
        for m in re.finditer(r'NZ\.(\w+)\s*=\s*\{', text):
            depth, i = 1, m.end()
            body_start = i
            while i < len(text) and depth:
                if text[i] == '{':
                    depth += 1
                elif text[i] == '}':
                    depth -= 1
                i += 1
            body = text[body_start:i - 1]
            for k in re.findall(r'^\s*(\w+)\s*=', body, re.M):
                defs[side].add(f'{m.group(1)}.{k}')

    seen = set()
    for side, f, member, line in uses:
        avail = defs[side] | defs['shared'] if side != 'shared' else defs['shared'] | defs['client'] | defs['server']
        if member not in avail:
            key = (side, member)
            if key in seen:
                continue
            seen.add(key)
            problems.append(f'{f}:{line}: NZ.{member} used on {side} but never defined there')

    server_text = '\n'.join(t for f, t in src.items() if files[f] in ('server', 'shared'))
    client_text = '\n'.join(t for f, t in src.items() if files[f] in ('client', 'shared'))

    server_cbs = set(re.findall(r"lib\.callback\.register\(\s*'([^']+)'", server_text))
    server_cbs |= set(re.findall(r"\bregister(?:Callback)?\(\s*'(nz:[^']+)'", server_text))
    client_awaits = set(re.findall(r"lib\.callback\.await\(\s*'([^']+)'", client_text))
    client_awaits |= set(re.findall(r"lib\.callback\(\s*'([^']+)'", client_text))
    for name in sorted(client_awaits):
        if name.startswith('nz:') and name not in server_cbs:
            problems.append(f'client awaits server callback {name!r} which is never registered')

    types_ts = read(os.path.join(ROOT, 'web/src/lib/types.ts'))
    block = re.search(r'export interface NuiCallbacks \{(.*?)\n\}', types_ts, re.S).group(1)
    declared = set(re.findall(r"^\s*'?([\w:]+)'?\s*:\s*Cb<", block, re.M))
    for name in sorted(declared):
        if f"'{name}'" not in client_text:
            problems.append(f'NUI callback {name!r} (types.ts) is not registered by any client Lua file')
        if name not in CLIENT_ONLY_NUI and f'nz:{name}' not in server_cbs:
            problems.append(f'forwarded NUI callback {name!r} has no server callback nz:{name}')
        if name in CLIENT_TO_SERVER and CLIENT_TO_SERVER[name] not in server_cbs:
            problems.append(f'client NUI handler {name!r} needs server callback {CLIENT_TO_SERVER[name]!r} (missing)')

    web_names = set()
    for dirpath, _, filenames in os.walk(os.path.join(ROOT, 'web/src')):
        for fn in filenames:
            if fn.endswith(('.ts', '.tsx')):
                t = read(os.path.join(dirpath, fn))
                web_names |= set(re.findall(r"(?:request|fetchNui|mockNui)\(\s*'([^']+)'", t))
    for name in sorted(web_names - declared):
        problems.append(f'web code calls undeclared NUI callback {name!r}')

    for name in sorted(set(re.findall(r"TriggerClientEvent\(\s*'(nz:[^']+)'", server_text))):
        if not re.search(r"(?:RegisterNetEvent|AddEventHandler)\(\s*'" + re.escape(name) + "'", client_text):
            problems.append(f'server fires client event {name!r} but no client handler exists')
    for name in sorted(set(re.findall(r"TriggerServerEvent\(\s*'(nz:[^']+)'", client_text))):
        if not re.search(r"(?:RegisterNetEvent|AddEventHandler)\(\s*'" + re.escape(name) + "'", server_text):
            problems.append(f'client fires server event {name!r} but no server handler exists')

    for m in re.finditer(r"NZ\.NUI\.(open|close|isOpen)\(\s*'([^']+)'", client_text):
        if m.group(2) not in APPS:
            problems.append(f'NZ.NUI.{m.group(1)} with unknown app {m.group(2)!r}')
    for m in re.finditer(r"NZ\.NUI\.send\(\s*'([^']+)'", client_text):
        if m.group(1) not in ACTIONS:
            problems.append(f'NZ.NUI.send with unknown action {m.group(1)!r}')

    if problems:
        print('\n'.join(problems))
        print(f'\n{len(problems)} problem(s)')
        return 1
    print('contract OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
