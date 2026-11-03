--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_esx_garage" (ESX) — client part.

  WHERE IT GOES  npwd_esx_garage/client/client.lua  (replace the file; keep a backup)
  WHAT IT DOES   Same NUI callbacks as the original ('npwd:esx-garage:getVehicles',
                 'npwd:esx-garage:requestWaypoint') and the same server event. The map button
                 sends only { parking, type }, so the coordinates come from the last list the
                 server sent (nayzeee's garage / house / private garage or impound position).
                 Fixes the original registering a new 'npwd:esx-garage:sendVehicles' handler
                 on every open, and times a request out after 8 s.
  NEEDS          server/server.lua from this folder (it adds `coords` to every vehicle).
  CONFIRMED      callback / event names and the { parking, type } payload against
                 npwd_esx_garage (itschip, main). Notifications use ESX.ShowNotification when
                 the manifest's '@es_extended/imports.lua' provides ESX, else nayzeee's toast.
]]

local pending = {}        -- NUI callbacks waiting for the server's answer
local coordsByParking = {}

local function notify(message, kind)
    local shown = false
    if type(ESX) == 'table' and type(ESX.ShowNotification) == 'function' then
        shown = pcall(ESX.ShowNotification, message)
    end
    if not shown then
        TriggerEvent('nz:client:notify', { type = kind or 'info', message = message })
    end
end

RegisterNetEvent('npwd:esx-garage:sendVehicles', function(vehicles)
    if type(vehicles) ~= 'table' then vehicles = {} end
    coordsByParking = {}
    for _, v in pairs(vehicles) do
        local key, coords = v.key, v.coords
        if type(key) == 'string' and type(coords) == 'table' and tonumber(coords.x) and tonumber(coords.y)
            and coordsByParking[key] == nil then
            coordsByParking[key] = coords
        end
    end
    local waiting = pending
    pending = {}
    for _, cb in ipairs(waiting) do
        pcall(cb, { status = 'ok', data = vehicles })
    end
end)

RegisterNUICallback('npwd:esx-garage:getVehicles', function(_, cb)
    pending[#pending + 1] = cb
    TriggerServerEvent('npwd:esx-garage:getVehicles')
    SetTimeout(8000, function()
        for i = #pending, 1, -1 do
            if pending[i] == cb then
                table.remove(pending, i)
                pcall(cb, { status = 'error', data = {} })
            end
        end
    end)
end)

RegisterNUICallback('npwd:esx-garage:requestWaypoint', function(data, cb)
    local parking = type(data) == 'table' and data.parking or nil
    local coords = type(parking) == 'string' and coordsByParking[parking] or nil
    if coords then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        notify('Your vehicle has been marked', 'success')
    else
        notify('This vehicle cannot be located', 'error')
    end
    cb({})
end)
