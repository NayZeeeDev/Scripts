--[[
    NAYZEEE Inventory Manager — ox_inventory live bridge (server)
    Drop this folder into ox_inventory and add the two lines from INSTALL.md to its fxmanifest.
    It lets the manager apply edits to data/*.lua without restarting ox_inventory.
    Only the resource named by the `inventory:nzmanager` convar can call it.
]]
if not lib then return end

local RESOURCE = shared.resource
local MANAGER = GetConvar('inventory:nzmanager', 'nayzeee-inventorylogs')
local BRIDGE_VERSION = 3

local Sigs = {}          -- file -> { key -> signature }
local Raw = {}           -- file -> latest raw table from disk
local ClientState = {}   -- file -> payload new clients need (items: map, others: full table)
local Images = {}        -- item -> data uri for freshly uploaded images

-- ─── helpers ────────────────────────────────────────────────────────────────
local function useExport(resource, export)
    return function(...) return exports[resource][export](nil, ...) end
end

local function deepcopy(v, strip)
    if type(v) ~= 'table' then
        if strip and type(v) == 'function' then return nil end
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        local c = deepcopy(x, strip)
        if c ~= nil then out[k] = c end
    end
    return out
end

local function sig(v)
    local t = type(v)
    if t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for i, k in ipairs(keys) do parts[i] = tostring(k) .. '=' .. sig(v[k]) end
        return '{' .. table.concat(parts, ',') .. '}'
    elseif t == 'function' then return 'fn'
    elseif t == 'string' then return ('%q'):format(v) end
    return tostring(v)
end

local function loadData(name)
    local file = ('data/%s.lua'):format(name)
    local src = LoadResourceFile(RESOURCE, file)
    if not src then return nil, 'missing ' .. file end
    local fn, err = load(src, ('@@%s/%s'):format(RESOURCE, file))
    if not fn then return nil, err end
    local ok, res = pcall(fn)
    if not ok then return nil, res end
    if type(res) ~= 'table' then return nil, file .. ' did not return a table' end
    return res
end

local function hasFunctions(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    for _, x in pairs(v) do if hasFunctions(x) then return true end end
    return false
end

--- find a table held as an upvalue called `name`, starting from a set of root functions
local function findUpvalue(roots, name)
    if not debug or not debug.getupvalue then return end
    local seen = {}
    local function walk(fn, depth)
        if seen[fn] or depth > 4 then return end
        seen[fn] = true
        for i = 1, 250 do
            local n, v = debug.getupvalue(fn, i)
            if not n then break end
            if n == name and type(v) == 'table' then return v end
            if type(v) == 'function' then
                local r = walk(v, depth + 1)
                if r then return r end
            end
        end
    end
    for _, fn in ipairs(roots) do
        if type(fn) == 'function' then
            local r = walk(fn, 0)
            if r then return r end
        end
    end
end

local function replaceInPlace(target, fresh)
    for k in pairs(target) do target[k] = nil end
    for k, v in pairs(fresh) do target[k] = v end
end

local function broadcast(event, payload, target)
    TriggerLatentClientEvent(event, target or -1, 262144, payload)
end

-- ─── items & weapons ───────────────────────────────────────────────────────
local WEAPON_FLAG = { Ammo = 'ammo', Components = 'component', Tints = 'tint' }

local function flatten(file, data)
    local out = {}
    if file == 'weapons' then
        for category, list in pairs(data) do
            if type(list) == 'table' then
                for name, v in pairs(list) do
                    if type(v) == 'table' then
                        v.__category = category
                        out[name] = v
                    end
                end
            end
        end
    else
        for name, v in pairs(data) do
            if type(v) == 'table' then out[name] = v end
        end
    end
    return out
end

local function serverItem(name, raw)
    local data = deepcopy(raw)
    local category = data.__category
    data.__category = nil
    data.name = name

    if category then
        data.close = category == 'Ammo'
        data.weight = data.weight or 0
        if category == 'Weapons' then
            data.model = data.model or name
            data.hash = joaat(data.model)
            data.stack = data.throwable and true or false
            data.durability = data.durability or 0.05
            data.weapon = true
        else
            data.stack = true
        end
        data[WEAPON_FLAG[category] or 'weapon'] = true
        data.client = nil
        return data
    end

    data.weight = data.weight or 0
    if data.close == nil then data.close = true end
    if data.stack == nil then data.stack = true end
    local clientData, serverData = data.client, data.server
    if not data.consume and (clientData and (clientData.status or clientData.usetime or clientData.export) or (serverData and serverData.export)) then
        data.consume = 1
    end
    data.client = nil
    if not data.durability then
        if data.degrade or (data.consume and data.consume ~= 0 and data.consume < 1) then data.durability = true end
    end
    if serverData and serverData.export then
        data.cb = useExport(string.strsplit('.', serverData.export))
    end
    return data
end

local function clientPayload(name, raw)
    local c = deepcopy(raw, true)
    if c.server then
        c.server = c.server.export and { export = c.server.export } or nil
    end
    if Images[name] then
        c.client = c.client or {}
        c.client.image = Images[name]
        c.__imageUri = true
    end
    return c
end

local function applyItems(file)
    local data, err = loadData(file)
    if not data then return { ok = false, err = err } end
    local ItemList = require 'modules.items.shared'
    local fresh = flatten(file, data)
    Raw[file] = fresh
    local old = Sigs[file] or {}
    local newSigs, upsert, remove = {}, {}, {}
    local changed, funcs = 0, {}

    for name, raw in pairs(fresh) do
        local s = sig(raw)
        newSigs[name] = s
        if old[name] ~= s then
            local ok, item = pcall(serverItem, name, raw)
            if ok then
                ItemList[name] = item
                if name == 'money' then ItemList.cash = item end
                upsert[name] = clientPayload(name, raw)
                changed = changed + 1
                if hasFunctions(raw.client) or hasFunctions(raw.buttons) then funcs[#funcs + 1] = name end
            else
                warn(('[nayzeee] failed to apply item %s: %s'):format(name, item))
            end
        end
    end

    local other = file == 'items' and (Raw.weapons or {}) or (Raw.items or {})
    for name in pairs(old) do
        if not newSigs[name] then
            if not other[name] then ItemList[name] = nil end
            remove[#remove + 1] = name
            changed = changed + 1
        end
    end

    Sigs[file] = newSigs
    ClientState[file] = ClientState[file] or {}
    for name, p in pairs(upsert) do ClientState[file][name] = p end
    for _, name in ipairs(remove) do ClientState[file][name] = false end

    if changed > 0 then broadcast('ox_inventory:nz:items', { file = file, upsert = upsert, remove = remove }) end
    local note
    if #funcs > 0 then
        note = ('%s use Lua functions on the client; those parts start working after the next ox_inventory restart'):format(table.concat(funcs, ', '))
    end
    return { ok = true, live = true, changed = changed, note = note }
end

-- ─── shops ─────────────────────────────────────────────────────────────────
local function applyShops()
    local data, err = loadData('shops')
    if not data then return { ok = false, err = err } end
    local before = Raw.shops or {}
    for shopType, def in pairs(data) do
        exports[RESOURCE]:RegisterShop(shopType, deepcopy(def, true))
    end
    for shopType, def in pairs(before) do
        if not data[shopType] then
            exports[RESOURCE]:RegisterShop(shopType, { name = def.name or shopType, inventory = {}, groups = { __nz_removed = 99 } })
        end
    end
    Raw.shops = data
    ClientState.shops = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'shops', data = ClientState.shops })
    return { ok = true, live = true }
end

-- ─── stashes ───────────────────────────────────────────────────────────────
local function applyStashes()
    local data, err = loadData('stashes')
    if not data then return { ok = false, err = err } end
    local names = {}
    for _, s in pairs(data) do
        if s.name then
            names[s.name] = true
            local coords = shared.target and s.target and s.target.loc or s.coords
            exports[RESOURCE]:RegisterStash(s.name, s.label, s.slots, s.weight, s.owner, s.groups or s.jobs, coords)
        end
    end
    for _, s in pairs(Raw.stashes or {}) do
        if s.name and not names[s.name] then
            exports[RESOURCE]:RegisterStash(s.name, s.label, s.slots, s.weight, s.owner, { __nz_removed = 99 })
        end
    end
    Raw.stashes = data
    ClientState.stashes = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'stashes', data = ClientState.stashes })
    return { ok = true, live = true }
end

-- ─── crafting (needs the RegisterCraftingBench export from INSTALL.md) ────
local function craftingExport()
    return NZ_CRAFTING_EXPORT == true
end

local function applyCrafting()
    local data, err = loadData('crafting')
    if not data then return { ok = false, err = err } end
    local live = craftingExport()
    if live then
        local ids = {}
        for id, bench in pairs(data) do
            local benchId = bench.name or id
            ids[benchId] = true
            exports[RESOURCE]:RegisterCraftingBench(benchId, deepcopy(bench, true))
        end
        for id, bench in pairs(Raw.crafting or {}) do
            local benchId = bench.name or id
            if not ids[benchId] then exports[RESOURCE]:RemoveCraftingBench(benchId) end
        end
    end
    Raw.crafting = data
    ClientState.crafting = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'crafting', data = ClientState.crafting })
    if not live then
        return { ok = true, live = false, note = 'Crafting benches were updated for players, but the server keeps the old recipes until ox_inventory restarts. Add the crafting export from INSTALL.md to make crafting fully live.' }
    end
    return { ok = true, live = true }
end

-- ─── evidence / vehicles / animations ─────────────────────────────────────
local function applyEvidence()
    local data, err = loadData('evidence')
    if not data then return { ok = false, err = err } end
    ClientState.evidence = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'evidence', data = ClientState.evidence })
    return { ok = true, live = true }
end

local function applyVehicles()
    local data, err = loadData('vehicles')
    if not data then return { ok = false, err = err } end
    local Inventory = require 'modules.inventory.server'
    local roots = {}
    local mt = getmetatable(Inventory)
    if mt and mt.__call then roots[#roots + 1] = mt.__call end
    for _, fn in pairs(Inventory) do if type(fn) == 'function' then roots[#roots + 1] = fn end end
    local live = findUpvalue(roots, 'Vehicles')
    if live then replaceInPlace(live, data) end
    ClientState.vehicles = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'vehicles', data = ClientState.vehicles })
    if not live then return { ok = true, live = false, note = 'Saved. Trunk and glovebox sizes apply after ox_inventory restarts.' } end
    return { ok = true, live = true }
end

local function applyAnimations()
    local data, err = loadData('animations')
    if not data then return { ok = false, err = err } end
    ClientState.animations = deepcopy(data, true)
    broadcast('ox_inventory:nz:module', { file = 'animations', data = ClientState.animations })
    return { ok = true, live = true }
end

local Appliers = {
    items = function() return applyItems('items') end,
    weapons = function() return applyItems('weapons') end,
    shops = applyShops,
    stashes = applyStashes,
    crafting = applyCrafting,
    evidence = applyEvidence,
    vehicles = applyVehicles,
    animations = applyAnimations,
}

-- ─── boot: remember the state the server started with ─────────────────────
CreateThread(function()
    Wait(2000)
    for _, file in ipairs({ 'items', 'weapons' }) do
        local data = loadData(file)
        if data then
            local flat = flatten(file, data)
            Raw[file] = flat
            local s = {}
            for name, raw in pairs(flat) do s[name] = sig(raw) end
            Sigs[file] = s
        end
    end
    Raw.shops = loadData('shops') or {}
    Raw.stashes = loadData('stashes') or {}
    Raw.crafting = loadData('crafting') or {}
end)

-- ─── API for the manager resource ──────────────────────────────────────────
local function allowed()
    local inv = GetInvokingResource()
    return inv == MANAGER or inv == nil
end

exports('nzInfo', function()
    return {
        version = BRIDGE_VERSION,
        crafting = craftingExport(),
        target = shared.target,
        framework = shared.framework,
        imagepath = GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images'),
        manager = MANAGER,
    }
end)

exports('nzApply', function(file)
    if not allowed() then return { ok = false, err = 'not allowed' } end
    local fn = Appliers[file]
    if not fn then return { ok = true, live = false, note = 'Saved. This file applies after ox_inventory restarts.' } end
    local ok, res = pcall(fn)
    if not ok then return { ok = false, err = tostring(res) } end
    return res
end)

--- FiveM only lets a resource write inside its own folder, so the manager hands file writes to us.
exports('nzWrite', function(path, content)
    if not allowed() then return { ok = false, err = 'not allowed' } end
    if type(path) ~= 'string' or type(content) ~= 'string' then return { ok = false, err = 'bad arguments' } end
    if not (path:match('^data/[%w_]+%.lua$') or path:match('^web/images/[%w_%-]+%.png$')) then
        return { ok = false, err = 'path not allowed' }
    end
    local ok = SaveResourceFile(RESOURCE, path, content, #content)
    return { ok = ok == true or ok == 1, err = (ok ~= true and ok ~= 1) and ('could not write ' .. path) or nil }
end)

exports('nzImage', function(item, dataUri)
    if not allowed() then return false end
    if type(item) ~= 'string' or type(dataUri) ~= 'string' then return false end
    Images[item] = dataUri
    local raw = (Raw.items or {})[item] or (Raw.weapons or {})[item]
    if not raw then return true end
    local file = (Raw.items or {})[item] and 'items' or 'weapons'
    local payload = clientPayload(item, raw)
    ClientState[file] = ClientState[file] or {}
    ClientState[file][item] = payload
    broadcast('ox_inventory:nz:items', { file = file, upsert = { [item] = payload }, remove = {} })
    return true
end)

lib.callback.register('ox_inventory:nz:state', function(source)
    return ClientState
end)
