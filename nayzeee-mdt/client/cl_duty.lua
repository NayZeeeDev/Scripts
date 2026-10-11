-- ═══════════════════════════════════════════════════════════
--  DUTY & LIVE POSITION
-- ═══════════════════════════════════════════════════════════

--- Push our position while on duty so the live map has something to draw.
--- Only sends when we have moved, or every 20 seconds as a heartbeat.
CreateThread(function()
    local lastPos, lastSent = nil, 0
    local every = (Config.Map.updateSeconds or 4) * 1000

    while true do
        if Config.Map.enabled and MDT.onDuty then
            Wait(every)
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local now = GetGameTimer()
            if not lastPos or #(pos - lastPos) > 6.0 or now - lastSent > 20000 then
                lastPos, lastSent = pos, now
                TriggerServerEvent('nz_mdt:position', pos.x, pos.y, pos.z, GetEntityHeading(ped), MDT.streetName(pos))
            end
        else
            lastPos = nil
            Wait(5000)
        end
    end
end)

--- Ask the server where we stand — on start, and whenever ESX loads us in.
local function syncDuty()
    local state = lib.callback.await('nz_mdt:duty:state', false)
    if state then
        MDT.onDuty = state.onDuty == true
        MDT.status = state.status or MDT.status
        MDT.identifier = state.identifier or MDT.identifier
    end
end

CreateThread(function()
    Wait(2500)
    syncDuty()
end)

RegisterNetEvent('esx:playerLoaded', function()
    SetTimeout(2500, syncDuty)
end)

-- ═══════════════════════════════════════════════════════════
--  ON-DUTY BLIPS FOR OTHER UNITS
-- ═══════════════════════════════════════════════════════════
local unitBlips = {}

local function clearUnitBlips()
    for _, blip in pairs(unitBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    unitBlips = {}
end

--- Compact list from the server: { i = identifier, x, y, z, n = label, s = status, d = department }
RegisterNetEvent('nz_mdt:units', function(list)
    if not Config.Map.unitBlips then return end
    if not MDT.onDuty then return clearUnitBlips() end

    local seen = {}
    for _, u in ipairs(list or {}) do
        if u.x and u.i ~= MDT.identifier then
            seen[u.i] = true
            local blip = unitBlips[u.i]

            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(u.x + 0.0, u.y + 0.0, (u.z or 0.0) + 0.0)
                SetBlipSprite(blip, 1)
                SetBlipScale(blip, 0.75)
                SetBlipAsShortRange(blip, true)
                SetBlipCategory(blip, 7)
                local dept = Config.Departments[u.d]
                SetBlipColour(blip, dept and dept.blipColour or 38)
                unitBlips[u.i] = blip
            else
                SetBlipCoords(blip, u.x + 0.0, u.y + 0.0, (u.z or 0.0) + 0.0)
            end

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('%s · %s'):format(u.n or 'Unit', u.s or 'available'))
            EndTextCommandSetBlipName(blip)
        end
    end

    for identifier, blip in pairs(unitBlips) do
        if not seen[identifier] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            unitBlips[identifier] = nil
        end
    end
end)

RegisterNetEvent('nz_mdt:dutyChanged', function(onDuty)
    if not onDuty then clearUnitBlips() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearUnitBlips()
end)
