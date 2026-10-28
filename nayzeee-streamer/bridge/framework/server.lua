-- Framework bridge (server): ESX Legacy, QBCore and Qbox behind one API.
-- Open under escrow. Item functions go through bridge/inventory/server.lua.

Bridge = Bridge or {}

local ESX, QBCore

local function started(name)
    return GetResourceState(name) == 'started'
end

local function detectFramework()
    local wanted = Config.Framework
    if wanted == 'qbx' or wanted == 'qbx_core' then wanted = 'qbox' end
    if wanted == 'qb' or wanted == 'qb-core' then wanted = 'qbcore' end
    if wanted == 'es_extended' then wanted = 'esx' end
    if wanted == 'esx' or wanted == 'qbcore' or wanted == 'qbox' then return wanted end

    -- qbx_core provides qb-core, so it is checked first
    local order = { { 'qbx_core', 'qbox' }, { 'qb-core', 'qbcore' }, { 'es_extended', 'esx' } }
    for _, entry in ipairs(order) do
        if started(entry[1]) then return entry[2] end
    end
    for _, entry in ipairs(order) do
        if GetResourceState(entry[1]) == 'starting' then return entry[2] end
    end
    return 'none'
end

Bridge.Framework = detectFramework()

---------------------------------------------------------------------------------------------------
-- Core objects (fetched lazily so a late framework start still works)

local function getESX()
    if not ESX and started('es_extended') then
        local ok, obj = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok then ESX = obj end
    end
    return ESX
end

local function getQB()
    if not QBCore and started('qb-core') then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then QBCore = obj end
    end
    return QBCore
end

local function qbx(fnName, ...)
    if not started('qbx_core') then return nil end
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports.qbx_core[fnName](exports.qbx_core, table.unpack(args, 1, args.n)) end)
    if not ok then return nil end
    return a, b
end

--- ESX shared object / QBCore core object / nil (Qbox uses exports).
function Bridge.GetCore()
    if Bridge.Framework == 'esx' then return getESX() end
    if Bridge.Framework == 'qbcore' then return getQB() end
    if Bridge.Framework == 'qbox' then return getQB() end   -- qbx_core keeps a qb-core compatible object
    return nil
end

