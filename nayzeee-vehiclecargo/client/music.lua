-----------------------------------------------------------------
-- Mission score
-- native: GTA's own Import/Export music events (from game files)
-- custom: your own files in web/sounds/ through the UI
-----------------------------------------------------------------
Music = { stage = nil }

local M = Config.Music

local function native(name)
    if not name then return end
    PrepareMusicEvent(name)
    TriggerMusicEvent(name)
end

function Music.Play(stage)
    if not M.Enabled or M.Mode == 'off' or Music.stage == stage then return end
    local previous = Music.stage
    Music.stage = stage
    if M.Mode == 'native' then
        -- leaving the countdown early needs the kill event first
        if previous == 'countdown' and stage ~= 'countdown' then native(M.Native.countdownKill) end
        native(M.Native[stage])
    elseif M.Mode == 'custom' then
        Client.Send('music', { stage = stage, file = M.Custom[stage], volume = M.Custom.Volume })
    end
end

function Music.Stop(success)
    if not Music.stage then return end
    if M.Mode == 'native' then
        if Music.stage == 'countdown' then native(M.Native.countdownKill) end
        native(success and M.Native.finish or M.Native.fail)
        SetTimeout(4000, function() if not Music.stage then native(M.Native.radio) end end)
    elseif M.Mode == 'custom' then
        Client.Send('music', { stage = success and 'finish' or 'fail', file = M.Custom[success and 'finish' or 'fail'], volume = M.Custom.Volume, last = true })
    end
    Music.stage = nil
end

function Music.RadioOff(vehicle)
    if not M.RadioOff or not vehicle or vehicle == 0 then return end
    SetVehRadioStation(vehicle, 'OFF')
    SetVehicleRadioEnabled(vehicle, false)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Music.stage and M.Mode == 'native' then
        native(M.Native.finish)
    end
end)
