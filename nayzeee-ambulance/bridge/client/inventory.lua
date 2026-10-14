--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: inventory (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Read-only item checks for menus and target
    options. The server always re-checks items before anything is used.

      Bridge.Inv.Has(name, count?) → bool      never blocks (safe in canInteract)
      Bridge.Inv.Count(name)       → number    never blocks
      Bridge.Inv.CountAwait(name)  → number    asks the server (yields)
      Bridge.Inv.Label(name)       → label
      Bridge.Inv.Image(name)       → 'nui://...png'

    ox_inventory, qb-style inventories and plain ESX are read locally. Every
    other inventory is read through the server callback 'nza:bridge:inv:counts'
    and cached for a moment (a stale value is returned while it refreshes).
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Inv = Bridge.Inv or {}

local CACHE_MS = 1500

local function qbItemsCount(items, name)
    local total = 0
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name == name then
            total = total + (tonumber(item.amount or item.count) or 0)
        end
    end
    return total
end

local function qbStyle(name)
    local pd = Bridge.PlayerData()
    if Bridge.Framework == 'qbcore' then
        local QBCore = Bridge.Core()
        local ok, fresh = pcall(function() return QBCore.Functions.GetPlayerData() end)
        if ok and type(fresh) == 'table' then pd = fresh end
    end
    return qbItemsCount(pd and pd.items, name)
end

-- Local readers: return a number, or nil when the server must be asked
local LOCAL = {
    ['ox_inventory'] = function(name)
        return tonumber(exports.ox_inventory:GetItemCount(name)) or 0
    end,
    ['qb-inventory'] = qbStyle,
    ['ps-inventory'] = qbStyle,
    ['lj-inventory'] = qbStyle,
    ['framework'] = function(name)
        if Bridge.Framework == 'qbcore' then return qbStyle(name) end
        if Bridge.Framework == 'esx' then
            local ESX = Bridge.Core()
            local pd = ESX and ESX.GetPlayerData() or {}
            for _, item in pairs(pd.inventory or {}) do
                if item.name == name then return tonumber(item.count) or 0 end
            end
            return 0
        end
        return nil
    end,
}
Bridge.InventoryClientReaders = LOCAL

local resolved, resolvedOnce = nil, false

local function resolve()
    if resolvedOnce then return resolved end
    resolvedOnce = true
    resolved = Bridge.Pick('inventory', Bridge.Cfg('inventory', 'auto')) or 'framework'
    return resolved
end

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('inventory', resource) then resolvedOnce, resolved = false, nil end
end
AddEventHandler('onClientResourceStart', reset)
AddEventHandler('onClientResourceStop', reset)

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVER-BACKED CACHE
-- ═══════════════════════════════════════════════════════════════════════════

local cache = {}      -- [name] = { count = n, at = ms }
local pending = {}    -- names waiting for the next request
local requesting = false

local function flush()
    if requesting then return end
    requesting = true
    CreateThread(function()
        Wait(50)
        local names = {}
        for name in pairs(pending) do names[#names + 1] = name end
        pending = {}
        if #names > 0 then
            local result = lib.callback.await('nza:bridge:inv:counts', false, names)
            local now = GetGameTimer()
            if type(result) == 'table' then
                for _, name in ipairs(names) do
                    cache[name] = { count = tonumber(result[name]) or 0, at = now }
                end
            end
        end
        requesting = false
        if next(pending) then flush() end
    end)
end

local function cached(name)
    local entry = cache[name]
    if not entry or GetGameTimer() - entry.at > CACHE_MS then
        pending[name] = true
        flush()
    end
    return entry and entry.count or 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.Inv.Count(name)
    if type(name) ~= 'string' then return 0 end
    local reader = LOCAL[resolve()]
    if reader then
        local ok, n = pcall(reader, name)
        if ok and n ~= nil then return n end
    end
    return cached(name)
end

function Bridge.Inv.Has(name, count)
    return Bridge.Inv.Count(name) >= (tonumber(count) or 1)
end

function Bridge.Inv.CountAwait(name)
    if type(name) ~= 'string' then return 0 end
    local result = lib.callback.await('nza:bridge:inv:counts', false, { name })
    local n = type(result) == 'table' and tonumber(result[name]) or nil
    if n then cache[name] = { count = n, at = GetGameTimer() } end
    return n or Bridge.Inv.Count(name)
end

-- server tells us something changed (any module may trigger this after item changes)
RegisterNetEvent('nza:bridge:inv:dirty', function(names)
    if type(names) == 'string' then names = { names } end
    if type(names) ~= 'table' then
        cache = {}
        return
    end
    for _, name in pairs(names) do cache[name] = nil end
end)

local labelCache, imageCache = {}, {}

function Bridge.Inv.Label(name)
    if type(name) ~= 'string' then return '' end
    if labelCache[name] then return labelCache[name] end
    local label
    local inv = resolve()
    if inv == 'ox_inventory' then
        local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
        label = ok and type(item) == 'table' and item.label or nil
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local QBCore = Bridge.Core()
        local items = QBCore and QBCore.Shared and QBCore.Shared.Items
        label = items and items[name] and items[name].label or nil
    end
    label = label or Bridge.ItemLabel(name)
    labelCache[name] = label
    return label
end

local IMAGE_PATHS = {
    ['ox_inventory']     = { 'ox_inventory', 'web/images/%s.png' },
    ['qb-inventory']     = { 'qb-inventory', 'html/images/%s.png' },
    ['ps-inventory']     = { 'ps-inventory', 'html/images/%s.png' },
    ['lj-inventory']     = { 'lj-inventory', 'html/images/%s.png' },
    ['qs-inventory']     = { 'qs-inventory', 'html/images/%s.png' },
    ['codem-inventory']  = { 'codem-inventory', 'html/itemimages/%s.png' },
    ['origen_inventory'] = { 'origen_inventory', 'html/images/%s.png' },
    ['tgiann-inventory'] = { 'inventory_images', 'images/%s.png' },
    ['core_inventory']   = { 'core_inventory', 'html/img/%s.png' },
}
Bridge.InventoryImagePaths = IMAGE_PATHS

local function fileExists(resource, path)
    if not Bridge.Started(resource) then return false end
    local data = LoadResourceFile(resource, path)
    return data ~= nil and data ~= ''
end

function Bridge.Inv.Image(name)
    if type(name) ~= 'string' or name == '' then name = 'nza_unknown' end
    if imageCache[name] then return imageCache[name] end
    local url
    local spec = IMAGE_PATHS[resolve()]
    if spec and Bridge.Cfg('preferInventoryImages', true) then
        local path = spec[2]:format(name)
        if fileExists(spec[1], path) then url = ('nui://%s/%s'):format(spec[1], path) end
    end
    local own = GetCurrentResourceName()
    if not url and fileExists(own, ('html/img/items/%s.png'):format(name)) then
        url = ('nui://%s/html/img/items/%s.png'):format(own, name)
    end
    url = url or ('nui://%s/html/img/items/nza_unknown.png'):format(own)
    imageCache[name] = url
    return url
end
