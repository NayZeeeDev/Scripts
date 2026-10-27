--[[
    NAYZEEE RADIO - Radio (server): player radios, items, power, channel slots, presets

    The server owns every radio. NZR.Radio.players[src] is the only truth about what a
    player's radio is doing; the client asks for changes and gets the record back with
    'nzr:radio:state' after every change the server makes.

    RECORD (SPEC §4)
      NZR.Radio.players[src] = {
        src, identifier, name, callsign, job = { name, grade, onDuty },
        model = 'handheld' | 'fieldpro' | 'military' | nil, owned = { handheld = true, ... },
        earpieceOwned, power, slots = { [1] = 155.5, [3] = 160.25 }, txSlot,
        muted, earpiece, handsfree, underwater,
        unlocked = { ['155.50'] = true }, presets = { 155.5 | false, ... },
        codeFails = { ['155.50'] = { n, lockedUntil } },
        tx = nil | routing's transmission (see routing.lua),
      }
      NZR.Radio.members[fkey] = { [src] = slot }      powered radios with fkey in a slot

    PUBLIC RECORD (what the owner's client gets: init, nzr:radio:state)
      { src, name, callsign ('1G' | false = none), model, owned, earpieceOwned, power,
        slots (holes allowed), slotCount, txSlot, muted, earpiece, handsfree, underwater,
        presets (false = free), presetCount, unlocked, tx = { fkey, slot, device, emergency } | nil }

    Items are re-checked on power-on, on a model change, every 5 s for powered radios and
    whenever the inventory bridge reports a change. Losing every radio powers the radio off,
    leaves every channel and sends 'nzr:radio:dropped'.

    API
      NZR.Radio.Get(src)                       → record | nil
      NZR.Radio.Ensure(src)                    → record (created and loaded on first use; yields)
      NZR.Radio.Public(rec)                    → public record
      NZR.Radio.Push(src)                      send 'nzr:radio:state'
      NZR.Radio.RefreshOwned(src, silent?)     → changed
      NZR.Radio.SetPower(src, on)              → ok, reason ('noradio')
      NZR.Radio.SetModel(src, model)           → ok, reason
      NZR.Radio.Join(src, slot, freq, code?, opts?) → { ok, label, access, slot, freq } | { ok = false, reason }
            opts.force = skip the access rules, opts.offline = store it on a radio that is off
            (exports only; a radio switched on later re-checks every stored channel)
      NZR.Radio.Leave(src, slot)               → { ok }
      NZR.Radio.SetTxSlot(src, slot)           → ok
      NZR.Radio.Kick(src, slot, fkey)          take a channel away (lost access) + notify
      NZR.Radio.Cleanup(src)                   drop the record (logout / disconnect)
      NZR.Radio.SlotCount(model)               → 1..5 (0 for no radio)
      NZR.Radio.FkeysOf(src)                   → { fkey = slot } of a powered radio

    Exports
      getPlayerRadio(src) → public record | nil      setPlayerFrequency(src, slot, freq|false, force?) → ok, reason
      setPower(src, on) → ok, reason                 isTalking(src) → bool
      getChannelMembers(freq) → { src, ... }

    Callbacks (lib.callback through NZR.Callback)
      nzr:radio:init ()                    → { ok, record, owned, labels }
      nzr:radio:join (slot, freq, code?)   → { ok = true, label, access, slot, freq } | { ok = false, reason }
                                             reason ∈ denied, code, badcode, locked, invalid, busy
                                             (busy + slot = that channel is already on another slot)
      nzr:radio:leave (slot)               → { ok }
      nzr:radio:preset (index, freq|false) → { ok, presets } | { ok = false, reason = 'invalid' }
      nzr:radio:callsign (text|false)      → { ok, callsign } | { ok = false, reason = 'disabled' }

    Events handled (C→S)
      nzr:radio:power (on)   nzr:radio:model (model)   nzr:radio:txslot (slot)   nzr:radio:mute (muted)
      nzr:radio:handsfree (on)   nzr:radio:earpiece (on)   nzr:radio:underwater (under)

    Events sent (S→C)
      nzr:radio:state (record)    after every change the server makes
      nzr:radio:use (model)       a radio item was used: make it active and raise it
      nzr:radio:dropped ()        the last radio item is gone
      nzr:jammer:begin (type)     through NZR.Jammers.Begin when a jammer item is used

    Bus (emitted)
      radio:power (src, on)  radio:joined (src, fkey, slot)  radio:left (src, fkey, slot)
      radio:txslot (src)     radio:callsign (src)            radio:changed (src)   mute / earpiece /
                                                             underwater / model: who hears what may differ
    Bus (listens): player:job (src, job), player:unloaded (src), player:dropped (src)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Radio = NZR.Radio or {}
local R = NZR.Radio
local Core = NZR.Core

R.players = R.players or {}
R.members = R.members or {}

local MODELS = { 'handheld', 'fieldpro', 'military' }
local MODEL_SET = { handheld = true, fieldpro = true, military = true }
local MAX_SLOTS = 5

local function L(key, ...) return NZR.L('server.' .. key, ...) end

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function modelCfg(m)
    local models = Config.Radios and Config.Radios.Models
    return models and models[m] or nil
end

function R.SlotCount(m)
    local c = m and modelCfg(m)
    if not c then return 0 end
    return NZR.Util.Clamp(math.floor(tonumber(c.slots) or 3), 1, MAX_SLOTS)
end
local slotCount = R.SlotCount

local function presetCount()
    return NZR.Util.Clamp(math.floor(tonumber(Config.Radios and Config.Radios.presets) or 6), 0, 20)
end

local function copyTable(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function fail(reason) return { ok = false, reason = reason } end

local function jobSummary(src)
    local job = Core.B('GetJob', src)
    if type(job) ~= 'table' then return { name = 'unemployed', grade = 0, onDuty = false } end
    return { name = job.name, grade = tonumber(job.grade) or 0, onDuty = job.onDuty == true }
end

local function emptyPresets()
    local out = {}
    for i = 1, presetCount() do out[i] = false end
    return out
end

local function anyOwned(owned)
    for _, m in ipairs(MODELS) do
        if owned[m] then return true end
    end
    return false
end

local function itemCount(src, key)
    local name = Config.Items and Config.Items[key]
    if type(name) ~= 'string' or name == '' then return 0 end
    return tonumber(Core.B('Inv.Count', src, name)) or 0
end

-- ════════════════════════════════════════════════════════════════════════
-- RECORDS
-- ════════════════════════════════════════════════════════════════════════

local function newRecord(src)
    local s = NZR.Channels.TakeSession(src)
    return {
        src = src, identifier = nil, name = Core.Name(src), callsign = nil, job = jobSummary(src),
        model = nil, owned = {}, earpieceOwned = false,
        power = false, slots = {}, txSlot = 1,
        muted = false, earpiece = false, handsfree = false, underwater = false,
        unlocked = s and s.unlocked or {}, presets = emptyPresets(),
        codeFails = s and s.codeFails or {},
        tx = nil,
    }
end

-- Presets and callsign are saved per character, so they wait for an identifier: before the
-- framework has loaded the character the record runs on defaults and picks them up later.
local function loadPersisted(rec)
    local identifier = Core.Identifier(rec.src)
    if not identifier then return end
    rec.loading = true
    local data = NZR.DB.LoadPlayer(identifier)
    rec.loading = nil
    if R.players[rec.src] ~= rec then return end
    rec.identifier = identifier
    rec.name = Core.Name(rec.src)
    if type(data.presets) == 'table' then
        local presets = emptyPresets()
        for i = 1, #presets do presets[i] = data.presets[i] or false end
        rec.presets = presets
    end
    if type(data.callsign) == 'string' and Config.Radios.callsign then rec.callsign = data.callsign end
end

local function persist(rec)
    if not rec.identifier then return end
    NZR.DB.SavePlayer(rec.identifier, { presets = rec.presets, callsign = rec.callsign })
end

function R.Get(src)
    return R.players[tonumber(src) or -1]
end

function R.Ensure(src)
    src = tonumber(src)
    if not src or not Core.Online(src) then return nil end
    local rec = R.players[src]
    if rec then
        -- another call is still reading this player from the database: wait for it
        local t = GetGameTimer()
        while rec.loading and GetGameTimer() - t < 5000 do Wait(25) end
        rec = R.players[src]
        if rec and not rec.identifier and not rec.loading then loadPersisted(rec) end
        return rec
    end
    rec = newRecord(src)
    R.players[src] = rec
    loadPersisted(rec)
    if R.players[src] ~= rec then return R.players[src] end
    R.RefreshOwned(src, true)
    return rec
end

function R.Public(rec)
    local count = slotCount(rec.model)
    local slots = {}
    for i = 1, count do slots[i] = rec.slots[i] end
    local tx = nil
    if rec.tx then
        tx = { fkey = rec.tx.fkey, slot = rec.tx.slot, device = rec.tx.device, emergency = rec.tx.emergency == true }
    end
    -- false, not nil: a missing key would leave the client showing a callsign that was
    -- cleared (another character on the same player id, an export clearing it)
    return {
        src = rec.src, name = rec.name, callsign = rec.callsign or false,
        model = rec.model, owned = copyTable(rec.owned), earpieceOwned = rec.earpieceOwned == true,
        power = rec.power == true, slots = slots, slotCount = count, txSlot = rec.txSlot,
        muted = rec.muted == true, earpiece = rec.earpiece == true, handsfree = rec.handsfree == true,
        underwater = rec.underwater == true,
        presets = copyTable(rec.presets), presetCount = #rec.presets,
        unlocked = copyTable(rec.unlocked), tx = tx,
    }
end

function R.Push(src)
    local rec = R.players[src]
    if not rec then return end
    TriggerClientEvent('nzr:radio:state', src, R.Public(rec))
end

function R.FkeysOf(src)
    local rec = R.players[src]
    local out = {}
    if not rec or not rec.power then return out end
    for slot, f in pairs(rec.slots) do
        local fkey = NZR.Freq.Key(f)
        if fkey then out[fkey] = slot end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- MEMBERSHIP (who is tuned where)
-- ════════════════════════════════════════════════════════════════════════

local function addMember(rec, fkey, slot)
    local m = R.members[fkey]
    if not m then
        m = {}
        R.members[fkey] = m
    end
    m[rec.src] = slot
    NZR.Bus.Emit('radio:joined', rec.src, fkey, slot)
end

local function removeMember(rec, fkey, slot)
    local m = R.members[fkey]
    if not m or m[rec.src] == nil then return end
    m[rec.src] = nil
    if next(m) == nil then R.members[fkey] = nil end
    NZR.Bus.Emit('radio:left', rec.src, fkey, slot)
end

local function stopHandheldTx(rec, slot)
    local tx = rec.tx
    if tx and tx.device == 'handheld' and (slot == nil or tx.slot == slot) then
        NZR.Routing.Stop(rec.src, 'radio')
    end
end

local function leaveSlot(rec, slot)
    local f = rec.slots[slot]
    if not f then return false end
    stopHandheldTx(rec, slot)
    rec.slots[slot] = nil
    local fkey = NZR.Freq.Key(f)
    if rec.power and fkey then removeMember(rec, fkey, slot) end
    return true
end

-- Hands-free is an open mic on the TX slot: when that slot changes it follows to the new
-- channel instead of silently going quiet.
local function resumeHandsfree(rec, wasOn)
    if not wasOn or rec.tx then return end
    if not rec.power or not rec.slots[rec.txSlot] then
        rec.handsfree = false
        return
    end
    local ok = NZR.Routing.Start(rec.src, 'handheld', { handsfree = true })
    rec.handsfree = ok == true
end

-- The slots stay in the record: switching the radio back on rejoins them.
local function powerOff(rec)
    stopHandheldTx(rec)
    rec.handsfree = false
    for slot, f in pairs(rec.slots) do
        local fkey = NZR.Freq.Key(f)
        if fkey then removeMember(rec, fkey, slot) end
    end
    rec.power = false
end

-- ════════════════════════════════════════════════════════════════════════
-- MODEL & ITEMS
-- ════════════════════════════════════════════════════════════════════════

local function pickModel(rec)
    for _, m in ipairs((Config.Radios and Config.Radios.Priority) or MODELS) do
        if rec.owned[m] then return m end
    end
    for _, m in ipairs(MODELS) do
        if rec.owned[m] then return m end
    end
    return nil
end

-- A smaller radio has fewer slots: the channels that do not fit are left.
local function applyModel(rec, m)
    if rec.model == m then return false end
    rec.model = m
    local count = slotCount(m)
    for slot in pairs(rec.slots) do
        if slot > count then leaveSlot(rec, slot) end
    end
    if count > 0 and (rec.txSlot < 1 or rec.txSlot > count) then
        stopHandheldTx(rec)
        rec.txSlot = 1
    end
    NZR.Bus.Emit('radio:changed', rec.src)
    return true
end

function R.RefreshOwned(src, silent)
    local rec = R.players[src]
    if not rec then return false end
    local changed = false
    local hadAny = anyOwned(rec.owned)

    for _, m in ipairs(MODELS) do
        local own = itemCount(src, m) > 0
        if (rec.owned[m] == true) ~= own then changed = true end
        rec.owned[m] = own or nil
    end

    local ear = itemCount(src, 'earpiece') > 0
    if ear ~= rec.earpieceOwned then
        rec.earpieceOwned = ear
        changed = true
    end
    if not ear and rec.earpiece then
        rec.earpiece = false
        NZR.Bus.Emit('radio:changed', src)
        changed = true
    end

    if not rec.model or not rec.owned[rec.model] then
        if applyModel(rec, pickModel(rec)) then changed = true end
    end

    if not rec.model then
        if rec.power then
            powerOff(rec)
            NZR.Bus.Emit('radio:power', src, false)
            changed = true
        end
        if hadAny then TriggerClientEvent('nzr:radio:dropped', src) end
    end

    if changed and not silent then R.Push(src) end
    return changed
end

function R.SetModel(src, model)
    local rec = R.Ensure(src)
    if not rec then return false, 'noradio' end
    if not MODEL_SET[model] then return false, 'invalid' end
    R.RefreshOwned(src, true)
    if not rec.owned[model] then
        R.Push(src)
        return false, 'noradio'
    end
    applyModel(rec, model)
    R.Push(src)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- POWER
-- ════════════════════════════════════════════════════════════════════════

function R.SetPower(src, on)
    local rec = R.Ensure(src)
    if not rec then return false, 'noradio' end
    on = on == true
    if on then
        R.RefreshOwned(src, true)
        if not rec.model then
            R.Push(src)
            return false, 'noradio'
        end
        if rec.power then
            R.Push(src)
            return true
        end
        rec.power = true
        -- stored channels come back, each re-checked (a job may have changed while it was off)
        local count = slotCount(rec.model)
        for slot = 1, MAX_SLOTS do
            local f = rec.slots[slot]
            if f then
                local fkey = NZR.Freq.Key(f)
                if slot <= count and fkey and NZR.Channels.Allowed(src, fkey) then
                    addMember(rec, fkey, slot)
                else
                    rec.slots[slot] = nil
                end
            end
        end
    else
        if not rec.power then
            R.Push(src)
            return true
        end
        powerOff(rec)
    end
    NZR.Bus.Emit('radio:power', src, on)
    R.Push(src)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- CHANNELS
-- ════════════════════════════════════════════════════════════════════════

function R.Join(src, slot, freq, code, opts)
    opts = opts or {}
    local rec = R.Ensure(src)
    if not rec or not rec.model then return fail('denied') end
    if not rec.power and not opts.offline then return fail('denied') end

    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > slotCount(rec.model) then return fail('invalid') end
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return fail('invalid') end
    local fkey = NZR.Freq.Key(f)

    local current = rec.slots[slot]
    if current and NZR.Freq.Key(current) == fkey then
        local label, access = NZR.Channels.Label(fkey)
        return { ok = true, label = label, access = access, slot = slot, freq = fkey }
    end
    -- one frequency per radio: a second slot on the same channel would only double the audio
    for other, of in pairs(rec.slots) do
        if other ~= slot and NZR.Freq.Key(of) == fkey then return { ok = false, reason = 'busy', slot = other } end
    end

    if not opts.force then
        local ok, reason = NZR.Channels.Check(src, fkey, code)
        if not ok then return fail(reason or 'denied') end
    end

    local wasHandsfree = rec.handsfree and slot == rec.txSlot
    leaveSlot(rec, slot)
    rec.slots[slot] = f
    if rec.power then addMember(rec, fkey, slot) end
    if slot == rec.txSlot then resumeHandsfree(rec, wasHandsfree) end
    R.Push(src)

    local label, access = NZR.Channels.Label(fkey)
    return { ok = true, label = label, access = access, slot = slot, freq = fkey }
end

function R.Leave(src, slot)
    local rec = R.Ensure(src)
    if not rec then return { ok = false } end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > MAX_SLOTS then return { ok = false } end
    if slot == rec.txSlot and rec.handsfree then rec.handsfree = false end
    leaveSlot(rec, slot)
    R.Push(src)
    return { ok = true }
end

function R.SetTxSlot(src, slot)
    local rec = R.Ensure(src)
    if not rec or not rec.model then return false end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > slotCount(rec.model) then return false end
    if slot ~= rec.txSlot then
        local wasHandsfree = rec.handsfree
        stopHandheldTx(rec)
        rec.txSlot = slot
        resumeHandsfree(rec, wasHandsfree)
        NZR.Bus.Emit('radio:txslot', src)
    end
    R.Push(src)
    return true
end

function R.Kick(src, slot, fkey)
    local rec = R.players[src]
    if not rec or not rec.slots[slot] then return end
    if slot == rec.txSlot then rec.handsfree = false end
    leaveSlot(rec, slot)
    R.Push(src)
    Core.Notify(src, L('kicked', fkey or '?', slot), 'warning')
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

function R.Cleanup(src)
    local rec = R.players[src]
    if not rec then return end
    NZR.Routing.Stop(src, 'drop')
    if rec.power then powerOff(rec) end
    R.players[src] = nil
end

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS
-- ════════════════════════════════════════════════════════════════════════

local function useRadio(src, model)
    local rec = R.Ensure(src)
    if not rec then return end
    R.RefreshOwned(src, true)
    if not rec.owned[model] then
        R.Push(src)
        return
    end
    applyModel(rec, model)
    R.Push(src)
    TriggerClientEvent('nzr:radio:use', src, model)
end

local function useEarpiece(src)
    local rec = R.Ensure(src)
    if not rec then return end
    R.RefreshOwned(src, true)
    if not rec.earpieceOwned then
        R.Push(src)
        return
    end
    rec.earpiece = not rec.earpiece
    NZR.Bus.Emit('radio:changed', src)
    R.Push(src)
    Core.Notify(src, L(rec.earpiece and 'earpiece_in' or 'earpiece_out'), 'info')
end

local function registerUsables()
    local items = Config.Items or {}
    for _, m in ipairs(MODELS) do
        if type(items[m]) == 'string' and items[m] ~= '' then
            Core.B('Inv.RegisterUsable', items[m], function(src) useRadio(src, m) end)
        end
    end
    if type(items.earpiece) == 'string' and items.earpiece ~= '' then
        Core.B('Inv.RegisterUsable', items.earpiece, function(src) useEarpiece(src) end)
    end
    for key in pairs((Config.Jammers and Config.Jammers.Types) or {}) do
        if type(items[key]) == 'string' and items[key] ~= '' then
            Core.B('Inv.RegisterUsable', items[key], function(src) NZR.Jammers.Begin(src, key) end)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

NZR.Callback('nzr:radio:init', function(src)
    if not Core.Rate('nzr:radio:init', src, 6, 5000) then return { ok = false, reason = 'busy' } end
    local rec = R.Ensure(src)
    if not rec then return { ok = false, reason = 'error' } end
    R.RefreshOwned(src, true)
    return { ok = true, record = R.Public(rec), owned = copyTable(rec.owned), labels = NZR.Channels.Labels() }
end)

NZR.Callback('nzr:radio:join', function(src, slot, freq, code)
    if not Core.Rate('nzr:radio:join', src, 8, 2000) then return fail('busy') end
    if code ~= nil and type(code) ~= 'string' and type(code) ~= 'number' then code = nil end
    return R.Join(src, slot, freq, code)
end)

NZR.Callback('nzr:radio:leave', function(src, slot)
    if not Core.Rate('nzr:radio:leave', src, 8, 2000) then return { ok = false } end
    return R.Leave(src, slot)
end)

NZR.Callback('nzr:radio:preset', function(src, index, freq)
    if not Core.Rate('nzr:radio:preset', src, 10, 2000) then return fail('busy') end
    local rec = R.Ensure(src)
    if not rec then return fail('invalid') end
    index = math.floor(tonumber(index) or 0)
    if index < 1 or index > #rec.presets then return fail('invalid') end
    local value = false
    if freq ~= false and freq ~= nil then
        local f = NZR.Freq.Parse(freq)
        if not f or not NZR.Freq.Valid(f) then return fail('invalid') end
        value = f
    end
    rec.presets[index] = value
    persist(rec)
    R.Push(src)
    return { ok = true, presets = copyTable(rec.presets) }
end)

-- Letters, digits, space and - / . # only: a callsign is shown in other players' rosters.
local function cleanCallsign(text, max)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[^%w%-%./# ]', ''):gsub('%s+', ' ')
    return Bridge.CleanText(text, max)
end

NZR.Callback('nzr:radio:callsign', function(src, text)
    if not Core.Rate('nzr:radio:callsign', src, 4, 5000) then return fail('busy') end
    local max = Config.Radios and Config.Radios.callsign
    if not max then return fail('disabled') end
    local rec = R.Ensure(src)
    if not rec then return fail('invalid') end
    if text == false or text == nil or text == '' then
        rec.callsign = nil
    else
        local clean = cleanCallsign(text, math.floor(tonumber(max) or 8))
        if not clean then return fail('invalid') end
        rec.callsign = clean
    end
    persist(rec)
    NZR.Bus.Emit('radio:callsign', src)
    R.Push(src)
    return { ok = true, callsign = rec.callsign }
end)

-- ════════════════════════════════════════════════════════════════════════
-- NET EVENTS (C→S)
-- ════════════════════════════════════════════════════════════════════════

-- source check + rate limit + record, shared by every toggle below
local function handler(name, limit, fn)
    RegisterNetEvent(name, function(...)
        local src = source
        if Core.IsLocalSource(src) then return end
        src = tonumber(src)
        if not Core.Rate(name, src, limit, 2000) then return end
        local rec = R.Ensure(src)
        if not rec then return end
        fn(src, rec, ...)
    end)
end

handler('nzr:radio:power', 6, function(src, rec, on)
    local ok, reason = R.SetPower(src, on == true)
    if not ok and reason == 'noradio' then Core.Notify(src, L('no_radio'), 'error') end
end)

handler('nzr:radio:model', 6, function(src, rec, model)
    if type(model) ~= 'string' then return end
    R.SetModel(src, model)
end)

handler('nzr:radio:txslot', 10, function(src, rec, slot)
    R.SetTxSlot(src, slot)
end)

handler('nzr:radio:mute', 10, function(src, rec, muted)
    muted = muted == true
    if rec.muted ~= muted then
        rec.muted = muted
        NZR.Bus.Emit('radio:changed', src)
    end
    R.Push(src)
end)

handler('nzr:radio:handsfree', 6, function(src, rec, on)
    on = on == true
    if on then
        if not rec.power or not rec.slots[rec.txSlot] then
            rec.handsfree = false
            TriggerClientEvent('nzr:tx:denied', src, 'nofreq')
        else
            rec.handsfree = true
            local ok = NZR.Routing.Start(src, 'handheld', { handsfree = true })
            if not ok then rec.handsfree = false end
        end
    else
        rec.handsfree = false
        NZR.Routing.Release(src, 'handsfree')
    end
    R.Push(src)
end)

handler('nzr:radio:earpiece', 6, function(src, rec, on)
    on = on == true
    if on then
        R.RefreshOwned(src, true)
        if not rec.earpieceOwned then on = false end
    end
    if rec.earpiece ~= on then
        rec.earpiece = on
        NZR.Bus.Emit('radio:changed', src)
    end
    R.Push(src)
end)

handler('nzr:radio:underwater', 10, function(src, rec, under)
    under = under == true
    if rec.underwater ~= under then
        rec.underwater = under
        NZR.Bus.Emit('radio:changed', src)
        R.Push(src)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('getPlayerRadio', function(src)
    local rec = R.players[tonumber(src) or -1]
    return rec and R.Public(rec) or nil
end)

exports('setPlayerFrequency', function(src, slot, freq, force)
    src = tonumber(src)
    local rec = src and R.Ensure(src)
    if not rec then return false, 'offline' end
    if not rec.model then return false, 'noradio' end
    slot = tonumber(slot) or rec.txSlot
    if freq == false or freq == nil then
        local res = R.Leave(src, slot)
        return res.ok == true, res.ok and nil or 'invalid'
    end
    local res = R.Join(src, slot, freq, nil, { force = force == true, offline = true })
    if not res.ok then return false, res.reason end
    return true
end)

exports('setPower', function(src, on)
    return R.SetPower(tonumber(src), on == true)
end)

exports('isTalking', function(src)
    return NZR.Routing.IsTalking(tonumber(src))
end)

exports('getChannelMembers', function(freq)
    local fkey = NZR.Freq.Key(freq)
    local out = {}
    for src in pairs((fkey and R.members[fkey]) or {}) do out[#out + 1] = src end
    table.sort(out)
    return out
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

-- A character (re)loaded: a different character on the same player id starts from scratch,
-- the same one picks up its presets if the record was made before the framework knew it.
local function onLoaded(src)
    src = tonumber(src)
    if not src then return end
    CreateThread(function()
        local rec = R.players[src]
        local identifier = Core.Identifier(src)
        if rec and rec.identifier and identifier and rec.identifier ~= identifier then
            R.Cleanup(src)
            rec = nil
        end
        rec = R.Ensure(src)
        if not rec then return end
        rec.name = Core.Name(src)
        rec.job = jobSummary(src)
        R.RefreshOwned(src, true)
        R.Push(src)
    end)
end

NZR.Bus.On('player:job', function(src, job)
    local rec = R.players[src]
    if rec then rec.job = jobSummary(src) end
end)

NZR.Bus.On('player:unloaded', function(src)
    R.Cleanup(src)
end)

NZR.Bus.On('player:dropped', function(src)
    R.Cleanup(src)
end)

CreateThread(function()
    Wait(0)
    Core.B('OnPlayerLoaded', onLoaded, true)
    Core.B('Inv.OnChanged', function(src, name)
        if not R.players[src] then return end
        if name ~= nil and not Bridge.ItemKey(name) then return end
        SetTimeout(0, function() R.RefreshOwned(src) end)
    end)
    Wait(1000)   -- the inventory bridge picks its adapter shortly after start
    registerUsables()
end)

-- Items can leave an inventory without the bridge hearing of it (most inventories do not
-- announce moves), so powered radios check their item on a timer.
CreateThread(function()
    while true do
        Wait(5000)
        local ids = {}
        for src, rec in pairs(R.players) do
            if rec.power then ids[#ids + 1] = src end
        end
        for _, src in ipairs(ids) do
            if not Core.Online(src) then
                R.Cleanup(src)
            else
                R.RefreshOwned(src)
            end
        end
    end
end)
