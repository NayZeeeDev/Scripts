if not NAYZEEE_LOCK_OK then return end

--[[
    Server bridge (open file). Framework, inventory, garage, keys and notifications.
    Change the options below or add your own resource in the matching function.
]]

Bridge = {
    Framework = 'auto',        -- auto | esx | qbcore | qbox
    Inventory = 'auto',        -- auto | framework | ox_inventory | qs-inventory | codem-inventory | core_inventory
                               -- | origen_inventory | tgiann-inventory | ps-inventory | qb-inventory | custom
    Garage    = 'default',     -- default (writes owned_vehicles / player_vehicles) | jg-advancedgarages | cd_garage
                               -- | okokGarage | qs-advancedgarages | loaf_garage | custom
    Keys      = 'default',     -- default (client events) | qb-vehiclekeys | qs-vehiclekeys | wasabi_carlock | vehicles_keys
                               -- | okokVehicleKey | mk_vehiclekeys | MrNewbVehicleKeys | custom
    NotifyWith = 'ox_lib',     -- ox_lib | esx | qb | okokNotify | wasabi_notify | custom
}

local ESX, QB

-- ── detection ───────────────────────────────────────────────────────────
local function started(name) return GetResourceState(name) == 'started' or GetResourceState(name) == 'starting' end

if Bridge.Framework == 'auto' then
    if started('qbx_core') then Bridge.Framework = 'qbox'
    elseif started('qb-core') then Bridge.Framework = 'qbcore'
    elseif started('es_extended') then Bridge.Framework = 'esx'
    else Bridge.Framework = 'standalone' end
end
if Bridge.Framework == 'esx' then ESX = exports.es_extended:getSharedObject()
elseif Bridge.Framework == 'qbcore' then QB = exports['qb-core']:GetCoreObject() end

if Bridge.Inventory == 'auto' then
    Bridge.Inventory = 'framework'
    for _, name in ipairs({ 'ox_inventory', 'qs-inventory', 'codem-inventory', 'core_inventory', 'origen_inventory', 'tgiann-inventory', 'ps-inventory' }) do
        if started(name) then Bridge.Inventory = name break end
    end
end

local function qbPlayer(src)
    if Bridge.Framework == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    return QB and QB.Functions.GetPlayer(src)
end

local function esxPlayer(src) return ESX and ESX.GetPlayerFromId(src) end

-- ── identity ────────────────────────────────────────────────────────────
-- The identifier coins are stored under (character id on multi-character servers)
function Bridge.GetIdentifier(src)
    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        return x and x.identifier
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local p = qbPlayer(src)
        return p and p.PlayerData.citizenid
    end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.GetName(src)
    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        if x then return x.getName() end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local p = qbPlayer(src)
        if p then return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) end
    end
    return GetPlayerName(src) or ('Player ' .. src)
end

function Bridge.GetDiscord(src)
    local id = GetPlayerIdentifierByType(src, 'discord')
    return id and id:gsub('discord:', '') or nil
end

function Bridge.IsFrameworkAdmin(src)
    local groups = ServerConfig.FrameworkGroups or {}
    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        local g = x and x.getGroup()
        for _, v in ipairs(groups) do if g == v then return true end end
    elseif Bridge.Framework == 'qbcore' then
        for _, v in ipairs(groups) do if QB.Functions.HasPermission(src, v) then return true end end
    elseif Bridge.Framework == 'qbox' then
        for _, v in ipairs(groups) do if IsPlayerAceAllowed(src, 'group.' .. v) then return true end end
    end
    return false
end

-- ── items ───────────────────────────────────────────────────────────────
function Bridge.CanCarry(src, item, count)
    local inv = Bridge.Inventory
    if inv == 'ox_inventory' then return exports.ox_inventory:CanCarryItem(src, item, count) end
    if Bridge.Framework == 'esx' and inv == 'framework' then
        local x = esxPlayer(src)
        if x and x.canCarryItem then return x.canCarryItem(item, count) end
    end
    return true
end

-- Returns true when the item was given
function Bridge.GiveItem(src, item, count, metadata)
    count = count or 1
    local inv = Bridge.Inventory
    if not Bridge.CanCarry(src, item, count) then return false end
    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(src, item, count, metadata) and true or false
    elseif inv == 'core_inventory' then
        return exports.core_inventory:addItem(src, item, count, metadata) and true or false
    elseif inv == 'origen_inventory' then
        return exports.origen_inventory:addItem(src, item, count, metadata) and true or false
    elseif inv == 'qs-inventory' or inv == 'codem-inventory' or inv == 'tgiann-inventory' or inv == 'ps-inventory' then
        return exports[inv]:AddItem(src, item, count, nil, metadata) and true or false
    elseif inv == 'custom' then
        -- return exports['my-inventory']:AddItem(src, item, count)
        return false
    end
    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        if x then x.addInventoryItem(item, count) return true end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local p = qbPlayer(src)
        if p then return p.Functions.AddItem(item, count, nil, metadata) ~= false end
    end
    return false
end

-- Weapon purchases. Inventory based servers get the weapon as an item.
function Bridge.GiveWeapon(src, weapon, ammo)
    local lower = weapon:lower()
    if Bridge.Inventory ~= 'framework' then
        return Bridge.GiveItem(src, lower, 1, Bridge.Inventory == 'ox_inventory' and { ammo = ammo } or nil)
    end
    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        if x then
            if x.hasWeapon and x.hasWeapon(weapon:upper()) then
                x.addWeaponAmmo(weapon:upper(), ammo)
            else
                x.addWeapon(weapon:upper(), ammo)
            end
            return true
        end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local p = qbPlayer(src)
        if p then return p.Functions.AddItem(lower, 1) ~= false end
    end
    return false
