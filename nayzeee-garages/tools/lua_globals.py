#!/usr/bin/env python3
"""
Flags global variable access that is not a Lua builtin, a FiveM native/runtime global,
or one of the resource's sanctioned globals. Catches missing `local` and typos.
Usage: python3 tools/lua_globals.py <file.lua> [...]
"""
import re, subprocess, sys

LUA_STD = set('''_G _VERSION assert collectgarbage coroutine debug dofile error getmetatable io ipairs
load loadfile math next os package pairs pcall print rawequal rawget rawlen rawset require select
setmetatable string table tonumber tostring type utf8 xpcall'''.split())
FIVEM = set('''vector2 vector3 vector4 vec vec2 vec3 vec4 quat json msgpack exports source promise Citizen
joaat GlobalState LocalPlayer Player Entity AddEventHandler RegisterNetEvent TriggerEvent TriggerServerEvent
TriggerClientEvent TriggerLatentClientEvent RemoveEventHandler CreateThread Wait SetTimeout ClearTimeout
GetCurrentResourceName lib cache MySQL locale RegisterCommand RegisterNUICallback SendNUIMessage
SetNuiFocus SetNuiFocusKeepInput IsDuplicityVersion GetGameTimer GetHashKey PerformHttpRequest
LoadResourceFile SaveResourceFile GetResourceState GetResourceMetadata GetInvokingResource
NetworkGetEntityFromNetworkId NetworkGetNetworkIdFromEntity AddStateBagChangeHandler
GetPlayerIdentifierByType GetPlayers GetPlayerName GetPlayerPed GetEntityCoords
'''.split())
SANCTIONED = {'NZ', 'Config', 'ServerConfig', 'Locales', 'L'}
ASSIGN_OK = {'NZ', 'Config', 'ServerConfig', 'Locales', 'L'}

def check(path):
    out = subprocess.run(['luac5.4', '-p', '-l', '-l', path], capture_output=True, text=True)
    if out.returncode != 0:
        return [f'{path}: SYNTAX {out.stderr.strip()}']
    problems = []
    for line in out.stdout.splitlines():
        m = re.search(r'\[(\d+)\]\s+(GETTABUP|SETTABUP)\s.*?_ENV "([A-Za-z_][A-Za-z0-9_]*)"', line)
        if not m:
            continue
        ln, op, name = m.group(1), m.group(2), m.group(3)
        if op == 'SETTABUP':
            if name not in ASSIGN_OK:
                problems.append(f'{path}:{ln}: assigns global "{name}" (missing local?)')
            continue
        if name in LUA_STD or name in FIVEM or name in SANCTIONED:
            continue
        if re.match(r'^[A-Z][A-Za-z0-9_]*$', name):
            continue  # FiveM natives are PascalCase
        if name.startswith('_'):
            continue
        problems.append(f'{path}:{ln}: reads unknown global "{name}"')
    return problems

if __name__ == '__main__':
    probs = []
    for p in sys.argv[1:]:
        probs += check(p)
    print('\n'.join(probs) if probs else 'globals OK')
    sys.exit(1 if probs else 0)
