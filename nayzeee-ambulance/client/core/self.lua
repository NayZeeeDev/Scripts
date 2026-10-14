--[[
    NAYZEEE AMBULANCE - Client core: the local player as a patient (NZA.Self)

      NZA.Self.State()                 'alive'|'wounded'|'arrest'|'dead' (own state bag 'nza')
      NZA.Self.Summary()               own state bag summary table (§4.3) or nil
      NZA.Self.Get()                   last self snapshot (callback 'nza:self:get' / push)
      NZA.Self.IsDown()                state ~= 'alive'
      NZA.Self.Refresh()               re-fetch the self snapshot now (awaits)
      NZA.Self.SetMoveOverride(name, clipset|false|nil)
                                       crutches / wheelchair / beds override the walk. A string
                                       clipset replaces the injured walk, false suppresses it,
                                       nil removes the override. Latest override wins.
      NZA.Self.Suspend(name, bool)     pause all injury effects while any suspension is set
      NZA.Self.Effects()               current computed effect levels (debug / HUD use)

    Injury effects (only while state == 'alive', all removed cleanly on any state change
    and on revive):
      legs     injured walk (move_m@injured / move_f@injured), heavy limp for unsplinted
               fractures, no sprint / jump with any leg or pelvis fracture
      arms     hand shake while aiming with a fractured arm
      head     concussion: short blurred / wavy vision spells, stumbles when sprinting
      blood    desaturation + vignette scaling with blood loss
      pain     camera sway scaling with pain
      hypoxia  gasping (out of breath anim + face), blur pulses, darker vignette
      server fx hints from the self snapshot: limp, shake, blur, tunnel, breathless,
               drunk (drunk walk + sway), cold (shiver sway)
    GTA health sync (Config.Physiology.syncHealth): the GTA health bar follows blood volume
    by deltas, so blood loss lowers it, transfusions raise it, gun damage still shows, and
    the sync never takes health below a safe floor (it can never kill the player).

    State bag handler: 'nza' on player:<own server id>
    Net events handled: nza:self:update (snapshot), nza:revived (opts)
    Bus events emitted: self:state (new, old), self:update (snapshot), self:revived (opts)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Self = NZA.Self or {}
local Self = NZA.Self
local U = NZA.Util

local current = 'alive'
local summary = nil
local snapshot = nil
local moveOverrides = {}       -- { { name = , clipset = }, ... } latest last
local suspended = {}
local lastTarget = nil         -- last blood-derived health target (for delta sync)

local LEG = { l_upper_leg = true, l_lower_leg = true, r_upper_leg = true, r_lower_leg = true, pelvis = true }
local ARM = { l_upper_arm = true, l_lower_arm = true, r_upper_arm = true, r_lower_arm = true }
local HEAD = { head = true, face = true }

local CLIP_INJURED_M = 'move_m@injured'
local CLIP_INJURED_F = 'move_f@injured'
local CLIP_LIMP = 'move_injured_generic'
local CLIP_DRUNK = 'move_m@drunk@moderatedrunk'
local CLIP_DRUNK_HEAVY = 'move_m@drunk@verydrunk'

local TC_BLOOD = 'rply_saturation_neg'
local TC_VIGNETTE = 'rply_vignette'
local FX_CONCUSSION = 'Dont_tazeme_bro'
local FX_HYPOXIA = 'DrugsDrivingIn'
local FX_HYPOXIA_OUT = 'DrugsDrivingOut'
local GASP_DICT, GASP_CLIP = 're@construction', 'out_of_breath'
local FACE_HURT = 'mood_injured_1'

-- ════════════════════════════════════════════════════════════════════════
-- SNAPSHOT READING (defensive: accepts arrays or maps, several field spellings)
-- ════════════════════════════════════════════════════════════════════════

local function asList(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for _, v in pairs(t) do
        if type(v) == 'table' then out[#out + 1] = v end
    end
    return out
end

local function conditionSet(snap)
    local out = {}
    local c = snap and snap.conditions
    if type(c) ~= 'table' then return out end
    for k, v in pairs(c) do
        if type(k) == 'number' then
            if type(v) == 'string' then out[v] = true
            elseif type(v) == 'table' and v.name then out[v.name] = v end
        elseif v then
            out[k] = v
        end
    end
    return out
end

local function lossDown()
    return (Config.Wounded and Config.Wounded.lossDown) or 0.30
end

-- Blood loss fraction 0..1. core-server's self snapshot has no exact blood numbers; it gives
-- health = 100 * (1 - loss / lossDown) while alive (5..100) and fx.tunnel = (loss - 0.10) * 3.
local function lossOf(snap)
    if not snap then return 0 end
    if tonumber(snap.loss) then return U.clamp(tonumber(snap.loss), 0, 1) end
    local pct = tonumber(snap.bloodPct)
    if pct then
        if pct > 1.0001 then pct = pct / 100 end
        return U.clamp(1 - pct, 0, 1)
    end
    local blood, max = tonumber(snap.blood), tonumber(snap.bloodMax)
    if blood and max and max > 0 then return U.clamp(1 - blood / max, 0, 1) end
    local loss = 0
    local health = tonumber(snap.health)
    if health and (snap.state == nil or snap.state == 'alive') then
        loss = lossDown() * (1 - U.clamp(health, 0, 100) / 100)
    end
    local tunnel = type(snap.fx) == 'table' and tonumber(snap.fx.tunnel)
    if tunnel and tunnel > 0 and tunnel < 1 then loss = math.max(loss, 0.10 + tunnel / 3) end
    return U.clamp(loss, 0, 1)
end

-- region list or map → set
local function regionSet(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if type(k) == 'number' then
            if type(v) == 'string' then out[v] = true end
        elseif v then
            out[k] = true
        end
    end
    return out
end

local function isSplinted(snap, inj, splints)
    if inj.splinted then return true end
    if type(inj.treat) == 'table' and (inj.treat.splinted or inj.treat.cast) then return true end
    if splints[inj.region] then return true end
    if summary and type(summary.splints) == 'table' and summary.splints[inj.region] then return true end
    return false
end

local function injuryPain(inj)
    if tonumber(inj.pain) then return tonumber(inj.pain) end
    local t = NZA.Const.InjuryTypes[inj.type or inj.kind]
    local sev = U.clamp(math.floor(tonumber(inj.severity or inj.sev) or 1), 1, 4)
    return t and t.pain[sev] or 0
end

local function emptyFx()
    return { leg = 0, legFracture = false, arm = 0, head = 0, loss = 0, pain = 0, hypoxia = 0,
             blur = 0, drunk = 0, cold = false }
end

local fx = emptyFx()

local function computeEffects()
    local snap = snapshot
    local out = emptyFx()
    if not snap then return out end

    local dev = type(snap.devices) == 'table' and snap.devices or {}
    local splints = regionSet(dev.splints or snap.splints)
    local legScore, armScore, painMax = 0, 0, 0
    for _, inj in ipairs(asList(snap.injuries or snap.inj)) do
        local region = inj.region
        local kind = inj.type or inj.kind
        local sev = tonumber(inj.severity or inj.sev) or 1
        local healing = inj.status == 'healing' and (tonumber(inj.heal) or 0) >= 60
        if healing then sev = sev - 2 end
        local fracture = kind == 'fracture' or type(inj.fracture) == 'table'
        local splint = isSplinted(snap, inj, splints)
        if sev > 0 and region then
            if LEG[region] then
                if fracture then
                    legScore = legScore + (splint and 2 or 3)
                    out.legFracture = true
                elseif sev >= 2 and kind ~= 'contusion' and kind ~= 'abrasion' then
                    legScore = legScore + sev * 0.5
                elseif sev >= 3 then
                    legScore = legScore + 1
                end
            elseif ARM[region] then
                if fracture then
                    armScore = armScore + (splint and 1 or 2)
                elseif sev >= 3 then
                    armScore = armScore + 0.5
                end
            elseif HEAD[region] and sev >= 2 then
                out.head = math.max(out.head, math.min(3, sev - 1))
            end
        end
        if not healing then painMax = math.max(painMax, injuryPain(inj)) end
    end

    -- server-side hints (core-server self snapshot 'fx')
    local hint = type(snap.fx) == 'table' and snap.fx or {}
    if hint.limp then legScore = math.max(legScore, 1) end
    if tonumber(hint.shake) then armScore = math.max(armScore, tonumber(hint.shake) * 2) end

    out.leg = legScore >= 3 and 2 or (legScore >= 1 and 1 or 0)
    out.arm = math.min(2, armScore)

    local cond = conditionSet(snap)
    if cond.concussion then
        local grade = type(cond.concussion) == 'table' and tonumber(cond.concussion.grade) or 1
        out.head = math.max(out.head, U.clamp(grade or 1, 1, 3))
    end

    out.pain = tonumber(snap.pain) or painMax
    out.loss = lossOf(snap)
    out.blur = U.clamp(tonumber(hint.blur) or 0, 0, 1)
    out.drunk = U.clamp(tonumber(hint.drunk) or 0, 0, 1)
    out.cold = hint.cold == true

    local hyp = 0
    if cond.hypoxia or cond.airway then hyp = 0.6 end
    if hint.breathless then hyp = math.max(hyp, 0.5) end
    local spo2 = tonumber(snap.spo2) or (type(snap.vitals) == 'table' and tonumber(snap.vitals.spo2))
    if spo2 and spo2 < 94 then hyp = math.max(hyp, U.clamp((94 - spo2) / 20, 0, 1)) end
    local breathing = snap.breathing or (type(snap.vitals) == 'table' and snap.vitals.breathing)
    if breathing == 'labored' then hyp = math.max(hyp, 0.3)
    elseif breathing == 'shallow' then hyp = math.max(hyp, 0.5)
    elseif breathing == 'agonal' then hyp = math.max(hyp, 0.9) end
    out.hypoxia = hyp
    return out
end

local function anyEffect(f)
    return f.leg > 0 or f.legFracture or f.arm > 0 or f.head > 0 or f.loss >= 0.12
        or f.pain >= 35 or f.hypoxia > 0 or f.blur >= 0.3 or f.drunk >= 0.2 or f.cold
end

-- ════════════════════════════════════════════════════════════════════════
-- APPLIED VISUALS (only what we set is ever cleared)
-- ════════════════════════════════════════════════════════════════════════

local applied = {
    clipset = nil, clipPed = 0,
    tc = false, tcStrength = -1,
    extra = false, extraStrength = -1,
    shake = nil, shakeAmp = 0,
    postfx = {},          -- [name] = endTime
    facial = false,
}
local timers = { head = 0, hypoxia = 0, gasp = 0, stumble = 0 }

local function overrideClipset()
    local o = moveOverrides[#moveOverrides]
    if o then return true, o.clipset end
    return false, nil
end

local function setClipset(ped, clip)
    if applied.clipset == clip and applied.clipPed == ped then return end
    if clip then
        local ok = pcall(lib.requestAnimSet, clip, 3000)
        if not ok then
            if clip == CLIP_LIMP then
                clip = IsPedMale(ped) and CLIP_INJURED_M or CLIP_INJURED_F
                ok = pcall(lib.requestAnimSet, clip, 3000)
            end
            if not ok then return end
        end
        SetPedMovementClipset(ped, clip, 0.35)
        RemoveAnimSet(clip)
        applied.clipset, applied.clipPed = clip, ped
    elseif applied.clipset then
        ResetPedMovementClipset(ped, 0.35)
        applied.clipset, applied.clipPed = nil, 0
    end
end

local function setShake(name, amp)
    if name == nil then
        if applied.shake then StopGameplayCamShaking(false) end
        applied.shake, applied.shakeAmp = nil, 0
        return
    end
    if applied.shake ~= name or not IsGameplayCamShaking() then
        if applied.shake then StopGameplayCamShaking(true) end
        ShakeGameplayCam(name, amp)
        applied.shake, applied.shakeAmp = name, amp
    elseif math.abs(applied.shakeAmp - amp) >= 0.04 then
        SetGameplayCamShakeAmplitude(amp)
        applied.shakeAmp = amp
    end
end

local function setTimecycle(strength)
    if strength <= 0 then
        if applied.tc then ClearTimecycleModifier() end
        applied.tc, applied.tcStrength = false, -1
        return
    end
    if not applied.tc then
        SetTimecycleModifier(TC_BLOOD)
        applied.tc = true
    end
    if math.abs(applied.tcStrength - strength) >= 0.02 then
        SetTimecycleModifierStrength(strength)
        applied.tcStrength = strength
    end
end

local function setVignette(strength)
    if strength <= 0 then
        if applied.extra then ClearExtraTimecycleModifier() end
        applied.extra, applied.extraStrength = false, -1
        return
    end
    if not applied.extra then
        SetExtraTimecycleModifier(TC_VIGNETTE)
        applied.extra = true
    end
    if math.abs(applied.extraStrength - strength) >= 0.02 then
        SetExtraTimecycleModifierStrength(strength)
        applied.extraStrength = strength
    end
end

local function playPostfx(name, ms)
    AnimpostfxPlay(name, 0, true)
    applied.postfx[name] = GetGameTimer() + ms
end

local function tickPostfx(now)
    local expired = nil
    for name, untilAt in pairs(applied.postfx) do
        if now >= untilAt then
            expired = expired or {}
            expired[#expired + 1] = name
        end
    end
    if not expired then return end
    for _, name in ipairs(expired) do
        AnimpostfxStop(name)
        applied.postfx[name] = nil
        if name == FX_HYPOXIA then
            -- soft fade back to sharp vision
            AnimpostfxPlay(FX_HYPOXIA_OUT, 0, false)
            applied.postfx[FX_HYPOXIA_OUT] = now + 1500
        end
    end
end

local function setFacial(ped, on)
    if on and not applied.facial then
        SetFacialIdleAnimOverride(ped, FACE_HURT, nil)
        applied.facial = true
    elseif not on and applied.facial then
        ClearFacialIdleAnimOverride(ped)
        applied.facial = false
    end
end

local function clearVisuals()
    local ped = PlayerPedId()
    -- keep a crutch/wheelchair walk even when injuries stop mattering
    local has, clip = overrideClipset()
    if has and clip and current == 'alive' then
        setClipset(ped, clip)
    else
        setClipset(ped, nil)
    end
    setShake(nil)
    setTimecycle(0)
    setVignette(0)
    for name in pairs(applied.postfx) do AnimpostfxStop(name) end
    applied.postfx = {}
    setFacial(ped, false)
    if IsEntityPlayingAnim(ped, GASP_DICT, GASP_CLIP, 3) then StopAnimTask(ped, GASP_DICT, GASP_CLIP, 2.0) end
end

-- ════════════════════════════════════════════════════════════════════════
-- EFFECT LOOP
-- ════════════════════════════════════════════════════════════════════════

local loopRunning = false
local loopGen = 0

local function effectsAllowed()
    if current ~= 'alive' then return false end
    for _ in pairs(suspended) do return false end
    return true
end

local function desiredClipset(ped)
    local has, clip = overrideClipset()
    if has then return clip or nil end
    if IsPedInAnyVehicle(ped, false) then return applied.clipset end
    if fx.leg >= 2 then return CLIP_LIMP end
    if fx.leg >= 1 then return IsPedMale(ped) and CLIP_INJURED_M or CLIP_INJURED_F end
    if fx.drunk >= 0.7 then return CLIP_DRUNK_HEAVY end
    if fx.drunk >= 0.35 then return CLIP_DRUNK end
    return nil
end

local function slowTick(ped, now)
    local pid = PlayerId()

    -- walk
    setClipset(ped, desiredClipset(ped))

    -- camera shake: hand shake while aiming with a broken arm, otherwise pain sway
    local aiming = fx.arm > 0 and IsPlayerFreeAiming(pid)
    if aiming then
        setShake('HAND_SHAKE', 0.55 + 0.45 * fx.arm)
    else
        local amp = 0
        if fx.pain >= 35 then amp = 0.12 + ((fx.pain - 35) / 65) * 0.65 end
        if fx.hypoxia > 0 then amp = amp + fx.hypoxia * 0.25 end
        if fx.drunk >= 0.2 then amp = amp + fx.drunk * 0.6 end
        if fx.cold then amp = amp + 0.12 end
        if amp > 0 then setShake('DRUNK_SHAKE', U.clamp(amp, 0, 1.0)) else setShake(nil) end
    end

    -- blood loss: colour drains first, edges darken after
    local loss = fx.loss
    setTimecycle(loss >= 0.12 and U.clamp((loss - 0.12) / 0.2, 0.15, 1.0) or 0)
    local vig = 0
    if loss >= 0.18 then vig = U.clamp((loss - 0.18) / 0.15, 0.1, 1.0) end
    if fx.hypoxia > 0 then vig = math.max(vig, 0.25 + fx.hypoxia * 0.6) end
    setVignette(U.clamp(vig, 0, 1))

    -- head injury / concussion spells
    if fx.head > 0 then
        if timers.head == 0 then timers.head = now + math.random(8000, 20000) end
        if now >= timers.head then
            playPostfx(FX_CONCUSSION, math.random(1500, 2500 + fx.head * 800))
            local gap = ({ 45000, 30000, 18000 })[fx.head] or 30000
            timers.head = now + math.random(gap, gap * 2)
        end
        if fx.head >= 2 and IsPedSprinting(ped) and now >= timers.stumble and math.random() < 0.015 * fx.head then
            SetPedToRagdoll(ped, 900, 1200, 0, false, false, false)
            timers.stumble = now + 15000
        end
    else
        timers.head = 0
    end

    -- hypoxia: blur pulses and gasping
    if fx.hypoxia > 0 then
        if timers.hypoxia == 0 then timers.hypoxia = now + math.random(3000, 7000) end
        if now >= timers.hypoxia then
            playPostfx(FX_HYPOXIA, math.floor(1500 + fx.hypoxia * 2500))
            timers.hypoxia = now + math.random(7000, 14000) - math.floor(fx.hypoxia * 4000)
        end
        if now >= timers.gasp and not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped)
            and GetEntitySpeed(ped) < 1.2 and not IsPedSwimming(ped) then
            local ok = pcall(lib.requestAnimDict, GASP_DICT, 2000)
            if ok then
                TaskPlayAnim(ped, GASP_DICT, GASP_CLIP, 2.0, -2.0, 2600, 48, 0.0, false, false, false)
                RemoveAnimDict(GASP_DICT)
            end
            timers.gasp = now + math.random(6000, 11000)
        end
    elseif fx.blur >= 0.3 then
        -- blurred vision without breathing trouble (blood loss, overdose, concussion)
        if timers.hypoxia == 0 then timers.hypoxia = now + math.random(5000, 10000) end
        if now >= timers.hypoxia then
            playPostfx(FX_HYPOXIA, math.floor(1200 + fx.blur * 2500))
            timers.hypoxia = now + math.random(9000, 16000) - math.floor(fx.blur * 5000)
        end
    else
        timers.hypoxia = 0
    end

    setFacial(ped, fx.hypoxia > 0 or fx.pain >= 55)
    tickPostfx(now)
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    loopGen = loopGen + 1
    local gen = loopGen
    CreateThread(function()
        local nextSlow = 0
        while loopRunning and gen == loopGen do
            if not effectsAllowed() then break end
            local hasOverride = moveOverrides[1] ~= nil
            if not anyEffect(fx) and not hasOverride and next(applied.postfx) == nil then break end
            local ped = PlayerPedId()
            local now = GetGameTimer()
            if now >= nextSlow then
                slowTick(ped, now)
                nextSlow = now + 250
            end
            if fx.legFracture then
                -- per frame only while a broken leg needs sprint/jump blocked
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                Wait(0)
            else
                Wait(250)
            end
        end
        -- a newer loop may have started while this one slept; leave it alone
        if gen ~= loopGen then return end
        loopRunning = false
        if not effectsAllowed() or not anyEffect(fx) then clearVisuals() end
    end)
end

local function stopEffects()
    loopRunning = false
    loopGen = loopGen + 1
    clearVisuals()
    timers.head, timers.hypoxia, timers.gasp = 0, 0, 0
end

local function evaluate()
    fx = computeEffects()
    if effectsAllowed() and (anyEffect(fx) or moveOverrides[1] ~= nil) then
        startLoop()
    elseif loopRunning then
        stopEffects()
    end
end

function Self.Effects()
    return U.deepcopy(fx)
end

function Self.SetMoveOverride(name, clipset)
    if type(name) ~= 'string' then return end
    for i = #moveOverrides, 1, -1 do
        if moveOverrides[i].name == name then table.remove(moveOverrides, i) end
    end
    if clipset ~= nil then
        moveOverrides[#moveOverrides + 1] = { name = name, clipset = clipset }
    end
    local ped = PlayerPedId()
    if current == 'alive' then
        if moveOverrides[1] == nil and not anyEffect(fx) then
            setClipset(ped, nil)
        else
            setClipset(ped, desiredClipset(ped))
        end
    end
    evaluate()
end

function Self.Suspend(name, on)
    if type(name) ~= 'string' then return end
    suspended[name] = on and true or nil
    if on then stopEffects() end
    evaluate()
end

-- ════════════════════════════════════════════════════════════════════════
-- GTA HEALTH SYNC
-- ════════════════════════════════════════════════════════════════════════

-- GTA health the blood volume allows. core-server's 'health' (0..100, reaches ~0 at the
-- lossDown threshold) maps straight onto the bar; otherwise blood loss vs deathLoss.
local function bloodHealthTarget(ped, snap)
    local maxHp = GetEntityMaxHealth(ped)
    local f
    local health = tonumber(snap.health)
    if health and (snap.state == nil or snap.state == 'alive') then
        f = U.clamp(health / 100, 0, 1)
    else
        local deathLoss = (Config.Physiology and Config.Physiology.deathLoss) or 0.5
        f = U.clamp((deathLoss - lossOf(snap)) / deathLoss, 0, 1)
    end
    return math.floor(100 + f * (maxHp - 100) + 0.5), maxHp
end

local function syncHealth(snap)
    if not (Config.Physiology and Config.Physiology.syncHealth) then return end
    if snap.syncHealth == false then return end
    if current ~= 'alive' or (snap.state and snap.state ~= 'alive') then lastTarget = nil return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then return end

    local target, maxHp = bloodHealthTarget(ped, snap)
    local cur = GetEntityHealth(ped)
    local new = cur
    if lastTarget and target > lastTarget then
        new = cur + (target - lastTarget)        -- transfusion / fluids / healing
    end
    new = math.min(new, target)                  -- blood caps the bar
    if #asList(snap.injuries or snap.inj) == 0 and lossOf(snap) <= 0.01 then
        new = maxHp                              -- fully healed: clear old gun damage too
    end
    -- the sync never lowers health past the floor, so it can never kill
    local floor = math.floor(100 + (maxHp - 100) * 0.12)
    if new < cur then new = math.max(new, math.min(cur, floor)) end
    lastTarget = target
    if math.abs(new - cur) >= 1 then
        SetEntityHealth(ped, new)
        if NZA.Damage and NZA.Damage.SyncBaseline then NZA.Damage.SyncBaseline() end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE BAG + SNAPSHOT
-- ════════════════════════════════════════════════════════════════════════

local function applySummary(value)
    summary = type(value) == 'table' and value or nil
    local new = summary and summary.st or 'alive'
    if not NZA.Const.States[new] then new = 'alive' end
    if new == current then return end
    local old = current
    current = new
    -- clear our visuals BEFORE modules react, so their own effects are not wiped
    if new ~= 'alive' then
        stopEffects()
        lastTarget = nil
    end
    NZA.Bus.Emit('self:state', new, old)
    evaluate()
end

function Self.State()
    return current
end

function Self.Summary()
    return summary
end

function Self.Get()
    return snapshot
end

function Self.IsDown()
    return current ~= 'alive'
end

local function onSnapshot(snap)
    snapshot = snap
    syncHealth(snap)
    evaluate()
    NZA.Bus.Emit('self:update', snap)
end

function Self.Refresh()
    local ok, snap = pcall(lib.callback.await, 'nza:self:get', false)
    if ok and type(snap) == 'table' then
        onSnapshot(snap)
        return snap
    end
    return snapshot
end

AddStateBagChangeHandler('nza', ('player:%d'):format(cache.serverId), function(_, _, value)
    applySummary(value)
end)

RegisterNetEvent('nza:self:update', function(snap)
    if type(snap) ~= 'table' then return end
    onSnapshot(snap)
end)

RegisterNetEvent('nza:revived', function(opts)
    opts = type(opts) == 'table' and opts or {}
    stopEffects()
    lastTarget = nil

    local ped = PlayerPedId()
    if not opts.rosc and not opts.stay then
        if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
            local c = GetEntityCoords(ped)
            NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), 0, false)
            ped = PlayerPedId()
        end
        FreezeEntityPosition(ped, false)
        if IsPedInAnyVehicle(ped, false) then
            ClearPedTasks(ped)
        else
            ClearPedTasksImmediately(ped)
        end
        ClearPedSecondaryTask(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        if NZA.Damage and NZA.Damage.SyncBaseline then NZA.Damage.SyncBaseline() end
    end

    applied.clipset, applied.clipPed = nil, 0   -- tasks were cleared; re-apply walk on next tick
    NZA.Bus.Emit('self:revived', opts)
    evaluate()
end)

-- ped model changes (clothing scripts, character switch) drop the clipset
lib.onCache('ped', function()
    applied.clipset, applied.clipPed = nil, 0
    applied.facial = false
end)

CreateThread(function()
    Wait(500)
    applySummary(LocalPlayer.state.nza)
    Self.Refresh()
end)

CreateThread(function()
    Wait(0)
    if Bridge and Bridge.OnPlayerLoaded then
        Bridge.OnPlayerLoaded(function()
            -- own thread: the bridge runs its hooks one after another
            CreateThread(function()
                Wait(1000)
                applySummary(LocalPlayer.state.nza)
                Self.Refresh()
            end)
        end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    stopEffects()
    setClipset(PlayerPedId(), nil)
end)
