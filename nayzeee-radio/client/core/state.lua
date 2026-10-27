--[[
    NAYZEEE RADIO - Client core: radio state, the radio API, keys, commands and exports

    The server owns the record (SPEC §4); this file keeps the client's copy in
    NZR.Radio.State, sends every change through NZR.Radio.API and tells the rest of the
    client through the bus. Volume and mic clicks are personal settings (client KVP).

      NZR.Radio.State
          ready, model ('handheld'|'fieldpro'|'military'|nil), owned = { [model] = true },
          power, slots = { [i] = 155.5 }, txSlot, volume (0-100, KVP), muted, handsfree,
          earpiece, earpieceOwned, presets = { [i] = 155.5 | false }, callsign, clicks (KVP),
          labels (GlobalState nzr_labels), tx = { active, device, since }, rx = { [talker] = info },
          raised, rosterOn, underwater, emergencyUntil (ms, game timer)
      NZR.Radio.API
          Init()                         ask the server for the record (nzr:radio:init)
          Join(slot, freq, code?) → res  (yields) { ok, label, access } | { ok = false, reason }
          Leave(slot) → res              (yields)
          SetTxSlot(i)  NextSlot()  Power(on)  Volume(delta) → v  SetVolume(v)  Mute(on)
          Handsfree(on)  Earpiece(on)  Clicks(on)  ToggleRoster()  SetModel(model)
          PresetSet(i, freq | false) → res  (yields) { ok, presets }
          Callsign(text | false) → res      (yields) { ok, callsign }
          Emergency(device?) → ok, reason   Ptt(down, device?)   Device() → 'vehicle'|'handheld'
          CanTalk(device) → ok, reason      IsDead()   Raise()   Lower()   ToggleRaise()
          SlotCount() → n                   TxFreq() → 155.5 | nil
      NZR.Radio.ApplyRecord(rec, owned?)   NZR.Radio.Labels() → { [fkey] = { label, access } }
      NZR.Radio.Battery() → 0..1 (cosmetic)   NZR.Radio.KeyName(bind) → current key of a keybind
      NZR.Radio.SetRaised(on)   NZR.Radio.SetTx(active, device)   NZR.Radio.Changed(what)

    KEYBINDS (lib.addKeybind, Settings > Key Bindings > FiveM)
      nzr_ptt (hold), nzr_raise, nzr_handsfree, nzr_mute, nzr_nextslot, nzr_roster,
      nzr_emergency (hold Config.Emergency.holdTime)          defaults from Config.Keys
    COMMANDS   Config.Commands.radio (raise / lower), Config.Commands.callsign (text | empty)
    EXPORTS    isRadioOpen, isTalking, getFrequency, setFrequency(freq, slot?), raise, lower,
               getModel, useRadio(data) (ox_inventory client export hook)

    EVENTS SENT      nzr:radio:power, nzr:radio:model, nzr:radio:txslot, nzr:radio:mute,
                     nzr:radio:handsfree, nzr:radio:earpiece, nzr:radio:underwater,
                     nzr:alerts:emergency (C→S)
    CALLBACKS        nzr:radio:init, nzr:radio:join, nzr:radio:leave, nzr:radio:preset,
                     nzr:radio:callsign (C→S, lib.callback)
    EVENTS HANDLED   nzr:radio:state (record), nzr:radio:use (model), nzr:radio:dropped (S→C)
    STATE BAGS       writes Player(me).state.nzr_hold = { m, r, t } | nil (replicated)
                     reads GlobalState.nzr_labels (+ change handler)
    BUS EMITTED      'radio:changed' (what), 'radio:notice' (key, device), 'radio:power' (on)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Radio = NZR.Radio or {}
NZR.Radio.State = NZR.Radio.State or {}
NZR.Radio.API = NZR.Radio.API or {}
local R = NZR.Radio
local S = R.State
local API = R.API

local KVP_VOLUME = 'nzr_volume'
local KVP_CLICKS = 'nzr_clicks'
local RESYNC_MS = 2500           -- an optimistic change the server never confirmed is re-read after this
local INIT_TRIES = 6

local function L(key, ...) return NZR.L('client.' .. key, ...) end

-- ════════════════════════════════════════════════════════════════════════
-- STATE
-- ════════════════════════════════════════════════════════════════════════

local function kvpString(key)
    local ok, v = pcall(GetResourceKvpString, key)
    if ok and type(v) == 'string' and v ~= '' then return v end
    return nil
end

local function defaultVolume()
    local v = tonumber(kvpString(KVP_VOLUME))
    if not v then v = tonumber(Config.Radios.volume) or 60 end
    return math.max(0, math.min(100, math.floor(v + 0.5)))
end

local function defaultClicks()
    local v = kvpString(KVP_CLICKS)
    if v == '1' then return true end
    if v == '0' then return false end
    return Config.Audio == nil or Config.Audio.clicks ~= false
end

local function emptyPresets()
    local out = {}
    for i = 1, (Config.Radios.presets or 0) do out[i] = false end
    return out
end

S.ready = false
S.model = nil
S.owned = {}
S.power = false
S.slots = {}
S.txSlot = 1
S.volume = defaultVolume()
S.muted = false
S.handsfree = false
S.earpiece = false
S.earpieceOwned = false
S.presets = emptyPresets()
S.callsign = nil
S.clicks = defaultClicks()
S.labels = {}
S.channelInfo = {}       -- what join replies said about a channel (label / access), until the labels catch up
S.tx = { active = false, device = nil, since = 0 }
S.rx = {}
S.raised = false
S.rosterOn = false
S.underwater = false
S.emergencyUntil = 0
S.poweredAt = 0

local lastStateAt = 0
local resyncAt = nil
local lastEmergency = -1e9

function R.Changed(what)
    NZR.Bus.Emit('radio:changed', what)
end
local changed = R.Changed

function R.Labels()
    if next(S.channelInfo) == nil then return S.labels end
    local out = {}
    for k, v in pairs(S.channelInfo) do out[k] = v end
    for k, v in pairs(S.labels) do out[k] = v end
    return out
end

-- Cosmetic: drains over ~10 hours of powered time, never below 12 %.
function R.Battery()
    if not S.power or S.poweredAt <= 0 then return 1.0 end
    local hours = (GetGameTimer() - S.poweredAt) / 3600000
    return math.max(0.12, 1.0 - hours * 0.088)
end

function API.SlotCount()
    local m = S.model and Config.Radios.Models[S.model]
    return math.max(1, math.min(5, m and tonumber(m.slots) or 1))
end

function API.TxFreq()
    return S.slots[S.txSlot]
end

-- ════════════════════════════════════════════════════════════════════════
-- RECORD
-- ════════════════════════════════════════════════════════════════════════

local function normSlots(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        local i = tonumber(k)
        local f = v and NZR.Freq.Parse(v) or nil
        if i and f and i >= 1 and i <= 5 then out[math.floor(i)] = f end
    end
    return out
end

local function normPresets(t)
    local out = emptyPresets()
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        local i = tonumber(k)
        if i and out[math.floor(i)] ~= nil then
            out[math.floor(i)] = v and NZR.Freq.Parse(v) or false
        end
    end
    return out
end

-- owned arrives as { handheld = true } or as a list of model keys
local function normOwned(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if type(k) == 'string' and v then out[k] = true end
        if type(v) == 'string' then out[v] = true end
    end
    return out
end

local function onPower(on)
    if on then
        S.poweredAt = GetGameTimer()
        R.WatchPower()
    else
        S.poweredAt = 0
        S.emergencyUntil = 0
    end
    NZR.Bus.Emit('radio:power', on)
end

function R.ApplyRecord(rec, owned)
    if type(rec) ~= 'table' then return end
    lastStateAt = GetGameTimer()
    resyncAt = nil
    local wasPower = S.power
    if owned ~= nil then
        S.owned = normOwned(owned)
    elseif rec.owned ~= nil then
        S.owned = normOwned(rec.owned)
    end
    if S.owned.earpiece then S.earpieceOwned = true end
    local model = rec.model
    S.model = (type(model) == 'string' and Config.Radios.Models[model]) and model or nil
    if S.model then S.owned[S.model] = true end
    if rec.earpieceOwned ~= nil then S.earpieceOwned = rec.earpieceOwned == true end
    S.power = rec.power == true and S.model ~= nil
    S.slots = normSlots(rec.slots)
    S.txSlot = math.max(1, math.min(API.SlotCount(), math.floor(tonumber(rec.txSlot) or 1)))
    S.muted = rec.muted == true
    S.handsfree = rec.handsfree == true and S.power
    S.earpiece = rec.earpiece == true and S.earpieceOwned
    if rec.presets ~= nil then S.presets = normPresets(rec.presets) end
    if rec.callsign ~= nil then
        S.callsign = type(rec.callsign) == 'string' and rec.callsign ~= '' and rec.callsign or nil
    end
    if wasPower ~= S.power then onPower(S.power) end
    changed('record')
    R.SyncHold()
end

-- An optimistic change (power, slot, mute ...) is shown at once. If the server never
-- sends the record back (it refused, or the event was dropped) the record is read again.
local function expectState()
    local asked = GetGameTimer()
    resyncAt = asked
    SetTimeout(RESYNC_MS, function()
        if resyncAt ~= asked or lastStateAt >= asked then return end
        resyncAt = nil
        API.Init(true)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function await(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok then
        NZR.Debug('callback failed', name, tostring(res))
        return nil
    end
    return res
end

local function toast(key, kind, ...)
    if NZR.UI and NZR.UI.Toast then
        NZR.UI.Toast({ title = L('title'), message = L(key, ...), type = kind or 'info' })
    end
end
R.Toast = toast

local initBusy = false
function API.Init(quiet)
    if initBusy then return end
    initBusy = true
    CreateThread(function()
        for attempt = 1, INIT_TRIES do
            local res = await('nzr:radio:init')
            if type(res) == 'table' and res.ok ~= false then
                if type(res.labels) == 'table' then S.labels = res.labels end
                local rec = type(res.record) == 'table' and res.record or res
                R.ApplyRecord(rec, res.owned)
                local first = not S.ready
                S.ready = true
                if first then
                    if NZR.UI and NZR.UI.PushConfig then NZR.UI.PushConfig() end
                    changed('init')
                end
                break
            end
            if quiet and attempt >= 2 then break end
            Wait(1500 * attempt)
        end
        initBusy = false
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- API
-- ════════════════════════════════════════════════════════════════════════

function API.Join(slot, freq, code)
    if not S.model then return { ok = false, reason = 'power' } end
    if not S.power then return { ok = false, reason = 'power' } end
    slot = math.floor(tonumber(slot) or S.txSlot)
    if slot < 1 or slot > API.SlotCount() then return { ok = false, reason = 'invalid' } end
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return { ok = false, reason = 'invalid' } end
    if code ~= nil then code = tostring(code) end
    local res = await('nzr:radio:join', slot, f, code)
    if type(res) ~= 'table' then return { ok = false, reason = 'error' } end
    if res.ok then
        S.slots[slot] = f
        local key = NZR.Freq.Key(f)
        if res.label ~= nil or res.access ~= nil then
            S.channelInfo[key] = { label = res.label, access = res.access or 'open' }
        end
        changed('slots')
    end
    return res
end

function API.Leave(slot)
    slot = math.floor(tonumber(slot) or S.txSlot)
    if not S.slots[slot] then return { ok = false, reason = 'invalid' } end
    local res = await('nzr:radio:leave', slot)
    if type(res) ~= 'table' then return { ok = false, reason = 'error' } end
    if res.ok then
        S.slots[slot] = nil
        changed('slots')
    end
    return res
end

function API.SetTxSlot(i)
    i = math.floor(tonumber(i) or 1)
    if i < 1 or i > API.SlotCount() then return false end
    if i == S.txSlot then return true end
    S.txSlot = i
    TriggerServerEvent('nzr:radio:txslot', i)
    expectState()
    changed('txslot')
    return true
end

-- the next slot that holds a frequency (any slot when none do)
function API.NextSlot()
    local n = API.SlotCount()
    if n <= 1 then return false end
    for k = 1, n do
        local i = (S.txSlot - 1 + k) % n + 1
        if S.slots[i] then return API.SetTxSlot(i) end
    end
    return API.SetTxSlot(S.txSlot % n + 1)
end

function API.Power(on)
    on = on == true
    if on and not S.model then
        toast('no_radio', 'error')
        return false
    end
    if S.power == on then return true end
    S.power = on
    if not on then S.handsfree = false end
    TriggerServerEvent('nzr:radio:power', on)
    expectState()
    onPower(on)
    changed('power')
    return true
end

function API.SetVolume(v)
    v = math.max(0, math.min(100, math.floor((tonumber(v) or 0) + 0.5)))
    if v == S.volume then return v end
    S.volume = v
    pcall(SetResourceKvp, KVP_VOLUME, tostring(v))
    changed('volume')
    return v
end

function API.Volume(delta)
    return API.SetVolume(S.volume + (tonumber(delta) or 0))
end

function API.Mute(on)
    on = on == true
    if S.muted == on then return true end
    S.muted = on
    TriggerServerEvent('nzr:radio:mute', on)
    expectState()
    changed('mute')
    return true
end

function API.Handsfree(on)
    on = on == true
    if on and (not S.power or not S.slots[S.txSlot]) then return false end
    if on and not Config.Radios.Talk.whileDead and API.IsDead() then return false end
    if S.handsfree == on then return true end
    S.handsfree = on
    TriggerServerEvent('nzr:radio:handsfree', on)
    expectState()
    changed('handsfree')
    return true
end

function API.Earpiece(on)
    on = on == true
    if on and not S.earpieceOwned then return false end
    if S.earpiece == on then return true end
    S.earpiece = on
    TriggerServerEvent('nzr:radio:earpiece', on)
    expectState()
    changed('earpiece')
    return true
end

function API.Clicks(on)
    on = on == true
    S.clicks = on
    pcall(SetResourceKvp, KVP_CLICKS, on and '1' or '0')
    changed('clicks')
    return true
end

function API.ToggleRoster()
    S.rosterOn = not S.rosterOn
    changed('roster')
    return S.rosterOn
end

function API.SetModel(model)
    if type(model) ~= 'string' or not Config.Radios.Models[model] then return false end
    if S.model == model then return true end
    S.model = model
    S.owned[model] = true
    TriggerServerEvent('nzr:radio:model', model)
    expectState()
    changed('model')
    R.SyncHold()
    return true
end

function API.PresetSet(index, freq)
    index = math.floor(tonumber(index) or 0)
    if index < 1 or index > (Config.Radios.presets or 0) then return { ok = false, reason = 'invalid' } end
    local f = false
    if freq then
        f = NZR.Freq.Parse(freq)
        if not f or not NZR.Freq.Valid(f) then return { ok = false, reason = 'invalid' } end
    end
    local res = await('nzr:radio:preset', index, f)
    if type(res) ~= 'table' then return { ok = false, reason = 'error' } end
    if res.ok then
        if type(res.presets) == 'table' then
            S.presets = normPresets(res.presets)
        else
            S.presets[index] = f
        end
        changed('presets')
    end
    return res
end

function API.Callsign(text)
    if Config.Radios.callsign == false then return { ok = false, reason = 'off' } end
    local res = await('nzr:radio:callsign', text or false)
    if type(res) ~= 'table' then return { ok = false, reason = 'error' } end
    if res.ok then
        S.callsign = type(res.callsign) == 'string' and res.callsign ~= '' and res.callsign or nil
        changed('callsign')
    end
    return res
end

function API.IsDead()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return true end
    local st = LocalPlayer.state
    if st.isDead or st.dead then return true end
    local pd = Bridge and Bridge.PlayerData and Bridge.PlayerData()
    local md = type(pd) == 'table' and pd.metadata or nil
    if type(md) == 'table' and (md.isdead or md.inlaststand) then return true end
    return false
end

-- In an operating seat of a radio car with its head unit on, PTT talks through the car.
function API.Device()
    if Config.Vehicles and Config.Vehicles.enabled ~= false and Config.Vehicles.pttPriority
        and NZR.Vehicle and NZR.Vehicle.CanTransmit then
        local ok, can = pcall(NZR.Vehicle.CanTransmit)
        if ok and can then return 'vehicle' end
    end
    return 'handheld'
end

local function localJam()
    if NZR.Jammers and NZR.Jammers.LocalJam then
        local ok, j = pcall(NZR.Jammers.LocalJam)
        if ok then return tonumber(j) or 0.0 end
    end
    return 0.0
end

-- The client-side gate before asking the server to open the mic (the server re-checks).
function API.CanTalk(device)
    if not Config.Radios.Talk.whileDead and API.IsDead() then return false, 'dead' end
    if device == 'vehicle' then return true end
    if not S.model or not S.power then return false, 'power' end
    if not S.slots[S.txSlot] then return false, 'nofreq' end
    if localJam() >= ((Config.Signal and Config.Signal.txBlockJam) or 0.92) then return false, 'nosignal' end
    return true
end

function API.Ptt(down, device)
    if not (NZR.Voice and NZR.Voice.Ptt) then return false end
    return NZR.Voice.Ptt(down == true, device or API.Device())
end

function API.Emergency(device)
    local cfg = Config.Emergency or {}
    if not cfg.enabled then return false, 'disabled' end
    device = device or API.Device()
    if device ~= 'vehicle' and (not S.power or not S.slots[S.txSlot]) then return false, 'nofreq' end
    if cfg.jobs and Bridge and Bridge.JobMatches and Bridge.GetJob then
        local ok, match = pcall(Bridge.JobMatches, Bridge.GetJob(), cfg.jobs, false)
        if ok and not match then return false, 'denied' end
    end
    local now = GetGameTimer()
    if now - lastEmergency < (tonumber(cfg.cooldown) or 30) * 1000 then return false, 'cooldown' end
    lastEmergency = now
    TriggerServerEvent('nzr:alerts:emergency', device)
    local hot = math.max(0, tonumber(cfg.hotMic) or 0) * 1000
    S.emergencyUntil = now + math.max(hot, 4000)
    changed('emergency')
    if hot > 0 and NZR.Voice and NZR.Voice.HotMic then NZR.Voice.HotMic(device, hot) end
    SetTimeout(math.max(hot, 4000) + 50, function() changed('emergency') end)
    return true
end

function API.Raise()
    if NZR.Interact and NZR.Interact.Raise then return NZR.Interact.Raise() end
    return false
end

function API.Lower()
    if NZR.Interact and NZR.Interact.Lower then return NZR.Interact.Lower() end
    return false
end

function API.ToggleRaise()
    if NZR.UI and NZR.UI.IsOpen and NZR.UI.IsOpen('headunit') then
        if NZR.Vehicle and NZR.Vehicle.Close then pcall(NZR.Vehicle.Close) end
        return
    end
    if S.raised then return API.Lower() end
    return API.Raise()
end

-- ════════════════════════════════════════════════════════════════════════
-- HOLD STATE BAG + MODULE HOOKS
-- ════════════════════════════════════════════════════════════════════════

local lastHold = nil

-- nzr_hold = { m = model, r = raised, t = talking } while the radio is up or talking,
-- nil otherwise. Every client draws radios in hands from it (held.lua).
function R.SyncHold()
    local v = nil
    local talking = S.tx.active == true
    if S.model and (S.raised or talking) then v = { m = S.model, r = S.raised == true, t = talking } end
    local sig = v and ('%s|%s|%s'):format(v.m, tostring(v.r), tostring(v.t)) or '-'
    if sig == lastHold then return end
    lastHold = sig
    pcall(function() LocalPlayer.state:set('nzr_hold', v, true) end)
end

function R.SetRaised(on)
    on = on == true
    if S.raised == on then return end
    S.raised = on
    changed('raised')
    R.SyncHold()
end

function R.SetTx(active, device)
    active = active == true
    if S.tx.active == active and S.tx.device == device then return end
    S.tx = { active = active, device = active and device or nil, since = active and GetGameTimer() or 0 }
    changed('tx')
    R.SyncHold()
end

-- Only while powered: once a second, tell the server when the radio goes under water.
local watching = false
function R.WatchPower()
    if watching then return end
    watching = true
    CreateThread(function()
        while S.power do
            local under = IsPedSwimmingUnderWater(PlayerPedId()) == true
            if under ~= S.underwater then
                S.underwater = under
                TriggerServerEvent('nzr:radio:underwater', under)
                changed('underwater')
            end
            Wait(1000)
        end
        if S.underwater then
            S.underwater = false
            TriggerServerEvent('nzr:radio:underwater', false)
            changed('underwater')
        end
        watching = false
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER → CLIENT
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nzr:radio:state', function(rec)
    R.ApplyRecord(rec)
    if not S.ready then
        S.ready = true
        changed('init')
    end
end)

-- tellServer: the item was used through the ox_inventory client export (the server has
-- not switched the model yet); nzr:radio:use comes after the server already did.
local function useModel(model, tellServer)
    if type(model) ~= 'string' or not Config.Radios.Models[model] then return end
    S.owned[model] = true
    local switching = S.model ~= model
    if switching then
        if tellServer then
            TriggerServerEvent('nzr:radio:model', model)
            expectState()
        end
        S.model = model
        changed('model')
        R.SyncHold()
    end
    CreateThread(function()
        if switching and S.raised then
            API.Lower()
            Wait(500)
        end
        Wait(50)
        if not S.raised then API.Raise() end
    end)
end

RegisterNetEvent('nzr:radio:use', function(model) useModel(model, false) end)

RegisterNetEvent('nzr:radio:dropped', function()
    API.Lower()
    S.handsfree = false
    if S.power then
        S.power = false
        onPower(false)
    end
    S.owned = {}
    S.slots = {}
    changed('dropped')
    R.SyncHold()
end)

AddStateBagChangeHandler('nzr_labels', 'global', function(_, _, value)
    S.labels = type(value) == 'table' and value or {}
    -- the published list is the truth again for every channel it names
    for k in pairs(S.channelInfo) do
        if S.labels[k] then S.channelInfo[k] = nil end
    end
    changed('labels')
end)

-- ════════════════════════════════════════════════════════════════════════
-- KEYBINDS
-- ════════════════════════════════════════════════════════════════════════

local binds = {}

function R.KeyName(name)
    local b = binds[name]
    if b and b.getCurrentKey then
        local ok, key = pcall(b.getCurrentKey, b)
        if ok and type(key) == 'string' and key ~= '' then return key end
    end
    local defaults = { ptt = 'ptt', raise = 'raise', handsfree = 'handsfree', mute = 'mute',
        nextslot = 'nextSlot', roster = 'roster', emergency = 'emergency' }
    local k = Config.Keys and Config.Keys[defaults[name] or name]
    return k ~= '' and k or nil
end

local function bind(name, key, desc, pressed, released)
    local ok, kb = pcall(lib.addKeybind, {
        name = 'nzr_' .. name,
        description = L(desc),
        defaultKey = key or '',
        defaultMapper = 'keyboard',
        onPressed = pressed,
        onReleased = released,
    })
    if ok then binds[name] = kb else NZR.Warn(('keybind nzr_%s failed: %s'):format(name, tostring(kb))) end
end

local function canUseKeys()
    return S.ready and not IsPauseMenuActive()
end

local pttDevice = nil
local keys = Config.Keys or {}

bind('ptt', keys.ptt, 'key_ptt', function()
    if not canUseKeys() then return end
    pttDevice = API.Device()
    API.Ptt(true, pttDevice)
end, function()
    API.Ptt(false, pttDevice)
    pttDevice = nil
end)

bind('raise', keys.raise, 'key_raise', function()
    if not canUseKeys() then return end
    API.ToggleRaise()
end)

bind('handsfree', keys.handsfree, 'key_handsfree', function()
    if not canUseKeys() then return end
    if not API.Handsfree(not S.handsfree) then
        if NZR.UI then NZR.UI.Send('_core', 'sfx', { name = 'error' }) end
    end
end)

bind('mute', keys.mute, 'key_mute', function()
    if not canUseKeys() or not S.power then return end
    API.Mute(not S.muted)
end)

bind('nextslot', keys.nextSlot, 'key_nextslot', function()
    if not canUseKeys() or not S.power then return end
    if API.NextSlot() and NZR.UI then NZR.UI.Send('_core', 'sfx', { name = 'key' }) end
end)

bind('roster', keys.roster, 'key_roster', function()
    if not canUseKeys() then return end
    API.ToggleRoster()
end)

local emergencyHolding = false
bind('emergency', keys.emergency, 'key_emergency', function()
    if not canUseKeys() or emergencyHolding then return end
    if not (Config.Emergency and Config.Emergency.enabled) then return end
    emergencyHolding = true
    CreateThread(function()
        local hold = math.max(0, tonumber(Config.Emergency.holdTime) or 1500)
        local started = GetGameTimer()
        local device = API.Device()
        local kb = binds.emergency
        while kb and kb.isPressed and GetGameTimer() - started < hold do
            if NZR.UI then
                NZR.UI.Prompt('nzr_emergency', { key = R.KeyName('emergency') or '', label = L('emergency_hold'),
                    progress = (GetGameTimer() - started) / math.max(1, hold), tone = 'red' })
            end
            Wait(50)
        end
        if NZR.UI then NZR.UI.HidePrompt('nzr_emergency') end
        if not kb or GetGameTimer() - started >= hold then
            local ok, reason = API.Emergency(device)
            if not ok and reason then
                if NZR.UI then NZR.UI.Send('_core', 'sfx', { name = 'error' }) end
                NZR.Bus.Emit('radio:notice', reason == 'cooldown' and 'cooldown' or reason == 'nofreq' and 'nofreq' or 'denied', device)
            end
        end
        emergencyHolding = false
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════════════

local function suggest(name, help, params)
    TriggerEvent('chat:addSuggestion', '/' .. name, help, params or {})
end

local cmds = Config.Commands or {}

if cmds.radio then
    RegisterCommand(cmds.radio, function()
        if not S.ready then return end
        API.ToggleRaise()
    end, false)
end

if cmds.callsign and Config.Radios.callsign ~= false then
    RegisterCommand(cmds.callsign, function(_, args)
        local text = table.concat(args or {}, ' '):gsub('^%s+', ''):gsub('%s+$', '')
        CreateThread(function()
            local res = API.Callsign(text ~= '' and text or false)
            if res.ok then
                if S.callsign then toast('callsign_set', 'success', S.callsign) else toast('callsign_cleared', 'info') end
            elseif res.reason == 'off' then
                toast('callsign_off', 'error')
            else
                toast('callsign_failed', 'error')
            end
        end)
    end, false)
end

CreateThread(function()
    Wait(1000)
    if cmds.radio then suggest(cmds.radio, L('cmd_radio')) end
    if cmds.callsign and Config.Radios.callsign ~= false then
        suggest(cmds.callsign, L('cmd_callsign'), { { name = 'callsign', help = L('cmd_callsign_param', Config.Radios.callsign or 8) } })
    end
    for name in pairs(binds) do
        TriggerEvent('chat:removeSuggestion', ('/+nzr_%s'):format(name))
        TriggerEvent('chat:removeSuggestion', ('/-nzr_%s'):format(name))
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('isRadioOpen', function() return S.raised == true end)
exports('isTalking', function() return S.tx.active == true end)
exports('getFrequency', function(slot)
    local f = S.slots[math.floor(tonumber(slot) or S.txSlot)]
    return f
end)
exports('getModel', function() return S.model end)
exports('raise', function() return API.Raise() end)
exports('lower', function() return API.Lower() end)

-- Returns at once (the join itself is a server round trip): true when the request went
-- out, false + reason when it could not. Pass a function as 3rd argument to get the reply.
exports('setFrequency', function(freq, slot, cb)
    if not S.power then return false, 'power' end
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return false, 'invalid' end
    CreateThread(function()
        local res = API.Join(slot or S.txSlot, f)
        if type(cb) == 'function' then pcall(cb, res) end
    end)
    return true
end)

-- ox_inventory: item = { client = { export = 'nayzeee-radio.useRadio' } }
exports('useRadio', function(data)
    local name = type(data) == 'table' and data.name or data
    for model, item in pairs(Config.Items or {}) do
        if item == name and Config.Radios.Models[model] then
            useModel(model, true)
            return true
        end
    end
    return false
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

local function resetLocal()
    API.Lower()
    S.ready = false
    S.handsfree = false
    if S.power then
        S.power = false
        onPower(false)
    end
    S.model, S.owned, S.slots = nil, {}, {}
    S.presets = emptyPresets()
    S.callsign, S.rosterOn = nil, false
    changed('reset')
    R.SyncHold()
end

CreateThread(function()
    Wait(0)
    S.labels = type(GlobalState.nzr_labels) == 'table' and GlobalState.nzr_labels or {}
    if Bridge and Bridge.OnPlayerLoaded then
        Bridge.OnPlayerLoaded(function() API.Init() end, true)
    end
    if Bridge and Bridge.OnPlayerUnloaded then
        Bridge.OnPlayerUnloaded(resetLocal)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    pcall(function() LocalPlayer.state:set('nzr_hold', nil, true) end)
    if NZR.UI and NZR.UI.HidePrompt then NZR.UI.HidePrompt('nzr_emergency') end
end)
