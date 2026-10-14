--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: vehicle keys & fuel (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore).

      Bridge.Vehicle.GiveKeys(vehicle, plate?)     Bridge.Vehicle.RemoveKeys(vehicle, plate?)
      Bridge.Vehicle.SetFuel(vehicle, level)       Bridge.Vehicle.GetFuel(vehicle) → 0..100
      Bridge.Vehicle.KeysResource() / Bridge.Vehicle.FuelResource()

    Keys: qbx_vehiclekeys, qb-vehiclekeys (both granted by the server, see
    bridge/server/vehicle.lua), qs-vehiclekeys, wasabi_carlock,
    MrNewbVehicleKeys, cd_garage, Renewed-Vehiclekeys, t1ger_keys, okokGarage,
    jaksam vehicles_keys.
    Fuel: ox_fuel (state bag), LegacyFuel, cdn-fuel, ps-fuel, lc_fuel,
    okokGasStation, Renewed-Fuel, native.

    EVENTS
      nza:bridge:vehicle:keys (C→S) netId, plate   - server-granted key scripts
      nza:bridge:vehicle:keys (S→C) netId, plate   - server asked us to give keys locally

    ADDING YOUR OWN
      Bridge.KeyAdapters['my_keys'] = { give = fn(vehicle, plate, model), remove = fn(vehicle, plate, model) }
      Bridge.FuelAdapters['my_fuel'] = { set = fn(vehicle, level), get = fn(vehicle) }
      plus Bridge.Resources.keys / .fuel and the priority lists in bridge/shared.lua
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Vehicle = Bridge.Vehicle or {}

local K = {}
local F = {}
Bridge.KeyAdapters = K
Bridge.FuelAdapters = F

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYS
-- ═══════════════════════════════════════════════════════════════════════════

local function serverKeys(vehicle, plate)
    if not NetworkGetEntityIsNetworked(vehicle) then return false end
    TriggerServerEvent('nza:bridge:vehicle:keys', NetworkGetNetworkIdFromEntity(vehicle), plate)
    return true
end

K['qbx_vehiclekeys'] = { give = serverKeys }
K['qb-vehiclekeys'] = {
    give = serverKeys,
    remove = function(_, plate) TriggerEvent('qb-vehiclekeys:client:RemoveKeys', plate) end,
}
K['qs-vehiclekeys'] = {
    give = function(_, plate, model) return exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end,
    remove = function(_, plate, model) return exports['qs-vehiclekeys']:RemoveKeys(plate, model) end,
}
K['wasabi_carlock'] = {
    give = function(_, plate) exports.wasabi_carlock:GiveKey(plate) end,
    remove = function(_, plate) exports.wasabi_carlock:RemoveKey(plate) end,
}
K['MrNewbVehicleKeys'] = {
    give = function(_, plate) return exports.MrNewbVehicleKeys:GiveKeysByPlate(plate) end,
    remove = function(_, plate) return exports.MrNewbVehicleKeys:RemoveKeysByPlate(plate) end,
}
K['Renewed-Vehiclekeys'] = {
    give = function(_, plate) return exports['Renewed-Vehiclekeys']:addKey(plate) end,
    remove = function(_, plate) return exports['Renewed-Vehiclekeys']:removeKey(plate) end,
}
K['t1ger_keys'] = {
    give = function(_, plate, model) return exports['t1ger_keys']:GiveTemporaryKeys(plate, model, '') end,
}
K['cd_garage'] = {
    give = function(_, plate) TriggerEvent('cd_garage:AddKeys', plate) end,
}
K['okokGarage'] = {
    give = function(_, plate) TriggerServerEvent('okokGarage:GiveKeys', plate) end,
    remove = function(_, plate) TriggerServerEvent('okokGarage:RemoveKeys', plate, GetPlayerServerId(PlayerId())) end,
}
K['jaksam'] = {
    give = function(_, plate) TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate) end,
    remove = function(_, plate) TriggerServerEvent('vehicles_keys:selfRemoveKeys', plate) end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- FUEL
-- ═══════════════════════════════════════════════════════════════════════════

local function nativeSet(vehicle, level)
    SetVehicleFuelLevel(vehicle, level + 0.0)
    if DecorIsRegisteredAsType('_FUEL_LEVEL', 1) then DecorSetFloat(vehicle, '_FUEL_LEVEL', level + 0.0) end
