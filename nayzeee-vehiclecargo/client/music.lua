-----------------------------------------------------------------
-- Mission score
-- native: GTA's own Import/Export music events (from game files)
-- custom: your own files in web/sounds/ through the UI
-----------------------------------------------------------------
Music = { stage = nil }

local M = Config.Music

-- Score events stream in from the game files. Triggering one before it has
-- loaded plays nothing, so each waits until it is ready. They run one at a
-- time in order (a countdown's kill event must land before the next cue).
local queue, worker = {}, false
local function native(name)
    if not name then return end
    queue[#queue + 1] = name
    if worker then return end
    worker = true
    CreateThread(function()
        while #queue > 0 do
            local ev = table.remove(queue, 1)
            local t = GetGameTimer() + 3000
            while not PrepareMusicEvent(ev) and GetGameTimer() < t do Wait(50) end
            local ok = TriggerMusicEvent(ev)
            if Config.Debug or not ok then
                print(('^3[vehiclecargo] music %s: %s^7'):format(ev, ok and 'playing' or 'did not play (check the event name in Config.Music.Native)'))
            end
        end
        worker = false
    end)
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

-- /cargomusic [stage]: test the score (start, delivering, attack, countdown, finish, fail, stop)
RegisterCommand('cargomusic', function(_, args)
    local stage = args[1] or 'start'
    if stage == 'stop' then Music.Stop(true) return end
    Music.stage = nil
    print(('[vehiclecargo] music mode %s, playing %s'):format(M.Mode, stage))
    Music.Play(stage)
end, false)
