--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE RADIO - Bridge: inventory (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Read-only item checks for menus and target
    options. The server always re-checks items before anything is used.

      Bridge.Inv.Has(name, count?) → bool      never blocks (safe in canInteract)
      Bridge.Inv.Count(name)       → number    never blocks
      Bridge.Inv.CountAwait(name)  → number    asks the server (yields)
      Bridge.Inv.Label(name)       → label
      Bridge.Inv.Image(name)       → 'nui://...png'
      Bridge.Inv.BlockHotbar(owner, on)   the inventory's number-row hotbar off while any
                                          owner ('raised', 'headunit') types on a keypad

    ox_inventory, qb-style inventories and plain ESX are read locally. Every
    other inventory is read through the server callback 'nzr:bridge:inv:counts'
    and cached for a moment (a stale value is returned while it refreshes).
    Requests respect the server's 200 ms throttle and carry every name in use.

    EVENTS HANDLED
      nzr:bridge:inv:dirty (S→C) { name } | nil   drop cached counts (sent after item changes)
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

-- ════════════════════════════════════════════════════════════════════════
-- SERVER-BACKED CACHE
-- ════════════════════════════════════════════════════════════════════════

local cache = {}      -- [name] = { count = n, at = ms fetched, read = ms last asked for }
local pending = {}    -- names waiting for the next request
local requesting = false
local lastAt = nil    -- GetGameTimer() of the last 'nzr:bridge:inv:counts' request
local failed = 0      -- requests in a row the server answered with nothing

-- the server answers one request per 200 ms per player and nil to anything sooner,
-- and reads at most 40 names per request (bridge/server/inventory.lua 'inv:counts')
local GAP_MS = 220
local RETRIES = 3         -- quick retries after a nil answer
local BACKOFF_MS = 2000   -- gap after that, until an answer comes back
local MAX_NAMES = 40
local SOON_MS = CACHE_MS // 2   -- names still in use that go stale this soon ride along

local function waitForGap(minWait)
    local gap = failed > RETRIES and BACKOFF_MS or GAP_MS
    local left = lastAt and (gap - (GetGameTimer() - lastAt)) or 0
    local ms = math.max(minWait or 0, left)
    if ms > 0 then Wait(ms) end
end

local function flush()
    if requesting then return end
    requesting = true
    CreateThread(function()
        waitForGap(50)
        local names, batch = {}, {}
        for name in pairs(pending) do
            if #names >= MAX_NAMES then break end
            names[#names + 1] = name
            batch[name] = true
        end
        for name in pairs(batch) do pending[name] = nil end
        if #names > 0 then
            -- one request instead of one per name: refresh what is still being read
            local t = GetGameTimer()
            for name, e in pairs(cache) do
                if #names >= MAX_NAMES then break end
                if not batch[name] and t - (e.read or 0) < CACHE_MS and t - e.at > CACHE_MS - SOON_MS then
                    names[#names + 1] = name
                    batch[name] = true
                end
            end
            lastAt = GetGameTimer()
            local result = lib.callback.await('nzr:bridge:inv:counts', false, names)
            local now = GetGameTimer()
            if type(result) == 'table' then
                failed = 0
                for _, name in ipairs(names) do
                    local prev = cache[name]
                    cache[name] = { count = tonumber(result[name]) or 0, at = now, read = prev and prev.read or now }
                    pending[name] = nil   -- read again (still stale) while this request was out
                end
            else
                -- throttled: ask again after the gap. After a few misses in a row the names
                -- are dropped and the gap grows to BACKOFF_MS; the next Count/Has queues them again.
                failed = failed + 1
                if failed <= RETRIES then
                    for _, name in ipairs(names) do pending[name] = true end
                end
            end
        end
        requesting = false
        if next(pending) then flush() end
    end)
end

local function cached(name)
    local now = GetGameTimer()
    local entry = cache[name]
    if entry then entry.read = now end
    if not entry or now - entry.at > CACHE_MS then
        pending[name] = true
        flush()
    end
    return entry and entry.count or 0
end

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════════════════

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
    waitForGap(0)
    lastAt = GetGameTimer()
    local result = lib.callback.await('nzr:bridge:inv:counts', false, { name })
    local n = type(result) == 'table' and tonumber(result[name]) or nil
    if n then
        local now = GetGameTimer()
        cache[name] = { count = n, at = now, read = now }
    end
    return n or Bridge.Inv.Count(name)
end

-- server tells us something changed (any module may trigger this after item changes)
RegisterNetEvent('nzr:bridge:inv:dirty', function(names)
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
    if type(name) ~= 'string' or name == '' then name = 'nzr_unknown' end
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
    -- a renamed item keeps its picture through Config.ItemDefs[key].image (as on the server)
    if not url then
        local def = Bridge.ItemDef(name)
        if def and type(def.image) == 'string' and fileExists(own, 'html/img/items/' .. def.image) then
            url = ('nui://%s/html/img/items/%s'):format(own, def.image)
        end
    end
    url = url or ('nui://%s/html/img/items/nzr_unknown.png'):format(own)
    imageCache[name] = url
    return url
end

-- ════════════════════════════════════════════════════════════════════════
-- HOTBAR
-- Key mappings of other resources still fire while the radio's keypad uses the number row
-- (raised radio, head unit), so the inventory's hotbar is switched off meanwhile.
-- ox_inventory: LocalPlayer.state.invHotkeys. qb-inventory and its forks (ps, lj): their busy
-- flag inv_busy, the only switch they read (it also keeps the inventory shut meanwhile).
-- Re-asserted every 500 ms (a progress bar that ends clears inv_busy); only a value set here
-- is put back, so a flag another script holds is never cleared by us.
-- ════════════════════════════════════════════════════════════════════════

local HOTBAR = {
    ['ox_inventory'] = { key = 'invHotkeys', block = false, free = true, replicate = false },
    ['qb-inventory'] = { key = 'inv_busy', block = true, free = false, replicate = true },
    ['ps-inventory'] = { key = 'inv_busy', block = true, free = false, replicate = true },
    ['lj-inventory'] = { key = 'inv_busy', block = true, free = false, replicate = true },
}
local hotbarBy = {}        -- [owner] = true
local hotbarSet = nil      -- the rule whose value was set here
local hotbarLoop = false

local function setPlayerState(key, value, replicate)
    local ok, err = pcall(function() LocalPlayer.state:set(key, value, replicate) end)
    if not ok then Bridge.Debug(('could not set %s: %s'):format(key, tostring(err))) end
end

local function hotbarHold()
    local inv = resolve()
    local rule = HOTBAR[inv]
    if not rule or GetResourceState(inv) ~= 'started' then return end
    if LocalPlayer.state[rule.key] ~= rule.block then
        setPlayerState(rule.key, rule.block, rule.replicate)
        hotbarSet = rule
    end
end

local function hotbarFree()
    local rule = hotbarSet
    hotbarSet = nil
    if rule and LocalPlayer.state[rule.key] == rule.block then
        setPlayerState(rule.key, rule.free, rule.replicate)
    end
end

function Bridge.Inv.BlockHotbar(owner, on)
    hotbarBy[owner or 'default'] = on and true or nil
    if next(hotbarBy) == nil then
        hotbarFree()
        return
    end
    hotbarHold()
    if hotbarLoop then return end
    hotbarLoop = true
    CreateThread(function()
        while next(hotbarBy) ~= nil do
            Wait(500)
            if next(hotbarBy) ~= nil then hotbarHold() end
        end
        hotbarLoop = false
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hotbarBy = {}
    hotbarFree()
end)