--- xPlayer (ESX) or Player (QBCore / Qbox) for a source.
function Bridge.GetPlayerObject(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local fw = Bridge.Framework
    if fw == 'esx' then
        local core = getESX()
        if not core then return nil end
        local ok, xPlayer = pcall(core.GetPlayerFromId, src)
        return ok and xPlayer or nil
    elseif fw == 'qbcore' then
        local core = getQB()
        if not core then return nil end
        local ok, player = pcall(core.Functions.GetPlayer, src)
        return ok and player or nil
    elseif fw == 'qbox' then
        return qbx('GetPlayer', src)
    end
    return nil
end

local function playerData(src)
    local player = Bridge.GetPlayerObject(src)
    return player and player.PlayerData or nil
end

---------------------------------------------------------------------------------------------------
-- Identity

--- License without the "license:" prefix.
function Bridge.GetLicense(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, id = pcall(GetPlayerIdentifierByType, tostring(src), 'license')
    if not ok or not id then
        id = nil
        for i = 0, GetNumPlayerIdentifiers(tostring(src)) - 1 do
            local value = GetPlayerIdentifier(tostring(src), i)
            if value and value:sub(1, 8) == 'license:' then id = value break end
        end
    end
    if not id then return nil end
    return (id:gsub('^license:', ''))
end

--- ESX identifier or QBCore / Qbox citizenid. License when no framework runs.
function Bridge.GetIdentifier(src)
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        return xPlayer and xPlayer.identifier or nil
    elseif fw == 'qbcore' or fw == 'qbox' then
        local data = playerData(src)
        return data and data.citizenid or nil
    end
    return Bridge.GetLicense(src)
end

--- Stable server-local identity for the network (SPEC §6): 'char:<id>' or 'lic:<license>'.
function Bridge.GetRef(src)
    if Config.Identity == 'license' or Bridge.Framework == 'none' then
        local license = Bridge.GetLicense(src)
        return license and ('lic:' .. license) or nil
    end
    local identifier = Bridge.GetIdentifier(src)
    return identifier and ('char:' .. tostring(identifier)) or nil
end

--- Character full name, or the player name when no character is loaded.
function Bridge.GetName(src)
    src = tonumber(src)
    if not src then return 'Unknown' end
    local name
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        if xPlayer then
            local ok, value = pcall(function() return xPlayer.getName() end)
            if ok and type(value) == 'string' then name = value end
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local data = playerData(src)
        local info = data and data.charinfo
        if info and (info.firstname or info.lastname) then
            name = ('%s %s'):format(info.firstname or '', info.lastname or '')
        end
    end
    name = Utils.Trim(name or '')
    if name == '' then name = Utils.Trim(GetPlayerName(src) or '') end
    if name == '' then name = 'Player ' .. src end
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

function Bridge.IsLoaded(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false end
    if Bridge.Framework == 'none' then return true end
    return Bridge.GetPlayerObject(src) ~= nil
end

function Bridge.GetSourceFromIdentifier(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return nil end
    local fw = Bridge.Framework
    if fw == 'esx' then
        local core = getESX()
        if core then
            local ok, xPlayer = pcall(core.GetPlayerFromIdentifier, identifier)
            if ok and xPlayer then return xPlayer.source end
        end
        return nil
    elseif fw == 'qbcore' then
        local core = getQB()
        if core then
            local ok, player = pcall(core.Functions.GetPlayerByCitizenId, identifier)
            if ok and player and player.PlayerData then return player.PlayerData.source end
        end
        return nil
    elseif fw == 'qbox' then
        local player = qbx('GetPlayerByCitizenId', identifier)
        return player and player.PlayerData and player.PlayerData.source or nil
    end
    for _, src in ipairs(Bridge.GetPlayers()) do
        if Bridge.GetLicense(src) == identifier then return src end
    end
    return nil
end

--- Online source for a network ref ('char:...' / 'lic:...').
function Bridge.GetSourceFromRef(ref)
    if type(ref) ~= 'string' then return nil end
    local kind, value = ref:match('^(%a+):(.+)$')
    if not kind then return nil end
    if kind == 'char' and Bridge.Framework ~= 'none' then
        local src = Bridge.GetSourceFromIdentifier(value)
        if src and Bridge.GetRef(src) == ref then return src end
        return nil
    end
    for _, src in ipairs(Bridge.GetPlayers()) do
        if Bridge.GetRef(src) == ref then return src end
    end
    return nil
end

--- Sources of every loaded player.
function Bridge.GetPlayers()
    local list = {}
    local fw = Bridge.Framework
    if fw == 'esx' then
        local core = getESX()
        if core then
            if core.GetExtendedPlayers then
                local ok, players = pcall(core.GetExtendedPlayers)
                if ok and type(players) == 'table' then
                    for _, xPlayer in pairs(players) do
                        if xPlayer and xPlayer.source then list[#list + 1] = xPlayer.source end
                    end
                    return list
                end
            end
            local ok, sources = pcall(core.GetPlayers)
            if ok and type(sources) == 'table' then
                for _, src in pairs(sources) do list[#list + 1] = tonumber(src) end
            end
        end
        return list
    elseif fw == 'qbcore' or fw == 'qbox' then
        local players
        if fw == 'qbox' then
            players = qbx('GetQBPlayers')
        else
            local core = getQB()
            if core then
                local ok, value = pcall(core.Functions.GetQBPlayers)
                if ok then players = value end
            end
        end
        if type(players) == 'table' then
            for src, player in pairs(players) do
                local id = tonumber(src) or (player and player.PlayerData and player.PlayerData.source)
                if id then list[#list + 1] = id end
            end
        end
        return list
    end
    for _, src in ipairs(GetPlayers()) do list[#list + 1] = tonumber(src) end
    return list
end

---------------------------------------------------------------------------------------------------
-- Money

local function moneyAccount(account)
    account = type(account) == 'string' and account or 'bank'
    if Bridge.Framework == 'esx' then
        if account == 'cash' then return 'money' end
        if account == 'dirty' or account == 'black' then return 'black_money' end
        return account
    end
    if account == 'money' then return 'cash' end
    return account
end

local function amountOf(amount)
    amount = tonumber(amount)
    if not Utils.IsFinite(amount) then return nil end
    amount = math.floor(amount)
    if amount <= 0 then return nil end
    return amount
end

function Bridge.GetMoney(src, account)
    local name = moneyAccount(account)
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        if not xPlayer then return 0 end
        local ok, acc = pcall(xPlayer.getAccount, name)
        return ok and acc and tonumber(acc.money) or 0
    elseif fw == 'qbcore' or fw == 'qbox' then
        local data = playerData(src)
        return data and data.money and tonumber(data.money[name]) or 0
    end
    return 0
end

function Bridge.AddMoney(src, account, amount, reason)
    amount = amountOf(amount)
    if not amount then return false end
    local name = moneyAccount(account)
    reason = reason or 'nayzeee-streamer'
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        if not xPlayer then return false end
        local okAcc, acc = pcall(xPlayer.getAccount, name)
        if not okAcc or not acc then return false end
        local ok = pcall(xPlayer.addAccountMoney, name, amount, reason)
        return ok
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = Bridge.GetPlayerObject(src)
        if not player then return false end
        if player.PlayerData and player.PlayerData.money and player.PlayerData.money[name] == nil then return false end
        if player.Functions and player.Functions.AddMoney then
            local ok, res = pcall(player.Functions.AddMoney, name, amount, reason)
            return ok and res ~= false
        end
        if fw == 'qbox' then
            return qbx('AddMoney', src, name, amount, reason) == true
        end
    end
    return false
end

function Bridge.RemoveMoney(src, account, amount, reason)
    amount = amountOf(amount)
    if not amount then return false end
    if Bridge.GetMoney(src, account) < amount then return false end   -- QBCore lets bank go negative, we never do
    local name = moneyAccount(account)
    reason = reason or 'nayzeee-streamer'
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        if not xPlayer then return false end
        local ok = pcall(xPlayer.removeAccountMoney, name, amount, reason)
        return ok
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = Bridge.GetPlayerObject(src)
        if not player then return false end
        if player.Functions and player.Functions.RemoveMoney then
            local ok, res = pcall(player.Functions.RemoveMoney, name, amount, reason)
            return ok and res ~= false
        end
        if fw == 'qbox' then
            return qbx('RemoveMoney', src, name, amount, reason) == true
        end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- Items (bridge/inventory/server.lua does the work)

local function inventory()
    return Bridge.Inventory
end

function Bridge.GetItemCount(src, item)
    local inv = inventory()
    if not inv or type(item) ~= 'string' then return 0 end
    return math.floor(tonumber(inv.GetItemCount(src, item)) or 0)
end

function Bridge.HasItem(src, item, count)
    return Bridge.GetItemCount(src, item) >= (tonumber(count) or 1)
end

function Bridge.AddItem(src, item, count, meta)
    local inv = inventory()
    count = amountOf(count or 1)
    if not inv or not count or type(item) ~= 'string' then return false end
    return inv.AddItem(src, item, count, meta) == true
end

function Bridge.RemoveItem(src, item, count)
    local inv = inventory()
    count = amountOf(count or 1)
    if not inv or not count or type(item) ~= 'string' then return false end
    if Bridge.GetItemCount(src, item) < count then return false end
    return inv.RemoveItem(src, item, count) == true
end

function Bridge.CanCarry(src, item, count)
    local inv = inventory()
    count = amountOf(count or 1)
    if not inv or not count or type(item) ~= 'string' then return false end
    return inv.CanCarry(src, item, count) ~= false
end

--- fn(src) runs when the item is used. With ox_inventory the client export handles use instead.
function Bridge.RegisterUsableItem(item, fn)
    local inv = inventory()
    if not inv or type(item) ~= 'string' or type(fn) ~= 'function' then return false end
    return inv.RegisterUsableItem(item, fn) == true
end

function Bridge.GetItemLabel(item)
    local inv = inventory()
    local label = inv and inv.GetItemLabel and inv.GetItemLabel(item)
    return type(label) == 'string' and label or Utils.ItemLabel(item)
end

---------------------------------------------------------------------------------------------------
-- Staff

function Bridge.IsAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end   -- server console
    local admin = Config.Admin or {}
    if admin.Ace and IsPlayerAceAllowed(src, admin.Ace) then return true end

    local groups = admin.Groups or {}
    local fw = Bridge.Framework
    if fw == 'esx' then
        local xPlayer = Bridge.GetPlayerObject(src)
        if xPlayer then
            local ok, group = pcall(xPlayer.getGroup)
            if ok and group and Utils.Contains(groups, group) then return true end
        end
    elseif fw == 'qbcore' then
        local core = getQB()
        if core and core.Functions.HasPermission then
            for _, group in ipairs(groups) do
                local ok, allowed = pcall(core.Functions.HasPermission, src, group)
                if ok and allowed then return true end
            end
        end
    end

    -- ACE groups (Qbox and most setups): add_ace group.admin admin allow
    for _, group in ipairs(groups) do
        if IsPlayerAceAllowed(src, group) or IsPlayerAceAllowed(src, 'group.' .. group) then return true end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- Player loaded / unloaded hooks

local loadedHooks, unloadedHooks = {}, {}
local loaded = {}

local function runHook(fn, src)
    CreateThread(function()
        local ok, err = pcall(fn, src)
        if not ok then Utils.Print('error', ('player hook failed: %s'):format(err)) end
    end)
end

local function markLoaded(src)
    src = tonumber(src)
    if not src or src <= 0 or loaded[src] then return end
    if not GetPlayerName(src) then return end
    if Bridge.Framework ~= 'none' and not Bridge.GetPlayerObject(src) then return end
    loaded[src] = true
    DebugPrint('player loaded', src)
    for i = 1, #loadedHooks do runHook(loadedHooks[i], src) end
end

local function markUnloaded(src)
    src = tonumber(src)
    if not src or not loaded[src] then return end
    loaded[src] = nil
    DebugPrint('player unloaded', src)
    for i = 1, #unloadedHooks do runHook(unloadedHooks[i], src) end
end

-- Logout events fire before the framework drops the player object. Wait for it to go so a
-- faked event can't unload someone who is still in.
local function confirmUnload(src)
    src = tonumber(src)
    if not src or not loaded[src] then return end
    CreateThread(function()
        for _ = 1, 10 do
            Wait(500)
            if not loaded[src] then return end
            if not GetPlayerName(src) or not Bridge.GetPlayerObject(src) then
                markUnloaded(src)
                return
            end
        end
    end)
end

function Bridge.OnPlayerLoaded(fn)
    if type(fn) ~= 'function' then return end
    loadedHooks[#loadedHooks + 1] = fn
    for src in pairs(loaded) do runHook(fn, src) end
end

function Bridge.OnPlayerUnloaded(fn)
    if type(fn) ~= 'function' then return end
    unloadedHooks[#unloadedHooks + 1] = fn
end

if Bridge.Framework == 'esx' then
    AddEventHandler('esx:playerLoaded', function(playerId)
        markLoaded(playerId)
    end)
    AddEventHandler('esx:playerLogout', function(playerId)
        confirmUnload(playerId)
    end)
    AddEventHandler('esx:playerDropped', function(playerId)
        confirmUnload(playerId)
    end)
elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source
        markLoaded(src)
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        confirmUnload(src)
    end)
    if Bridge.Framework == 'qbox' then
        AddEventHandler('qbx_core:server:playerLoaded', function(player)
            local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or player
            markLoaded(src)
        end)
        AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
            confirmUnload(src)
        end)
    end
else
    AddEventHandler('playerJoining', function()
        local src = source
        SetTimeout(1000, function() markLoaded(src) end)
    end)
end

AddEventHandler('playerDropped', function()
    markUnloaded(source)
end)

-- Restart support: players already in count as loaded.
CreateThread(function()
    if Bridge.Framework == 'none' then
        Utils.Print('warn', L('console.no_framework'))
    else
        DebugPrint(L('console.framework', Bridge.Framework))
    end
    for _, src in ipairs(Bridge.GetPlayers()) do markLoaded(src) end
end)

--- Sources the bridge has seen load (cheaper than Bridge.GetPlayers for hot paths).
function Bridge.LoadedPlayers()
    local list = {}
    for src in pairs(loaded) do list[#list + 1] = src end
    return list
end
