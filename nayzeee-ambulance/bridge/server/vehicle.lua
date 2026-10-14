--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: vehicles (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore).

      Bridge.Vehicle.SetPlate(vehicle, plate)          entity or netId
      Bridge.Vehicle.GiveKeys(src, vehicle, plate?)    → bool
          qbx_vehiclekeys / qb-vehiclekeys are given keys from the server
          (exports GiveKeys); every other key script runs on the client
          (bridge/client/vehicle.lua).

    NET EVENT (C→S)
      nza:bridge:vehicle:keys (netId, plate)  - client Bridge.Vehicle.GiveKeys on
      qb/qbx. Checked: on-duty medic or police, vehicle exists, within
      Config.Bridge.keysDistance, plate matches, max 1 per second.

    EVENTS SENT
      nza:bridge:vehicle:keys (S→C) netId, plate   - client half for client-side key scripts
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Vehicle = Bridge.Vehicle or {}

local SERVER_KEYS = {
    ['qbx_vehiclekeys'] = function(src, vehicle)
        return exports.qbx_vehiclekeys:GiveKeys(src, vehicle) ~= false
    end,
    ['qb-vehiclekeys'] = function(src, _, plate)
        exports['qb-vehiclekeys']:GiveKeys(src, plate)
        return true
    end,
}
Bridge.ServerKeyAdapters = SERVER_KEYS

local function toEntity(vehicle)
    vehicle = tonumber(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    if DoesEntityExist(vehicle) then return vehicle end
    local ent = NetworkGetEntityFromNetworkId(vehicle)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    return nil
end

local function trimPlate(plate)
    if type(plate) ~= 'string' then return nil end
    return (plate:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function keysAdapter()
    return Bridge.Pick('keys', Bridge.Cfg('keys', 'auto'))
end

function Bridge.Vehicle.SetPlate(vehicle, plate)
    local ent = toEntity(vehicle)
    plate = trimPlate(plate)
    if not ent or not plate or plate == '' then return false end
    SetVehicleNumberPlateText(ent, plate:sub(1, 8))
    return true
end

function Bridge.Vehicle.GiveKeys(src, vehicle, plate)
    src = tonumber(src)
    local ent = toEntity(vehicle)
    if not src or not ent then return false end
    plate = trimPlate(plate) or trimPlate(GetVehicleNumberPlateText(ent))
    local name = keysAdapter()
    if not name then return false end
    local fn = SERVER_KEYS[name]
    if fn then
        local ok, done = Bridge.Try('keys.' .. name, fn, src, ent, plate)
        return ok and done ~= false
    end
    TriggerClientEvent('nza:bridge:vehicle:keys', src, NetworkGetNetworkIdFromEntity(ent), plate)
    return true
end

RegisterNetEvent('nza:bridge:vehicle:keys', function(netId, plate)
    local src = tonumber(source)
    if not src or not Bridge.Throttle(src, 'vehicle:keys', 1000) then return end
    if type(netId) ~= 'number' then return end
    local job = Bridge.GetJob(src)
    if not job.onDuty or not (Bridge.IsMedicJob(job.name) or Bridge.IsPoliceJob(job.name)) then return end

    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return end
    local dist = #(GetEntityCoords(GetPlayerPed(tostring(src))) - GetEntityCoords(ent))
    if dist > (tonumber(Bridge.Cfg('keysDistance', 8.0)) or 8.0) then return end

    local realPlate = trimPlate(GetVehicleNumberPlateText(ent))
    plate = trimPlate(plate)
    if plate and realPlate and plate:upper() ~= realPlate:upper() then return end

    local name = keysAdapter()
    local fn = name and SERVER_KEYS[name]
    if fn then Bridge.Try('keys.' .. name, fn, src, ent, realPlate) end
end)
