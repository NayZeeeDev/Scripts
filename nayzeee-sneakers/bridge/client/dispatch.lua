--[[
    DISPATCH (client side)
    The server picks the system. Client-side dispatch resources raise the alert
    from the client of the player it's about; the built-in alert is drawn here
    for police.
]]

local outgoing = {
    ['ps-dispatch'] = function(d)
        exports['ps-dispatch']:CustomAlert({
            message = d.title, codeName = 'nzs_sneakers', code = d.code, description = d.message,
            icon = 'fas fa-shoe-prints', priority = 2, coords = d.coords, jobs = { 'leo' },
            alertTime = d.blipTime, sprite = d.blip.sprite, color = d.blip.colour, scale = 1.0, length = 3,
        })
    end,
    ['cd_dispatch'] = function(d)
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = d.jobs, coords = d.coords, title = ('%s - %s'):format(d.code, d.title),
            message = d.message, flash = 0, unique_id = tostring(math.random(0, 9999999)), sound = 1,
            blip = { sprite = d.blip.sprite, scale = 1.0, colour = d.blip.colour, flashes = true, text = d.title, time = d.blipTime * 1000, radius = 0 },
        })
    end,
    ['qs-dispatch'] = function(d)
        TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = d.jobs, callLocation = d.coords, callCode = { code = d.code, snippet = d.title },
            message = d.message, flashes = true, image = nil,
            blip = { sprite = d.blip.sprite, scale = 1.0, colour = d.blip.colour, flashes = true, text = d.title, time = d.blipTime * 1000 },
        })
    end,
}

RegisterNetEvent('nayzeee-sneakers:dispatchOut', function(system, data)
    local fn = outgoing[system]
    if not fn then return end
    local ok, err = pcall(fn, data)
    if not ok then print(('^1[nayzeee-sneakers] %s alert failed: %s^7'):format(system, tostring(err))) end
end)

-- Built-in alert: a flashing blip and a notification
RegisterNetEvent('nayzeee-sneakers:dispatch', function(d)
    local c = d.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, d.blip.sprite)
    SetBlipColour(blip, d.blip.colour)
    SetBlipScale(blip, 1.1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s · %s'):format(d.code, d.title))
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
    UI.Notify(('%s · %s'):format(d.code, d.message), 'warning', d.title)
    SetTimeout(d.blipTime * 1000, function() if DoesBlipExist(blip) then RemoveBlip(blip) end end)
end)