end

local function exportFuel(resource)
    return {
        set = function(vehicle, level) exports[resource]:SetFuel(vehicle, level + 0.0) end,
        get = function(vehicle) return exports[resource]:GetFuel(vehicle) end,
    }
end

F['ox_fuel'] = {
    set = function(vehicle, level)
        SetVehicleFuelLevel(vehicle, level + 0.0)
        Entity(vehicle).state:set('fuel', level + 0.0, true)
    end,
    get = function(vehicle) return Entity(vehicle).state.fuel or GetVehicleFuelLevel(vehicle) end,
}
F['LegacyFuel'] = exportFuel('LegacyFuel')
F['cdn-fuel'] = exportFuel('cdn-fuel')
F['ps-fuel'] = exportFuel('ps-fuel')
F['lc_fuel'] = exportFuel('lc_fuel')
F['okokGasStation'] = exportFuel('okokGasStation')
F['Renewed-Fuel'] = exportFuel('Renewed-Fuel')
F['native'] = { set = nativeSet, get = function(vehicle) return GetVehicleFuelLevel(vehicle) end }

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local cache = {}

local function resolve(kind, adapters)
    if cache[kind] ~= nil then return cache[kind] or nil end
    local name = Bridge.Pick(kind, Bridge.Cfg(kind, 'auto'), { has = function(n) return adapters[n] ~= nil end })
    if kind == 'fuel' then name = name or 'native' end
    cache[kind] = name or false
    return name
end

function Bridge.Vehicle.KeysResource() return resolve('keys', K) end
function Bridge.Vehicle.FuelResource() return resolve('fuel', F) end

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('keys', resource) then cache.keys = nil end
    if Bridge.IsKnownResource('fuel', resource) then cache.fuel = nil end
end
AddEventHandler('onClientResourceStart', reset)
AddEventHandler('onClientResourceStop', reset)

local function plateOf(vehicle, plate)
    if type(plate) == 'string' and plate ~= '' then
        return (plate:gsub('^%s+', ''):gsub('%s+$', ''))
    end
    return (GetVehicleNumberPlateText(vehicle):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function validVehicle(vehicle)
    vehicle = tonumber(vehicle)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle) and vehicle or nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.Vehicle.GiveKeys(vehicle, plate)
    vehicle = validVehicle(vehicle)
    if not vehicle then return false end
    local name = resolve('keys', K)
    if not name then return false end
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local ok, result = Bridge.Try('keys.' .. name, K[name].give, vehicle, plateOf(vehicle, plate), model)
    return ok and result ~= false
end

function Bridge.Vehicle.RemoveKeys(vehicle, plate)
    vehicle = validVehicle(vehicle)
    if not vehicle then return false end
    local name = resolve('keys', K)
    if not name or not K[name].remove then return false end
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local ok, result = Bridge.Try('keys.' .. name, K[name].remove, vehicle, plateOf(vehicle, plate), model)
    return ok and result ~= false
end

function Bridge.Vehicle.SetFuel(vehicle, level)
    vehicle = validVehicle(vehicle)
    if not vehicle then return false end
    level = math.max(0.0, math.min(100.0, tonumber(level) or 100.0))
    local name = resolve('fuel', F)
    local ok = Bridge.Try('fuel.' .. name, F[name].set, vehicle, level)
    if not ok then nativeSet(vehicle, level) end
    return true
end

function Bridge.Vehicle.GetFuel(vehicle)
    vehicle = validVehicle(vehicle)
    if not vehicle then return 0.0 end
    local name = resolve('fuel', F)
    local ok, level = Bridge.Try('fuel.' .. name, F[name].get, vehicle)
    return (ok and tonumber(level)) or GetVehicleFuelLevel(vehicle)
end

-- the server asks for keys handled on the client
RegisterNetEvent('nza:bridge:vehicle:keys', function(netId, plate)
    if type(netId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local tries = 0
    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and tries < 20 do
        Wait(100)
        tries = tries + 1
        vehicle = NetworkGetEntityFromNetworkId(netId)
    end
    if vehicle and vehicle ~= 0 then Bridge.Vehicle.GiveKeys(vehicle, plate) end
end)
