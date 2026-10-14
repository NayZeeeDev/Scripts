--[[
    NAYZEEE AMBULANCE - Wounded (client): the downed stage

    Reacts to the local player's patient state (state bag 'nza', bus 'self:state'):
      wounded / arrest  → ragdoll, then a downed pose picked from the injuries (wounded_pose.lua),
                          crawl (W start · S stop · A/D turn) while conscious and not moved by
                          someone, controls in Config.Wounded.disableControls blocked (chat,
                          voice and phone stay usable), the 'wounded' HUD (flip clock, status,
                          key hints, injury chips), screen effects (wounded_fx.lua)
      dead              → death screen + respawn (wounded_death.lua)
      alive             → get-up animation, everything cleared
    Re-entry after relog / restart works through the same path: the core re-applies the
    saved state bag and emits 'self:state'.

    Keys (ox_lib keybinds, players can rebind them):
      nza_wounded_call     Config.Wounded.callEms.key   call EMS / request body recovery
      nza_wounded_giveup   Config.WoundedUI.keys.giveUp hold to give up (after minTime)
      nza_wounded_respawn  Config.WoundedUI.keys.respawn hold to respawn (death screen)

    Bus events handled: self:state, self:update, self:revived, self:resurrected
    Net events handled: nza:wounded:called, nza:wounded:status, nza:wounded:help, nza:wounded:alert
    Net events sent:    nza:wounded:callEms, nza:wounded:giveUp
    Callbacks used:     nza:wounded:info
    NUI app:            'wounded' (opened without focus) - actions open, state, injuries, fx,
                        hold, flash, close
    Client API (other modules):
      NZA.Wounded.Active()            → 'wounded' | 'arrest' | 'dead' | nil
      NZA.Wounded.SuspendPose(name, on)  stop re-applying the downed pose while a module plays its
                                      own animation on the downed player (beds, bay, stretcher)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded
W.S = W.S or {}
local S = W.S
local U = NZA.Util

local APP = 'wounded'

-- runtime state shared by wounded*.lua (all fields reset on exit)
S.mode = S.mode or nil          -- 'wounded' | 'arrest' | 'dead' | nil
S.sum = S.sum or nil            -- last state bag summary
S.snap = S.snap or nil          -- last self snapshot
S.status = S.status or {}       -- live status from the server (cpr, treating, onScene)
S.help = S.help or nil          -- { eta, etaAt, unit, ai, status }

local hudOpen = false
local lastHudJson = nil
local loopRunning = false
local radarHidden = false
local phoneOpen, phoneCheckAt = false, 0
local getUpTimer = nil
local hold = { kind = nil, down = false, start = 0 }
local settledAt = GetGameTimer()   -- module start / character load: states applied right after are re-entries

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function wcfg(key, default)
    local s = Config.Wounded
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function ui(key, default)
    local s = Config.WoundedUI
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end
W.ui = ui
W.wcfg = wcfg

local function giveUpCfg(key, default)
    local g = wcfg('giveUp', nil)
    if type(g) ~= 'table' or g[key] == nil then return default end
    return g[key]
end

-- ════════════════════════════════════════════════════════════════════════
-- SMALL QUERIES
-- ════════════════════════════════════════════════════════════════════════

function W.Active()
    return S.mode
end

function W.SuspendPose(name, on)
    if W.Pose and W.Pose.Suspend then W.Pose.Suspend(name, on) end
end

local function phoneIsOpen()
    local now = GetGameTimer()
    if now < phoneCheckAt then return phoneOpen end
    phoneCheckAt = now + 300
    phoneOpen = false
    if Bridge and Bridge.Phone and Bridge.Phone.IsOpen then
        local ok, res = pcall(Bridge.Phone.IsOpen)
        phoneOpen = ok and res == true
    end
    return phoneOpen
end
W.PhoneOpen = phoneIsOpen

-- keyboard free for our keys (no phone, no other focused UI, no pause menu)
local function inputFree()
    if IsPauseMenuActive() then return false end
    if IsNuiFocused() then return false end
    if phoneIsOpen() then return false end
    return true
end
W.InputFree = inputFree

local function avpu()
    return (S.sum and S.sum.avpu) or 'A'
end

local function unconscious()
    if S.mode == 'arrest' or S.mode == 'dead' then return true end
    local a = avpu()
    return a == 'P' or a == 'U'
end
W.Unconscious = unconscious

local function cprActive()
    if S.status and S.status.cpr then return true end
    if S.sum and S.sum.cpr then return true end
    local ok, v = pcall(function() return LocalPlayer.state.nzaCpr end)
    return ok and v and true or false
end
W.CprActive = cprActive

-- someone else is moving / holding the body
local function heldBySomeone(ped)
    local sum = S.sum or {}
    if sum.carried or sum.stretcher or sum.bag then return true end
    if IsEntityAttached(ped) then return true end
    return false
end
W.Held = heldBySomeone

function W.CanCrawl()
    if S.mode ~= 'wounded' then return false, 'nomove' end
    if not wcfg('crawl', true) then return false, 'nomove' end
    if unconscious() then return false, 'nomove' end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or heldBySomeone(ped) then return false, 'held' end
    if IsPedSwimming(ped) then return false, 'nomove' end
    if W.Pose and W.Pose.Suspended and W.Pose.Suspended() then return false, 'held' end
    return true
end

local function giveUpLeft()
    if not S.giveUpAt then return tonumber(giveUpCfg('minTime', 60)) or 60 end
    return math.max(0, math.ceil((S.giveUpAt - GetGameTimer()) / 1000))
end

local function canGiveUp()
    if not giveUpCfg('enabled', true) then return false end
    if S.mode == 'wounded' then return true end
    if S.mode == 'arrest' and ui('giveUpInArrest', true) then return true end
    return false
end

local function callLeft()
    if not S.callUntil then return 0 end
    return math.max(0, math.ceil((S.callUntil - GetGameTimer()) / 1000))
end

local function canCall()
    if not S.mode then return false end
    if S.mode == 'dead' then return ui('bodyRecoveryCall', true) and true or false end
    if not ui('callWhileUnconscious', true) and unconscious() then return false end
    return true
end
W.CanCall = canCall
W.CallLeft = callLeft

-- ════════════════════════════════════════════════════════════════════════
-- KEY NAMES (what the HUD shows; follows the player's own bindings)
-- ════════════════════════════════════════════════════════════════════════

local keybinds = {}

local function controlKey(control, fallback)
    local ok, name = pcall(GetControlInstructionalButton, 0, control, true)
    if ok and type(name) == 'string' and name:sub(1, 2) == 't_' then return name:sub(3) end
    return fallback
end

local function bindKey(name, fallback)
    local kb = keybinds[name]
    if kb and kb.getCurrentKey then
        local ok, key = pcall(kb.getCurrentKey, kb)
        if ok and type(key) == 'string' and key ~= '' and #key <= 12 then return key end
    end
    return fallback
end

local keyCache, keyCacheAt = nil, 0
function W.Keys()
    local now = GetGameTimer()
    if keyCache and now < keyCacheAt then return keyCache end
    local callKey = (type(wcfg('callEms', nil)) == 'table' and wcfg('callEms').key) or 'G'
    local keys = ui('keys', {}) or {}
    keyCache = {
        crawl = controlKey(32, 'W'),
        stop = controlKey(33, 'S'),
        left = controlKey(34, 'A'),
        right = controlKey(35, 'D'),
        call = bindKey('call', callKey),
        giveUp = bindKey('giveUp', keys.giveUp or 'E'),
        respawn = bindKey('respawn', keys.respawn or 'E'),
    }
    keyCacheAt = now + 5000
    return keyCache
end

-- ════════════════════════════════════════════════════════════════════════
-- HUD
-- ════════════════════════════════════════════════════════════════════════

local function clockRunning()
    local sum = S.sum or {}
    if S.mode == 'wounded' then return not sum.stab end
    if S.mode == 'arrest' then return not cprActive() end
    return false
end

local function helpPayload()
    local h = S.help
    if not h then return nil end
    local eta = nil
    if h.etaAt then eta = math.max(0, math.ceil((h.etaAt - GetGameTimer()) / 1000)) end
    return { eta = eta, unit = h.unit, ai = h.ai, status = h.status }
end

local function hudState()
    local sum = S.sum or {}
    local ped = PlayerPedId()
    local can, why = W.CanCrawl()
    local st = S.status or {}
    return {
        state = S.mode,
        avpu = avpu(),
        unconscious = unconscious(),
        bleed = tonumber(sum.bleed) or 0,
        stab = sum.stab == true,
        clock = math.max(0, math.floor(tonumber(sum.clock) or 0)),
        -- full scale of the HUD's bleed-out ring (arrest: time until death)
        clockMax = S.mode == 'arrest'
            and math.max(1, math.floor(tonumber(Config.Death and Config.Death.arrestToDeath) or 300))
            or math.max(1, math.floor(tonumber(wcfg('maxClock', 300)) or 300)),
        running = clockRunning(),
        rate = (S.mode == 'wounded' and S.snap and tonumber(S.snap.clockRate)) and U.clamp(tonumber(S.snap.clockRate), 0, 1) or 1,
        critical = tonumber(ui('criticalClock', 30)) or 30,
        carried = sum.carried == true,
        stretcher = sum.stretcher ~= nil and sum.stretcher ~= false,
        bag = sum.bag == true,
        vehicle = IsPedInAnyVehicle(ped, false),
        crawl = {
            enabled = wcfg('crawl', true) and true or false,
            can = can,
            why = why,
            on = W.Pose and W.Pose.IsCrawling and W.Pose.IsCrawling() or false,
            stamina = W.Pose and W.Pose.Stamina and U.round(W.Pose.Stamina(), 2) or 1,
            toggle = (type(ui('crawl', nil)) == 'table' and ui('crawl').toggle ~= false),
        },
        giveUp = {
            enabled = giveUpCfg('enabled', true) and true or false,
            allowed = canGiveUp(),
            left = giveUpLeft(),
            hold = tonumber(giveUpCfg('hold', 3)) or 3,
        },
        call = {
            allowed = canCall(),
            left = callLeft(),
            called = S.called == true,
            pending = S.callPending == true,
            medics = S.medics,
            ai = S.callAi == true,
        },
        status = {
            cpr = cprActive(),
            cprBy = st.cprBy,
            treating = st.treating == true,
            onScene = st.onScene,
        },
        help = helpPayload(),
        keys = W.Keys(),
    }
end

local function shortLabel(kind, fallback)
    local key = 'wounded.short_' .. tostring(kind)
    local txt = NZA.L(key)
    if txt ~= key then return txt end
    return fallback or kind
end

local function injuryPayload()
    local snap = S.snap
    if not snap then return {} end
    local out = {}
    local tq = {}
    local splints = {}
    local dev = snap.devices or {}
    for _, r in ipairs(type(dev.tourniquet) == 'table' and dev.tourniquet or {}) do tq[r] = true end
    for _, r in ipairs(type(dev.splints) == 'table' and dev.splints or {}) do splints[r] = true end
    for _, inj in ipairs(type(snap.injuries) == 'table' and snap.injuries or {}) do
        if type(inj) == 'table' and inj.region and inj.type then
            local t = NZA.Const.InjuryTypes[inj.type]
            out[#out + 1] = {
                region = inj.region,
                regionLabel = inj.regionLabel or U.RegionLabel(inj.region),
                type = inj.type,
                label = shortLabel(inj.type, t and t.short or inj.label),
                icon = (t and t.icon) or 'drop',
                severity = tonumber(inj.severity) or 1,
                bleeding = inj.bleeding == true,
                tourniquet = tq[inj.region] == true,
                splinted = splints[inj.region] == true,
                treated = inj.status == 'treated' or inj.status == 'healing' or inj.status == 'controlled',
            }
        end
    end
    return out
end

function W.PushHud(force)
    if not hudOpen then return end
    local st = hudState()
    local ok, enc = pcall(json.encode, st)
    if not force and ok and enc == lastHudJson then return end
    lastHudJson = ok and enc or nil
    NZA.UI.Send(APP, 'state', st)
end

function W.PushInjuries()
    if not hudOpen then return end
    if ui('showInjuries', true) == false then return end
    NZA.UI.Send(APP, 'injuries', { list = injuryPayload(), max = tonumber(ui('maxInjuryChips', 5)) or 5 })
end

local function openHud()
    if hudOpen then return end
    hudOpen = true
    lastHudJson = nil
    local fx = ui('effects', {}) or {}
    NZA.UI.Open(APP, {
        L = NZA.LocaleTable('wounded'),
        state = hudState(),
        injuries = ui('showInjuries', true) ~= false and injuryPayload() or {},
        maxChips = tonumber(ui('maxInjuryChips', 5)) or 5,
        pulseLine = ui('pulseLine', true) ~= false,
        overlay = fx.overlay ~= false,
        heartbeat = fx.heartbeat ~= false,
        volume = tonumber(fx.heartbeatVolume) or 0.6,
    }, { focus = false })
end

local function closeHud()
    if not hudOpen then return end
    hudOpen = false
    lastHudJson = nil
    NZA.UI.Close(APP)
end
W.CloseHud = closeHud
W.HudOpen = function() return hudOpen end

function W.Flash(kind, text, ms)
    if type(text) ~= 'string' or text == '' then return end
    if hudOpen then NZA.UI.Send(APP, 'flash', { kind = kind, text = text, ms = ms or 3200 }) end
    if W.Death and W.Death.Flash then W.Death.Flash(kind, text, ms) end
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER INFO (time down, cooldowns; also restores timers after a relog)
-- ════════════════════════════════════════════════════════════════════════

function W.FetchInfo(cb)
    lib.callback('nza:wounded:info', false, function(info)
        if type(info) ~= 'table' then
            if cb then cb(nil) end
            return
        end
        local now = GetGameTimer()
        S.info = info
        S.giveUpAt = now + (tonumber(info.giveUpIn) or 0) * 1000
        S.downSince = now - (tonumber(info.downFor) or 0) * 1000
        local left = tonumber(info.callLeft) or 0
        if left > 0 then S.callUntil = now + left * 1000 end
        if info.called then S.called = true end
        S.medics = tonumber(info.medics)
        if cb then cb(info) end
        W.PushHud()
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL EMS
-- ════════════════════════════════════════════════════════════════════════

function W.Call()
    if not S.mode or not inputFree() then return end
    if not canCall() then
        W.Flash('bad', NZA.L('wounded.call_unconscious'))
        return
    end
    if S.callPending then return end
    local left = callLeft()
    if left > 0 then
        W.Flash('warn', NZA.L('wounded.call_cooldown', U.formatTime(left)))
        return
    end
    S.callPending = true
    S.callPendingAt = GetGameTimer()
    TriggerServerEvent('nza:wounded:callEms')
    W.PushHud()
    if W.Death and W.Death.Push then W.Death.Push() end
end

RegisterNetEvent('nza:wounded:called', function(d)
    if type(d) ~= 'table' then return end
    S.callPending = false
    local now = GetGameTimer()
    if tonumber(d.left) and d.left > 0 then S.callUntil = now + d.left * 1000 end
    if d.ok then
        S.called = true
        S.medics = tonumber(d.medics) or S.medics
        S.callAi = d.ai == true
        if d.ai and not S.help then S.help = { ai = true, status = 'enroute' } end
        W.Flash('ok', d.text)
    else
        W.Flash(d.kind == 'cooldown' and 'warn' or 'bad', d.text)
    end
    W.PushHud()
    if W.Death and W.Death.Push then W.Death.Push() end
end)

RegisterNetEvent('nza:wounded:status', function(d)
    if type(d) ~= 'table' then return end
    S.status = d
    if d.called then S.called = true end
    W.PushHud()
end)

RegisterNetEvent('nza:wounded:help', function(d)
    if type(d) ~= 'table' then return end
    if d.status == 'cancelled' or d.status == 'cleared' then
        S.help = nil
    else
        local eta = tonumber(d.eta)
        S.help = {
            eta = eta,
            etaAt = eta and (GetGameTimer() + eta * 1000) or nil,
            unit = type(d.unit) == 'string' and d.unit or nil,
            ai = d.ai == true,
            status = type(d.status) == 'string' and d.status or 'enroute',
        }
    end
    W.PushHud()
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOLD KEYS (give up / respawn) - progress drawn by the NUI ring
-- ════════════════════════════════════════════════════════════════════════

local function holdSeconds(kind)
    if kind == 'respawn' then return tonumber(Config.Death and Config.Death.respawnHold) or 3 end
    return tonumber(giveUpCfg('hold', 3)) or 3
end

local function sendHold(kind, p)
    if kind == 'respawn' then
        if W.Death and W.Death.Hold then W.Death.Hold(p) end
    elseif hudOpen then
        NZA.UI.Send(APP, 'hold', { kind = kind, p = p })
    end
end

local function holdAllowed(kind)
    if not inputFree() then return false end
    if kind == 'giveUp' then
        return canGiveUp() and giveUpLeft() <= 0
    end
    if kind == 'respawn' then
        return W.Death and W.Death.CanRespawn and W.Death.CanRespawn() or false
    end
    return false
end

local function holdFire(kind)
    if kind == 'giveUp' then
        TriggerServerEvent('nza:wounded:giveUp')
    elseif kind == 'respawn' and W.Death and W.Death.Respawn then
        W.Death.Respawn()
    end
end

function W.HoldStart(kind)
    if not S.mode then return end
    if hold.down then return end
    if not holdAllowed(kind) then
        if kind == 'giveUp' and canGiveUp() and giveUpLeft() > 0 then
            W.Flash('warn', NZA.L('wounded.giveup_early', U.formatTime(giveUpLeft())))
        end
        return
    end
    hold.kind, hold.down, hold.start = kind, true, GetGameTimer()
    local secs = holdSeconds(kind)
    CreateThread(function()
        local lastSent = -1
        while hold.down and hold.kind == kind do
            if not S.mode or not holdAllowed(kind) then break end
            local p = math.min(1, (GetGameTimer() - hold.start) / (secs * 1000))
            local q = math.floor(p * 40) / 40
            if q ~= lastSent then
                lastSent = q
                sendHold(kind, q)
            end
            if p >= 1 then
                hold.down = false
                holdFire(kind)
                Wait(250)
                break
            end
            Wait(0)
        end
        hold.down = false
        hold.kind = nil
        sendHold(kind, 0)
    end)
end

function W.HoldStop(kind)
    if hold.kind == kind then hold.down = false end
end

-- ════════════════════════════════════════════════════════════════════════
-- CONTROL LOOP (per frame only while downed)
-- ════════════════════════════════════════════════════════════════════════

local ALWAYS_BLOCK = {
    21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38, 44, 45, 46, 47, 51, 54, 58,
    140, 141, 142, 143, 257, 263, 264,
}
local VEHICLE_BLOCK = { 59, 60, 63, 64, 71, 72, 75, 76, 86 }

local function blockList()
    local list = {}
    local seen = {}
    for _, c in ipairs(ALWAYS_BLOCK) do
        if not seen[c] then seen[c] = true; list[#list + 1] = c end
    end
    for _, c in ipairs(wcfg('disableControls', {}) or {}) do
        c = tonumber(c)
        if c and not seen[c] then seen[c] = true; list[#list + 1] = c end
    end
    return list
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        local list = blockList()
        local last = GetGameTimer()
        local pid = PlayerId()
        local crawlOn = false
        local crawlCfg = ui('crawl', {}) or {}
        local toggle = crawlCfg.toggle ~= false
        while S.mode do
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - last) / 1000)
            last = now
            local ped = PlayerPedId()
            for i = 1, #list do DisableControlAction(0, list[i], true) end
            DisablePlayerFiring(pid, true)
            if IsPedInAnyVehicle(ped, false) then
                for i = 1, #VEHICLE_BLOCK do DisableControlAction(0, VEHICLE_BLOCK[i], true) end
            end

            local turn = 0
            if W.CanCrawl() and inputFree() then
                if toggle then
                    if IsDisabledControlJustPressed(0, 32) then crawlOn = true end
                    if IsDisabledControlJustPressed(0, 33) then crawlOn = false end
                else
                    crawlOn = IsDisabledControlPressed(0, 32)
                end
                if IsDisabledControlPressed(0, 34) then turn = turn + 1 end
                if IsDisabledControlPressed(0, 35) then turn = turn - 1 end
            else
                crawlOn = false
            end
            if W.Pose and W.Pose.Tick then
                local stillOn = W.Pose.Tick(ped, dt, crawlOn, turn)
                if crawlOn and stillOn == false then crawlOn = false end
            end
            Wait(0)
        end
        loopRunning = false
    end)
end

-- slow loop: HUD pushes, health top-up, call timeout
local slowRunning = false
local function startSlowLoop()
    if slowRunning then return end
    slowRunning = true
    CreateThread(function()
        local tick = 0
        while S.mode do
            tick = tick + 1
            local ped = PlayerPedId()
            -- GTA must never kill a downed player again (damage still becomes injuries)
            if wcfg('invincible', true) and tick % 4 == 0 and not IsEntityDead(ped) then
                local maxHp = GetEntityMaxHealth(ped)
                if GetEntityHealth(ped) < maxHp * 0.7 then
                    SetEntityHealth(ped, maxHp)
                    if NZA.Damage and NZA.Damage.SyncBaseline then NZA.Damage.SyncBaseline() end
                end
            end
            if S.callPending and S.callPendingAt and GetGameTimer() - S.callPendingAt > 8000 then
                S.callPending = false
            end
            W.PushHud()
            if W.Death and W.Death.Push then W.Death.Push() end
            Wait(250)
        end
        slowRunning = false
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- RADAR
-- ════════════════════════════════════════════════════════════════════════

local function applyRadar()
    local cfgR = ui('hideRadar', {}) or {}
    local want = false
    if S.mode == 'dead' then want = cfgR.dead == true
    elseif S.mode then want = cfgR.wounded == true end
    if want and not radarHidden then
        -- only touch it when it is showing, so a HUD that hides the map on foot stays in charge
        if IsRadarHidden() then return end
        DisplayRadar(false)
        radarHidden = true
    elseif not want and radarHidden then
        DisplayRadar(true)
        radarHidden = false
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE MACHINE
-- ════════════════════════════════════════════════════════════════════════

-- a real fall (not a relog / restart re-entry) gets the ragdoll
local function fellFrom(old)
    return old == 'alive' and GetGameTimer() - settledAt > 8000
end

local function poseMode()
    if S.mode == 'dead' then return 'dead' end
    if S.mode == 'arrest' then return 'arrest' end
    if unconscious() then return 'unconscious' end
    return 'wounded'
end
W.PoseMode = poseMode

local function enterDown(state, old)
    getUpTimer, S.leaving = nil, false
    local wasDead = S.mode == 'dead'
    S.mode = state
    if wasDead and W.Death and W.Death.Close then W.Death.Close() end
    if old == 'alive' or old == nil then
        S.called, S.callAi, S.help = false, false, nil
        S.status = {}
    end
    openHud()
    W.FetchInfo()
    W.PushInjuries()
    startLoop()
    startSlowLoop()
    applyRadar()
    if W.Pose and W.Pose.Enter then W.Pose.Enter(poseMode(), fellFrom(old)) end
    if W.Fx and W.Fx.Update then W.Fx.Update() end
end

local function enterDead(old)
    getUpTimer, S.leaving = nil, false
    S.mode = 'dead'
    hold.down = false
    closeHud()
    startLoop()
    startSlowLoop()
    applyRadar()
    if W.Pose and W.Pose.Enter then W.Pose.Enter('dead', fellFrom(old)) end
    if W.Fx and W.Fx.Update then W.Fx.Update() end
    if W.Death and W.Death.Open then W.Death.Open() end
end

-- everything back to normal. how = 'getup' | 'none' | 'respawn'
local function exitAll(how)
    if not S.mode then return end
    S.mode = nil
    S.leaving = false
    hold.down = false
    closeHud()
    if W.Death and W.Death.Close then W.Death.Close() end
    applyRadar()
    if W.Fx and W.Fx.Clear then W.Fx.Clear() end
    if W.Pose and W.Pose.Exit then W.Pose.Exit(how) end
    S.status, S.help, S.called, S.callAi, S.callPending = {}, nil, false, false, false
    S.callUntil, S.giveUpAt, S.info = nil, nil, nil
end
W.ExitAll = exitAll

local function exitHow()
    if S.respawn then return 'respawn' end
    return 'getup'
end

function W.Apply(new, old)
    if new == 'alive' then
        if not S.mode then return end
        -- visuals go now (before the core re-applies its own injury effects for 'alive')
        S.leaving = true
        closeHud()
        if W.Death and W.Death.Close then W.Death.Close() end
        if W.Fx and W.Fx.Clear then W.Fx.Clear() end
        -- give a following 'nza:revived' a moment to clear tasks first, so the get-up plays once
        local how = exitHow()
        if how == 'getup' then
            if getUpTimer then return end
            getUpTimer = true
            SetTimeout(350, function()
                if not getUpTimer then return end
                getUpTimer = nil
                exitAll('getup')
            end)
        else
            exitAll(how)
        end
        return
    end
    if new == 'dead' then
        enterDead(old)
    elseif new == 'wounded' or new == 'arrest' then
        enterDown(new, old)
    end
end

local function onSummary(value)
    if type(value) ~= 'table' then return end
    local prev = S.sum
    S.sum = value
    if not S.mode or S.leaving then return end
    -- conscious ↔ unconscious changes the pose; being carried changes nothing here
    local prevAvpu = prev and prev.avpu or 'A'
    if prevAvpu ~= value.avpu and S.mode == 'wounded' and W.Pose and W.Pose.SetMode then
        W.Pose.SetMode(poseMode())
    end
    if W.Fx and W.Fx.Update then W.Fx.Update() end
    W.PushHud()
end

-- ════════════════════════════════════════════════════════════════════════
-- CORE HOOKS
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new, old)
    S.sum = (NZA.Self and NZA.Self.Summary and NZA.Self.Summary()) or S.sum
    W.Apply(new, old)
end)

NZA.Bus.On('self:update', function(snap)
    if type(snap) ~= 'table' then return end
    S.snap = snap
    if not S.mode or S.leaving then return end
    W.PushInjuries()
    if W.Pose and W.Pose.Refresh then W.Pose.Refresh() end
    if W.Fx and W.Fx.Update then W.Fx.Update() end
end)

NZA.Bus.On('self:revived', function(opts)
    opts = type(opts) == 'table' and opts or {}
    if opts.rosc then return end
    local pending = getUpTimer ~= nil
    getUpTimer = nil
    if S.mode then
        exitAll(exitHow())
    elseif pending or (W.Pose and W.Pose.RecentlyGotUp and W.Pose.RecentlyGotUp()) then
        -- the state bag beat this event and the core just cleared our get-up: play it again
        if W.Pose and W.Pose.GetUp then W.Pose.GetUp(true) end
    end
    if W.Death and W.Death.Revived then W.Death.Revived(opts) end
end)

NZA.Bus.On('self:resurrected', function()
    if S.mode and W.Pose and W.Pose.Reapply then W.Pose.Reapply(true) end
end)

AddStateBagChangeHandler('nza', ('player:%d'):format(cache.serverId), function(_, _, value)
    onSummary(value)
end)

-- ════════════════════════════════════════════════════════════════════════
-- FALLBACK ALERT FOR MEDICS (only when the dispatch module is not running)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:wounded:alert', function(d)
    if type(d) ~= 'table' or type(d.coords) ~= 'table' then return end
    if NZA.OnDuty and not NZA.OnDuty() then return end
    local b = ui('fallbackBlip', {}) or {}
    local blip = AddBlipForCoord(d.coords.x + 0.0, d.coords.y + 0.0, d.coords.z + 0.0)
    SetBlipSprite(blip, tonumber(b.sprite) or 153)
    SetBlipColour(blip, tonumber(b.colour) or 1)
    SetBlipScale(blip, (tonumber(b.scale) or 1.0) + 0.0)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(NZA.L('wounded.alert_blip', d.title or ''))
    EndTextCommandSetBlipName(blip)
    NZA.UI.Toast({
        title = NZA.L('wounded.alert_title', tostring(d.code or '')),
        message = NZA.L('wounded.alert_msg', d.title or '', d.name or ''),
        type = (tonumber(d.priority) == 1) and 'error' or 'warning',
        duration = 9000,
        icon = 'ambulance',
    })
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
    SetTimeout(math.floor((tonumber(b.time) or 180) * 1000), function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- KEYBINDS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    local keys = ui('keys', {}) or {}
    local callKey = (type(wcfg('callEms', nil)) == 'table' and wcfg('callEms').key) or 'G'
    keybinds.call = lib.addKeybind({
        name = 'nza_wounded_call',
        description = NZA.L('wounded.bind_call'),
        defaultMapper = 'keyboard',
        defaultKey = callKey,
        onPressed = function()
            if S.mode then W.Call() end
        end,
    })
    keybinds.giveUp = lib.addKeybind({
        name = 'nza_wounded_giveup',
        description = NZA.L('wounded.bind_giveup'),
        defaultMapper = 'keyboard',
        defaultKey = keys.giveUp or 'E',
        onPressed = function()
            if S.mode == 'wounded' or S.mode == 'arrest' then W.HoldStart('giveUp') end
        end,
        onReleased = function() W.HoldStop('giveUp') end,
    })
    keybinds.respawn = lib.addKeybind({
        name = 'nza_wounded_respawn',
        description = NZA.L('wounded.bind_respawn'),
        defaultMapper = 'keyboard',
        defaultKey = keys.respawn or 'E',
        onPressed = function()
            if S.mode == 'dead' then W.HoldStart('respawn') end
        end,
        onReleased = function() W.HoldStop('respawn') end,
    })
    keyCache = nil
end)

-- ════════════════════════════════════════════════════════════════════════
-- START / STOP
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    if Bridge and Bridge.OnPlayerLoaded then
        Bridge.OnPlayerLoaded(function() settledAt = GetGameTimer() end)
    end
end)

-- safety net: pick up a state the bus event was emitted for before this file listened
CreateThread(function()
    Wait(2500)
    if S.mode then return end
    local st = NZA.Self and NZA.Self.State and NZA.Self.State() or 'alive'
    if st ~= 'alive' then
        S.sum = NZA.Self.Summary and NZA.Self.Summary() or S.sum
        S.snap = NZA.Self.Get and NZA.Self.Get() or S.snap
        W.Apply(st, 'relog')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    if radarHidden then DisplayRadar(true) end
    if S.mode then
        local ped = PlayerPedId()
        if W.Fx and W.Fx.Clear then pcall(W.Fx.Clear) end
        if W.Pose and W.Pose.Exit then pcall(W.Pose.Exit, 'none') end
        ClearPedTasks(ped)
    end
end)
