--[[
    NAYZEEE AMBULANCE - Wounded (client): screen effects & the death camera

      NZA.Wounded.Fx.Update()        recompute from the current downed state (wounded.lua calls it
                                     on every state bag / snapshot change)
      NZA.Wounded.Fx.Clear()         remove everything this file applied (idempotent - only what
                                     we set is ever cleared, so the core's own injury effects
                                     that follow a revive are never wiped)
      NZA.Wounded.Fx.DeathCam(on)    slow orbit camera over the body while dead

    Game side (Config.WoundedUI.effects): colour drains and edges darken with blood loss
    (timecycle + extra timecycle), blurred vision while AVPU is P/U, black & white in cardiac
    arrest and death, a slight sway while conscious. The NUI side (vignette, red edge pulse on
    the heartbeat, eyelid fades, heartbeat sound) lives in the 'wounded' app and is fed with
    action 'fx'.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded
W.Fx = W.Fx or {}
local F = W.Fx
local U = NZA.Util

local applied = {
    tc = nil, tcStrength = -1,
    extra = nil, extraStrength = -1,
    blur = false,
    shake = false, shakeAmp = 0,
}
local cam = nil   -- { handle, angle, gen }

local function fxCfg()
    local e = Config.WoundedUI and Config.WoundedUI.effects
    return type(e) == 'table' and e or {}
end

-- ════════════════════════════════════════════════════════════════════════
-- PRIMITIVES
-- ════════════════════════════════════════════════════════════════════════

local function setTimecycle(name, strength)
    if not name or strength <= 0 then
        if applied.tc then ClearTimecycleModifier() end
        applied.tc, applied.tcStrength = nil, -1
        return
    end
    if applied.tc ~= name then
        SetTimecycleModifier(name)
        applied.tc = name
        applied.tcStrength = -1
    end
    if math.abs(applied.tcStrength - strength) >= 0.02 then
        SetTimecycleModifierStrength(strength + 0.0)
        applied.tcStrength = strength
    end
end

local function setExtra(name, strength)
    if not name or strength <= 0 then
        if applied.extra then ClearExtraTimecycleModifier() end
        applied.extra, applied.extraStrength = nil, -1
        return
    end
    if applied.extra ~= name then
        SetExtraTimecycleModifier(name)
        applied.extra = name
        applied.extraStrength = -1
    end
    if math.abs(applied.extraStrength - strength) >= 0.02 then
        SetExtraTimecycleModifierStrength(strength + 0.0)
        applied.extraStrength = strength
    end
end

local function setBlur(on)
    if on and not applied.blur then
        TriggerScreenblurFadeIn(1600.0)
        applied.blur = true
    elseif not on and applied.blur then
        TriggerScreenblurFadeOut(1200.0)
        applied.blur = false
    end
end

local function setShake(amp)
    if amp <= 0 then
        if applied.shake then StopGameplayCamShaking(false) end
        applied.shake, applied.shakeAmp = false, 0
        return
    end
    if not applied.shake or not IsGameplayCamShaking() then
        ShakeGameplayCam('DRUNK_SHAKE', amp + 0.0)
        applied.shake, applied.shakeAmp = true, amp
    elseif math.abs(applied.shakeAmp - amp) >= 0.04 then
        SetGameplayCamShakeAmplitude(amp + 0.0)
        applied.shakeAmp = amp
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- UPDATE / CLEAR
-- ════════════════════════════════════════════════════════════════════════

function F.Clear()
    setTimecycle(nil, 0)
    setExtra(nil, 0)
    setBlur(false)
    setShake(0)
end

function F.Update()
    local S = W.S or {}
    local mode = S.mode
    if not mode or S.leaving then
        F.Clear()
        return
    end
    local fx = fxCfg()
    local snap = S.snap or {}
    local sfx = type(snap.fx) == 'table' and snap.fx or {}
    local tunnel = U.clamp(tonumber(sfx.tunnel) or 0, 0, 1)
    local bleed = tonumber(S.sum and S.sum.bleed) or 0
    local unconscious = W.Unconscious and W.Unconscious() or false
    local mono = (mode == 'arrest' or mode == 'dead') and fx.arrestMono ~= false

    if fx.timecycle ~= false then
        local strength
        if mono then
            strength = 1.0
        else
            strength = 0.22 + 0.62 * tunnel + (bleed >= 3 and 0.08 or 0) + (unconscious and 0.1 or 0)
        end
        setTimecycle(fx.bloodModifier or 'rply_saturation_neg', U.clamp(strength, 0, 1))
        local vig
        if mode == 'dead' then vig = 0.75
        elseif mode == 'arrest' then vig = 0.9
        else vig = 0.28 + tunnel * 0.55 + (unconscious and 0.2 or 0) end
        setExtra(fx.vignetteModifier or 'rply_vignette', U.clamp(vig, 0, 1))
    else
        setTimecycle(nil, 0)
        setExtra(nil, 0)
    end

    setBlur(fx.unconsciousBlur ~= false and unconscious and mode ~= 'dead')

    if fx.cameraShake ~= false and mode == 'wounded' and not unconscious then
        setShake(U.clamp(0.12 + tunnel * 0.4, 0, 0.6))
    else
        setShake(0)
    end

    if W.HudOpen and W.HudOpen() then
        NZA.UI.Send('wounded', 'fx', {
            mode = mode,
            tunnel = U.round(tunnel, 2),
            bleed = bleed,
            unconscious = unconscious,
            cpr = W.CprActive and W.CprActive() or false,
            stab = S.sum and S.sum.stab == true or false,
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- DEATH CAMERA
-- ════════════════════════════════════════════════════════════════════════

local function camTarget(ped)
    local c = GetEntityCoords(ped)
    return vector3(c.x, c.y, c.z + 0.1)
end

-- keeps the camera under ceilings and out of walls
local function camPosition(ped, angle, dc)
    local base = camTarget(ped)
    local r = tonumber(dc.radius) or 2.6
    local h = tonumber(dc.height) or 4.2
    local rad = math.rad(angle)
    local want = vector3(base.x + math.cos(rad) * r, base.y + math.sin(rad) * r, base.z + h)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(base.x, base.y, base.z + 0.4, want.x, want.y, want.z, 1 + 16, ped, 4)
    local _, hit, hitPos = GetShapeTestResult(handle)
    if (hit == 1 or hit == true) and hitPos then
        local dir = want - base
        local len = #dir
        local hitLen = #(hitPos - base)
        local keep = math.max(0.8, hitLen - 0.35)
        if len > 0 then want = base + dir * (keep / len) end
    end
    return want
end

function F.DeathCam(on)
    local dc = Config.WoundedUI and Config.WoundedUI.deathCam
    dc = type(dc) == 'table' and dc or {}
    if on then
        if cam or dc.enabled == false then return end
        local ped = PlayerPedId()
        local handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(handle, (tonumber(dc.fov) or 50.0) + 0.0)
        local state = { handle = handle, angle = GetEntityHeading(ped) + 120.0 }
        cam = state
        local pos = camPosition(ped, state.angle, dc)
        SetCamCoord(handle, pos.x, pos.y, pos.z)
        local t = camTarget(ped)
        PointCamAtCoord(handle, t.x, t.y, t.z)
        SetCamActive(handle, true)
        RenderScriptCams(true, true, 1800, true, false)
        CreateThread(function()
            local last = GetGameTimer()
            local nextProbe = 0
            local target = pos
            local smooth = pos
            while cam == state do
                local now = GetGameTimer()
                local dt = math.min(0.1, (now - last) / 1000)
                last = now
                local p = PlayerPedId()
                state.angle = (state.angle + (tonumber(dc.speed) or 2.5) * dt) % 360.0
                if now >= nextProbe then
                    target = camPosition(p, state.angle, dc)
                    nextProbe = now + 120
                end
                smooth = smooth + (target - smooth) * math.min(1.0, dt * 4.0)
                SetCamCoord(handle, smooth.x, smooth.y, smooth.z)
                local tt = camTarget(p)
                PointCamAtCoord(handle, tt.x, tt.y, tt.z)
                Wait(0)
            end
        end)
    else
        if not cam then return end
        local handle = cam.handle
        cam = nil
        RenderScriptCams(false, true, 900, true, false)
        SetCamActive(handle, false)
        SetTimeout(1000, function()
            if DoesCamExist(handle) then DestroyCam(handle, false) end
        end)
    end
end

function F.DeathCamActive()
    return cam ~= nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    F.Clear()
    if cam then
        local handle = cam.handle
        cam = nil
        RenderScriptCams(false, false, 0, true, false)
        if DoesCamExist(handle) then DestroyCam(handle, false) end
    end
end)
