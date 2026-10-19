--[[
    NAYZEEE AMBULANCE - Dispatch (client): calls, call card, blips, GPS, status toasts

    Keeps the local copy of the active calls (pushed by server/modules/dispatch.lua), shows
    the call card (NUI app 'callcard', top right, no focus: respond / dismiss work with
    keybinds), the "your call" strip with the call progress ring, map blips per call and the
    GPS route to the call you respond to (and to the hospital once you transport).

    NUI app 'callcard' (opened without focus while on duty, or for police notices)
      actions sent: open, alert, alertUpdate, alertResponded, alertHide, queue, active, live
    Keybinds: nza_dispatch_respond (Config.Dispatch.card.respondKey, E)
              nza_dispatch_dismiss (Config.Dispatch.card.dismissKey, BACK = Backspace)
    Net events handled: nza:dispatch:sync, :call, :update, :close, :me, :units, :stage,
                        :assigned, :police
    Net events sent:    nza:dispatch:respond, :decline, :clear, :street, :unitStatus, :npc, :pair, :duty
    Callbacks used:     nza:dispatch:state
    Client bus emitted: dispatch:sync (S), dispatch:call (call, flags), dispatch:update (call),
                        dispatch:close (id, reason), dispatch:me (me), dispatch:stage (id, stage)

    Client API (other modules)
      NZA.Dispatch.Calls() → { call } (priority, newest)   NZA.Dispatch.Get(id) → call | nil
      NZA.Dispatch.Me() → own unit record                 NZA.Dispatch.Current() → my call | nil
      NZA.Dispatch.Respond(id?) / Decline(id) / Clear() / SetStatus('10-8'|'10-7')
      NZA.Dispatch.SetNpcCalls(bool) / Pair(bool) / SetDuty(bool)
      NZA.Dispatch.Live(call) → dist, compassDir, relAngle, eta      NZA.Dispatch.Units() → roster
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Dispatch = NZA.Dispatch or {}
local D = NZA.Dispatch
D.S = D.S or {}
local S = D.S

local APP = 'callcard'

D.Stages = { 'DSP', 'ENR', 'SCN', 'CARE', 'TRN', 'HSP' }   -- server codes (internal, never shown)
-- what players see: four phases (locale 'dispatch.ph_<phase>'), see html/apps/callcard/app.js (NZD)
D.Phase = { DSP = 'paged', ENR = 'rolling', SCN = 'patient', CARE = 'patient', TRN = 'hospital', HSP = 'hospital' }

S.calls = S.calls or {}       -- id → call
S.units = S.units or {}
S.recent = S.recent or {}
S.me = S.me or { medic = false, onDuty = false, status = '10-7' }
S.queue = S.queue or {}       -- alert queue (call ids)
S.dismissed = S.dismissed or {}
S.blips = S.blips or {}       -- id → blip
S.police = S.police or {}     -- id → { blip, call }
S.card = nil                  -- { id, shownAt, police = bool, responded = bool }
S.cardOpen = false
S.activeShown = nil
S.hospBlip = nil

local function cfg(section, key, default)
    local root = Config.Dispatch
    local c = type(root) == 'table' and root[section] or nil
    if type(c) ~= 'table' then return default end
    local v = c[key]
    if v == nil then return default end
    return v
end
D.Cfg = cfg

-- phone alerts: 'paired' | 'always' | false (same rule as the server, see Config.Dispatch.phone)
function D.PhoneMode()
    local m = cfg('phone', 'alerts', nil)
    if m == nil then return cfg('pager', 'phonePairing', true) ~= false and 'paired' or false end
    if m == 'always' or m == 'paired' then return m end
    return false
end

-- what the card shows for a keyboard mapper key name (FiveM names like BACK, RETURN)
local KEY_LABELS = {
    BACK = '⌫', RETURN = 'Enter', SPACE = 'Space', ESCAPE = 'Esc', DELETE = 'Del', INSERT = 'Ins',
    LSHIFT = 'Shift', RSHIFT = 'Shift', LCONTROL = 'Ctrl', RCONTROL = 'Ctrl', LMENU = 'Alt', RMENU = 'Alt',
    TAB = 'Tab', HOME = 'Home', END = 'End', PAGEUP = 'PgUp', PAGEDOWN = 'PgDn',
    UP = '↑', DOWN = '↓', LEFT = '←', RIGHT = '→',
}
local function keyLabel(k)
    k = tostring(k or '')
    return KEY_LABELS[k:upper()] or k
end

local function L(key, ...) return NZA.L(key, ...) end

local function toast(kind, key, ...)
    NZA.UI.Toast({ title = L('dispatch.title'), message = L(key, ...), type = kind })
end
D.Toast = toast

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY
-- ════════════════════════════════════════════════════════════════════════

local DIRS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }

local function callCoords(c)
    return vector3(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
end
D.Coords = callCoords

-- distance (m), compass direction ('SW'), arrow angle relative to the camera (deg), ETA (s)
function D.Live(c)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local dx, dy = c.x - p.x, c.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local bearing = (math.deg(math.atan(dx, dy)) + 360.0) % 360.0
    local dir = DIRS[(math.floor((bearing + 22.5) / 45.0) % 8) + 1]
    local camBearing = (-GetGameplayCamRot(2).z + 360.0) % 360.0
    local rel = (bearing - camBearing + 360.0) % 360.0
    local speed = tonumber(cfg('status', 'etaSpeed', 19.0)) or 19.0
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then speed = math.max(GetEntitySpeed(veh), speed * 0.7) else speed = math.max(speed, 1.0) end
    return dist, dir, rel, math.floor(dist / speed)
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL STORE
-- ════════════════════════════════════════════════════════════════════════

local function stamp(c)
    c.t0 = GetGameTimer() - math.floor((tonumber(c.age) or 0) * 1000)
    return c
end

local function ageOf(c)
    return math.max(0, math.floor((GetGameTimer() - (c.t0 or GetGameTimer())) / 1000))
end
D.Age = ageOf

local function resolveStreet(c)
    if c.street and c.zone then return end
    local s1, s2 = GetStreetNameAtCoord(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    local a = s1 and s1 ~= 0 and GetStreetNameFromHashKey(s1) or nil
    local b = s2 and s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil
    local street = a and a ~= '' and ((b and b ~= '') and (a .. ' / ' .. b) or a) or nil
    local zoneName = GetNameOfZone(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    local zone = zoneName and GetLabelText(zoneName) or nil
    if zone == 'NULL' or zone == '' then zone = zoneName end
    local report = not c.street and street ~= nil
    c.street = c.street or street
    c.zone = c.zone or zone
    if report and not c._reported then
        c._reported = true
        local id = c.id
        SetTimeout(math.random(0, 1200), function()
            local cur = S.calls[id]
            if cur and cur.street == street and not cur._serverStreet then
                TriggerServerEvent('nza:dispatch:street', id, street, zone)
            end
        end)
    end
end

local function public(c)
    if not c then return nil end
    resolveStreet(c)
    local out = {}
    for k, v in pairs(c) do
        if type(k) == 'string' and k:sub(1, 1) ~= '_' and k ~= 't0' then out[k] = v end
    end
    out.age = ageOf(c)
    out.mine = S.me.call == c.id
    return out
end
D.Public = public

local function store(c)
    if type(c) ~= 'table' or type(c.id) ~= 'string' then return nil end
    local old = S.calls[c.id]
    if c.street then c._serverStreet = true end
    if old then
        c._reported = old._reported
        if not c.street then c.street = old.street end
        if not c.zone then c.zone = old.zone end
    end
    stamp(c)
    S.calls[c.id] = c
    return c, old
end

function D.Calls()
    local list = {}
    for _, c in pairs(S.calls) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return (a.t0 or 0) > (b.t0 or 0)
    end)
    return list
end

function D.Get(id) return S.calls[id] end
function D.Me() return S.me end
function D.Units() return S.units end
function D.Recent() return S.recent end
function D.Current() return S.me.call and S.calls[S.me.call] or nil end

-- ════════════════════════════════════════════════════════════════════════
-- BLIPS
-- ════════════════════════════════════════════════════════════════════════

local function removeBlip(id)
    local b = S.blips[id]
    if b and DoesBlipExist(b) then RemoveBlip(b) end
    S.blips[id] = nil
end

local function blipStyle(c)
    local bc = Config.Dispatch.blips or {}
    local sprites = bc.sprites or {}
    local colours = bc.colours or {}
    local sprite = (c.blip and tonumber(c.blip.sprite)) or sprites[c.type] or sprites.default or 153
    local colour = (c.blip and tonumber(c.blip.colour)) or colours[c.priority] or 1
    return sprite, colour, tonumber(bc.scale) or 0.95
end

local function setBlipName(b, text)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandSetBlipName(b)
end

local function syncBlip(c, fresh)
    if cfg('blips', 'enabled', true) == false then return end
    local b = S.blips[c.id]
    local sprite, colour, scale = blipStyle(c)
    if not b or not DoesBlipExist(b) then
        b = AddBlipForCoord(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
        S.blips[c.id] = b
        SetBlipAsShortRange(b, cfg('blips', 'shortRange', false) == true)
        SetBlipDisplay(b, 4)
        if fresh and c.priority == 1 then
            SetBlipFlashes(b, true)
            local flashFor = (tonumber(cfg('blips', 'flash', 12)) or 12) * 1000
            SetTimeout(flashFor, function() if DoesBlipExist(b) then SetBlipFlashes(b, false) end end)
        end
    end
    SetBlipCoords(b, c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, colour)
    SetBlipScale(b, scale)
    SetBlipPriority(b, 12 - (c.priority or 3))
    setBlipName(b, ('%s · %s'):format(c.code or '', c.title or L('dispatch.call_default')))
    local mine = S.me.call == c.id
    if cfg('blips', 'route', true) and mine and not S.hospBlip then
        SetBlipRoute(b, true)
        SetBlipRouteColour(b, tonumber(cfg('blips', 'routeColour', 1)) or 1)
    else
        SetBlipRoute(b, false)
    end
end

local function clearHospitalRoute()
    if S.hospBlip and DoesBlipExist(S.hospBlip) then RemoveBlip(S.hospBlip) end
    S.hospBlip = nil
end

local function routeToHospital(extra)
    clearHospitalRoute()
    if not (extra and extra.x) or cfg('blips', 'route', true) == false then return end
    local b = AddBlipForCoord(extra.x + 0.0, extra.y + 0.0, (extra.z or 0.0) + 0.0)
    SetBlipSprite(b, 61)
    SetBlipColour(b, 2)
    SetBlipScale(b, 0.9)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, 2)
    setBlipName(b, extra.hospital or L('dispatch.hospital'))
    S.hospBlip = b
    for id in pairs(S.calls) do
        local cb = S.blips[id]
        if cb and DoesBlipExist(cb) then SetBlipRoute(cb, false) end
    end
end

local function clearAllBlips()
    for id in pairs(S.blips) do removeBlip(id) end
    clearHospitalRoute()
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL CARD (NUI 'callcard')
-- ════════════════════════════════════════════════════════════════════════

local function cardLocale()
    return NZA.LocaleTable('dispatch')
end

local function ensureCardApp()
    if S.cardOpen and NZA.UI.IsOpen(APP) then return end
    S.cardOpen = true
    NZA.UI.Open(APP, {
        locale = cardLocale(),
        keys = { respond = keyLabel(cfg('card', 'respondKey', 'E')), dismiss = keyLabel(cfg('card', 'dismissKey', 'BACK')) },
        timeout = tonumber(cfg('card', 'timeout', 30)) or 30,
        voiceVolume = tonumber(cfg('card', 'voiceVolume', 0.85)) or 0.85,
    }, { focus = false })
end

local function closeCardApp()
    if S.cardOpen then NZA.UI.Close(APP) end
    S.cardOpen = false
    S.card = nil
    S.activeShown = nil
end

local function selfDown()
    return NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() or false
end

local function cardAllowed()
    if cfg('card', 'enabled', true) == false then return false end
    if cfg('card', 'hideWhenDown', true) and selfDown() then return false end
    return true
end

local function inQueue(id)
    for _, x in ipairs(S.queue) do if x == id then return true end end
    return false
end

local function showNext()
    S.card = nil
    while #S.queue > 0 do
        local id = table.remove(S.queue, 1)
        local c = S.calls[id] or (S.police[id] and S.police[id].call)
        if c and not S.dismissed[id] and S.me.call ~= id then
            local police = S.police[id] ~= nil and S.calls[id] == nil
            ensureCardApp()
            S.card = { id = id, shownAt = GetGameTimer(), police = police }
            NZA.UI.Send(APP, 'alert', {
                call = public(c), queue = #S.queue, police = police,
                sound = cfg('card', 'sound', true) and not (D.PagerVisible and D.PagerVisible()),
                voice = cfg('card', 'voice', true) and not police and c.voice or nil,
            })
            return true
        end
    end
    NZA.UI.Send(APP, 'alertHide', {})
    if not (S.me.medic and S.me.onDuty) and next(S.police) == nil then closeCardApp() end
    return false
end

local function enqueue(id, front)
    if inQueue(id) or (S.card and S.card.id == id) then return end
    local max = tonumber(cfg('card', 'queue', 6)) or 6
    if front then table.insert(S.queue, 1, id) else S.queue[#S.queue + 1] = id end
    while #S.queue > max do table.remove(S.queue) end
    if not S.card then showNext() else NZA.UI.Send(APP, 'queue', { n = #S.queue }) end
end

local function dropFromQueue(id)
    for i = #S.queue, 1, -1 do
        if S.queue[i] == id then table.remove(S.queue, i) end
    end
    if S.card and S.card.id == id then showNext() elseif S.cardOpen then NZA.UI.Send(APP, 'queue', { n = #S.queue }) end
end

function D.Respond(id)
    id = id or (S.card and not S.card.police and S.card.id) or nil
    if not id then
        local best, bestD = nil, math.huge
        for _, c in ipairs(D.Calls()) do
            if S.me.call ~= c.id then
                local d = D.Live(c)
                local score = (c.priority - 1) * 100000 + d + (#(c.units or {}) > 0 and 50000 or 0)
                if score < bestD then best, bestD = c, score end
            end
        end
        id = best and best.id
    end
    if not id then
        toast('info', 'dispatch.no_calls')
        return false
    end
    if S.me.call == id then
        toast('info', 'dispatch.err_already')
        return false
    end
    TriggerServerEvent('nza:dispatch:respond', id)
    S.dismissed[id] = true
    if S.card and S.card.id == id then
        S.card.responded = true
        NZA.UI.Send(APP, 'alertResponded', { id = id })
        local shown = S.card
        SetTimeout(1100, function() if S.card == shown then showNext() end end)
    else
        dropFromQueue(id)
    end
    return true
end

function D.Decline(id)
    if not id then return false end
    S.dismissed[id] = true
    if S.calls[id] then TriggerServerEvent('nza:dispatch:decline', id) end
    dropFromQueue(id)
    return true
end

function D.Clear()
    if not S.me.call then
        toast('info', 'dispatch.err_not_on_call')
        return false
    end
    TriggerServerEvent('nza:dispatch:clear', S.me.call)
    return true
end

function D.SetStatus(code) TriggerServerEvent('nza:dispatch:unitStatus', code) end
function D.SetNpcCalls(on) TriggerServerEvent('nza:dispatch:npc', on == true) end
function D.Pair(on) TriggerServerEvent('nza:dispatch:pair', on == true) end
-- departments (hospital module) own duty when the medic belongs to one; else the framework job
function D.SetDuty(on)
    local rec = NZA.Staff and NZA.Staff.Get and NZA.Staff.Get() or nil
    if NZA.Hospitals and type(NZA.Hospitals.ToggleDuty) == 'function' and rec and rec.dept ~= nil then
        CreateThread(function() NZA.Hospitals.ToggleDuty(on == true, nil) end)
        return
    end
    TriggerServerEvent('nza:dispatch:duty', on == true)
end

-- police notice: E sets the waypoint
local function policeGps(id)
    local e = S.police[id]
    if not e then return end
    SetNewWaypoint(e.call.x + 0.0, e.call.y + 0.0)
    toast('success', 'dispatch.gps_set')
end

local function onRespondKey()
    if not S.card or IsPauseMenuActive() or IsNuiFocused() then return end
    if S.card.police then
        local id = S.card.id
        policeGps(id)
        S.dismissed[id] = true
        showNext()
        return
    end
    D.Respond(S.card.id)
end

local function onDismissKey()
    if not S.card or IsPauseMenuActive() or IsNuiFocused() then return end
    local id = S.card.id
    if S.card.police then
        S.dismissed[id] = true
        showNext()
    else
        D.Decline(id)
    end
end

-- "your call" strip with the call progress ring
local function refreshActive()
    if not S.cardOpen then return end
    local c = D.Current()
    local want = c and cfg('card', 'activeStrip', true) and not (D.PagerVisible and D.PagerVisible()) and not selfDown()
    if want then
        S.activeShown = c.id
        NZA.UI.Send(APP, 'active', { call = public(c), stage = S.me.status })
    elseif S.activeShown then
        S.activeShown = nil
        NZA.UI.Send(APP, 'active', { call = false })
    end
end
D.RefreshActive = refreshActive

-- live distance / direction while something is on the card
CreateThread(function()
    while true do
        local wait = 600
        -- another module closed every NUI app (NZA.UI.CloseAll): bring the card back
        if S.cardOpen and not NZA.UI.IsOpen(APP) then
            S.cardOpen = false
            S.activeShown = nil
            if (S.me.medic and S.me.onDuty) or next(S.police) ~= nil then
                ensureCardApp()
                if S.card then
                    table.insert(S.queue, 1, S.card.id)
                    S.card = nil
                    showNext()
                end
                refreshActive()
            else
                S.card = nil
            end
        end
        if S.cardOpen and (S.card or S.activeShown) then
            wait = 200
            local out = {}
            if S.card then
                local c = S.calls[S.card.id] or (S.police[S.card.id] and S.police[S.card.id].call)
                if c then
                    local dist, dir, rel, eta = D.Live(c)
                    out.alert = { id = c.id, dist = dist, dir = dir, rel = rel, eta = eta }
                end
                local timeout = (tonumber(cfg('card', 'timeout', 30)) or 30) * 1000
                if GetGameTimer() - S.card.shownAt > timeout and not S.card.responded then
                    local id = S.card.id
                    S.dismissed[id] = true
                    showNext()
                end
                if S.card and (cfg('card', 'hideWhenDown', true) and selfDown()) then
                    table.insert(S.queue, 1, S.card.id)
                    S.card = nil
                    NZA.UI.Send(APP, 'alertHide', {})
                end
            end
            if S.activeShown then
                local c = S.calls[S.activeShown]
                if c then
                    local dist, dir, rel, eta = D.Live(c)
                    out.active = { id = c.id, dist = dist, dir = dir, rel = rel, eta = eta }
                end
            end
            -- under a focused procedure the card is out of sight: no live numbers; otherwise only on change
            local top = NZA.UI.Top()
            if top and top ~= APP and top ~= 'pager' then
                wait = 1000
            else
                local sig = json.encode(out)
                if sig ~= S.liveSig then S.liveSig = sig; NZA.UI.Send(APP, 'live', out) end
            end
        elseif S.cardOpen and not S.card and #S.queue > 0 and cardAllowed() then
            showNext()
        end
        Wait(wait)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SYNC & NET EVENTS
-- ════════════════════════════════════════════════════════════════════════

local function onDuty()
    return S.me.medic == true and S.me.onDuty == true
end
D.IsOnDuty = onDuty

local function applySync(payload)
    if type(payload) ~= 'table' then return end
    clearAllBlips()
    S.calls = {}
    S.queue = {}
    S.card = nil
    S.me = type(payload.me) == 'table' and payload.me or S.me
    S.units = type(payload.units) == 'table' and payload.units or {}
    S.recent = type(payload.recent) == 'table' and payload.recent or S.recent
    for _, c in ipairs(payload.calls or {}) do
        if store(c) then syncBlip(c, false) end
    end
    if onDuty() then
        ensureCardApp()
        NZA.UI.Send(APP, 'alertHide', {})
        refreshActive()
    else
        closeCardApp()
    end
    NZA.Bus.Emit('dispatch:sync', S)
end

local function requestSync()
    CreateThread(function()
        local payload = lib.callback.await('nza:dispatch:state', false)
        if payload then applySync(payload) end
    end)
end
D.Sync = requestSync

RegisterNetEvent('nza:dispatch:sync', applySync)

RegisterNetEvent('nza:dispatch:call', function(c, flags)
    if type(c) ~= 'table' or not onDuty() then return end
    store(c)
    syncBlip(c, true)
    flags = type(flags) == 'table' and flags or {}
    if flags.realert then S.dismissed[c.id] = nil end
    if flags.alert and cardAllowed() and not S.dismissed[c.id] then enqueue(c.id, c.priority == 1) end
    NZA.Bus.Emit('dispatch:call', c, flags)
end)

RegisterNetEvent('nza:dispatch:update', function(c)
    if type(c) ~= 'table' or not onDuty() then return end
    local cur = store(c)
    if not cur then return end
    syncBlip(cur, false)
    if S.card and S.card.id == c.id and S.cardOpen then NZA.UI.Send(APP, 'alertUpdate', { call = public(cur) }) end
    if S.activeShown == c.id then refreshActive() end
    NZA.Bus.Emit('dispatch:update', cur)
end)

RegisterNetEvent('nza:dispatch:close', function(id, reason)
    if type(id) ~= 'string' then return end
    local c = S.calls[id]
    S.calls[id] = nil
    removeBlip(id)
    S.dismissed[id] = nil
    if c then
        c.closed = true
        c.reason = reason
        table.insert(S.recent, 1, public(c))
        while #S.recent > 40 do table.remove(S.recent) end
    end
    if S.me.call == id then S.me.call = nil end
    if S.activeShown == id then clearHospitalRoute() end
    dropFromQueue(id)
    refreshActive()
    NZA.Bus.Emit('dispatch:close', id, reason)
end)

RegisterNetEvent('nza:dispatch:me', function(me)
    if type(me) ~= 'table' then return end
    local wasCall = S.me.call
    local was = onDuty()
    S.me = me
    if was ~= onDuty() then requestSync() return end
    if wasCall ~= me.call then
        if wasCall and S.calls[wasCall] then syncBlip(S.calls[wasCall], false) end
        if not me.call then clearHospitalRoute() end
        if me.call and S.calls[me.call] then syncBlip(S.calls[me.call], false) end
        if me.call then dropFromQueue(me.call) end
    end
    refreshActive()
    NZA.Bus.Emit('dispatch:me', me)
end)

RegisterNetEvent('nza:dispatch:units', function(list)
    if type(list) == 'table' then S.units = list end
end)

RegisterNetEvent('nza:dispatch:stage', function(id, stage, extra)
    if type(id) ~= 'string' then return end
    local c = S.calls[id]
    if stage == 'ENR' then
        toast('info', 'dispatch.st_enr', c and c.title or id)
    elseif stage == 'SCN' then
        toast('info', 'dispatch.st_scn')
        clearHospitalRoute()
    elseif stage == 'TRN' then
        routeToHospital(extra)
        toast('info', 'dispatch.st_trn', extra and extra.hospital or L('dispatch.hospital'))
    elseif stage == 'HSP' then
        clearHospitalRoute()
        toast('success', 'dispatch.st_hsp')
    end
    if c then syncBlip(c, false) end
    refreshActive()
    NZA.Bus.Emit('dispatch:stage', id, stage)
end)

RegisterNetEvent('nza:dispatch:assigned', function(c, byName)
    if type(c) ~= 'table' then return end
    store(c)
    syncBlip(c, false)
    dropFromQueue(c.id)
    PlaySoundFrontend(-1, 'Event_Message_Purple', 'GTAO_FM_Events_Soundset', false)
    toast('warning', 'dispatch.assigned_you', c.id, c.title or '', tostring(byName or L('dispatch.dispatcher')))
end)

-- police notice (violent EMS calls)
RegisterNetEvent('nza:dispatch:police', function(c)
    if type(c) ~= 'table' or type(c.id) ~= 'string' then return end
    c.age = math.max(0, (GetCloudTimeAsInt() or 0) - (tonumber(c.created) or 0))
    if c.age > 3600 then c.age = 0 end
    c._reported = true
    stamp(c)
    resolveStreet(c)
    local old = S.police[c.id]
    if old and old.blip and DoesBlipExist(old.blip) then RemoveBlip(old.blip) end
    local b = AddBlipForCoord(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0)
    local sprite, colour = blipStyle(c)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, colour)
    SetBlipScale(b, 0.9)
    SetBlipFlashes(b, true)
    setBlipName(b, ('%s · %s'):format(c.code or '', c.title or ''))
    S.police[c.id] = { blip = b, call = c }
    local life = (tonumber(c.blipTime) or 240) * 1000
    SetTimeout(life, function()
        local e = S.police[c.id]
        if e and e.blip == b then
            if DoesBlipExist(b) then RemoveBlip(b) end
            S.police[c.id] = nil
            dropFromQueue(c.id)
        end
    end)
    if cfg('card', 'enabled', true) ~= false then
        ensureCardApp()
        enqueue(c.id, false)
    else
        toast('warning', 'dispatch.police_notice', c.title or '', c.street or c.zone or '')
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- KEYBINDS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    if cfg('card', 'enabled', true) == false then return end
    lib.addKeybind({
        name = 'nza_dispatch_respond',
        description = L('dispatch.bind_respond'),
        defaultMapper = 'keyboard',
        defaultKey = cfg('card', 'respondKey', 'E'),
        onPressed = onRespondKey,
    })
    lib.addKeybind({
        name = 'nza_dispatch_dismiss',
        description = L('dispatch.bind_dismiss'),
        defaultMapper = 'keyboard',
        defaultKey = cfg('card', 'dismissKey', 'BACK'),
        onPressed = onDismissKey,
    })
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('staff:changed', function(rec)
    if type(rec) ~= 'table' then return end
    local duty = rec.medic == true and rec.onDuty == true
    if duty ~= onDuty() or rec.medic ~= S.me.medic then
        S.me.medic = rec.medic == true
        S.me.onDuty = rec.onDuty == true
        requestSync()
    end
end)

NZA.Bus.On('self:state', function()
    refreshActive()
end)

NZA.Bus.On('ui:closed', function(app)
    if app == APP then
        S.cardOpen = false
        S.card = nil
        S.activeShown = nil
        if onDuty() then SetTimeout(250, function() if onDuty() then ensureCardApp() end end) end
    end
end)

CreateThread(function()
    Wait(3000)
    requestSync()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearAllBlips()
    for _, e in pairs(S.police) do
        if e.blip and DoesBlipExist(e.blip) then RemoveBlip(e.blip) end
    end
    S.police = {}
end)
