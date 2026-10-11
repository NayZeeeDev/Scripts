if not NAYZEEE_LOCK_OK then return end

--[[
    Server bridge (open file). Framework + inventory hooks. Edit freely.
    Every function receives a player source.
]]

Bridge = { framework = 'standalone', inventory = nil }

local ESX, QB

local function detectFramework()
    local want = Config.Env.Framework
    if want ~= 'auto' then return want end
    if GetResourceState('es_extended') ~= 'missing' then return 'esx' end
    if GetResourceState('qbx_core') ~= 'missing' then return 'qbox' end
    if GetResourceState('qb-core') ~= 'missing' then return 'qbcore' end
    return 'standalone'
end

local inventories = {
    'ox_inventory', 'qb-inventory', 'ps-inventory', 'lj-inventory', 'qs-inventory', 'codem-inventory',
    'core_inventory', 'origen_inventory', 'tgiann-inventory', 'mf-inventory', 'tprp_inventory',
}

local function detectInventory()
    local want = Config.Env.Inventory
    if want == 'none' then return nil end
    if want ~= 'auto' then return want end
    for _, name in ipairs(inventories) do
        if GetResourceState(name) ~= 'missing' then return name end
    end
    return nil
end

Bridge.framework = detectFramework()
Bridge.inventory = detectInventory()

if Bridge.framework == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif Bridge.framework == 'qbcore' then
    QB = exports['qb-core']:GetCoreObject()
end

local function qbPlayer(src)
    if Bridge.framework == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    return QB and QB.Functions.GetPlayer(src)
end

local function qbAccount(name) return name == 'money' and 'cash' or name end

-- ── identity ────────────────────────────────────────────────────────────
function Bridge.GetIdentifier(src)
    if Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        return x and x.identifier
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        local p = qbPlayer(src)
        return p and p.PlayerData.citizenid
    end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, 'command') then return true end
    if Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        local g = x and x.getGroup()
        return g == 'admin' or g == 'superadmin' or g == 'god'
    elseif Bridge.framework == 'qbcore' then
        return QB.Functions.HasPermission(src, 'admin') or QB.Functions.HasPermission(src, 'god')
    end
    return false
end

-- ── money ───────────────────────────────────────────────────────────────
function Bridge.GetBalance(src, currency)
    currency = currency or 'money'
    local account = currency == 'crypto' and 'crypto' or Config.Env.Accounts.wager
    if Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x then return 0 end
        if currency == 'crypto' then return 0 end
        if account == 'money' then return x.getMoney() end
        local acc = x.getAccount(account)
        return acc and acc.money or 0
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        local p = qbPlayer(src)
        return p and (p.PlayerData.money[qbAccount(account)] or 0) or 0
    end
    return 0
end

-- Returns true when the amount was removed
function Bridge.RemoveMoney(src, amount, currency, reason)
    currency = currency or 'money'
    local account = currency == 'crypto' and 'crypto' or Config.Env.Accounts.wager
    if amount <= 0 then return true end
    if Bridge.GetBalance(src, currency) < amount then return false end
    if Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x or currency == 'crypto' then return false end
        x.removeAccountMoney(account, amount, reason)
        return true
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.RemoveMoney(qbAccount(account), amount, reason) or false
    end
    return false
end

function Bridge.AddMoney(src, amount, currency, reason)
    currency = currency or 'money'
    local account = currency == 'crypto' and 'crypto' or Config.Env.Accounts.payout
    if amount <= 0 then return true end
    if Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x or currency == 'crypto' then return false end
        x.addAccountMoney(account, amount, reason)
        return true
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.AddMoney(qbAccount(account), amount, reason) or false
    end
    return false
end

-- Hook your XP / levelling system here
function Bridge.GiveXp(src, amount)
    -- exports['pickle_xp']:AddPlayerXP(src, 'racing', amount)
end

-- ── vehicles ────────────────────────────────────────────────────────────
-- Returns a list of { plate, model } owned by the player
function Bridge.GetOwnedVehicles(src)
    local id = Bridge.GetIdentifier(src)
    if not id then return {} end
    local out = {}
    if Bridge.framework == 'esx' then
        local rows = MySQL.query.await('SELECT plate, vehicle FROM owned_vehicles WHERE owner = ?', { id }) or {}
        for _, r in ipairs(rows) do
            local ok, v = pcall(json.decode, r.vehicle or '{}')
            if ok and v and v.model then out[#out + 1] = { plate = r.plate or v.plate, model = v.model } end
        end
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        local rows = MySQL.query.await('SELECT plate, hash, vehicle FROM player_vehicles WHERE citizenid = ?', { id }) or {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { plate = r.plate, model = tonumber(r.hash) or joaat(r.vehicle or '') }
        end
    end
    return out
end

-- ── items ───────────────────────────────────────────────────────────────
function Bridge.RegisterUsableItem(name, cb)
    if not name then return end
    CreateThread(function()
        if Bridge.inventory then
            while GetResourceState(Bridge.inventory) ~= 'started' do Wait(250) end
        end
        if Bridge.inventory == 'ox_inventory' and Bridge.framework == 'standalone' then
            exports('racing_tablet', function(event, _, inventory)
                if event == 'usedItem' then cb(inventory.id) end
            end)
        elseif Bridge.inventory == 'qs-inventory' then
            exports['qs-inventory']:CreateUsableItem(name, function(src) cb(src) end)
        elseif Bridge.inventory == 'origen_inventory' then
            exports.origen_inventory:CreateUsableItem(name, function(src) cb(src) end)
        elseif Bridge.framework == 'esx' then
            ESX.RegisterUsableItem(name, function(src) cb(src) end)
        elseif Bridge.framework == 'qbcore' then
            QB.Functions.CreateUseableItem(name, function(src) cb(src) end)
        elseif Bridge.framework == 'qbox' then
            exports.qbx_core:CreateUseableItem(name, function(src) cb(src) end)
        end
    end)
end

-- Returns true if the items were given
function Bridge.GiveItem(src, item, amount, metadata)
    local inv = Bridge.inventory
    amount = amount or 1
    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(src, item, amount, metadata) and true or false
    elseif inv == 'core_inventory' then
        return exports.core_inventory:addItem(src, item, amount, metadata) and true or false
    elseif inv == 'origen_inventory' then
        return exports.origen_inventory:addItem(src, item, amount, metadata) and true or false
    elseif inv == 'tprp_inventory' then
        return exports.tprp_inventory:AddItem(src, item, amount, metadata) and true or false
    elseif inv == 'mf-inventory' then
        local p = qbPlayer(src)
        return p and p.Functions.AddItem(item, amount, nil, metadata) or false
    elseif inv then
        return exports[inv]:AddItem(src, item, amount, nil, metadata) and true or false
    elseif Bridge.framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if x then x.addInventoryItem(item, amount) return true end
    end
    return false
end

-- ── logout hooks ────────────────────────────────────────────────────────
function Bridge.OnLogout(fn)
    if Bridge.framework == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) fn(src) end)
    elseif Bridge.framework == 'qbcore' or Bridge.framework == 'qbox' then
        RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(src) fn(src or source) end)
    end
end
