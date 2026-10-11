--[[
    NAYZEEE WorldControl - Server Time
    The server owns the clock. Clients let GTA run the clock natively at the
    same speed and only correct on drift, so there are no per-frame time loops.
    discord.gg/nayzeeedev
]]

local function RealMinutes()
    local offset = (Config.Time.real.useWeatherApiZone and State.weather.method == 'real' and RealTimezoneOffset)
        or (Config.Time.real.utcOffset or 0) * 3600
    local t = os.date('!*t', os.time() + offset)
    return t.hour * 60 + t.min + t.sec / 60
end

function SetTime(hour, minute, instant, src)
    hour = NWC.Clamp(hour, 0, 23)
    minute = NWC.Clamp(minute or 0, 0, 59)
    if not hour or not minute then return false end
    if State.time.method == 'real' then
        if src then NotifyPlayer(src, 'Time is following real-world time - switch to Game time first', 'error') end
        return false
    end

    State.time.minutes = math.floor(hour) * 60 + math.floor(minute)
    if instant == nil then instant = State.time.instant end

    if not State.restart.active then
        Broadcast({ time = TimePayload(instant and 'instant' or 'smooth') })
    end
    if src then
        AddLog(src, ('set time to %02d:%02d%s'):format(hour, minute, instant and ' (instant)' or ''), 'clock')
    end
    MarkDirty()
    return true
end

function SetFrozen(frozen, src)
    State.time.frozen = frozen == true
    Broadcast({ time = TimePayload('drift') })
    if src then AddLog(src, State.time.frozen and 'froze time' or 'unfroze time', 'snowflake') end
    MarkDirty()
end

function SetTimeSpeed(msPerMinute, src)
    msPerMinute = NWC.Clamp(msPerMinute, 250, 60000)
    if not msPerMinute then return end
    State.time.msPerMinute = math.floor(msPerMinute)
    Broadcast({ time = TimePayload('drift') })
    if src then
        AddLog(src, ('set day length to %d min'):format(math.floor(State.time.msPerMinute * 1440 / 60000 + 0.5)), 'gauge')
    end
    MarkDirty()
end

function SetTimeMethod(method, src)
    if method ~= 'game' and method ~= 'real' then return end
    State.time.method = method
    if method == 'real' then
        State.time.frozen = false
        State.time.minutes = RealMinutes()
    end
    Broadcast({ time = TimePayload('smooth') })
    if src then AddLog(src, ('switched time to %s time'):format(method == 'real' and 'real-world' or 'game'), 'earth-americas') end
    MarkDirty()
end

-- Clock + drift-correction heartbeat
CreateThread(function()
    if State.time.method == 'real' then State.time.minutes = RealMinutes() end

    local last = GetGameTimer()
    local sinceSync = 0
    local sinceSave = 0
    while true do
        Wait(1000)
        local now = GetGameTimer()
        local delta = now - last
        last = now

        if State.time.method == 'real' then
            State.time.minutes = RealMinutes()
        elseif not State.time.frozen then
            State.time.minutes = (State.time.minutes + delta / State.time.msPerMinute) % 1440
        end

        sinceSync = sinceSync + delta
        if sinceSync >= Config.Time.syncInterval * 1000 then
            sinceSync = 0
            if not State.restart.active then
                Broadcast({ time = TimePayload('drift') })
            end
        end

        sinceSave = sinceSave + delta
        if sinceSave >= 60000 then
            sinceSave = 0
            MarkDirty()
        end
    end
end)
