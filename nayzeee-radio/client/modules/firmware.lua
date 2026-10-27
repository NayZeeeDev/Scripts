--[[
    NAYZEEE RADIO - Firmware (client): what every radio does when a key is pressed

    Lua owns every decision. The screens (the DUI on a handheld, the MV-90 head unit app)
    only draw the state this file renders. One firmware object per device; it keeps the
    UI-only state (view, typed digits, cursor, notices, volume popup, hold timers) and
    reads everything else from its device through `source()`. Changes go out through
    `actions`, so the same code drives a handheld (wired to NZR.Radio.State / API below)
    and the vehicle head unit (client-world builds its own source + actions).

    ── API ───────────────────────────────────────────────────────────────
      NZR.Firmware.New(device, opts) → fw
          device   'handheld' | 'vehicle'
          opts = {
            model     = 'handheld'|'fieldpro'|'military'|'vehicle'   nil = read source().model
            skin      = 'px740'|'fx280'|'mx905'|'mv90'                default from model
            render    = function(state)    sink, called with the screen state (below) when it changed
            source    = function() → DEVICE STATE (below), read on every press / render
            actions   = ACTIONS (below); a missing action hides its menu entry / makes its key an error
            powerHold = 1200    ms to hold 'power' (0 = a tap toggles, e.g. the head unit PWR key)
            knobPower = true    the volume knob switches the set: up from off = on, held below 0 for 1 s = off
            emergencyHold = Config.Emergency.holdTime   ms to hold 'emerg' (0 = tap)
            listViews = true    memories / slots / menu views exist (false: a single-line device)
            sfx       = function(name)     default NZR.UI.Send('_core', 'sfx', { name = name })
            now       = function() → ms    default GetGameTimer
            clock     = function() → '14:32'   default the game clock
            manual    = false   no internal ticker thread (tests call fw:Tick(now))
            sync      = false   run server round trips inline instead of in a thread (tests)
          }
      fw:Press(action, value, down, step)  an edge from a key / part (down = true | false)
            action  §6 vocabulary: digit (value '0'..'9'), star, hash, ok, back, menu, up, down,
                    left, right, dpad (value = 'up'|'down'|'left'|'right' resolved by the caller),
                    p1, p2, power, emerg, ptt, side1, side2, knob (value 'channel'|'volume',
                    step = -1 | +1), mute, pre
      fw:Repeat(action, value, step)       auto-repeat while held (interact.lua drives the timing)
      fw:Tick(now?)                        timers (holds, boot, notices, debounced memory)
      fw:Render() → state                  fw:Refresh(force)  render + call opts.render if changed
      fw:SetActive(on)                     a ticker runs (50-250 ms) only while the screen is seen
      fw:Notice(text, ms?)                 transient line on the screen (default 1.5 s)
      fw:View() → name                     fw:Reset()   back to home / off, buffers cleared
      NZR.Firmware.Handheld() → fw         the handheld instance wired to NZR.Radio.State / API,
                                           rendering into NZR.Screen.Push(model, state)
      NZR.Firmware.ModelCode(model) → 'PX-740'    NZR.Firmware.Skin(model) → 'px740'

    ── DEVICE STATE (source()) ───────────────────────────────────────────
      { power, model, slots = { [i] = 155.5 }, slotCount, txSlot, volume = 0..100, muted,
        handsfree, clicks, earpiece, earpieceOwned, presets = { [i] = 155.5 | false },
        presetCount, callsign, labels = { [fkey] = { label, access } }, tx = bool,
        rx = { [talker] = { name, callsign, q, fkey, slot, mode, emergency, at } },
        rosterOn, jam = 0..1, underwater, waterproof, battery = 0..1, emergency = bool }
      Missing fields read as off / empty. labels: the channel label tag (code channels show
      access = 'code' → the LOCK indicator); Config.Channels.Restricted ranges are added here.

    ── ACTIONS ───────────────────────────────────────────────────────────
      join(slot, freq, code?) → { ok, label, access } | { ok = false, reason }   (may yield)
          reason ∈ denied, code, badcode, locked, invalid, busy, error, power
      leave(slot) → { ok }  (may yield)          setTx(slot)        power(on)
      volume(delta)                              mute(on)           handsfree(on)
      clicks(on)    earpiece(on)                 memories(index, freq | false) → { ok, presets } (may yield)
      emergency() → ok, reason                   toggleRoster()     ptt(down)

    ── SCREEN STATE (render(state), SPEC §10.3 + extras) ─────────────────
      { view = 'off'|'boot'|'home'|'tune'|'code'|'memories'|'slots'|'menu'|'emergency',
        skin, model = 'PX-740', freq = '155.50'|nil, label, access = 'open'|'code'|'job'|nil,
        slot, slots = { { n, f, tx, rx, label, access } }, sel (slots view cursor, 1-based),
        tx, rx = { name, callsign, q, slot, emergency } | nil, bars = 0..4, nosignal, jam,
        volume, showVolume, mute, handsfree, clicks, earpiece, battery, time = '14:32',
        entry = '15', code = '**', target = '155.50' (code view: the channel being unlocked),
        memories = { index (1-based), count, f, label }, mem = index of the memory matching
        the TX frequency | nil,
        menu = { items = { { id, label, value } }, index (0-based) },
        title (heading of the view, our wording), hint (key help line), notice, busy, emergency }
      Every string on it comes from locales/en/client.lua (client.scr_*), Rule A.

    ── EVENTS / BUS ──────────────────────────────────────────────────────
      NUI sent:  '_core' sfx { name = 'key' | 'error' | 'boot' | 'power_off' }
      Bus handled (handheld instance): 'radio:changed' (re-render while seen),
                                       'radio:notice' (key, device) → client.scr_<key> notice
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Firmware = NZR.Firmware or {}
local FW = NZR.Firmware

local MODEL_CODE = { handheld = 'PX-740', fieldpro = 'FX-280', military = 'MX-905', vehicle = 'MV-90' }
local MODEL_SKIN = { handheld = 'px740', fieldpro = 'fx280', military = 'mx905', vehicle = 'mv90' }

local BOOT_MS = 1500
local NOTICE_MS = 1500
local VOLUME_POPUP_MS = 1200
local KNOB_OFF_MS = 1000
local POWER_WANT_MS = 2500       -- how long an asked-for power state wins over a source that has not caught up
local MEMORY_DEBOUNCE_MS = 350   -- the channel knob tunes once it stops turning
local VOLUME_STEP = 5
local CODE_LEN = 4
local TICK_BUSY_MS = 50
local TICK_IDLE_MS = 250

local LIST_VIEWS = { memories = true, slots = true, menu = true }

local function L(key, ...) return NZR.L('client.' .. key, ...) end

function FW.ModelCode(model) return MODEL_CODE[model] or MODEL_CODE.handheld end
function FW.Skin(model) return MODEL_SKIN[model] or MODEL_SKIN.handheld end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function fkeyOf(f)
    if not f then return nil end
    return NZR.Freq.Key(f)
end

local function round2(n)
    return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100
end

local function tiers()
    return (Config.Signal and Config.Signal.tiers) or { clear = 0.75, weak = 0.45, poor = 0.15 }
end

local function bars(q)
    if NZR.Signal and NZR.Signal.Bars then
        local ok, b = pcall(NZR.Signal.Bars, q)
        if ok and tonumber(b) then return math.floor(tonumber(b)) end
    end
    local t = tiers()
    if q >= t.clear then return 4 elseif q >= t.weak then return 3 elseif q >= t.poor then return 2 elseif q > 0.02 then return 1 end
    return 0
end

-- Restricted ranges in the shared config have labels too; the server only publishes
-- per-frequency entries, so ranges are looked up here.
local function rangeInfo(f)
    local list = Config.Channels and Config.Channels.Restricted
    if not f or type(list) ~= 'table' then return nil end
    for i = 1, #list do
        local r = list[i]
        if r.from and r.to and f >= r.from and f <= r.to then
            return { label = r.label, access = 'job' }
        end
    end
    return nil
end

local function channelInfo(s, fkey)
    if not fkey then return nil end
    local e = type(s.labels) == 'table' and s.labels[fkey] or nil
    if type(e) == 'table' then return e end
    return rangeInfo(NZR.Freq.Parse(fkey))
end

-- Keypad entry for a frequency: digits, one point (star), two decimals, three integer
-- digits at most (a fourth digit puts the point in for you: 1555 → 155.5).
local function typeChar(entry, ch)
    if ch == '.' then
        if entry:find('.', 1, true) then return nil end
        if entry == '' then return '0.' end
        return entry .. '.'
    end
    local dot = entry:find('.', 1, true)
    if dot then
        if #entry - dot >= 2 then return nil end
        return entry .. ch
    end
    if #entry >= 3 then return entry .. '.' .. ch end
    return entry .. ch
end

local function clockString()
    local ok, h, m = pcall(function() return GetClockHours(), GetClockMinutes() end)
    if not ok or not h then return '00:00' end
    return ('%02d:%02d'):format(h, m)
end

-- ════════════════════════════════════════════════════════════════════════
-- OBJECT
-- ════════════════════════════════════════════════════════════════════════

local proto = {}
proto.__index = proto

function FW.New(device, opts)
    opts = opts or {}
    local emergencyHold = opts.emergencyHold
    if emergencyHold == nil then emergencyHold = (Config.Emergency and Config.Emergency.holdTime) or 1500 end
    local self = setmetatable({
        device = device or 'handheld',
        opts = opts,
        actions = opts.actions or {},
        powerHold = tonumber(opts.powerHold) or 1200,
        emergHold = tonumber(emergencyHold) or 1500,
        knobPower = opts.knobPower ~= false,
        listViews = opts.listViews ~= false,
        view = 'off',
        entry = '',
        code = '',
        pending = nil,        -- { slot, freq, back } waiting for an access code
        memIndex = 1,
        slotSel = 1,
        menuIndex = 1,
        menuId = nil,
        notice = nil, noticeUntil = 0,
        volumeUntil = 0,
        bootUntil = 0,
        emergencyUntil = 0,
        lastPower = nil,
        powerWant = nil,
        holds = {},           -- [action] = { at, done }
        knobOffAt = nil,
        pendingMem = nil,     -- { index, at }
        memCursor = nil,
        busy = false,
        active = false,
        lastSig = nil,
        ticking = false,
    }, proto)
    return self
end

function proto:Now()
    if self.opts.now then return self.opts.now() end
    return GetGameTimer()
end

function proto:Source()
    local fn = self.opts.source
    if not fn then return {} end
    local ok, s = pcall(fn)
    if not ok then
        NZR.Debug('firmware source failed', tostring(s))
        return {}
    end
    return type(s) == 'table' and s or {}
end

function proto:Sfx(name)
    if self.opts.sfx then return self.opts.sfx(name) end
    if NZR.UI and NZR.UI.Send then NZR.UI.Send('_core', 'sfx', { name = name }) end
end

function proto:Spawn(fn)
    if self.opts.sync then return fn() end
    CreateThread(fn)
end

function proto:Act(name, ...)
    local fn = self.actions[name]
    if not fn then return nil, 'missing' end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        NZR.Warn(('firmware action "%s" failed: %s'):format(name, tostring(a)))
        return nil, 'error'
    end
    return a, b
end

function proto:Has(name)
    return self.actions[name] ~= nil
end

function proto:View()
    return self.view
end

function proto:Notice(text, ms)
    if not text or text == '' then return end
    self.notice = text
    self.noticeUntil = self:Now() + (ms or NOTICE_MS)
    if self.active then self:Refresh() end
end

local function slotCount(s)
    return math.max(1, math.min(5, math.floor(tonumber(s.slotCount) or 1)))
end

local function presetCount(s)
    return math.max(0, math.floor(tonumber(s.presetCount) or 0))
end

local function txSlot(s)
    local n = slotCount(s)
    local i = math.floor(tonumber(s.txSlot) or 1)
    if i < 1 or i > n then i = 1 end
    return i
end

-- ════════════════════════════════════════════════════════════════════════
-- POWER / VIEW SYNC
-- ════════════════════════════════════════════════════════════════════════

function proto:EffectivePower(s, now)
    local w = self.powerWant
    if w then
        if (s.power == true) == w.on then
            self.powerWant = nil
        elseif now - w.at < POWER_WANT_MS then
            return w.on
        else
            self.powerWant = nil
        end
    end
    return s.power == true
end

function proto:ClearBuffers()
    self.entry, self.code, self.pending = '', '', nil
    self.holds, self.knobOffAt, self.pendingMem = {}, nil, nil
    self.busy = false
end

function proto:Reset()
    self:ClearBuffers()
    self.notice, self.volumeUntil = nil, 0
    self.view = self.lastPower and 'home' or 'off'
end

-- Brings the view in line with the device: power transitions, finished boot,
-- expired notices / emergency screen. Called before every press and render.
function proto:Sync(s, now)
    local on = self:EffectivePower(s, now)
    if on ~= self.lastPower then
        local was = self.lastPower
        self.lastPower = on
        if on then
            if was == false then
                self:ClearBuffers()
                self.view = 'boot'
                self.bootUntil = now + BOOT_MS
                if self.active then self:Sfx('boot') end
            else
                self.view = 'home'
            end
        else
            self:ClearBuffers()
            self.notice = nil
            self.view = 'off'
            self.emergencyUntil = 0
            if was == true and self.active then self:Sfx('power_off') end
        end
    end
    if on and self.view == 'off' then self.view = 'home' end
    if self.view == 'boot' and now >= self.bootUntil then self.view = 'home' end
    if self.emergencyUntil > 0 and now >= self.emergencyUntil then
        self.emergencyUntil = 0
        if self.view == 'emergency' then self.view = 'home' end
    end
    if self.notice and now >= self.noticeUntil then self.notice = nil end
    if not self.listViews and LIST_VIEWS[self.view] then self.view = 'home' end
    return on
end

function proto:SetPower(on, now)
    if not self:Has('power') then return end
    self.powerWant = { on = on, at = now }
    self:Act('power', on)
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER ROUND TRIPS
-- ════════════════════════════════════════════════════════════════════════

local JOIN_NOTICE = {
    badcode = 'scr_badcode', denied = 'scr_denied', locked = 'scr_locked', invalid = 'scr_invalid',
    busy = 'scr_busy', error = 'scr_error',
}

function proto:DoJoin(slot, freq, code, back)
    if not self:Has('join') then return self:Sfx('error') end
    self.busy = true
    if self.active then self:Refresh() end
    self:Spawn(function()
        local res = self:Act('join', slot, freq, code)
        self.busy = false
        self:OnJoin(type(res) == 'table' and res or { ok = false, reason = 'error' }, slot, freq, code, back)
        if self.active then self:Refresh() end
    end)
end

function proto:OnJoin(res, slot, freq, code, back)
    if res.ok then
        self.entry, self.code, self.pending = '', '', nil
        if self.view ~= 'off' and self.view ~= 'boot' then self.view = back or 'home' end
        return
    end
    local reason = res.reason
    if reason == 'code' then
        self.pending = { slot = slot, freq = freq, back = back }
        self.code = ''
        self.view = 'code'
        return
    end
    if reason == 'power' then return end
    self:Sfx('error')
    self:Notice(L(JOIN_NOTICE[reason] or 'scr_error'))
    if reason == 'badcode' then
        self.code = ''
        self.view = 'code'
    elseif reason == 'invalid' and self.view == 'tune' then
        -- keep what was typed so it can be corrected
        self.view = 'tune'
    else
        self.entry, self.code, self.pending = '', '', nil
        self.view = back or 'home'
    end
end

function proto:DoLeave(slot)
    if not self:Has('leave') then return self:Sfx('error') end
    self.busy = true
    self:Spawn(function()
        local res = self:Act('leave', slot)
        self.busy = false
        if type(res) == 'table' and res.ok then
            self:Notice(L('scr_left', slot))
        else
            self:Sfx('error')
            self:Notice(L('scr_error'))
        end
        if self.active then self:Refresh() end
    end)
end

function proto:DoPreset(index, freq)
    if not self:Has('memories') then return self:Sfx('error') end
    self.busy = true
    self:Spawn(function()
        local res = self:Act('memories', index, freq)
        self.busy = false
        if type(res) == 'table' and res.ok then
            self.entry = ''
            self:Notice(L(freq and 'scr_stored' or 'scr_cleared'))
        else
            self:Sfx('error')
            self:Notice(L('scr_notsaved'))
        end
        if self.active then self:Refresh() end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- SHARED KEY LOGIC
-- ════════════════════════════════════════════════════════════════════════

function proto:ChangeVolume(s, delta, now)
    if not self:Has('volume') then return self:Sfx('error') end
    self:Act('volume', delta)
    self.volumeUntil = now + VOLUME_POPUP_MS
    self:Sfx('key')
end

function proto:Toggle(s, what)
    local map = {
        mute = { action = 'mute', field = 'muted', on = 'scr_muted', off = 'scr_unmuted' },
        handsfree = { action = 'handsfree', field = 'handsfree', on = 'scr_hf_on', off = 'scr_hf_off' },
        clicks = { action = 'clicks', field = 'clicks', on = 'scr_clicks_on', off = 'scr_clicks_off' },
        earpiece = { action = 'earpiece', field = 'earpiece', on = 'scr_ear_in', off = 'scr_ear_out' },
    }
    local m = map[what]
    if not m or not self:Has(m.action) then return self:Sfx('error') end
    if what == 'earpiece' and not s.earpieceOwned then return self:Sfx('error') end
    local nextOn = s[m.field] ~= true
    if what == 'handsfree' and nextOn and not (s.slots and s.slots[txSlot(s)]) then
        self:Sfx('error')
        return self:Notice(L('scr_nofreq'))
    end
    self:Act(m.action, nextOn)
    self:Sfx('key')
    self:Notice(L(nextOn and m.on or m.off))
end

function proto:ToggleRoster(s)
    if not self:Has('toggleRoster') then return self:Sfx('error') end
    self:Act('toggleRoster')
    self:Sfx('key')
    self:Notice(L(s.rosterOn and 'scr_roster_off' or 'scr_roster_on'))
end

function proto:StepTxSlot(s, dir)
    local n = slotCount(s)
    if n <= 1 or not self:Has('setTx') then return self:Sfx('error') end
    local i = (txSlot(s) - 1 + dir) % n + 1
    self:Act('setTx', i)
    self:Sfx('key')
    self:Notice(L('scr_txslot', i))
end

-- Channel knob / PRE: the next stored memory goes on the TX slot. The screen shows it
-- at once; the join waits until the knob stops turning.
function proto:CycleMemory(s, dir, now)
    local count = presetCount(s)
    local list = {}
    for i = 1, count do
        if s.presets and s.presets[i] then list[#list + 1] = i end
    end
    if #list == 0 then
        self:Sfx('error')
        return self:Notice(L('scr_nomem'))
    end
    -- turn from: the memory still waiting to be tuned, else the one on the TX slot now,
    -- else the last one picked (the TX slot was tuned by hand since)
    local txf = fkeyOf(s.slots and s.slots[txSlot(s)])
    local cur = self.pendingMem and self.pendingMem.index or nil
    if not cur and txf then
        for i = 1, count do
            if s.presets[i] and fkeyOf(s.presets[i]) == txf then cur = i break end
        end
    end
    cur = cur or self.memCursor
    local pos = nil
    for k = 1, #list do
        if list[k] == cur then pos = k break end
    end
    if not pos then
        pos = dir > 0 and 1 or #list
    else
        pos = (pos - 1 + dir) % #list + 1
    end
    local index = list[pos]
    self.memCursor = index
    self.pendingMem = { index = index, at = now + MEMORY_DEBOUNCE_MS }
    self:Sfx('key')
    self:Notice(L('scr_mem', index, fkeyOf(s.presets[index]) or ''))
end

function proto:FireEmergency(s, now)
    if not self:Has('emergency') then return self:Sfx('error') end
    local ok, reason = self:Act('emergency')
    if ok then
        local hot = (Config.Emergency and tonumber(Config.Emergency.hotMic)) or 8
        self.emergencyUntil = now + math.max(3, hot) * 1000
        self:ClearBuffers()
        self.view = 'emergency'
    else
        self:Sfx('error')
        self:Notice(L(reason == 'cooldown' and 'scr_cooldown' or reason == 'nofreq' and 'scr_nofreq' or 'scr_denied'))
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- VIEWS
-- ════════════════════════════════════════════════════════════════════════

local function dirStep(action)
    if action == 'up' or action == 'left' then return -1 end
    return 1
end

function proto:PressHome(s, action, value, step, now)
    if action == 'digit' or action == 'star' then
        local e = typeChar('', action == 'star' and '.' or value)
        if not e then return self:Sfx('error') end
        self.entry = e
        self.view = 'tune'
        return self:Sfx('key')
    elseif action == 'ok' or action == 'menu' then
        if not self.listViews then return self:Sfx('error') end
        self.view, self.menuIndex, self.menuId = 'menu', 1, nil
        return self:Sfx('key')
    elseif action == 'back' then
        self.notice = nil
        return self:Sfx('key')
    elseif action == 'up' or action == 'down' then
        return self:StepTxSlot(s, dirStep(action))
    elseif action == 'left' or action == 'right' then
        return self:ChangeVolume(s, action == 'left' and -VOLUME_STEP or VOLUME_STEP, now)
    elseif action == 'knob' and value == 'channel' then
        return self:CycleMemory(s, step or 1, now)
    elseif action == 'pre' then
        return self:CycleMemory(s, 1, now)
    elseif action == 'p1' then
        if not self.listViews or presetCount(s) == 0 then return self:Sfx('error') end
        self.view, self.entry = 'memories', ''
        return self:Sfx('key')
    elseif action == 'hash' then
        local i = txSlot(s)
        if not (s.slots and s.slots[i]) then return self:Sfx('error') end
        self:Sfx('key')
        return self:DoLeave(i)
    end
    return self:Sfx('error')
end

function proto:PressTune(s, action, value, step, now)
    if action == 'digit' or action == 'star' then
        local e = typeChar(self.entry, action == 'star' and '.' or value)
        if not e then return self:Sfx('error') end
        self.entry = e
        return self:Sfx('key')
    elseif action == 'back' then
        self.entry = self.entry:sub(1, -2)
        if self.entry == '' then self.view = 'home' end
        return self:Sfx('key')
    elseif action == 'hash' then
        self.entry, self.view = '', 'home'
        return self:Sfx('key')
    elseif action == 'ok' then
        local f = NZR.Freq.Parse(self.entry)
        if not f or not NZR.Freq.Valid(f) then
            self:Sfx('error')
            return self:Notice(L('scr_invalid'))
        end
        self:Sfx('key')
        return self:DoJoin(txSlot(s), f, nil, 'home')
    elseif action == 'menu' then
        self.entry = ''
        return self:PressHome(s, 'menu', nil, nil, now)
    elseif action == 'left' or action == 'right' then
        return self:ChangeVolume(s, action == 'left' and -VOLUME_STEP or VOLUME_STEP, now)
    end
    return self:Sfx('error')
end

function proto:PressCode(s, action, value, step, now)
    if action == 'digit' then
        if #self.code >= CODE_LEN then return self:Sfx('error') end
        self.code = self.code .. value
        return self:Sfx('key')
    elseif action == 'back' then
        if self.code == '' then
            self.pending, self.view = nil, 'home'
        else
            self.code = self.code:sub(1, -2)
        end
        return self:Sfx('key')
    elseif action == 'hash' then
        self.code, self.pending, self.view = '', nil, 'home'
        return self:Sfx('key')
    elseif action == 'ok' then
        local p = self.pending
        if not p or #self.code ~= CODE_LEN then return self:Sfx('error') end
        self:Sfx('key')
        return self:DoJoin(p.slot, p.freq, self.code, p.back)
    end
    return self:Sfx('error')
end

function proto:PressMemories(s, action, value, step, now)
    local count = presetCount(s)
    if count == 0 then
        self.view = 'home'
        return self:Sfx('error')
    end
    if self.memIndex < 1 or self.memIndex > count then self.memIndex = 1 end
    local stored = s.presets and s.presets[self.memIndex] or nil
    if action == 'up' or action == 'down' or action == 'left' or action == 'right' or (action == 'knob' and value == 'channel') then
        local dir = action == 'knob' and (step or 1) or dirStep(action)
        self.memIndex = (self.memIndex - 1 + dir) % count + 1
        self.entry = ''
        return self:Sfx('key')
    elseif action == 'digit' or action == 'star' then
        local e = typeChar(self.entry, action == 'star' and '.' or value)
        if not e then return self:Sfx('error') end
        self.entry = e
        return self:Sfx('key')
    elseif action == 'ok' then
        if self.entry ~= '' then
            local f = NZR.Freq.Parse(self.entry)
            if not f or not NZR.Freq.Valid(f) then
                self:Sfx('error')
                return self:Notice(L('scr_invalid'))
            end
            self:Sfx('key')
            return self:DoPreset(self.memIndex, f)
        end
        if not stored then return self:Sfx('error') end
        self:Sfx('key')
        self.memCursor = self.memIndex
        return self:DoJoin(txSlot(s), stored, nil, 'home')
    elseif action == 'hash' then
        if self.entry ~= '' then
            self.entry = ''
            return self:Sfx('key')
        end
        if not stored then return self:Sfx('error') end
        self:Sfx('key')
        return self:DoPreset(self.memIndex, false)
    elseif action == 'back' then
        if self.entry ~= '' then
            self.entry = self.entry:sub(1, -2)
        else
            self.view = 'home'
        end
        return self:Sfx('key')
    elseif action == 'p1' or action == 'menu' then
        self.entry, self.view = '', 'home'
        return self:Sfx('key')
    end
    return self:Sfx('error')
end

function proto:PressSlots(s, action, value, step, now)
    local n = slotCount(s)
    if self.slotSel < 1 or self.slotSel > n then self.slotSel = txSlot(s) end
    local has = s.slots and s.slots[self.slotSel]
    if action == 'up' or action == 'down' or (action == 'knob' and value == 'channel') then
        local dir = action == 'knob' and (step or 1) or dirStep(action)
        self.slotSel = (self.slotSel - 1 + dir) % n + 1
        self.entry = ''
        return self:Sfx('key')
    elseif action == 'digit' or action == 'star' then
        local e = typeChar(self.entry, action == 'star' and '.' or value)
        if not e then return self:Sfx('error') end
        self.entry = e
        return self:Sfx('key')
    elseif action == 'ok' then
        if self.entry ~= '' then
            local f = NZR.Freq.Parse(self.entry)
            if not f or not NZR.Freq.Valid(f) then
                self:Sfx('error')
                return self:Notice(L('scr_invalid'))
            end
            self:Sfx('key')
            return self:DoJoin(self.slotSel, f, nil, 'slots')
        end
        if not self:Has('setTx') then return self:Sfx('error') end
        self:Act('setTx', self.slotSel)
        self:Sfx('key')
        return self:Notice(L('scr_txslot', self.slotSel))
    elseif action == 'hash' then
        if self.entry ~= '' then
            self.entry = ''
            return self:Sfx('key')
        end
        if not has then return self:Sfx('error') end
        self:Sfx('key')
        return self:DoLeave(self.slotSel)
    elseif action == 'back' then
        if self.entry ~= '' then
            self.entry = self.entry:sub(1, -2)
        else
            self.view = 'home'
        end
        return self:Sfx('key')
    elseif action == 'menu' then
        self.entry, self.view = '', 'home'
        return self:Sfx('key')
    elseif action == 'left' or action == 'right' then
        return self:ChangeVolume(s, action == 'left' and -VOLUME_STEP or VOLUME_STEP, now)
    end
    return self:Sfx('error')
end

function proto:MenuItems(s)
    local items = {}
    local function onOff(v) return L(v and 'scr_on' or 'scr_off') end
    if self:Has('memories') and presetCount(s) > 0 then
        items[#items + 1] = { id = 'memories', label = L('scr_menu_memories') }
    end
    if slotCount(s) > 1 then
        items[#items + 1] = { id = 'slots', label = L('scr_menu_slots') }
    end
    if self:Has('mute') then items[#items + 1] = { id = 'mute', label = L('scr_menu_mute'), value = onOff(s.muted) } end
    if self:Has('handsfree') then items[#items + 1] = { id = 'handsfree', label = L('scr_menu_handsfree'), value = onOff(s.handsfree) } end
    if self:Has('clicks') then items[#items + 1] = { id = 'clicks', label = L('scr_menu_clicks'), value = onOff(s.clicks) } end
    if self:Has('earpiece') and s.earpieceOwned then
        items[#items + 1] = { id = 'earpiece', label = L('scr_menu_earpiece'), value = onOff(s.earpiece) }
    end
    if self:Has('toggleRoster') then items[#items + 1] = { id = 'roster', label = L('scr_menu_roster'), value = onOff(s.rosterOn) } end
    if self.device ~= 'vehicle' then
        local cs = type(s.callsign) == 'string' and s.callsign ~= '' and s.callsign or L('scr_none')
        items[#items + 1] = { id = 'callsign', label = L('scr_menu_callsign'), value = cs }
    end
    items[#items + 1] = { id = 'close', label = L('scr_menu_close') }
    return items
end

function proto:MenuCursor(items)
    -- keep the cursor on the same entry when the list changes under it (earpiece added ...)
    if self.menuId then
        for i = 1, #items do
            if items[i].id == self.menuId then self.menuIndex = i break end
        end
    end
    if self.menuIndex < 1 or self.menuIndex > #items then self.menuIndex = 1 end
    self.menuId = items[self.menuIndex] and items[self.menuIndex].id or nil
    return self.menuIndex
end

function proto:PressMenu(s, action, value, step, now)
    local items = self:MenuItems(s)
    local i = self:MenuCursor(items)
    if action == 'up' or action == 'down' or (action == 'knob' and value == 'channel') then
        local dir = action == 'knob' and (step or 1) or dirStep(action)
        self.menuIndex = (i - 1 + dir) % #items + 1
        self.menuId = items[self.menuIndex].id
        return self:Sfx('key')
    elseif action == 'back' or action == 'menu' then
        self.view = 'home'
        return self:Sfx('key')
    elseif action == 'ok' then
        local id = items[i].id
        if id == 'memories' then
            self.view, self.entry = 'memories', ''
            return self:Sfx('key')
        elseif id == 'slots' then
            self.view, self.entry, self.slotSel = 'slots', '', txSlot(s)
            return self:Sfx('key')
        elseif id == 'roster' then
            return self:ToggleRoster(s)
        elseif id == 'callsign' then
            self:Sfx('key')
            return self:Notice(L('scr_callsign_hint', tostring(Config.Commands and Config.Commands.callsign or 'callsign'):upper()), 2500)
        elseif id == 'close' then
            self.view = 'home'
            return self:Sfx('key')
        end
        return self:Toggle(s, id)
    end
    return self:Sfx('error')
end

function proto:PressEmergency(s, action, value, step, now)
    if action == 'back' or action == 'ok' then
        self.view = 'home'
        return self:Sfx('key')
    end
    return self:Sfx('error')
end

local VIEW_PRESS = {
    home = proto.PressHome, tune = proto.PressTune, code = proto.PressCode,
    memories = proto.PressMemories, slots = proto.PressSlots, menu = proto.PressMenu,
    emergency = proto.PressEmergency,
}

-- ════════════════════════════════════════════════════════════════════════
-- INPUT
-- ════════════════════════════════════════════════════════════════════════

function proto:Release(action, value)
    if action == 'ptt' then
        self:Act('ptt', false)
    elseif action == 'power' or action == 'emerg' then
        self.holds[action] = nil
    elseif action == 'knob' and value == 'volume' then
        self.knobOffAt = nil
    end
end

function proto:Press(action, value, down, step, isRepeat)
    local now = self:Now()
    local s = self:Source()
    local on = self:Sync(s, now)
    if action == 'dpad' then action, value = value, nil end
    if type(action) ~= 'string' then return end
    if action == 'digit' then value = tostring(value or '') if not value:match('^%d$') then return end end
    step = tonumber(step) or 1
    step = step < 0 and -1 or 1

    if down == false then
        self:Release(action, value)
        if self.active then self:Refresh() end
        return
    end

    if action == 'ptt' then
        if not isRepeat then self:Act('ptt', true) end
        return
    end

    if action == 'power' then
        if isRepeat then return end
        if self.powerHold <= 0 then
            self:SetPower(not on, now)
        else
            self.holds.power = { at = now, done = false }
            if on then self:Sfx('key') end
        end
        self:EnsureTicker()
        if self.active then self:Refresh() end
        return
    end

    if action == 'knob' and value == 'volume' then
        if not on then
            if step > 0 and self.knobPower and not isRepeat then self:SetPower(true, now) end
        elseif step < 0 and (tonumber(s.volume) or 0) <= 0 then
            if self.knobPower then
                self.knobOffAt = self.knobOffAt or now
                self:EnsureTicker()
            end
            if not isRepeat then self:Sfx('key') end
            self.volumeUntil = now + VOLUME_POPUP_MS
        else
            self.knobOffAt = nil
            self:ChangeVolume(s, step * VOLUME_STEP, now)
        end
        if self.active then self:Refresh() end
        return
    end

    -- a set that is off (or still running its self test) ignores every other key
    if not on or self.view == 'boot' then return end

    if action == 'emerg' then
        if isRepeat then return end
        if not (Config.Emergency and Config.Emergency.enabled) then return self:Sfx('error') end
        if self.emergHold <= 0 then
            self:FireEmergency(s, now)
        else
            self.holds.emerg = { at = now, done = false }
            self:Sfx('key')
            self:EnsureTicker()
        end
        if self.active then self:Refresh() end
        return
    end

    -- keys that do the same thing on every screen
    if action == 'p2' or action == 'mute' then
        self:Toggle(s, 'mute')
    elseif action == 'side1' then
        self:Toggle(s, 'handsfree')
    elseif action == 'side2' then
        self:ToggleRoster(s)
    else
        local fn = VIEW_PRESS[self.view] or proto.PressHome
        fn(self, s, action, value, step, now)
    end
    if self.active then self:Refresh() end
end

function proto:Repeat(action, value, step)
    return self:Press(action, value, true, step, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- TIMERS
-- ════════════════════════════════════════════════════════════════════════

function proto:Pending()
    return next(self.holds) ~= nil or self.knobOffAt ~= nil or self.pendingMem ~= nil
        or self.notice ~= nil or self.view == 'boot' or self.busy
end

function proto:Tick(now)
    now = now or self:Now()
    local s = self:Source()
    local on = self:Sync(s, now)
    local h = self.holds.power
    if h and not h.done and now - h.at >= self.powerHold then
        h.done = true
        self:SetPower(not on, now)
        on = self:Sync(s, now)
    end
    h = self.holds.emerg
    if h and not h.done and on and now - h.at >= self.emergHold then
        h.done = true
        self:FireEmergency(s, now)
    end
    if self.knobOffAt and on and now - self.knobOffAt >= KNOB_OFF_MS then
        self.knobOffAt = nil
        self:SetPower(false, now)
        self:Sync(s, now)
    end
    local m = self.pendingMem
    if m and now >= m.at then
        self.pendingMem = nil
        if on and s.presets and s.presets[m.index] then
            self:DoJoin(txSlot(s), s.presets[m.index], nil, 'home')
        end
    end
    if self.active then self:Refresh() end
end

function proto:EnsureTicker()
    if self.opts.manual or self.ticking or not self.active then return end
    self.ticking = true
    CreateThread(function()
        while self.active do
            self:Tick()
            Wait(self:Pending() and TICK_BUSY_MS or TICK_IDLE_MS)
        end
        self.ticking = false
    end)
end

function proto:SetActive(on)
    on = on == true
    if on == self.active then return end
    self.active = on
    if on then
        -- whatever happened while nobody looked at the screen is not replayed as a boot
        local now = self:Now()
        local s = self:Source()
        self.lastPower = self:EffectivePower(s, now)
        if not self.lastPower then
            self:ClearBuffers()
            self.view = 'off'
        elseif self.view == 'off' then
            self.view = 'home'
        end
        self.lastSig = nil
        self:Refresh(true)
        self:EnsureTicker()
    else
        -- hold timers die with the hand that held the key
        self.holds, self.knobOffAt = {}, nil
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- RENDER
-- ════════════════════════════════════════════════════════════════════════

local TITLES = {
    boot = 'scr_selftest', tune = 'scr_tune', code = 'scr_code', memories = 'scr_memory',
    slots = 'scr_slots', menu = 'scr_menu', emergency = 'scr_emergency',
}
local HINTS = {
    tune = 'scr_tune_hint', code = 'scr_code_hint', memories = 'scr_memories_hint',
    slots = 'scr_slots_hint', menu = 'scr_menu_hint', emergency = 'scr_emergency_hint',
}

local function pickTalker(rx, txKey)
    local best, bestAt, bestTx = nil, -1, false
    if type(rx) ~= 'table' then return nil end
    for _, info in pairs(rx) do
        if type(info) == 'table' then
            local onTx = txKey ~= nil and info.fkey == txKey
            local at = tonumber(info.at) or 0
            -- the TX channel's talker wins, then the most recent one
            if (onTx and not bestTx) or (onTx == bestTx and at > bestAt) then
                best, bestAt, bestTx = info, at, onTx
            end
        end
    end
    return best
end

function proto:Render()
    local now = self:Now()
    local s = self:Source()
    local on = self:Sync(s, now)
    local model = self.opts.model or s.model or 'handheld'
    local n = slotCount(s)
    local tx = txSlot(s)
    local slots = type(s.slots) == 'table' and s.slots or {}
    local txKey = fkeyOf(slots[tx])
    local info = channelInfo(s, txKey)

    local rxKeys = {}
    if type(s.rx) == 'table' then
        for _, r in pairs(s.rx) do
            if type(r) == 'table' and r.fkey then rxKeys[r.fkey] = true end
        end
    end
    local rows = {}
    for i = 1, n do
        local k = fkeyOf(slots[i])
        local ci = channelInfo(s, k)
        rows[i] = {
            n = i, f = k, tx = i == tx, rx = k ~= nil and rxKeys[k] == true,
            label = ci and ci.label or nil, access = k and (ci and ci.access or 'open') or nil,
        }
    end

    local talker = on and pickTalker(s.rx, txKey) or nil
    local jam = math.max(0.0, math.min(1.0, tonumber(s.jam) or 0.0))
    local block = (Config.Signal and Config.Signal.txBlockJam) or 0.92
    local q
    if talker then
        q = tonumber(talker.q) or 0
    else
        q = 1.0 - jam
        if s.underwater and not s.waterproof then q = 0.0 end
    end

    local presets = type(s.presets) == 'table' and s.presets or {}
    local count = presetCount(s)
    local mem = nil
    if txKey then
        for i = 1, count do
            if presets[i] and fkeyOf(presets[i]) == txKey then mem = i break end
        end
    end
    if self.memIndex < 1 or self.memIndex > math.max(1, count) then self.memIndex = 1 end
    local memF = fkeyOf(presets[self.memIndex])
    local memInfo = channelInfo(s, memF)

    local view = on and self.view or 'off'
    local state = {
        view = view,
        skin = self.opts.skin or FW.Skin(model),
        model = FW.ModelCode(model),
        freq = txKey,
        label = info and info.label or nil,
        access = txKey and (info and info.access or 'open') or nil,
        slot = tx,
        slots = rows,
        sel = self.slotSel,
        tx = on and s.tx == true or false,
        rx = talker and {
            name = talker.name, callsign = talker.callsign, q = round2(q),
            slot = talker.slot, emergency = talker.emergency == true,
        } or nil,
        bars = (on and jam < block) and bars(q) or 0,
        nosignal = on and jam >= block or false,
        jam = round2(jam),
        volume = math.floor(tonumber(s.volume) or 0),
        showVolume = now < self.volumeUntil,
        mute = s.muted == true,
        handsfree = s.handsfree == true,
        clicks = s.clicks ~= false,
        earpiece = s.earpiece == true,
        battery = round2(tonumber(s.battery) or 1.0),
        time = self.opts.clock and self.opts.clock() or clockString(),
        entry = (view == 'tune' or view == 'memories' or view == 'slots') and self.entry or '',
        code = view == 'code' and ('*'):rep(#self.code) or '',
        target = view == 'code' and self.pending and fkeyOf(self.pending.freq) or nil,
        memories = {
            index = self.memIndex, count = count, f = memF,
            label = memF and (memInfo and memInfo.label or nil) or L('scr_free'),
        },
        mem = mem,
        title = TITLES[view] and L(TITLES[view]) or nil,
        hint = HINTS[view] and L(HINTS[view]) or nil,
        notice = on and self.notice or nil,
        busy = self.busy == true,
        emergency = on and (now < self.emergencyUntil or s.emergency == true) or false,
    }
    if view == 'menu' then
        local items = self:MenuItems(s)
        state.menu = { items = items, index = self:MenuCursor(items) - 1 }
    else
        state.menu = { items = {}, index = 0 }
    end
    return state
end

function proto:Refresh(force)
    local state = self:Render()
    local ok, sig = pcall(json.encode, state)
    if not ok then sig = nil end
    if not force and sig and sig == self.lastSig then return state end
    self.lastSig = sig
    if self.opts.render then
        local okR, err = pcall(self.opts.render, state)
        if not okR then NZR.Warn('firmware render failed: ' .. tostring(err)) end
    end
    return state
end

-- ════════════════════════════════════════════════════════════════════════
-- HANDHELD INSTANCE (wired to NZR.Radio.State / NZR.Radio.API)
-- ════════════════════════════════════════════════════════════════════════

local handheld = nil

-- 'radio:notice' reasons (tx:denied, emergency refusals) → the line shown on the screen
local NOTICE_KEYS = {
    nosignal = 'scr_nosignal', nofreq = 'scr_nofreq', cooldown = 'scr_cooldown', denied = 'scr_denied',
    disabled = 'scr_denied', busy = 'scr_busy',
}

local function handheldSource()
    local R = NZR.Radio
    local S = R and R.State
    if not S then return {} end
    local model = S.model
    local m = model and Config.Radios.Models[model] or nil
    local jam = R.API.LocalJam and R.API.LocalJam() or 0.0
    return {
        power = S.power, model = model, slots = S.slots, slotCount = m and m.slots or 1,
        txSlot = S.txSlot, volume = S.volume, muted = S.muted, handsfree = S.handsfree,
        clicks = S.clicks, earpiece = S.earpiece, earpieceOwned = S.earpieceOwned,
        presets = S.presets, presetCount = Config.Radios.presets or 0, callsign = S.callsign,
        labels = R.Labels and R.Labels() or S.labels, tx = S.tx and S.tx.active or false, rx = S.rx,
        rosterOn = S.rosterOn, jam = jam, underwater = S.underwater,
        waterproof = m and m.waterproof == true or false,
        battery = R.Battery and R.Battery() or 1.0,
        emergency = (S.emergencyUntil or 0) > GetGameTimer(),
    }
end

local function handheldActions()
    local API = NZR.Radio.API
    return {
        join = function(slot, freq, code) return API.Join(slot, freq, code) end,
        leave = function(slot) return API.Leave(slot) end,
        setTx = function(slot) return API.SetTxSlot(slot) end,
        power = function(on) return API.Power(on) end,
        volume = function(delta) return API.Volume(delta) end,
        mute = function(on) return API.Mute(on) end,
        handsfree = function(on) return API.Handsfree(on) end,
        clicks = function(on) return API.Clicks(on) end,
        earpiece = function(on) return API.Earpiece(on) end,
        memories = function(index, freq) return API.PresetSet(index, freq) end,
        emergency = function() return API.Emergency('handheld') end,
        toggleRoster = function() return API.ToggleRoster() end,
        ptt = function(down) return API.Ptt(down, 'handheld') end,
    }
end

function FW.Handheld()
    if handheld then return handheld end
    handheld = FW.New('handheld', {
        source = handheldSource,
        actions = handheldActions(),
        powerHold = 1200,
        render = function(state)
            local S = NZR.Radio and NZR.Radio.State
            if NZR.Screen and NZR.Screen.Push and S and S.model then NZR.Screen.Push(S.model, state) end
        end,
    })
    NZR.Bus.On('radio:changed', function()
        if handheld.active then handheld:Refresh() end
    end)
    NZR.Bus.On('radio:notice', function(key, device)
        if device == 'vehicle' or type(key) ~= 'string' then return end
        handheld:Notice(L(NOTICE_KEYS[key] or 'scr_error'))
    end)
    return handheld
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource or not handheld then return end
    handheld.active = false
end)
