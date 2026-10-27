--[[
    NAYZEEE RADIO - Vehicles (client): MV-90 head unit, passenger HUD, car PTT, cabin ambience

    Radio cars are the models and vehicle classes in GlobalState 'nzr_vehicles' (the server
    publishes Config.Vehicles plus the admin list; until it does, Config.Vehicles is used).
    A head unit's state lives on the car (Entity(veh).state.nzr_vradio, written only by the
    server); this file reads it, shows it and asks the server to change it.

    Where the player sits is tracked from ox_lib's cache events ('vehicle', 'seat') and the
    game's entered-vehicle event; while inside a car a 500 ms loop follows the seat, death
    and the HUD. On foot nothing runs (a 1 s check only when ox_lib's cache is missing).

    In an operating seat (Config.Vehicles.seats) the raise key opens the head unit
    (interact.lua calls NZR.Vehicle.Open): a firmware instance for device 'vehicle'
    (firmware.lua) drawn by the NUI app 'headunit' with focus, cursor and game input kept,
    so the car can still be driven. Head unit changes are shown at once and sent to the
    server coalesced (at most one 'nzr:vehicle:set' per 180 ms); the state bag then confirms.

      NZR.Vehicle.Open() → bool          open the head unit (false: not in an operating seat of a radio car)
      NZR.Vehicle.Close() → bool         NZR.Vehicle.IsOpen() → bool
      NZR.Vehicle.Set(patch) → bool      patch = { on?, f? (fkey | false), v? (0..1), mute? } → nzr:vehicle:set
      NZR.Vehicle.Join(freq, code?) → res   (yields) nzr:vehicle:join → { ok, label, access, freq } | { ok = false, reason }
      NZR.Vehicle.CanTransmit() → bool   operating seat, head unit on and tuned (state.lua routes PTT here)
      NZR.Vehicle.State() → { on, f, v, mute, label } | nil   the head unit of the current car (with pending changes)
      NZR.Vehicle.Current() → { veh, vnet, radio, seat, operator }
      NZR.Vehicle.IsRadioVehicle(veh) → bool    NZR.Vehicle.RangeMult(veh) → number (admin range multiplier)
      NZR.Vehicle.DoorsShut(veh) → bool  every door closed and a roof on (voice.lua leak attenuation)
      NZR.Vehicle.MapKey(key) → action, value, step   head unit key → firmware vocabulary (SPEC §6)
      NZR.Vehicle.HandleKey(key, down, data?)         what 'headunit:press' does

    HEAD UNIT KEYS ('headunit:press' { key, down })
      '0'..'9' digit · star · hash · ok · back · pre (cycle memories) · mut (mute) · pwr (tap = on / off)
      · emerg (held Config.Emergency.holdTime; data.held = true when the page timed the hold itself)
      · vol- / vol+ (volume knob) · ch- / ch+ (channel knob) · up / down (= ch+ / ch-) · left / right
      (= vol- / vol+) · ptt (hold to talk through the car). Every knob down is one detent (the page
      repeats a held knob by sending more downs); a repeated down of a held EMERG / PWR is ignored.

    EVENTS SENT      nzr:vehicle:set (vnet, patch) (C→S)
    CALLBACKS        nzr:vehicle:join (vnet, freq, code?) (C→S, lib.callback)
    NUI SENT         headunit open (state) / state (screen state SPEC §10.3 + knobs = { vol, ch } degrees,
                     pressed = key held | nil, hold = { emerg = 0..1 } | nil) / close
                     vhud open / data { freq, label, talker = { name, callsign, q } | nil, on, mute, model } / close
                     _core ambient { on, volume }
    NUI HANDLED      'headunit:press' { key, down, held? }, 'headunit:close'
    STATE BAGS       reads Entity(veh).state.nzr_vradio (+ change handler), GlobalState.nzr_vehicles (+ change handler)
    BUS              handles 'radio:changed', 'radio:notice' (device 'vehicle'); emits 'vehicle:changed' (veh | 0)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Vehicle = NZR.Vehicle or {}
local V = NZR.Vehicle

local APP_HU = 'headunit'
local APP_HUD = 'vhud'
local TRACK_MS = 500
local IDLE_POLL_MS = 1000        -- only when ox_lib's cache events are not there
local WANT_MS = 2500             -- a change sent to the server wins this long over a state bag that has not caught up
local SEND_GAP_MS = 180          -- the server takes 12 head unit changes per 2 s
local DOORS_CACHE_MS = 250
local HOLD_PUSH_MS = 100
local KNOB_DETENTS = 16
local VOL_ANGLE_MIN, VOL_ANGLE_SPAN = -135.0, 270.0

-- digits in the head unit must not reach the weapon slots, arrows the phone, Enter / Backspace
-- the frontend while game input is kept for driving
local HU_BLOCK = { 157, 158, 159, 160, 161, 162, 163, 164, 165, 27, 172, 173, 174, 175, 177, 194, 202, 18, 191, 201, 245 }

local KEYS = {
    star = { 'star' }, ['*'] = { 'star' },
    hash = { 'hash' }, ['#'] = { 'hash' },
    ok = { 'ok' }, enter = { 'ok' },
    back = { 'back' }, clr = { 'back' }, del = { 'back' }, backspace = { 'back' },
    pre = { 'pre' }, mem = { 'pre' },
    mut = { 'mute' }, mute = { 'mute' },
    pwr = { 'power' }, power = { 'power' },
    emerg = { 'emerg' },
    ptt = { 'ptt' },
    ['vol-'] = { 'knob', 'volume', -1 }, ['vol+'] = { 'knob', 'volume', 1 },
    ['ch-'] = { 'knob', 'channel', -1 }, ['ch+'] = { 'knob', 'channel', 1 },
    up = { 'knob', 'channel', 1 }, down = { 'knob', 'channel', -1 },
    left = { 'knob', 'volume', -1 }, right = { 'knob', 'volume', 1 },
}

local HOLD_KEYS = { emerg = true, power = true }

local NOTICE_KEYS = {
    nosignal = 'scr_nosignal', nofreq = 'scr_nofreq', cooldown = 'scr_cooldown', denied = 'scr_denied',
    disabled = 'scr_denied', busy = 'scr_busy',
}

local list = { models = {}, classes = {} }   -- radio vehicles (GlobalState nzr_vehicles)
local cur = { veh = 0, vnet = nil, radio = false, seat = nil, operator = false }
local vstate = nil              -- nzr_vradio of the current car as the state bag has it
local want = {}                 -- [field] = { value, at }: sent, not yet confirmed
local outbox = nil              -- { vnet, patch } waiting for the send gap
local flushing = false
local lastSentAt = -1e9
local channelInfo = {}          -- [fkey] = { label, access } from join replies (until nzr_labels has it)
local tracking = false

local fw = nil
local huOpen = false
local lastState = nil           -- last screen state the firmware rendered
local lastSentSig = nil
local pressedKey = nil
local pttHeld = false
local chSteps = 0
local emergAt = -1e9

local hudShown, hudSig = false, nil
local ambientSig = 'off'
local doorsCache = {}           -- [veh] = { at, shut }

local function LC(key, ...) return NZR.L('client.' .. key, ...) end
local function cfg() return Config.Vehicles or {} end
local function enabled() return cfg().enabled ~= false end
local function clamp(v, lo, hi) return NZR.Util.Clamp(v, lo, hi) end
local function round2(n) return math.floor(n * 100 + 0.5) / 100 end

local function defaultVolume()
    return clamp((tonumber(Config.Radios and Config.Radios.volume) or 60) / 100, 0.0, 1.0)
end

-- ════════════════════════════════════════════════════════════════════════
-- RADIO VEHICLE LIST
-- ════════════════════════════════════════════════════════════════════════

-- Model hashes as signed 32-bit numbers (GetEntityModel / GetHashKey); the server
-- publishes them that way, a hash read back unsigned must still match.
local function signedHash(h)
    h = tonumber(h)
    if not h then return nil end
    h = math.floor(h) % 4294967296
    if h >= 2147483648 then h = h - 4294967296 end
    return h
end

local function configList()
    local models, classes = {}, {}
    if enabled() then
        for _, name in ipairs(cfg().models or {}) do
            if type(name) == 'string' and name ~= '' then
                models[signedHash(GetHashKey(name))] = { label = name:upper(), range = 1.0, model = name }
            end
        end
        for _, c in ipairs(cfg().classes or {}) do
            local n = tonumber(c)
            if n then classes[math.floor(n)] = true end
        end
    end
    return models, classes
end

local function readList(value)
    if type(value) ~= 'table' then
        local models, classes = configList()
        list = { models = models, classes = classes }
        return
    end
    local models, classes = {}, {}
    for k, v in pairs(type(value.models) == 'table' and value.models or {}) do
        local h = signedHash(k)
        if h and type(v) == 'table' then models[h] = v end
    end
    for k, v in pairs(type(value.classes) == 'table' and value.classes or {}) do
        -- { [18] = true } as published, or a plain list { 18 }
        local n = v == true and tonumber(k) or tonumber(v)
        if n then classes[math.floor(n)] = true end
    end
    list = { models = models, classes = classes }
end

local function entryOf(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local h = signedHash(GetEntityModel(veh))
    return h and list.models[h] or nil
end

function V.IsRadioVehicle(veh)
    if not enabled() or not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    if entryOf(veh) then return true end
    if next(list.classes) == nil then return false end
    local ok, class = pcall(GetVehicleClass, veh)
    return ok and class ~= nil and list.classes[class] == true
end

function V.RangeMult(veh)
    local e = entryOf(veh)
    return e and tonumber(e.range) or 1.0
end

-- ════════════════════════════════════════════════════════════════════════
-- HEAD UNIT STATE
-- ════════════════════════════════════════════════════════════════════════

local function readState(veh)
    if not veh or veh == 0 then return nil end
    local ok, st = pcall(function() return Entity(veh).state.nzr_vradio end)
    if ok and type(st) == 'table' then return st end
    return nil
end

local function sameValue(field, a, b)
    if field == 'v' then return math.abs((tonumber(a) or -1) - (tonumber(b) or -2)) < 0.006 end
    if field == 'f' then return (a or false) == (b or false) end
    return (a == true) == (b == true)
end

-- The car's head unit as the player should see it: the state bag, with every change we
-- sent and the server has not confirmed yet laid over it.
local function headState()
    if cur.veh == 0 or not cur.radio then return nil end
    local st = vstate or {}
    local out = {
        on = st.on == true,
        f = NZR.Freq.Key(st.f),
        v = tonumber(st.v) and clamp(tonumber(st.v), 0.0, 1.0) or defaultVolume(),
        mute = st.mute == true,
        label = type(st.label) == 'string' and st.label or nil,
    }
    local now = GetGameTimer()
    for field, w in pairs(want) do
        if now - w.at > WANT_MS or sameValue(field, out[field], w.value) then
            want[field] = nil
        elseif field == 'f' then
            if out.f ~= (w.value or nil) then out.label = nil end
            out.f = w.value or nil
        else
            out[field] = w.value
        end
    end
    return out
end

function V.State()
    return headState()
end

function V.Current()
    return { veh = cur.veh, vnet = cur.vnet, radio = cur.radio, seat = cur.seat, operator = cur.operator }
end

local function flush()
    if flushing then return end
    flushing = true
    CreateThread(function()
        local gap = SEND_GAP_MS - (GetGameTimer() - lastSentAt)
        if gap > 0 then Wait(gap) end
        local box = outbox
        outbox = nil
        flushing = false
        if box and box.vnet and next(box.patch) ~= nil then
            lastSentAt = GetGameTimer()
            TriggerServerEvent('nzr:vehicle:set', box.vnet, box.patch)
        end
    end)
end

local refreshViews   -- forward (head unit + HUD)

function V.Set(patch)
    if type(patch) ~= 'table' or not enabled() then return false end
    if cur.veh == 0 or not cur.operator or not cur.vnet then return false end
    local clean = {}
    if patch.on ~= nil then clean.on = patch.on == true end
    if patch.mute ~= nil then clean.mute = patch.mute == true end
    if patch.v ~= nil then
        local v = tonumber(patch.v)
        if v and v == v then clean.v = round2(clamp(v, 0.0, 1.0)) end
    end
    if patch.f ~= nil then
        if patch.f == false then
            clean.f = false
        else
            local fkey = NZR.Freq.Key(patch.f)
            if fkey and NZR.Freq.Valid(fkey) then clean.f = fkey end
        end
    end
    if next(clean) == nil then return false end
    local now = GetGameTimer()
    if not outbox or outbox.vnet ~= cur.vnet then outbox = { vnet = cur.vnet, patch = {} } end
    for k, v in pairs(clean) do
        outbox.patch[k] = v
        want[k] = { value = v, at = now }
    end
    flush()
    if refreshViews then refreshViews() end
    return true
end

function V.Join(freq, code)
    if cur.veh == 0 or not cur.operator or not cur.vnet then return { ok = false, reason = 'denied' } end
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return { ok = false, reason = 'invalid' } end
    local veh = cur.veh
    local ok, res = pcall(lib.callback.await, 'nzr:vehicle:join', false, cur.vnet, f, code)
    if not ok or type(res) ~= 'table' then return { ok = false, reason = 'error' } end
    if res.ok and cur.veh == veh then
        local fkey = NZR.Freq.Key(res.freq or f)
        if fkey then
            want.f = { value = fkey, at = GetGameTimer() }
            channelInfo[fkey] = { label = res.label, access = res.access or 'open' }
        end
        if refreshViews then refreshViews() end
    end
    return res
end

function V.CanTransmit()
    if not enabled() or cur.veh == 0 or not cur.operator or not cur.vnet then return false end
    -- the 500 ms loop may not have seen the player get out yet
    if GetVehiclePedIsIn(PlayerPedId(), false) ~= cur.veh then return false end
    local st = headState()
    return st ~= nil and st.on and st.f ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- DOORS (leak attenuation)
-- ════════════════════════════════════════════════════════════════════════

local OPEN_CLASSES = { [8] = true, [13] = true, [14] = true }   -- motorbikes, cycles, boats

function V.DoorsShut(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local now = GetGameTimer()
    local c = doorsCache[veh]
    if c and now - c.at < DOORS_CACHE_MS then return c.shut end
    local shut = true
    local okC, class = pcall(GetVehicleClass, veh)
    if okC and OPEN_CLASSES[class] then shut = false end
    if shut then
        local okR, convertible = pcall(IsVehicleAConvertible, veh, false)
        if okR and convertible then
            local okS, roof = pcall(GetConvertibleRoofState, veh)
            if okS and roof ~= 0 then shut = false end
        end
    end
    if shut then
        for door = 0, 5 do
            local okD, ratio = pcall(GetVehicleDoorAngleRatio, veh, door)
            if okD and (tonumber(ratio) or 0) > 0.05 then
                shut = false
                break
            end
        end
    end
    -- forget cars that left
    if c == nil and next(doorsCache) ~= nil then
        for v, e in pairs(doorsCache) do
            if now - e.at > 10000 then doorsCache[v] = nil end
        end
    end
    doorsCache[veh] = { at = now, shut = shut }
    return shut
end

-- ════════════════════════════════════════════════════════════════════════
-- PASSENGER HUD + CABIN AMBIENCE
-- ════════════════════════════════════════════════════════════════════════

local function labelOf(fkey, fallback)
    if not fkey then return nil end
    local labels = NZR.Radio.Labels and NZR.Radio.Labels() or NZR.Radio.State.labels or {}
    local e = labels[fkey] or channelInfo[fkey]
    if type(e) == 'table' and e.label then return e.label end
    return fallback
end

local function talkerOn(fkey)
    if not fkey then return nil end
    local best, bestAt = nil, -1
    for _, info in pairs(NZR.Radio.State.rx or {}) do
        if type(info) == 'table' and info.fkey == fkey and (tonumber(info.at) or 0) > bestAt then
            best, bestAt = info, tonumber(info.at) or 0
        end
    end
    if not best then return nil end
    return { name = best.name, callsign = best.callsign, q = math.floor((tonumber(best.q) or 0) * 100 + 0.5) / 100 }
end

local function updateAmbient(st)
    local a = cfg().ambient
    local on, volume = false, 0.0
    if type(a) == 'table' and a.enabled and st and st.on and not st.mute then
        on = true
        volume = round2(clamp((tonumber(a.volume) or 0.25) * st.v, 0.0, 1.0))
    end
    local sig = on and ('on:%.2f'):format(volume) or 'off'
    if sig == ambientSig then return end
    ambientSig = sig
    NZR.UI.Send('_core', 'ambient', { on = on, volume = volume })
end

local function updateHud()
    local st = headState()
    updateAmbient(st)
    local show = cfg().hud ~= false and st ~= nil and st.on and not huOpen
    if show then
        local data = {
            freq = st.f, label = labelOf(st.f, st.label), talker = talkerOn(st.f),
            on = st.on, mute = st.mute, model = 'MV-90',
        }
        local ok, sig = pcall(json.encode, data)
        if not ok then sig = nil end
        if not hudShown then
            hudShown, hudSig = true, sig
            NZR.UI.Open(APP_HUD, data, { focus = false })
        elseif sig ~= hudSig then
            hudSig = sig
            NZR.UI.Send(APP_HUD, 'data', data)
        end
    elseif hudShown then
        hudShown, hudSig = false, nil
        NZR.UI.Close(APP_HUD)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- HEAD UNIT FIRMWARE
-- ════════════════════════════════════════════════════════════════════════

local function jamHere()
    if NZR.Jammers and NZR.Jammers.LocalJam then
        local ok, j = pcall(NZR.Jammers.LocalJam, 0.0)
        if ok then return tonumber(j) or 0.0 end
    end
    if NZR.Signal and NZR.Signal.Jam then
        local ok, j = pcall(NZR.Signal.Jam, GetEntityCoords(PlayerPedId()), nil, 0.0)
        if ok then return tonumber(j) or 0.0 end
    end
    return 0.0
end

local function vehicleSource()
    local S = NZR.Radio.State
    local st = headState() or { on = false, v = defaultVolume(), mute = false }
    local fkey = st.f
    local labels = NZR.Radio.Labels and NZR.Radio.Labels() or S.labels or {}
    if fkey and not labels[fkey] then
        local e = channelInfo[fkey] or (st.label and { label = st.label }) or nil
        if e then
            local copy = {}
            for k, v in pairs(labels) do copy[k] = v end
            copy[fkey] = e
            labels = copy
        end
    end
    local rx = {}
    if fkey then
        for talker, info in pairs(S.rx or {}) do
            if type(info) == 'table' and info.fkey == fkey then rx[talker] = info end
        end
    end
    return {
        power = st.on, model = 'vehicle',
        slots = { [1] = fkey and NZR.Freq.Parse(fkey) or nil }, slotCount = 1, txSlot = 1,
        volume = math.floor(st.v * 100 + 0.5), muted = st.mute, handsfree = false,
        clicks = S.clicks ~= false, earpiece = false, earpieceOwned = false,
        presets = S.presets, presetCount = Config.Radios.presets or 0, callsign = S.callsign,
        labels = labels, tx = S.tx and S.tx.active == true and S.tx.device == 'vehicle' or false, rx = rx,
        rosterOn = false, jam = jamHere(), underwater = false, waterproof = true, battery = 1.0,
        emergency = (S.emergencyUntil or 0) > GetGameTimer() and GetGameTimer() - emergAt < 60000,
    }
end

local function releasePtt()
    if not pttHeld then return end
    pttHeld = false
    NZR.Radio.API.Ptt(false, 'vehicle')
end

local function pttEdge(down)
    if not down then
        releasePtt()
        return true
    end
    if pttHeld then return true end
    if not V.CanTransmit() then
        NZR.UI.Send('_core', 'sfx', { name = 'error' })
        local st = headState()
        if fw and st and st.on then fw:Notice(LC('scr_nofreq')) end
        return false
    end
    pttHeld = true
    NZR.Radio.API.Ptt(true, 'vehicle')
    return true
end

local function vehicleActions()
    local API = NZR.Radio.API
    return {
        join = function(_, freq, code) return V.Join(freq, code) end,
        leave = function() return { ok = V.Set({ f = false }) } end,
        power = function(on) V.Set({ on = on }) end,
        volume = function(delta)
            local st = headState()
            if not st then return end
            V.Set({ v = clamp(st.v + (tonumber(delta) or 0) / 100, 0.0, 1.0) })
        end,
        mute = function(on) V.Set({ mute = on }) end,
        emergency = function()
            local ok, reason = API.Emergency('vehicle')
            if ok then emergAt = GetGameTimer() end
            return ok, reason
        end,
        ptt = function(down) return pttEdge(down) end,
    }
end

local function holdProgress()
    local h = fw and fw.holds and fw.holds.emerg
    local hold = fw and tonumber(fw.emergHold) or 0
    if not h or h.done or hold <= 0 then return nil end
    return { emerg = round2(clamp((fw:Now() - h.at) / hold, 0.0, 1.0)) }
end

local function decorate(state)
    local out = {}
    for k, v in pairs(state or {}) do out[k] = v end
    local vol = tonumber(out.volume) or 0
    out.knobs = {
        vol = math.floor((VOL_ANGLE_MIN + VOL_ANGLE_SPAN * clamp(vol, 0, 100) / 100) * 10 + 0.5) / 10,
        ch = chSteps * (360.0 / KNOB_DETENTS),
    }
    out.pressed = pressedKey or (pttHeld and 'ptt') or nil
    out.hold = holdProgress()
    return out
end

local function sendState()
    if not huOpen or not lastState then return end
    local data = decorate(lastState)
    local ok, sig = pcall(json.encode, data)
    if ok and sig == lastSentSig then return end
    lastSentSig = ok and sig or nil
    NZR.UI.Send(APP_HU, 'state', data)
end

local function firmware()
    if fw then return fw end
    if not (NZR.Firmware and NZR.Firmware.New) then return nil end
    fw = NZR.Firmware.New('vehicle', {
        model = 'vehicle',
        skin = 'mv90',
        source = vehicleSource,
        actions = vehicleActions(),
        powerHold = 0,          -- PWR is a plain switch on the head unit
        knobPower = false,
        emergencyHold = (Config.Emergency and tonumber(Config.Emergency.holdTime)) or 1500,
        listViews = false,      -- a single line LCD: tune, code and the home line only
        render = function(state)
            lastState = state
            sendState()
        end,
    })
    return fw
end

refreshViews = function()
    if fw and huOpen then fw:Refresh() end
    updateHud()
end

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE / KEYS
-- ════════════════════════════════════════════════════════════════════════

function V.MapKey(key)
    if type(key) == 'number' then key = tostring(math.floor(key)) end
    if type(key) ~= 'string' then return nil end
    key = key:lower()
    if key:match('^%d$') then return 'digit', key, 1 end
    local m = KEYS[key]
    if not m then return nil end
    return m[1], m[2], m[3] or 1
end

local function holdPushLoop()
    CreateThread(function()
        while huOpen and pressedKey == 'emerg' do
            sendState()
            Wait(HOLD_PUSH_MS)
        end
        sendState()
    end)
end

function V.HandleKey(key, down, data)
    if not huOpen or not fw then return false end
    down = down ~= false
    local action, value, step = V.MapKey(key)
    if not action then return false end
    key = type(key) == 'string' and key:lower() or tostring(key)

    if action == 'ptt' then
        pttEdge(down)
        sendState()
        return true
    end

    if down then
        -- a held EMERG / PWR repeating its down (keyboard auto-repeat) is still one hold
        if HOLD_KEYS[action] and pressedKey == key then return true end
        -- knobs have no pressed look (their angle moves) and every down is one detent,
        -- so a wheel tick that never sends an up cannot leave anything held
        if action ~= 'knob' then pressedKey = key end
        if action == 'knob' and value == 'channel' then chSteps = chSteps + step end
        if action == 'emerg' and type(data) == 'table' and data.held == true then
            -- the page already timed the hold (guarded button): fire on this edge
            local hold = fw.emergHold
            fw.emergHold = 0
            fw:Press('emerg', nil, true)
            fw.emergHold = hold
        else
            fw:Press(action, value, true, step)
        end
        if action == 'emerg' then holdPushLoop() end
    else
        if pressedKey == key then pressedKey = nil end
        fw:Press(action, value, false, step)
    end
    sendState()
    return true
end

function V.IsOpen()
    return huOpen
end

function V.Open()
    if not enabled() then return false end
    V.Refresh()
    if cur.veh == 0 or not cur.radio or not cur.operator or not cur.vnet then return false end
    if NZR.Radio.API.IsDead() then return false end
    if huOpen then return true end
    local f = firmware()
    if not f then return false end
    pressedKey = nil
    f:SetActive(true)
    lastState = f:Render()
    local state = decorate(lastState)
    local ok, sig = pcall(json.encode, state)
    lastSentSig = ok and sig or nil
    huOpen = true
    NZR.UI.Open(APP_HU, state, { focus = true, cursor = true, keepInput = true, controls = HU_BLOCK })
    updateHud()
    return true
end

function V.Close()
    if not huOpen then return false end
    huOpen = false
    releasePtt()
    if fw then
        if pressedKey then
            local action, value, step = V.MapKey(pressedKey)
            if action and action ~= 'ptt' then fw:Press(action, value, false, step) end
        end
        fw:SetActive(false)
    end
    pressedKey, lastSentSig = nil, nil
    NZR.UI.Close(APP_HU)
    updateHud()
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- WHERE THE PLAYER SITS
-- ════════════════════════════════════════════════════════════════════════

local function netOf(veh)
    local ok, networked = pcall(NetworkGetEntityIsNetworked, veh)
    if not ok or not networked then return nil end
    local okN, net = pcall(VehToNet, veh)
    net = okN and tonumber(net) or nil
    if net and net > 0 then return net end
    return nil
end

local function seatOf(ped, veh)
    local n = tonumber(GetVehicleMaxNumberOfPassengers(veh)) or 0
    for seat = -1, math.max(-1, n - 1) do
        if GetPedInVehicleSeat(veh, seat) == ped then return seat end
    end
    return nil
end

local function operatorSeat(seat)
    for _, s in ipairs(cfg().seats or { -1, 0 }) do
        if tonumber(s) == seat then return true end
    end
    return false
end

local function enterVehicle(veh)
    if huOpen then V.Close() end
    releasePtt()
    cur = { veh = veh, vnet = nil, radio = false, seat = nil, operator = false }
    want, outbox, chSteps = {}, nil, 0
    if fw then fw:Reset() end
    if veh ~= 0 then
        cur.radio = V.IsRadioVehicle(veh)
        cur.vnet = netOf(veh)
        vstate = cur.radio and readState(veh) or nil
    else
        vstate = nil
    end
    NZR.Bus.Emit('vehicle:changed', veh)
end

-- One look at where the player is. → true while inside a vehicle.
function V.Refresh()
    if not enabled() then return false end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then veh = 0 end
    if veh ~= cur.veh then enterVehicle(veh) end
    if veh ~= 0 then
        if not cur.vnet then cur.vnet = netOf(veh) end
        local seat = seatOf(ped, veh)
        local operator = cur.radio and seat ~= nil and operatorSeat(seat)
        if seat ~= cur.seat or operator ~= cur.operator then
            cur.seat, cur.operator = seat, operator
            if not operator then
                if huOpen then V.Close() end
                releasePtt()
            end
        end
        if huOpen and NZR.Radio.API.IsDead() then V.Close() end
    end
    updateHud()
    return veh ~= 0
end

local function track()
    if tracking or not enabled() then return end
    tracking = true
    CreateThread(function()
        while V.Refresh() do Wait(TRACK_MS) end
        tracking = false
    end)
end

local function onCacheChange()
    if tracking then V.Refresh() else track() end
end

-- ════════════════════════════════════════════════════════════════════════
-- EVENTS / BUS / STATE BAGS
-- ════════════════════════════════════════════════════════════════════════

AddStateBagChangeHandler('nzr_vehicles', 'global', function(_, _, value)
    readList(value)
    if cur.veh ~= 0 then
        local radio = V.IsRadioVehicle(cur.veh)
        if radio ~= cur.radio then
            -- the car was added to / removed from the list while sitting in it
            if huOpen then V.Close() end
            releasePtt()
            cur.radio, cur.seat, cur.operator = radio, nil, false
            vstate = radio and readState(cur.veh) or nil
            V.Refresh()
        end
    end
end)

AddStateBagChangeHandler('nzr_vradio', nil, function(bagName, _, value)
    if cur.veh == 0 or not cur.radio then return end
    local ok, ent = pcall(GetEntityFromStateBagName, bagName)
    if not ok or ent ~= cur.veh then return end
    vstate = type(value) == 'table' and value or nil
    if pttHeld and not V.CanTransmit() then releasePtt() end
    refreshViews()
end)

AddEventHandler('gameEventTriggered', function(name)
    if name == 'CEventNetworkPlayerEnteredVehicle' then track() end
end)

NZR.Bus.On('radio:changed', function(what)
    if cur.veh == 0 or not cur.radio then return end
    if fw and huOpen then fw:Refresh() end
    if what == 'rx' or what == 'labels' then updateHud() end
end)

NZR.Bus.On('radio:notice', function(key, device)
    if device ~= 'vehicle' or not fw or not huOpen or type(key) ~= 'string' then return end
    fw:Notice(LC(NOTICE_KEYS[key] or 'scr_error'))
end)

CreateThread(function()
    Wait(0)
    readList(GlobalState.nzr_vehicles)

    NZR.UI.On(APP_HU, 'press', function(data, cb)
        cb({ ok = true })
        if type(data) == 'table' then V.HandleKey(data.key, data.down, data) end
    end)
    NZR.UI.On(APP_HU, 'close', function(_, cb)
        V.Close()
        cb({ ok = true })
    end)

    local cached = false
    if lib and lib.onCache then
        cached = pcall(lib.onCache, 'vehicle', onCacheChange)
        pcall(lib.onCache, 'seat', onCacheChange)
    end
    track()
    if cached then return end
    -- without ox_lib's cache events: a single native a second while on foot
    while true do
        if not tracking and IsPedInAnyVehicle(PlayerPedId(), false) then track() end
        Wait(IDLE_POLL_MS)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    if huOpen then
        huOpen = false
        if fw then fw.active = false end
        NZR.UI.Close(APP_HU)
    end
    if pttHeld then
        pttHeld = false
        NZR.Radio.API.Ptt(false, 'vehicle')
    end
    if hudShown then
        hudShown = false
        NZR.UI.Close(APP_HUD)
    end
    if ambientSig ~= 'off' then
        ambientSig = 'off'
        NZR.UI.Send('_core', 'ambient', { on = false, volume = 0.0 })
    end
end)
