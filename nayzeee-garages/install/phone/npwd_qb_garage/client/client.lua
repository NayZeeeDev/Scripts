--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_qb_garage" (QBCore) — client part.

  WHERE IT GOES  npwd_qb_garage/client/client.lua  (replace the file; keep a backup)
  WHAT IT DOES   Same NUI callbacks as the original ('npwd:qb-garage:getVehicles',
                 'npwd:qb-garage:requestWaypoint') and the same server event. Fixes the
                 original registering a new 'npwd:qb-garage:sendVehicles' handler on every
                 open (each open answered every older request again), times a request out
                 after 8 s, and marks vehicles that are not streamed nearby with the
                 coordinates the server sent (where nayzeee tracks the vehicle).
  NEEDS          server/server.lua from this folder.
  CONFIRMED      callback / event names against npwd_qb_garage (npwd-community, main).
                 Notifications use qb-core's client event 'QBCore:Notify' (text, type).
]]

local pending = {}        -- NUI callbacks waiting for the server's answer
local coordsByPlate = {}

local function trimmed(plate)
    if type(plate) ~= 'string' then return nil end
    return (plate:gsub('^%s+', ''):gsub('%s+$', '')):upper()
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

RegisterNetEvent('npwd:qb-garage:sendVehicles', function(vehicles)
    if type(vehicles) ~= 'table' then vehicles = {} end
    coordsByPlate = {}
    for _, v in pairs(vehicles) do
        v.type = typeOf(v.model)
        local plate = trimmed(v.plate)
        if plate and type(v.coords) == 'table' and tonumber(v.coords.x) and tonumber(v.coords.y) then
            coordsByPlate[plate] = v.coords
        end
    end
    local waiting = pending
    pending = {}
    for _, cb in ipairs(waiting) do
        pcall(cb, { status = 'ok', data = vehicles })
    end
end)

RegisterNUICallback('npwd:qb-garage:getVehicles', function(_, cb)
    pending[#pending + 1] = cb
    TriggerServerEvent('npwd:qb-garage:getVehicles')
    SetTimeout(8000, function()
        for i = #pending, 1, -1 do
            if pending[i] == cb then
                table.remove(pending, i)
                pcall(cb, { status = 'error', data = {} })
            end
        end
    end)
end)

RegisterNUICallback('npwd:qb-garage:requestWaypoint', function(data, cb)
    local plate = trimmed(type(data) == 'table' and data.plate or nil)
    local coords = plate and (worldCoords(plate) or coordsByPlate[plate]) or nil
    if coords then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        TriggerEvent('QBCore:Notify', 'Your vehicle has been marked', 'success')
    else
        TriggerEvent('QBCore:Notify', 'This vehicle cannot be located', 'error')
    end
    cb({})
end)
