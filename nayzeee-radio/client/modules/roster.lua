--[[
    NAYZEEE RADIO - Roster (client): who is on your TX channel

    The roster card (NUI app 'roster', never takes focus) is shown while the radio is
    raised, while the player turned it on (key / radio menu), or for a few seconds when
    someone starts talking on the TX channel (Config.Roster.popOnRx). The server only
    sends rows to players who are watching, so watching is switched with the card.

      NZR.Roster.Visible() → bool      NZR.Roster.Update()   re-evaluate (called on every state change)

    EVENTS SENT      nzr:roster:watch (on) (C→S)
    EVENTS HANDLED   nzr:roster:data (fkey, { label, members = { { id, name, callsign, bars, talking } } }) (S→C)
    NUI SENT         roster open { x, y }, roster data { fkey, label, count, members = { { id, name, callsign,
                     bars, talking, you } } }, roster close
    NUI HANDLED      'roster:moved' { x, y } → saved (KVP nzr_roster_pos) and sent back with the next open
    BUS HANDLED      'radio:changed', 'radio:rx'
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Roster = NZR.Roster or {}
local Roster = NZR.Roster

local APP = 'roster'
local KVP_POS = 'nzr_roster_pos'
local POP_MS = 3000

local visible = false
local watchingKey = nil
local popUntil = 0
local myId = nil

local function me()
    if not myId then myId = GetPlayerServerId(PlayerId()) end
    return myId
end

local function savedPos()
    local ok, raw = pcall(GetResourceKvpString, KVP_POS)
    if not ok or type(raw) ~= 'string' or raw == '' then return {} end
    local okJ, t = pcall(json.decode, raw)
    if not okJ or type(t) ~= 'table' then return {} end
    local x, y = tonumber(t.x), tonumber(t.y)
    if not x or not y then return {} end
    return { x = math.max(0.0, math.min(1.0, x)), y = math.max(0.0, math.min(1.0, y)) }
end

local function txKey()
    local S = NZR.Radio.State
    local f = S.slots[S.txSlot]
    return f and NZR.Freq.Key(f) or nil
end

local function shouldShow()
    local S = NZR.Radio.State
    if not (Config.Roster and Config.Roster.enabled) then return false end
    if not S.ready or not S.power or not txKey() then return false end
    return S.rosterOn or S.raised or GetGameTimer() < popUntil
end

function Roster.Visible()
    return visible
end

function Roster.Update()
    local want = shouldShow()
    local key = want and txKey() or nil
    if want and not visible then
        visible = true
        watchingKey = key
        TriggerServerEvent('nzr:roster:watch', true)
        NZR.UI.Open(APP, savedPos(), { focus = false })
    elseif not want and visible then
        visible = false
        watchingKey = nil
        TriggerServerEvent('nzr:roster:watch', false)
        NZR.UI.Close(APP)
    elseif want and key ~= watchingKey then
        -- new TX channel: ask again so the server sends that channel's rows
        watchingKey = key
        TriggerServerEvent('nzr:roster:watch', true)
    end
end

local function pop()
    if not (Config.Roster and Config.Roster.popOnRx) then return end
    popUntil = math.max(popUntil, GetGameTimer() + POP_MS)
    Roster.Update()
    SetTimeout(POP_MS + 50, Roster.Update)
end

RegisterNetEvent('nzr:roster:data', function(fkey, data)
    if not visible or type(data) ~= 'table' then return end
    local key = fkey and NZR.Freq.Key(fkey) or nil
    if key and watchingKey and key ~= watchingKey then return end
    local rows = {}
    local list = type(data.members) == 'table' and data.members or {}
    for i = 1, #list do
        local m = list[i]
        if type(m) == 'table' then
            rows[#rows + 1] = {
                id = tonumber(m.id), name = m.name, callsign = m.callsign,
                bars = math.max(0, math.min(4, math.floor(tonumber(m.bars) or 0))),
                talking = m.talking == true, you = tonumber(m.id) == me(),
            }
        end
    end
    NZR.UI.Send(APP, 'data', {
        fkey = key, label = data.label, count = tonumber(data.count) or #rows, members = rows,
    })
end)

CreateThread(function()
    Wait(0)
    NZR.UI.On(APP, 'moved', function(data, cb)
        local x, y = tonumber(data.x), tonumber(data.y)
        if x and y then
            pcall(SetResourceKvp, KVP_POS, json.encode({ x = math.max(0.0, math.min(1.0, x)), y = math.max(0.0, math.min(1.0, y)) }))
        end
        cb({ ok = true })
    end)
end)

NZR.Bus.On('radio:changed', function(what)
    if what == 'rx' or what == 'volume' or what == 'labels' or what == 'clicks' then return end
    Roster.Update()
end)

NZR.Bus.On('radio:rx', function(_, info, phase)
    if phase == 'update' or type(info) ~= 'table' then return end
    if info.fkey and info.fkey == txKey() then pop() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource or not visible then return end
    visible = false
    NZR.UI.Close(APP)
end)
