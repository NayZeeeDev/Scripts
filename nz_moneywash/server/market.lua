--[[ Dynamic wash market — one city-wide rate that reacts to laundering volume and random events ]]

Market = {
    volume = {},   -- { { t = os.time(), amount = n }, ... }
    history = {},  -- rate points for the sparkline
    event = nil,   -- { label, mod, note, endsAt }
    rate = Config.Market.base,
}

local M = Config.Market

local function windowVolume(now)
    local cutoff = now - M.windowMinutes * 60
    local total, keep = 0, {}
    for _, v in ipairs(Market.volume) do
        if v.t >= cutoff then
            total = total + v.amount
            keep[#keep + 1] = v
        end
    end
    Market.volume = keep
    return total
end

function Market.recalc()
    local now = os.time()
    if Market.event and now >= Market.event.endsAt then Market.event = nil end

    local vol = windowVolume(now)
    local sat = math.min(1.0, vol / M.saturationAt) * M.saturationMax
    local mod = Market.event and Market.event.mod or 0
    Market.rate = NZ.round(NZ.clamp(M.base - sat + mod, M.min, M.max), 3)
    Market.saturation = NZ.round(vol / M.saturationAt, 3)

    GlobalState['nzmw:market'] = {
        rate = Market.rate,
        saturation = Market.saturation,
        history = Market.history,
        event = Market.event,
    }
    return Market.rate
end

function Market.addVolume(amount)
    Market.volume[#Market.volume + 1] = { t = os.time(), amount = amount }
    Market.recalc()
end

function Market.pushHistory()
    Market.history[#Market.history + 1] = Market.rate
    while #Market.history > M.historyPoints do table.remove(Market.history, 1) end
end

function Market.rollEvent()
    if Market.event or math.random() > M.eventChance then return end
    local e = M.events[math.random(#M.events)]
    Market.event = { label = e.label, mod = e.mod, note = e.note, endsAt = os.time() + e.minutes * 60 }
    Market.recalc()
    Bridge.log('Market event', { { 'Event', e.label }, { 'Modifier', ('%+d%%'):format(math.floor(e.mod * 100)) } })
    TriggerClientEvent('nzmw:marketEvent', -1, Market.event)
end

function Market.start()
    -- seed a flat history so the chart is never empty
    Market.recalc()
    for _ = 1, 8 do Market.pushHistory() end
    Market.recalc()

    CreateThread(function()
        local tick = 0
        while true do
            Wait(60000)
            tick = tick + 1
            Market.recalc()
            if tick % M.historyEvery == 0 then Market.pushHistory(); Market.recalc() end
            if tick % M.eventEvery == 0 then Market.rollEvent() end
        end
    end)
end
