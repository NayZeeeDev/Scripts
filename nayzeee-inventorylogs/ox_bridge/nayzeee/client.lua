--[[
    NAYZEEE Inventory Manager — ox_inventory live bridge (client)
    Receives data-file edits from the server and rebuilds the matching parts of ox_inventory
    in place: item list + inventory UI, shops, stashes, evidence lockers, crafting benches,
    vehicle storage and animations. Nothing here runs a loop while idle.
]]
if not lib then return end

local RESOURCE = shared.resource
local Items = require 'modules.items.client'
local Overrides = {}
local pending = {}
local pushing = false

-- ─── helpers ────────────────────────────────────────────────────────────────
local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
end

local function replaceInPlace(target, fresh)
    for k in pairs(target) do target[k] = nil end
    for k, v in pairs(fresh) do target[k] = v end
end

local function useExport(resource, export)
    return function(...) return exports[resource][export](nil, ...) end
end

local function setImagePath(path)
    if path then
        return path:match('^[%w]+://') and path or ('%s/%s'):format(client.imagepath, path)
    end
end

local function findUpvalue(name)
    if not debug or not debug.getupvalue then return end
    local roots = {}
    for _, fn in pairs(client) do if type(fn) == 'function' then roots[#roots + 1] = fn end end
    if type(OnPlayerData) == 'function' then roots[#roots + 1] = OnPlayerData end
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
        local r = walk(fn, 0)
        if r then return r end
    end
end

-- lib.load hands back the latest server copy for files we've been sent
local origLoad = lib.load
lib.load = function(path, ...)
    local key = type(path) == 'string' and path:match('^data%.([%w_]+)$')
    if key and Overrides[key] ~= nil then return deepcopy(Overrides[key]) end
    return origLoad(path, ...)
end

local function runModule(path)
    local src = LoadResourceFile(RESOURCE, path)
    if not src then return end
    local fn, err = load(src, ('@@%s/%s'):format(RESOURCE, path))
    if not fn then return warn(err) end
    local ok, res = pcall(fn)
    if not ok then return warn(res) end
    return res
end

-- ─── items ─────────────────────────────────────────────────────────────────
local WEAPON_FLAG = { Ammo = 'ammo', Components = 'component', Tints = 'tint' }

local function clientItem(name, data, old)
    local category = data.__category
    local uri = data.__imageUri
    data.__category, data.__imageUri = nil, nil
    data.name = name
    data.count = old and old.count or 0

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
        data.server = nil
        if data.client and data.client.image and not uri then data.client.image = setImagePath(data.client.image) end
    else
        data.weight = data.weight or 0
        if data.close == nil then data.close = true end
        if data.stack == nil then data.stack = true end
        local cd, sd = data.client, data.server
        if not data.consume and (cd and (cd.status or cd.usetime or cd.export) or (sd and sd.export)) then data.consume = 1 end
        data.server = nil
        if cd then
            if cd.export then data.export = useExport(string.strsplit('.', cd.export)) end
            if not uri then cd.image = setImagePath(cd.image) end
            if cd.propTwo then
                cd.prop = cd.prop and { cd.prop, cd.propTwo } or cd.propTwo
                cd.propTwo = nil
            end
        end
    end

    -- functions can't travel over the network; keep the ones this client already had
    if old then
        for k, v in pairs(old) do
            if type(v) == 'function' and data[k] == nil and k ~= 'export' then data[k] = v end
        end
        if type(old.client) == 'table' and type(data.client) == 'table' then
            for k, v in pairs(old.client) do
                if type(v) == 'function' and data.client[k] == nil then data.client[k] = v end
            end
        end
        if type(old.buttons) == 'table' and type(data.buttons) == 'table' then
            for i, b in ipairs(data.buttons) do
                local ob = old.buttons[i]
                if ob and b.action == nil then b.action = ob.action end
            end
        end
    end
    return data
end

local function nuiItem(v)
    local buttons
    if v.buttons then
        buttons = {}
        for i = 1, #v.buttons do buttons[i] = { label = v.buttons[i].label, group = v.buttons[i].group } end
    end
    return {
        label = v.label,
        stack = v.stack,
        close = v.close,
        count = v.count or 0,
        description = v.description,
        buttons = buttons,
        ammoName = v.ammoname,
        image = v.client and v.client.image,
    }
end

local function pushNui()
    if pushing then return end
    pushing = true
    CreateThread(function()
        while not (PlayerData and PlayerData.loaded) do Wait(1000) end
        local started = GetGameTimer()
        while LocalPlayer.state.invOpen and GetGameTimer() - started < 120000 do Wait(250) end
        local items = {}
        for name in pairs(pending) do
            local v = Items[name]
            if v then items[name] = nuiItem(v) end
        end
        pending = {}
        pushing = false
        if not next(items) then return end
        SendNUIMessage({
            action = 'init',
            data = {
                locale = {},
                items = items,
                leftInventory = {
                    id = cache.playerId,
                    slots = shared.playerslots,
                    items = PlayerData.inventory,
                    maxWeight = PlayerData.maxWeight or shared.playerweight,
                },
                imagepath = client.imagepath,
            },
        })
    end)
end

-- ─── weapon-out use limited to certain weapons ────────────────────────────
-- ox_inventory lets an item be used with a weapon out when `allowArmed` is true. With
-- `allowArmedWith = { 'WEAPON_PISTOL' }` we answer that question per weapon instead.
local function armedRule(item)
    if type(item) ~= 'table' then return end
    local list = rawget(item, 'allowArmedWith')
    if type(list) ~= 'table' or next(list) == nil then return end
    local allow = {}
    for _, w in pairs(list) do allow[tostring(w):upper()] = true end
    local mt = getmetatable(item)
    if mt and mt.__nzArmed then mt.__nzArmed = allow return end
    if mt then return end -- another script owns this table, keep ox's plain allowArmed
    rawset(item, 'allowArmed', nil)
    setmetatable(item, {
        __nzArmed = allow,
        __index = function(t, k)
            if k ~= 'allowArmed' then return nil end
            local ok, weapon = pcall(function() return exports[RESOURCE]:getCurrentWeapon() end)
            local name = ok and type(weapon) == 'table' and weapon.name
            return name and getmetatable(t).__nzArmed[tostring(name):upper()] == true or false
        end,
    })
end

for _, item in pairs(Items) do pcall(armedRule, item) end

local function applyItems(payload)
    for name, raw in pairs(payload.upsert or {}) do
        if raw then
            local ok, item = pcall(clientItem, name, raw, Items[name])
            if ok then
                pcall(armedRule, item)
                Items[name] = item
                if name == 'money' then Items.cash = item end
                pending[name] = true
            else
                warn(('[nayzeee] could not apply %s: %s'):format(name, item))
            end
        end
    end
    -- removed items stay known on this client so any copy still in a slot keeps rendering
    if next(pending) then pushNui() end
end

RegisterNetEvent('ox_inventory:nz:items', function(payload)
    if source == '' or type(payload) ~= 'table' then return end
    applyItems(payload)
end)

-- ─── modules ───────────────────────────────────────────────────────────────
local function removeBlipsNear(list)
    local doomed = {}
    for _, entry in ipairs(list) do
        if entry.sprite and entry.coords then
            local b = GetFirstBlipInfoId(entry.sprite)
            while DoesBlipExist(b) do
                local c = GetBlipInfoIdCoord(b)
                local p = entry.coords
                if #(vec3(c.x, c.y, 0.0) - vec3(p.x, p.y, 0.0)) < 1.5 then doomed[#doomed + 1] = b end
                b = GetNextBlipInfoId(entry.sprite)
            end
        end
    end
    for _, b in ipairs(doomed) do RemoveBlip(b) end
end

local Module = {}

Module.shops = function(data)
    Overrides.shops = data
    local Shops = require 'modules.shops.client'
    pcall(Shops.wipeShops)
    local fresh = runModule('modules/shops/client.lua')
    if not fresh then return end
    Shops.refreshShops, Shops.wipeShops = fresh.refreshShops, fresh.wipeShops
    if PlayerData and PlayerData.loaded then Shops.refreshShops() end
end

local function resetPoints(list)
    for _, s in pairs(list) do
        if type(s) == 'table' then
            if s.point then s.point:remove() s.point = nil end
            if s.zoneId then pcall(function() exports.ox_target:removeZone(s.zoneId) end) s.zoneId = nil end
        end
    end
end

Module.stashes = function(data)
    Overrides.stashes = data
    local Inventory = require 'modules.inventory.client'
    resetPoints(Inventory.Stashes)
    replaceInPlace(Inventory.Stashes, deepcopy(data))
    if PlayerData and PlayerData.loaded then Inventory.Stashes() end
end

Module.evidence = function(data)
    Overrides.evidence = data
    local Inventory = require 'modules.inventory.client'
    resetPoints(Inventory.Evidence)
    replaceInPlace(Inventory.Evidence, deepcopy(data))
    if PlayerData and PlayerData.loaded then Inventory.Evidence() end
end

Module.crafting = function(data)
    Overrides.crafting = data
    local Benches = require 'modules.crafting.client'
    local ok, all = pcall(lib.points.getAllPoints)
    if ok and type(all) == 'table' then
        for _, p in pairs(all) do if p.inv == 'crafting' then p:remove() end end
    end
    local blips = {}
    for _, bench in pairs(Benches) do
        if type(bench) == 'table' then
            local sprite = bench.blip and bench.blip.id
            for _, z in ipairs(bench.zones or {}) do
                if z.name then pcall(function() exports.ox_target:removeZone(z.name) end) end
                if sprite and z.coords then blips[#blips + 1] = { sprite = sprite, coords = z.coords } end
            end
            for _, c in ipairs(bench.points or {}) do
                if sprite then blips[#blips + 1] = { sprite = sprite, coords = c } end
            end
        end
    end
    removeBlipsNear(blips)
    local fresh = runModule('modules/crafting/client.lua')
    if fresh then replaceInPlace(Benches, fresh) end
end

Module.vehicles = function(data)
    Overrides.vehicles = data
    local live = findUpvalue('Vehicles')
    if live then replaceInPlace(live, deepcopy(data)) end
end

Module.animations = function(data)
    Overrides.animations = data
    local live = findUpvalue('Animations')
    if live then replaceInPlace(live, deepcopy(data)) end
end

RegisterNetEvent('ox_inventory:nz:module', function(payload)
    if source == '' or type(payload) ~= 'table' then return end
    local fn = Module[payload.file]
    if fn and type(payload.data) == 'table' then
        local ok, err = pcall(fn, payload.data)
        if not ok then warn(('[nayzeee] could not reload %s: %s'):format(payload.file, err)) end
    end
end)

-- ─── catch up with edits made before this player joined ───────────────────
CreateThread(function()
    local state = lib.callback.await('ox_inventory:nz:state', false)
    if type(state) ~= 'table' then return end
    for _, file in ipairs({ 'items', 'weapons' }) do
        if type(state[file]) == 'table' then
            local up = {}
            for k, v in pairs(state[file]) do if v then up[k] = v end end
            if next(up) then applyItems({ upsert = up }) end
        end
    end
    for _, file in ipairs({ 'shops', 'stashes', 'evidence', 'crafting', 'vehicles', 'animations' }) do
        if type(state[file]) == 'table' then pcall(Module[file], state[file]) end
    end
end)