end

-- ── vehicles ────────────────────────────────────────────────────────────
function Bridge.PlateExists(plate)
    if Bridge.Framework == 'standalone' then return false end
    local tbl = Bridge.Framework == 'esx' and 'owned_vehicles' or 'player_vehicles'
    local ok, row = pcall(MySQL.scalar.await, ('SELECT 1 FROM %s WHERE plate = ? LIMIT 1'):format(tbl), { plate })
    return ok and row ~= nil
end

-- Store a purchased vehicle. Returns the plate or nil.
function Bridge.AddVehicle(src, model, plate)
    local g = Bridge.Garage
    local hash = joaat(model)
    if g == 'jg-advancedgarages' then
        -- jg reads owned_vehicles / player_vehicles, the default insert below is correct for it
    elseif g == 'cd_garage' then
        exports['cd_garage']:AddVehicleBySpawnName(src, model, plate) return plate
    elseif g == 'okokGarage' then
        exports['okokGarage']:AddVehicle(src, model, plate, Config.Vehicles.Garage) return plate
    elseif g == 'qs-advancedgarages' then
        exports['qs-advancedgarages']:AddVehicleToGarage(src, model, plate, Config.Vehicles.Garage) return plate
    elseif g == 'loaf_garage' then
        exports['loaf_garage']:AddVehicle(src, model, plate) return plate
    elseif g == 'custom' then
        -- exports['my-garage']:AddVehicle(src, model, plate) return plate
        return nil
    end

    if Bridge.Framework == 'esx' then
        local x = esxPlayer(src)
        if not x then return nil end
        local props = json.encode({ model = hash, plate = plate, fuelLevel = 100.0, bodyHealth = 1000.0, engineHealth = 1000.0 })
        MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, ?)',
            { x.identifier, plate, props, Config.Vehicles.Type, Config.Vehicles.SpawnOnPurchase and 0 or 1 })
        return plate
    elseif Bridge.Framework == 'qbox' and started('qbx_vehicles') then
        local p = qbPlayer(src)
        if not p then return nil end
        local id = exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = p.PlayerData.citizenid, props = { plate = plate } })
        return id and (MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE id = ?', { id }) or plate) or nil
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local p = qbPlayer(src)
        if not p then return nil end
        MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { p.PlayerData.license, p.PlayerData.citizenid, model, hash, '{}', plate, Config.Vehicles.Garage, Config.Vehicles.SpawnOnPurchase and 0 or 1 })
        return plate
    end
    return nil
end

-- Server side key hand-out (the client also fires the common key events after spawning)
function Bridge.GiveKeys(src, plate)
    local k = Bridge.Keys
    if k == 'qs-vehiclekeys' then pcall(function() exports['qs-vehiclekeys']:GiveServerKeys(src, plate) end)
    elseif k == 'wasabi_carlock' then pcall(function() exports.wasabi_carlock:GiveKey(src, plate) end)
    elseif k == 'vehicles_keys' then pcall(function() exports.vehicles_keys:giveVehicleKeysToIdentifier(Bridge.GetIdentifier(src), plate) end)
    elseif k == 'mk_vehiclekeys' then pcall(function() exports.mk_vehiclekeys:AddKey(src, plate) end)
    elseif k == 'MrNewbVehicleKeys' then pcall(function() exports.MrNewbVehicleKeys:GiveKeysByPlate(src, plate) end)
    elseif k == 'custom' then
        -- exports['my-keys']:GiveKey(src, plate)
    end
end

-- ── notify ──────────────────────────────────────────────────────────────
function Bridge.Notify(src, message, kind)
    kind = kind or 'inform'
    local n = Bridge.NotifyWith
    if n == 'esx' then TriggerClientEvent('esx:showNotification', src, message, kind)
    elseif n == 'qb' then TriggerClientEvent('QBCore:Notify', src, message, kind == 'inform' and 'primary' or kind)
    elseif n == 'okokNotify' then TriggerClientEvent('okokNotify:Alert', src, T('APP_TITLE'), message, 5000, kind == 'inform' and 'info' or kind)
    elseif n == 'wasabi_notify' then TriggerClientEvent('wasabi_notify:notify', src, T('APP_TITLE'), message, 5000, kind)
    elseif n == 'custom' then
        -- TriggerClientEvent('my-notify', src, message, kind)
    else
        TriggerClientEvent('ox_lib:notify', src, { title = T('APP_TITLE'), description = message, type = kind })
    end
end

-- ── lifecycle ───────────────────────────────────────────────────────────
function Bridge.RegisterUsableItem(name, cb)
    if not name then return end
    CreateThread(function()
        Wait(1000)
        if Bridge.Framework == 'esx' then ESX.RegisterUsableItem(name, cb)
        elseif Bridge.Framework == 'qbcore' then QB.Functions.CreateUseableItem(name, function(src) cb(src) end)
        elseif Bridge.Framework == 'qbox' then exports.qbx_core:CreateUseableItem(name, function(src) cb(src) end) end
    end)
end

function Bridge.OnLogout(fn)
    if Bridge.Framework == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) fn(src) end)
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) fn(src or source) end)   -- server side event, never from clients
    end
end
