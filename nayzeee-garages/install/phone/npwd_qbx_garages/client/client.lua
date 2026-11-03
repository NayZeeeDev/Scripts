--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_qbx_garages" (Qbox) — client part.

  WHERE IT GOES  npwd_qbx_garages/client/client.lua  (replace the file; optional, keep a backup)
  WHAT IT DOES   Same two NUI callbacks as the original ('npwd:qbx_garage:getVehicles',
                 'npwd:qbx_garage:requestWaypoint'). The waypoint uses the vehicle when it is
                 streamed nearby, else the coordinates the server sent with the list (where
                 nayzeee tracks the vehicle, or its garage / impound).
  NEEDS          server/server.lua from this folder (it adds `coords` to every vehicle).
  CONFIRMED      NUI callback names and the createNotification call shape against
                 npwd_qbx_garages 1.1.0; locale keys 'notification.marked' /
                 'notification.cannot_locate' come from its locales/*.json (English fallback).
]]

local coordsByPlate = {}

local function trimmed(plate)
    if type(plate) ~= 'string' then return nil end
    return (plate:gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

local function text(key, fallback)
    local ok, value = pcall(locale, key)
    if ok and type(value) == 'string' and value ~= '' and value ~= key then return value end
    return fallback
end

local function typeOf(model)
    if model == nil then return 'car' end
    local ok, class = pcall(GetVehicleClassFromName, model)
    if not ok then return 'car' end
    if class == 15 or class == 16 then return 'aircraft' end
    if class == 14 then return 'boat' end
    if class == 13 or class == 8 then return 'bike' end
    return 'car'
end

local function worldCoords(plate)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and trimmed(GetVehicleNumberPlateText(vehicle)) == plate then
            return GetEntityCoords(vehicle)
        end
    end
    return nil
end

RegisterNUICallback('npwd:qbx_garage:getVehicles', function(_, cb)
    local ok, vehicles = pcall(lib.callback.await, 'npwd_qbx_garages:server:getPlayerVehicles', false)
    if not ok or type(vehicles) ~= 'table' then vehicles = {} end
    coordsByPlate = {}
    for _, v in pairs(vehicles) do
        v.type = typeOf(v.model)
        local plate = trimmed(v.plate)
        if plate and type(v.coords) == 'table' and tonumber(v.coords.x) and tonumber(v.coords.y) then
            coordsByPlate[plate] = v.coords
        end
    end
    cb({ status = 'ok', data = vehicles })
end)

RegisterNUICallback('npwd:qbx_garage:requestWaypoint', function(data, cb)
    local plate = trimmed(type(data) == 'table' and data.plate or nil)
    local coords = plate and (worldCoords(plate) or coordsByPlate[plate]) or nil
    if coords then SetNewWaypoint(coords.x + 0.0, coords.y + 0.0) end
    pcall(function()
        exports.npwd:createNotification({
            notisId = 'npwd:qbx_garage:requestWaypoint',
            appId = 'npwd_qbx_garages',
            content = coords and text('notification.marked', 'Your vehicle has been marked')
                or text('notification.cannot_locate', 'This vehicle cannot be located'),
            keepOpen = false,
            duration = 5000,
            path = '/npwd_qbx_garages',
        })
    end)
    cb({})
end)
