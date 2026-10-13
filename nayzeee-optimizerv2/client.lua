--[[
    NAYZEEE OPTIMIZER - Client
    Version: 1.1.0

    PERFORMANCE NOTES:
    - Single Wait(0) thread, only active when per-frame natives are needed
    - FPS is measured from GetFrameCount() deltas, so it is always correct
      even when nothing needs per-frame work
    - Every persistent native (shadows, light cutoff, blackout, cops, Potato
      timecycle) goes through ApplyPersistentState(), which only touches a
      native on a real transition and reverts everything on resource stop
    - All cleanup merged into one slow thread (2s interval)
    - Entity cleanup only removes ambient-population entities this client
      controls, never near another player
]]

-- Resource name lock (see lock.lua). Fails closed: if lock.lua was removed
-- from the manifest the global won't exist and this still refuses to load.
if type(NayZeeeResourceLock) ~= 'function' or not NayZeeeResourceLock() then
    return
end

local RES = GetCurrentResourceName()
local KVP_SETTINGS = 'nayzeee_optimizer_settings'
local KVP_BENCH    = 'nayzeee_optimizer_bench'

local settings = {}
local nuiReady = false
local menuOpen = false
local isAdmin = false
local adminChecked = false

-- Kill marker state
local killTable = {}

-- Hit particle state
local pendingHitParticles = {}
local activeHitPtfx = {}

-- Cached ped (updated once per frame in main thread)
local cachedPed = PlayerPedId()
local cachedCoords = vector3(0, 0, 0)

-- Background optimization state
local bgAmbientScale = 1.0

-- Idle / AFK state
local isAfk = false
local isUnfocused = false
local lastInputTime = 0

-- Adaptive optimizer state
local adaptiveLevel = 0
local adaptiveNotified = false

-- Session state
local sessionStart = 0
local advisoriesShown = {}
local fpsCapWarned = false

-- FPS tracking (GetFrameCount based, always live)
local fps = 0

-- Frame-time sampler (benchmark, telemetry, health grade)
local sampler = { active = false }

-- Benchmark
local benchmark = { running = false, results = {}, preset = nil, endAt = 0 }

-- Texture fix
local fixInProgress = false
local fixState = nil

-- Conflicts detected on last open: key -> { resource, message }
local conflicts = {}

-- Probe reports from other resources (client side)
local probeData = {}
local probeMem = {}

-- Health tab
local healthOpen = false
local lastClientGrade = nil

-- ═══════════════════════════════════════════════════════════════════════════════
--  INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════════

local function IsLocked(key)
    return Config.Locked ~= nil and Config.Locked[key] ~= nil
end

local function ApplyLocks()
    if not Config.Locked then return end
    for k, v in pairs(Config.Locked) do
        if settings[k] ~= nil then settings[k] = v end
    end
end

local function LoadSettings()
    local saved = GetResourceKvpString(KVP_SETTINGS)
    local decoded = saved and json.decode(saved) or nil
    if type(decoded) ~= 'table' then decoded = {} end

    -- NOTE: do not use `a ~= nil and a or b` here: it drops saved `false`.
    for k, v in pairs(Config.DefaultSettings) do
        local sv = decoded[k]
        if sv ~= nil and type(sv) == type(v) then
            settings[k] = sv
        else
            settings[k] = v
        end
    end
    ApplyLocks()

    local bench = GetResourceKvpString(KVP_BENCH)
    local b = bench and json.decode(bench) or nil
    benchmark.results = type(b) == 'table' and b or {}
end

local function SaveSettings()
    SetResourceKvp(KVP_SETTINGS, json.encode(settings))
end

local function SaveBench()
    SetResourceKvp(KVP_BENCH, json.encode(benchmark.results))
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════

local function Notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function GetParticleData(id)
    for _, p in ipairs(Config.HitParticles) do
        if p.id == id then return p end
    end
    return Config.HitParticles[1]
end

local function InList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function EffectiveCap()
    local c = tonumber(settings.frameCapTarget) or 0
    if c <= 0 then c = tonumber(settings.specHz) or 0 end
    return c
end

-- Validates a single setting write from any source (NUI, import, export API).
-- Returns true when applied.
local function SetSettingValidated(key, value)
    if type(key) ~= 'string' then return false end
    local def = Config.DefaultSettings[key]
    if def == nil then return false end
    if IsLocked(key) then return false end
    if type(value) ~= type(def) then return false end

    if key == 'killFx' or key == 'hitFx' then
        if not InList(Config.ScreenFX, value) then return false end
    elseif key == 'killSoundId' then
        if not InList(Config.KillSounds, value) then return false end
    elseif key == 'hitSoundId' then
        if not InList(Config.HitSounds, value) then return false end
    elseif key == 'hitParticleId' then
        if not GetParticleData(value) or GetParticleData(value).id ~= value then return false end
    elseif key == 'killSoundVolume' then
        value = math.max(0, math.min(Config.MaxKillSoundVolume or 100, math.floor(value)))
    elseif key == 'hitSoundVolume' then
        value = math.max(0, math.min(Config.MaxHitSoundVolume or 100, math.floor(value)))
    elseif key == 'frameCapTarget' then
        value = math.max(0, math.floor(value))
    elseif key == 'activePreset' then
        if value ~= '' and not Config.Presets[value] then return false end
    end

    settings[key] = value
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  PERSISTENT NATIVE STATE
--  Everything that is NOT a *ThisFrame native lives here. Each key only
--  calls natives on a transition, and ApplyPersistentState(true) reverts
--  all of it (resource stop, reset to defaults).
-- ═══════════════════════════════════════════════════════════════════════════════

local applied = { shadows = false, lights = false, cops = false, blackout = false, potato = false }

local function ShadowsOn()
    local s = Config.ShadowScale
    CascadeShadowsClearShadowSampleType()
    RopeDrawShadowEnabled(false)
    CascadeShadowsSetAircraftMode(false)
    CascadeShadowsEnableEntityTracker(false)
    CascadeShadowsSetDynamicDepthMode(false)
    CascadeShadowsSetEntityTrackerScale(s)
    CascadeShadowsSetDynamicDepthValue(s)
    CascadeShadowsSetCascadeBoundsScale(s)
end

local function ShadowsOff()
    CascadeShadowsClearShadowSampleType()
    RopeDrawShadowEnabled(true)
    CascadeShadowsSetAircraftMode(false)
    CascadeShadowsEnableEntityTracker(true)
    CascadeShadowsSetDynamicDepthMode(false)
    CascadeShadowsSetEntityTrackerScale(1.0)
    CascadeShadowsSetDynamicDepthValue(1.0)
    CascadeShadowsSetCascadeBoundsScale(1.0)
end

local function LightsOn()
    SetFlashLightFadeDistance(Config.LightCutoffDistance)
    SetLightsCutoffDistanceTweak(Config.LightCutoffDistance)
end

local function LightsOff()
    SetFlashLightFadeDistance(10.0)
    SetLightsCutoffDistanceTweak(10.0)
end

local function CopsOff()
    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)
end

local function CopsOn()
    SetCreateRandomCops(true)
    SetCreateRandomCopsNotOnScenarios(true)
    SetCreateRandomCopsOnScenarios(true)
end

local function PotatoOn()
    SetTimecycleModifier('yell_tunnel_nodirect')
    SetExtraTimecycleModifier('HicksbarNEW')
    SetPedAoBlobRendering(PlayerPedId(), false)
    DisableVehicleDistantlights(true)
    SetDistantCarsEnabled(false)
    SetFarDrawVehicles(false)
end

local function PotatoOff()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetPedAoBlobRendering(PlayerPedId(), true)
    DisableVehicleDistantlights(false)
    SetDistantCarsEnabled(true)
    SetFarDrawVehicles(true)
end

local function Persist(key, want, onFn, offFn)
    want = want == true
    if applied[key] == want then return end
    applied[key] = want
    if want then onFn() else offFn() end
end

local function ApplyPersistentState(reset)
    local s = reset and {} or settings
    local potato = (not reset) and s.activePreset == 'potato'
    Persist('shadows',  s.optimizeShadows, ShadowsOn, ShadowsOff)
    Persist('lights',   s.optimizeLights,  LightsOn,  LightsOff)
    Persist('cops',     s.optimizeObjects, CopsOff,   CopsOn)
    Persist('blackout', s.ultraMode or potato,
        function() SetArtificialLightsState(true) end,
        function() SetArtificialLightsState(false) end)
    Persist('potato',   potato, PotatoOn, PotatoOff)
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  FRAME-TIME SAMPLER
-- ═══════════════════════════════════════════════════════════════════════════════

local function Summarize(samples)
    local n = #samples
    if n < 10 then return nil end
    local sum, maxFt, stutters = 0, 0, 0
    for i = 1, n do
        local ft = samples[i]
        sum = sum + ft
        if ft > maxFt then maxFt = ft end
        if ft > 50 then stutters = stutters + 1 end
    end
    local mean = sum / n
    table.sort(samples)
    local worstCount = math.max(1, math.floor(n * 0.01))
    local worstSum = 0
    for i = n - worstCount + 1, n do worstSum = worstSum + samples[i] end
    local worstMean = worstSum / worstCount
    return {
        frames   = n,
        avgFps   = math.floor(1000 / mean + 0.5),
        low1Fps  = math.floor(1000 / worstMean + 0.5),
        maxFt    = math.floor(maxFt * 10 + 0.5) / 10,
        stutters = stutters,
    }
end

-- Collects GetFrameTime() for `seconds` seconds then calls cb(summary|nil).
local function SampleFrames(seconds, cb)
    if sampler.active then return false end
    sampler = { active = true, samples = {}, endAt = GetGameTimer() + seconds * 1000, cb = cb }
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  CONFLICTS (other running resources that fight an option)
-- ═══════════════════════════════════════════════════════════════════════════════

local function ComputeConflicts()
    local out = {}
    for _, c in ipairs(Config.Conflicts or {}) do
        local hit
        for _, r in ipairs(c.resources or {}) do
            if GetResourceState(r) == 'started' then hit = r break end
        end
        if hit then
            for _, k in ipairs(c.settings or {}) do out[k] = { resource = hit, message = c.message } end
            for _, a in ipairs(c.actions or {}) do out[a] = { resource = hit, message = c.message } end
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  OPEN / CLOSE MENU
-- ═══════════════════════════════════════════════════════════════════════════════

local function BuildMeta()
    local fc = Config.Background.frameCap or {}
    return {
        fps = fps,
        sessionMinutes = math.floor((GetGameTimer() - sessionStart) / 60000),
        preset = settings.activePreset ~= '' and settings.activePreset or nil,
        frameCapTarget = settings.frameCapTarget or 0,
        overshootMargin = fc.overshootMargin or 25,
        key = Config.Key,
        isAdmin = isAdmin,
        benchDuration = (Config.Benchmark and Config.Benchmark.duration) or 30,
    }
end

local function BuildOpenPayload(forceSetupDone)
    local setupCfg = Config.Background.setup or {}
    local sendSettings = settings
    if (setupCfg.enabled == false or forceSetupDone) and not settings.setupDone then
        sendSettings = {}
        for k, v in pairs(settings) do sendSettings[k] = v end
        sendSettings.setupDone = true
    end

    conflicts = ComputeConflicts()

    local lockedKeys = {}
    for k, _ in pairs(Config.Locked or {}) do lockedKeys[#lockedKeys + 1] = k end

    return {
        action   = 'open',
        settings = sendSettings,
        theme    = Config.UI,
        meta     = BuildMeta(),
        locked   = lockedKeys,
        impact   = Config.Impact or {},
        conflicts = conflicts,
        presets  = Config.Presets,
        bench    = benchmark.results,
        ui = {
            setup = {
                allowAutoDetect = setupCfg.allowAutoDetect ~= false,
                allowSkip = setupCfg.allowSkip ~= false,
            },
            graphicsTab = not (Config.Background.graphicsTab and Config.Background.graphicsTab.enabled == false),
            frameCap = {
                enabled = not (Config.Background.frameCap and Config.Background.frameCap.enabled == false),
                targets = (Config.Background.frameCap and Config.Background.frameCap.targets) or { 60, 75, 90, 120, 144, 165, 240 },
            },
            textureFix = not (Config.Background.textureFix and Config.Background.textureFix.enabled == false),
            telemetry = Config.Health and Config.Health.enabled and Config.Health.clientTelemetry or false,
            health = Config.Health and Config.Health.enabled or false,
        },
    }
end

local function OpenMenu(forceSetupDone)
    if not nuiReady or menuOpen then return end
    menuOpen = true
    SetNuiFocus(true, true)
    if not adminChecked then
        adminChecked = true
        TriggerServerEvent('nayzeee-optimizer:admin:check')
    end
    SendNUIMessage(BuildOpenPayload(forceSetupDone))
end

local function CloseMenu()
    if not menuOpen then return end
    menuOpen = false
    healthOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function PushSettings()
    SendNUIMessage({
        action = 'updateSettings',
        settings = settings,
        preset = settings.activePreset ~= '' and settings.activePreset or nil,
    })
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  PRESETS / RESET
-- ═══════════════════════════════════════════════════════════════════════════════

local function ApplyPreset(name)
    if not Config.Presets[name] then return false end
    for k, v in pairs(Config.Presets[name]) do
        if settings[k] ~= nil and not IsLocked(k) then settings[k] = v end
    end
    settings.activePreset = name
    ApplyLocks()
    ApplyPersistentState()
    SaveSettings()
    PushSettings()
    return true
end

local function ResetToDefaults()
    local keep = {
        setupDone = true, specGpu = true, specThreads = true, specRam = true,
        specWidth = true, specHeight = true, specHz = true, specTier = true, specGuessed = true,
    }
    for k, v in pairs(Config.DefaultSettings) do
        if not keep[k] then settings[k] = v end
    end
    ApplyLocks()
    ApplyPersistentState()
    SaveSettings()
    PushSettings()
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  NUI CALLBACKS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    healthOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('toggle', function(data, cb)
    if type(data) == 'table' and type(data.value) == 'boolean' and SetSettingValidated(data.setting, data.value) then
        settings.activePreset = ''
        ApplyPersistentState()
        SaveSettings()
        cb({ ok = true })
    else
        -- Rejected (locked / invalid): tell the UI the real state
        PushSettings()
        cb({ ok = false, locked = IsLocked(type(data) == 'table' and data.setting or nil) })
    end
end)

RegisterNUICallback('preset', function(data, cb)
    if type(data) == 'table' and ApplyPreset(data.preset) then cb({ ok = true }) else cb({ ok = false }) end
end)

RegisterNUICallback('resetDefaults', function(_, cb)
    ResetToDefaults()
    Notify('~b~Optimizer~s~: settings reset to defaults.')
    cb('ok')
end)

RegisterNUICallback('importSettings', function(data, cb)
    local incoming = type(data) == 'table' and data.settings or nil
    if type(incoming) ~= 'table' then cb({ ok = false, error = 'Invalid code' }) return end

    local skip = {
        setupDone = true, specGpu = true, specThreads = true, specRam = true, specWidth = true,
        specHeight = true, specHz = true, specTier = true, specGuessed = true, shareTelemetry = true,
    }
    local applied, rejected = 0, 0
    for k, v in pairs(incoming) do
        if not skip[k] and k ~= 'activePreset' then
            if SetSettingValidated(k, v) then applied = applied + 1 else rejected = rejected + 1 end
        end
    end
    if type(incoming.activePreset) == 'string' and Config.Presets[incoming.activePreset] then
        settings.activePreset = incoming.activePreset
    else
        settings.activePreset = ''
    end
    ApplyLocks()
    ApplyPersistentState()
    SaveSettings()
    PushSettings()
    cb({ ok = applied > 0, applied = applied, rejected = rejected })
end)

RegisterNUICallback('setupDone', function(_, cb)
    settings.setupDone = true
    SaveSettings()
    cb('ok')
end)

RegisterNUICallback('saveSpec', function(data, cb)
    data = type(data) == 'table' and data or {}
    settings.specGpu     = tostring(data.gpu or ''):sub(1, 120)
    settings.specThreads = tonumber(data.threads) or 0
    settings.specRam     = tostring(data.ram or ''):sub(1, 32)
    settings.specWidth   = tonumber(data.width) or 0
    settings.specHeight  = tonumber(data.height) or 0
    settings.specHz      = tonumber(data.hz) or 0
    settings.specTier    = tostring(data.tier or ''):sub(1, 16)
    settings.specGuessed = data.guessed == true
    SaveSettings()
    cb('ok')
end)

RegisterNUICallback('setEffectValue', function(data, cb)
    if type(data) == 'table' and SetSettingValidated(data.setting, data.value) then
        SaveSettings()
        cb({ ok = true })
    else
        PushSettings()
        cb({ ok = false })
    end
end)

RegisterNUICallback('setFrameCapTarget', function(data, cb)
    -- Records intent only. FiveM exposes no native or convar to apply a cap.
    local t = type(data) == 'table' and tonumber(data.target) or 0
    SetSettingValidated('frameCapTarget', math.floor(t or 0))
    SaveSettings()
    cb('ok')
end)

RegisterNUICallback('previewScreenFx', function(data, cb)
    if type(data) == 'table' and InList(Config.ScreenFX, data.fx) then
        AnimpostfxPlay(data.fx, 0, false)
        local fx = data.fx
        SetTimeout(1500, function() AnimpostfxStop(fx) end)
    end
    cb('ok')
end)

RegisterNUICallback('previewParticle', function(data, cb)
    local pData = type(data) == 'table' and GetParticleData(data.id) or nil
    cb('ok')
    if not pData then return end
    CreateThread(function()
        if not HasNamedPtfxAssetLoaded(pData.dict) then
            RequestNamedPtfxAsset(pData.dict)
            local t = GetGameTimer() + 3000
            while not HasNamedPtfxAssetLoaded(pData.dict) do
                if GetGameTimer() > t then return end
                Wait(10)
            end
        end
        local c = GetPedBoneCoords(cachedPed, 31086, 0.0, 0.0, 0.0)
        UseParticleFxAssetNextCall(pData.dict)
        local h = StartParticleFxLoopedAtCoord(pData.name, c.x, c.y, c.z, 0.0, 0.0, 0.0, Config.HitParticleScale, false, false, false, false)
        if h ~= 0 then
            SetTimeout(1200, function()
                if DoesParticleFxLoopedExist(h) then StopParticleFxLooped(h, false) end
            end)
        end
    end)
end)

-- ── Fix textures ───────────────────────────────────────────────────────────────

local function RestoreFixState(timedOut)
    local st = fixState
    if not st or st.restored then return end
    st.restored = true
    SetEntityCollision(st.entity, true, true)
    FreezeEntityPosition(st.entity, false)
    if st.inVeh then FreezeEntityPosition(st.veh, false) end
    SetEntityInvincible(st.ped, false)
    ClearFocus()
    NewLoadSceneStop()
    DoScreenFadeIn(500)
    fixInProgress = false
    if timedOut then
        Notify('~b~Optimizer~s~: texture reload timed out, control restored.')
    end
end

RegisterNUICallback('fixTextures', function(_, cb)
    cb('ok')
    if Config.Background.textureFix and Config.Background.textureFix.enabled == false then return end
    if fixInProgress then return end
    fixInProgress = true

    -- Release NUI focus immediately — the player must never be left with a
    -- stuck cursor while this runs.
    menuOpen = false
    healthOpen = false
    SetNuiFocus(false, false)

    CreateThread(function()
        local ped      = PlayerPedId()
        local veh      = GetVehiclePedIsIn(ped, false)
        local inVeh    = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        local entity   = inVeh and veh or ped
        local origin   = GetEntityCoords(ped)
        local heading  = GetEntityHeading(entity)
        fixState = { ped = ped, veh = veh, inVeh = inVeh, entity = entity, restored = false }
        local st = fixState

        -- Watchdog: if anything stalls, give the player control back.
        SetTimeout(20000, function() if not st.restored then RestoreFixState(true) end end)

        DoScreenFadeOut(500)
        local fadeTimeout = GetGameTimer() + 3000
        while not IsScreenFadedOut() do
            if GetGameTimer() > fadeTimeout then break end
            Wait(0)
        end

        SetEntityInvincible(ped, true)
        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, false, false)
        if inVeh then FreezeEntityPosition(veh, true) end

        -- Step 1: move far away so GTA drops every streamed texture here
        SetEntityCoordsNoOffset(entity, origin.x, origin.y, origin.z + 1500.0, false, false, false)
        ClearHdArea()
        ClearFocus()
        Wait(600)

        -- Step 2: release what the engine was holding
        for _, v in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(v) and v ~= veh then
                SetModelAsNoLongerNeeded(GetEntityModel(v))
            end
        end
        for _, o in ipairs(GetGamePool('CObject')) do
            if DoesEntityExist(o) then
                SetModelAsNoLongerNeeded(GetEntityModel(o))
            end
        end
        collectgarbage('collect')
        Wait(400)

        -- Step 3: back to the exact original position
        SetEntityCoordsNoOffset(entity, origin.x, origin.y, origin.z, false, false, false)
        SetEntityHeading(entity, heading)

        -- Step 4: clean streaming load at the original spot
        SetFocusPosAndVel(origin.x, origin.y, origin.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(origin.x, origin.y, origin.z)
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            RequestCollisionAtCoord(origin.x + math.cos(rad) * 50.0, origin.y + math.sin(rad) * 50.0, origin.z)
        end

        NewLoadSceneStartSphere(origin.x, origin.y, origin.z, 350.0, 0)
        local sceneTimeout = GetGameTimer() + 6000
        while not IsNewLoadSceneLoaded() do
            if GetGameTimer() > sceneTimeout then break end
            Wait(50)
        end
        NewLoadSceneStop()

        -- Step 5: wait for ground collision
        local collTimeout = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(entity) do
            if GetGameTimer() > collTimeout then break end
            Wait(50)
        end

        -- Step 6: lock HD textures in around the player
        SetHdArea(origin.x, origin.y, origin.z, 300.0)

        -- Step 7: brief LOD boost to pull in the highest mips
        for _ = 1, 60 do
            OverrideLodscaleThisFrame(2.0)
            Wait(0)
        end

        if st.restored then fixInProgress = false return end
        st.restored = true
        SetEntityCollision(entity, true, true)
        FreezeEntityPosition(entity, false)
        if inVeh then FreezeEntityPosition(veh, false) end
        SetEntityCoordsNoOffset(entity, origin.x, origin.y, origin.z, false, false, false)
        SetEntityHeading(entity, heading)

        ClearFocus()
        SetFocusEntity(ped)

        DoScreenFadeIn(600)
        while IsScreenFadingIn() do Wait(0) end
        SetEntityInvincible(ped, false)

        Notify('~b~Optimizer~s~: textures reloaded.')
        fixInProgress = false
        fixState = nil
    end)
end)

-- ── Benchmark ──────────────────────────────────────────────────────────────────

local function StartBenchmark()
    if benchmark.running or sampler.active then return false end
    local dur = (Config.Benchmark and Config.Benchmark.duration) or 30
    local cd  = (Config.Benchmark and Config.Benchmark.countdown) or 3
    benchmark.running = true
    benchmark.preset = settings.activePreset ~= '' and settings.activePreset or 'custom'
    benchmark.endAt = GetGameTimer() + (cd + dur) * 1000
    CloseMenu()
    Notify(('~b~Optimizer~s~: benchmark starts in %d seconds. Play normally for %d seconds.'):format(cd, dur))

    CreateThread(function()
        Wait(cd * 1000)
        local presetKey = benchmark.preset
        SampleFrames(dur, function(sum)
            benchmark.running = false
            if not sum then
                Notify('~b~Optimizer~s~: benchmark failed, not enough frames.')
                return
            end
            sum.at = os and os.time and os.time() or 0
            sum.preset = presetKey
            benchmark.results[presetKey] = sum
            SaveBench()
            Notify(('~b~Optimizer~s~: benchmark done. ~g~%d~s~ avg fps, ~y~%d~s~ 1%% low.'):format(sum.avgFps, sum.low1Fps))
            SendNUIMessage({ action = 'benchResult', result = sum, results = benchmark.results })
        end)
    end)
    return true
end

RegisterNUICallback('benchmark', function(_, cb)
    cb({ ok = StartBenchmark() })
end)

RegisterNUICallback('clearBenchmarks', function(_, cb)
    benchmark.results = {}
    SaveBench()
    cb('ok')
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  SOUND PLAYBACK
-- ═══════════════════════════════════════════════════════════════════════════════

local function PlayKillSound()
    if not settings.killEnabled or not settings.killSoundEnabled then return end
    SendNUIMessage({ action = 'playSound', soundId = settings.killSoundId, volume = math.min(settings.killSoundVolume, Config.MaxKillSoundVolume) })
end

local function PlayHitSound()
    if not settings.hitEnabled or not settings.hitSoundEnabled then return end
    SendNUIMessage({ action = 'playSound', soundId = settings.hitSoundId, volume = math.min(settings.hitSoundVolume, Config.MaxHitSoundVolume) })
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  KILL & HIT DETECTION (event-based only, no polling)
-- ═══════════════════════════════════════════════════════════════════════════════

AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' then return end
    if not settings.hitEnabled and not settings.killEnabled then return end

    local victim, attacker, isDead = data[1], data[2], data[6]

    if not DoesEntityExist(victim) or not IsEntityAPed(victim) or victim == cachedPed then return end

    local isMyHit = (attacker == cachedPed)
    if not isMyHit and DoesEntityExist(attacker) and IsEntityAVehicle(attacker) then
        isMyHit = (GetPedInVehicleSeat(attacker, -1) == cachedPed)
    end
    if not isMyHit then return end

    local fatal = (isDead == 1 or isDead == true)

    -- Hit effects (kill sound takes over on a fatal hit so both don't stack)
    if settings.hitEnabled then
        if settings.hitScreen and settings.hitFx then
            AnimpostfxPlay(settings.hitFx, 0, false)
            local fx = settings.hitFx
            SetTimeout(Config.HitEffect.screenDuration, function() AnimpostfxStop(fx) end)
        end
        if settings.hitParticle then
            local _, hitBone = GetPedLastDamageBone(victim)
            local bc = (hitBone and hitBone ~= 0) and GetPedBoneCoords(victim, hitBone, 0.0, 0.0, 0.0) or GetEntityCoords(victim)
            local pData = GetParticleData(settings.hitParticleId)
            if pData then
                pendingHitParticles[#pendingHitParticles + 1] = { x = bc.x, y = bc.y, z = bc.z, dict = pData.dict, name = pData.name, scale = Config.HitParticleScale }
            end
        end
        if not (fatal and settings.killEnabled and settings.killSoundEnabled) then
            PlayHitSound()
        end
    end

    -- Kill effects
    if fatal and settings.killEnabled then
        if settings.killMarker then
            local c = GetPedBoneCoords(victim, 31086, 0.0, 0.0, 0.0)
            killTable[#killTable + 1] = { x = c.x, y = c.y, z = c.z, expire = GetGameTimer() + (Config.KillEffect.markerDuration * 1000) }
        end
        if settings.killScreen and settings.killFx then
            AnimpostfxPlay(settings.killFx, 0, false)
            local fx = settings.killFx
            SetTimeout(Config.KillEffect.screenDuration, function() AnimpostfxStop(fx) end)
        end
        PlayKillSound()
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  FPS MEASUREMENT (frame-count based, zero per-frame cost)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local lastFrames, lastTime = GetFrameCount(), GetGameTimer()
    while true do
        Wait(500)
        local f, t = GetFrameCount(), GetGameTimer()
        local dt = t - lastTime
        if dt > 0 then
            fps = math.floor((f - lastFrames) * 1000 / dt + 0.5)
        end
        lastFrames, lastTime = f, t
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  MAIN RENDER THREAD (single Wait(0), only when needed)
-- ═══════════════════════════════════════════════════════════════════════════════

local function DrawHudText(text, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

CreateThread(function()
    while true do
        cachedPed = PlayerPedId()

        -- Frame-time sampling (benchmark / telemetry / health). Runs before
        -- the AFK branch so a benchmark is never cut short.
        if sampler.active then
            local s = sampler
            s.samples[#s.samples + 1] = GetFrameTime() * 1000.0
            if GetGameTimer() >= s.endAt then
                sampler = { active = false }
                local summary = Summarize(s.samples)
                if s.cb then s.cb(summary) end
            end
            if benchmark.running then
                local left = math.max(0, math.ceil((benchmark.endAt - GetGameTimer()) / 1000))
                DrawHudText(('BENCHMARK  %ds'):format(left), 0.5, 0.02, 0.45, Config.FPSColor.r, Config.FPSColor.g, Config.FPSColor.b)
            end
        end

        -- AFK / unfocused throttle takes priority over everything else
        local idleCfg = Config.Background.idle
        local throttled = (idleCfg and idleCfg.enabled) and (isAfk or isUnfocused) and not sampler.active or false

        if throttled then
            -- *ThisFrame natives last exactly one frame and must be re-applied
            -- every frame; running them on a timer makes LOD/density oscillate.
            local d = idleCfg.afkDensity or 0.0
            SetPedDensityMultiplierThisFrame(d)
            SetScenarioPedDensityMultiplierThisFrame(d, d)
            SetVehicleDensityMultiplierThisFrame(d)
            SetRandomVehicleDensityMultiplierThisFrame(d)
            SetParkedVehicleDensityMultiplierThisFrame(d)

            -- LOD only for a genuine AFK player; the pause menu shows the world.
            if isAfk and not isUnfocused then
                OverrideLodscaleThisFrame(idleCfg.afkLodScale or 0.1)
                DisableOcclusionThisFrame()
                SetDisableDecalRenderingThisFrame()
            end

            Wait(0)
            goto continue
        end

        local needsFrame = settings.optimizePeds or settings.optimizeVehicles
            or settings.lowTextures or settings.ultraMode or settings.showFPS
            or adaptiveLevel > 0 or menuOpen or sampler.active
            or (#killTable > 0 and settings.killEnabled and settings.killMarker)
            or (Config.Background.enabled and Config.Background.ambientScaling and bgAmbientScale < 1.0)

        if needsFrame then
            -- Adaptive escalation applies on top of everything
            if adaptiveLevel > 0 then
                local aLod = 1.0 - (adaptiveLevel * 0.2)   -- L1 0.8, L2 0.6, L3 0.4
                local aDen = 1.0 - (adaptiveLevel * 0.25)  -- L1 0.75, L2 0.5, L3 0.25
                OverrideLodscaleThisFrame(aLod)
                SetPedDensityMultiplierThisFrame(aDen)
                SetVehicleDensityMultiplierThisFrame(aDen)
                if adaptiveLevel >= 2 then DisableOcclusionThisFrame() end
                if adaptiveLevel >= 3 then SetDisableDecalRenderingThisFrame() end
            end

            -- Density (player toggles override, background scaling applies otherwise)
            if settings.optimizePeds then
                local m = settings.ultraMode and Config.UltraDensityMultiplier or Config.DensityMultiplier
                SetPedDensityMultiplierThisFrame(m)
                SetScenarioPedDensityMultiplierThisFrame(m, m)
            elseif bgAmbientScale < 1.0 then
                SetPedDensityMultiplierThisFrame(bgAmbientScale)
                SetScenarioPedDensityMultiplierThisFrame(bgAmbientScale, bgAmbientScale)
            end

            if settings.optimizeVehicles then
                local m = settings.ultraMode and Config.UltraDensityMultiplier or Config.DensityMultiplier
                SetVehicleDensityMultiplierThisFrame(m)
                SetRandomVehicleDensityMultiplierThisFrame(m)
                SetParkedVehicleDensityMultiplierThisFrame(m)
            elseif bgAmbientScale < 1.0 then
                SetVehicleDensityMultiplierThisFrame(bgAmbientScale)
                SetRandomVehicleDensityMultiplierThisFrame(bgAmbientScale)
                SetParkedVehicleDensityMultiplierThisFrame(bgAmbientScale)
            end

            -- LOD
            if settings.lowTextures then
                local lod = settings.ultraMode and Config.UltraLODScale or Config.LODScale
                OverrideLodscaleThisFrame(lod)
                DisableOcclusionThisFrame()
                SetDisableDecalRenderingThisFrame()
            end

            -- Ultra (persistent blackout handled by ApplyPersistentState)
            if settings.ultraMode then
                OverrideLodscaleThisFrame(Config.UltraLODScale)
                SetPedDensityMultiplierThisFrame(Config.UltraDensityMultiplier)
                SetVehicleDensityMultiplierThisFrame(Config.UltraDensityMultiplier)
            end

            -- FPS counter display
            if settings.showFPS then
                DrawHudText('FPS: ' .. fps, Config.FPSPosition.x, Config.FPSPosition.y, Config.FPSScale,
                    Config.FPSColor.r, Config.FPSColor.g, Config.FPSColor.b)
            end

            -- Kill markers
            if #killTable > 0 and settings.killEnabled and settings.killMarker then
                local now = GetGameTimer()
                local c = Config.KillEffect.markerColor
                local s = Config.KillEffect.markerScale
                for i = #killTable, 1, -1 do
                    local k = killTable[i]
                    if now >= k.expire then
                        table.remove(killTable, i)
                    else
                        k.z = k.z + Config.KillEffect.markerSpeed
                        DrawMarker(25, k.x, k.y, k.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s, s, s, c.r, c.g, c.b, c.a, false, true, 2, false, nil, nil, false)
                        DrawMarker(2, k.x, k.y, k.z + s, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, s*0.3, s*0.3, s*0.3, c.r, c.g, c.b, c.a, false, true, 2, false, nil, nil, false)
                    end
                end
            end

            Wait(0)
        else
            Wait(500)
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  SLOW CLEANUP THREAD (merged, runs every 2 seconds)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(2000)

        if not nuiReady then goto continue end

        cachedCoords = GetEntityCoords(cachedPed)

        if settings.clearBrokenGlass then ClearAllBrokenGlass() end

        if settings.cleanPedEffects then
            ClearPedBloodDamage(cachedPed)
            ClearPedWetness(cachedPed)
            ClearPedEnvDirt(cachedPed)
            ResetPedVisibleDamage(cachedPed)
        end

        -- "Clear Cache": only caches that belong to nobody. ClearHelp /
        -- ClearPrints / ClearGpsFlags were removed: they wiped other scripts'
        -- help prompts, subtitles and GPS routes every 2 seconds.
        if settings.clearUnnecessary then
            ClearBrief()
            ClearReplayStats()
            LeaderboardsReadClearAll()
            LeaderboardsClearCacheData()
        end

        -- Rain: intensity override only. Forcing EXTRASUNNY was removed
        -- because it fights every weather-sync script (flickering weather).
        if settings.disableRain then
            SetRainLevel(0.0)
        end

        if settings.disableWind then
            SetWindSpeed(0.0)
        end

        if settings.disableBloodStains then
            ClearPedBloodDamage(cachedPed)
        end

        -- Fire extinguishing moved here from the per-frame loop
        if settings.disableFireEffects then
            StopFireInRange(cachedCoords.x, cachedCoords.y, cachedCoords.z, 500.0)
        end

        if settings.removeParticles then
            RemoveParticleFxInRange(cachedCoords.x, cachedCoords.y, cachedCoords.z, Config.ParticleRemoveRange)
        end

        if settings.disableDecals then
            RemoveDecalsInRange(cachedCoords.x, cachedCoords.y, cachedCoords.z, 100.0)
        end

        -- Other scripts may change the light cutoff; keep ours applied while on
        if settings.optimizeLights then LightsOn() end

        -- Expire stale kill markers even if rendering is off
        if #killTable > 0 then
            local now = GetGameTimer()
            for i = #killTable, 1, -1 do
                if now >= killTable[i].expire then table.remove(killTable, i) end
            end
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  ENTITY DELETION HELPERS
--  Only ambient population (random/parked/scenario/patrol/permanent), only
--  entities we control, never a player vehicle, never near another player.
-- ═══════════════════════════════════════════════════════════════════════════════

local AMBIENT_POP = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

local function IsAmbient(ent)
    return AMBIENT_POP[GetEntityPopulationType(ent)] == true
end

local function NearAnyOtherPlayer(coords, range)
    local me = PlayerId()
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= me then
            local p = GetPlayerPed(id)
            if p ~= 0 and #(GetEntityCoords(p) - coords) < range then return true end
        end
    end
    return false
end

local function VehicleHasPlayer(veh)
    local seats = GetVehicleMaxNumberOfPassengers(veh)
    for seat = -1, seats - 1 do
        local occupant = GetPedInVehicleSeat(veh, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end

local function CanRemoveVehicle(veh, coords, minDist)
    if not DoesEntityExist(veh) then return false end
    if IsEntityAMissionEntity(veh) or not IsAmbient(veh) then return false end
    if not NetworkHasControlOfEntity(veh) then return false end
    if IsPedInVehicle(cachedPed, veh, false) or VehicleHasPlayer(veh) then return false end
    local vc = GetEntityCoords(veh)
    if #(coords - vc) < minDist then return false end
    if NearAnyOtherPlayer(vc, minDist) then return false end
    return true
end

local function CanRemovePed(npc, coords, minDist)
    if npc == cachedPed or not DoesEntityExist(npc) or IsPedAPlayer(npc) then return false end
    if IsEntityAMissionEntity(npc) or not IsAmbient(npc) then return false end
    if not NetworkHasControlOfEntity(npc) then return false end
    if IsPedInAnyVehicle(npc, false) then return false end
    local pc = GetEntityCoords(npc)
    if #(coords - pc) < minDist then return false end
    if NearAnyOtherPlayer(pc, minDist) then return false end
    return true
end

local function RemoveEntity(ent, isVeh)
    SetEntityAsMissionEntity(ent, true, true)
    if isVeh then DeleteVehicle(ent) else DeletePed(ent) end
    if DoesEntityExist(ent) then DeleteEntity(ent) end
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  ENTITY CLEANUP THREAD (player option, runs every 5 seconds)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(5000)

        if not settings.entityCleanup then goto continue end

        local coords = GetEntityCoords(cachedPed)
        local dist = Config.EntityCleanupDistance

        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if not IsEntityOnScreen(vehicle) and CanRemoveVehicle(vehicle, coords, dist) then
                RemoveEntity(vehicle, true)
            end
        end

        for _, npc in ipairs(GetGamePool('CPed')) do
            if not IsEntityOnScreen(npc) and CanRemovePed(npc, coords, dist) then
                RemoveEntity(npc, false)
            end
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  HIT PARTICLE SYSTEM (only wakes when particles exist)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        if #pendingHitParticles > 0 then
            local batch = pendingHitParticles
            pendingHitParticles = {}
            for i = 1, #batch do
                local p = batch[i]
                if not HasNamedPtfxAssetLoaded(p.dict) then
                    RequestNamedPtfxAsset(p.dict)
                    local t = GetGameTimer() + 2000
                    while not HasNamedPtfxAssetLoaded(p.dict) do
                        if GetGameTimer() > t then break end
                        Wait(0)
                    end
                end
                if HasNamedPtfxAssetLoaded(p.dict) then
                    UseParticleFxAssetNextCall(p.dict)
                    local h = StartParticleFxLoopedAtCoord(p.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, p.scale, false, false, false, false)
                    if h ~= 0 then
                        activeHitPtfx[#activeHitPtfx + 1] = { handle = h, expire = GetGameTimer() + Config.HitEffect.particleDuration }
                    end
                end
            end
        end

        if #activeHitPtfx > 0 then
            local now = GetGameTimer()
            for i = #activeHitPtfx, 1, -1 do
                if now >= activeHitPtfx[i].expire then
                    if DoesParticleFxLoopedExist(activeHitPtfx[i].handle) then
                        StopParticleFxLooped(activeHitPtfx[i].handle, false)
                    end
                    table.remove(activeHitPtfx, i)
                end
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  BACKGROUND OPTIMIZATIONS (server-configured, automatic for all players)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Texture Streaming Fix
CreateThread(function()
    if not Config.Background.enabled or not Config.Background.textureStreamFix then return end
    local interval = (Config.Background.textureRefreshInterval or 10) * 1000
    local radius = Config.Background.hdRadius or 150.0

    Wait(5000)

    local lastHd = GetEntityCoords(cachedPed)
    SetHdArea(lastHd.x, lastHd.y, lastHd.z, radius)

    while true do
        local coords = GetEntityCoords(cachedPed)
        if #(coords - lastHd) > (radius * 0.6) then
            SetHdArea(coords.x, coords.y, coords.z, radius)
            lastHd = coords
        end
        Wait(interval)
    end
end)

-- Entity Pool Monitor
CreateThread(function()
    if not Config.Background.enabled or not Config.Background.entityPoolMonitor then return end
    local interval = (Config.Background.poolCheckInterval or 15) * 1000
    local maxVeh = Config.Background.maxVehicles or 180
    local maxPed = Config.Background.maxPeds or 180

    Wait(10000)

    while true do
        local coords = GetEntityCoords(cachedPed)

        local vehicles = GetGamePool('CVehicle')
        if #vehicles > maxVeh then
            local sorted = {}
            for _, v in ipairs(vehicles) do
                if CanRemoveVehicle(v, coords, 60.0) then
                    sorted[#sorted + 1] = { ent = v, dist = #(coords - GetEntityCoords(v)) }
                end
            end
            table.sort(sorted, function(a, b) return a.dist > b.dist end)
            local toRemove = math.min(#sorted, #vehicles - maxVeh + 10)
            for i = 1, toRemove do
                if DoesEntityExist(sorted[i].ent) then RemoveEntity(sorted[i].ent, true) end
            end
        end

        local peds = GetGamePool('CPed')
        if #peds > maxPed then
            local sorted = {}
            for _, p in ipairs(peds) do
                if CanRemovePed(p, coords, 60.0) then
                    sorted[#sorted + 1] = { ent = p, dist = #(coords - GetEntityCoords(p)) }
                end
            end
            table.sort(sorted, function(a, b) return a.dist > b.dist end)
            local toRemove = math.min(#sorted, #peds - maxPed + 10)
            for i = 1, toRemove do
                if DoesEntityExist(sorted[i].ent) then RemoveEntity(sorted[i].ent, false) end
            end
        end

        Wait(interval)
    end
end)

-- Asset Memory Cleanup
CreateThread(function()
    if not Config.Background.enabled or not Config.Background.assetCleanup then return end
    local interval = (Config.Background.assetCleanupInterval or 30) * 1000
    local range = Config.Background.assetCleanupRange or 300.0

    Wait(15000)

    while true do
        local coords = GetEntityCoords(cachedPed)
        for _, v in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(v) and #(coords - GetEntityCoords(v)) > range then
                SetModelAsNoLongerNeeded(GetEntityModel(v))
            end
        end
        Wait(interval)
    end
end)

-- Ambient Population Scaling
CreateThread(function()
    if not Config.Background.enabled or not Config.Background.ambientScaling then return end

    local perPlayer = Config.Background.ambientScalePerPlayer or 0.05
    local minScale = Config.Background.ambientMinScale or 0.2
    local detectRange = Config.Background.ambientDetectRange or 200.0

    Wait(5000)

    while true do
        local coords = GetEntityCoords(cachedPed)
        local nearbyPlayers = 0
        for _, id in ipairs(GetActivePlayers()) do
            if id ~= PlayerId() then
                local otherPed = GetPlayerPed(id)
                if DoesEntityExist(otherPed) and #(coords - GetEntityCoords(otherPed)) < detectRange then
                    nearbyPlayers = nearbyPlayers + 1
                end
            end
        end
        bgAmbientScale = math.max(minScale, 1.0 - (nearbyPlayers * perPlayer))
        Wait(5000)
    end
end)

-- Lua Garbage Collection
CreateThread(function()
    if not Config.Background.enabled or not Config.Background.luaGC then return end
    local interval = (Config.Background.gcInterval or 60) * 1000
    Wait(30000)
    while true do
        collectgarbage('step', 100)
        Wait(interval)
    end
end)

-- CPU Load Reduction
local budgetsApplied = false
CreateThread(function()
    local cpu = Config.Background.cpu
    if not Config.Background.enabled or not cpu or not cpu.enabled then return end
    local interval = (cpu.cpuCheckInterval or 12) * 1000

    Wait(8000)

    if cpu.populationBudget then
        SetPedPopulationBudget(cpu.pedBudget or 2)
        SetVehiclePopulationBudget(cpu.vehicleBudget or 2)
        budgetsApplied = true
    end

    while true do
        local coords = GetEntityCoords(cachedPed)

        if cpu.populationBudget and cpu.dynamicBudget then
            local nearby = 0
            for _, id in ipairs(GetActivePlayers()) do
                if id ~= PlayerId() then
                    local p = GetPlayerPed(id)
                    if DoesEntityExist(p) and #(coords - GetEntityCoords(p)) < 200.0 then
                        nearby = nearby + 1
                    end
                end
            end

            local pedB, vehB = cpu.pedBudget or 2, cpu.vehicleBudget or 2
            if nearby >= 8 then
                pedB, vehB = 1, 1
            elseif nearby >= 4 then
                pedB, vehB = math.min(2, pedB), math.min(2, vehB)
            end
            SetPedPopulationBudget(pedB)
            SetVehiclePopulationBudget(vehB)
        end

        if cpu.ragdollLimiting then
            local range = cpu.ragdollRange or 60.0
            for _, p in ipairs(GetGamePool('CPed')) do
                if p ~= cachedPed and DoesEntityExist(p) and not IsPedAPlayer(p) and not IsEntityAMissionEntity(p) and IsAmbient(p) then
                    local far = #(coords - GetEntityCoords(p)) > range
                    SetPedRagdollOnCollision(p, not far)
                end
            end
        end

        if cpu.entityLodScaling then
            local beyond = cpu.lodApplyBeyond or 150.0
            local lodDist = cpu.lodDistance or 200
            for _, v in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(v) and not IsEntityAMissionEntity(v) and IsAmbient(v) and not IsPedInVehicle(cachedPed, v, false) then
                    if #(coords - GetEntityCoords(v)) > beyond then
                        SetEntityLodDist(v, lodDist)
                    end
                end
            end
        end

        Wait(interval)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  LIVE STATS FEED (only runs while the menu is open)
-- ═══════════════════════════════════════════════════════════════════════════════

local function CountPools()
    local v, p, o = GetGamePool('CVehicle'), GetGamePool('CPed'), GetGamePool('CObject')
    local scripted = 0
    for _, e in ipairs(v) do if GetEntityPopulationType(e) == 7 then scripted = scripted + 1 end end
    for _, e in ipairs(p) do if GetEntityPopulationType(e) == 7 then scripted = scripted + 1 end end
    return { vehicles = #v, peds = #p, objects = #o, scripted = scripted }
end

local function CountProbes()
    local n = 0
    for _ in pairs(probeData) do n = n + 1 end
    return n
end

CreateThread(function()
    while true do
        if menuOpen then
            local fc = Config.Background.frameCap or {}
            SendNUIMessage({
                action = 'stats',
                fps = fps,
                sessionMinutes = math.floor((GetGameTimer() - sessionStart) / 60000),
                preset = settings.activePreset ~= '' and settings.activePreset or nil,
                frameCapTarget = settings.frameCapTarget or 0,
                overshootMargin = fc.overshootMargin or 25,
                pools = CountPools(),
                systems = {
                    adaptive = adaptiveLevel,
                    afk = isAfk,
                    paused = isUnfocused,
                    ambient = math.floor(bgAmbientScale * 100 + 0.5),
                    probes = CountProbes(),
                    benchmark = benchmark.running,
                },
            })
        end
        Wait(1000)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  IDLE / AFK DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local cfg = Config.Background.idle
    if not Config.Background.enabled or not cfg or not cfg.enabled then return end

    local afkMs = (cfg.afkSeconds or 600) * 1000
    local lastPos = vector3(0, 0, 0)

    Wait(5000)
    lastPos = GetEntityCoords(cachedPed)

    while true do
        if cfg.throttleOnUnfocused then
            isUnfocused = IsPauseMenuActive()
        end

        local pos = GetEntityCoords(cachedPed)
        local moved = #(pos - lastPos) > 1.0

        local pressed = IsControlPressed(0, 30) or IsControlPressed(0, 31)
            or IsControlPressed(0, 32) or IsControlPressed(0, 33)
            or IsControlPressed(0, 34) or IsControlPressed(0, 35)
            or IsControlPressed(0, 24) or IsControlPressed(0, 25)
            or IsControlPressed(0, 22) or IsDisabledControlPressed(0, 1)
            or IsDisabledControlPressed(0, 2)

        -- Any NUI with focus (phone, inventory, this menu) counts as activity,
        -- otherwise a long inventory session would empty the world behind it.
        if moved or pressed or menuOpen or IsNuiFocused() then
            lastInputTime = GetGameTimer()
            lastPos = pos
            isAfk = false
        elseif GetGameTimer() - lastInputTime > afkMs then
            isAfk = true
        end

        Wait(1000)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  ADAPTIVE AUTO-OPTIMIZER (cap-aware)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local cfg = Config.Background.adaptive
    if not Config.Background.enabled or not cfg or not cfg.enabled then return end

    local interval = (cfg.checkInterval or 10) * 1000
    local lowT = cfg.lowFpsThreshold or 45
    local recT = cfg.recoverFpsThreshold or 70
    local maxL = cfg.maxLevel or 3

    Wait(20000)

    while true do
        if not isAfk and not isUnfocused and not benchmark.running and fps > 0 then
            -- A player capped at 60 can never exceed a recovery threshold of
            -- 70, so both thresholds scale down to the cap when one is set.
            local low, rec = lowT, recT
            local cap = EffectiveCap()
            if cap > 0 then
                rec = math.min(recT, math.floor(cap * 0.9))
                low = math.min(lowT, math.floor(cap * 0.7))
            end
            if rec <= low then rec = low + 5 end

            if fps < low and adaptiveLevel < maxL then
                adaptiveLevel = adaptiveLevel + 1
                if cfg.notifyPlayer and not adaptiveNotified then
                    Notify('~b~Optimizer~s~: low FPS detected, boosting performance automatically.')
                    adaptiveNotified = true
                end
            elseif fps >= rec and adaptiveLevel > 0 then
                adaptiveLevel = adaptiveLevel - 1
                if adaptiveLevel == 0 then
                    adaptiveNotified = false
                    if cfg.notifyPlayer then
                        Notify('~b~Optimizer~s~: performance recovered, restoring visual quality.')
                    end
                end
            end
        end
        Wait(interval)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  LONG SESSION MAINTENANCE
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local cfg = Config.Background.session
    if not Config.Background.enabled or not cfg or not cfg.enabled then return end

    local reclaimMs = (cfg.reclaimInterval or 30) * 60000
    local lastReclaim = GetGameTimer()

    Wait(60000)

    while true do
        local now = GetGameTimer()
        local sessionMinutes = (now - sessionStart) / 60000

        if now - lastReclaim >= reclaimMs then
            lastReclaim = now
            local coords = GetEntityCoords(cachedPed)
            for _, v in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(v) and #(coords - GetEntityCoords(v)) > 200.0 then
                    SetModelAsNoLongerNeeded(GetEntityModel(v))
                end
            end
            collectgarbage('collect')
        end

        if cfg.advisories and cfg.advisoryHours then
            for _, hr in ipairs(cfg.advisoryHours) do
                if sessionMinutes >= (hr * 60) and not advisoriesShown[hr] then
                    advisoriesShown[hr] = true
                    Notify(('~b~Optimizer~s~: %d hours played. A short break helps you and your PC cool off.'):format(hr))
                end
            end
        end

        if cfg.fpsCapAdvisory and not fpsCapWarned and sessionMinutes > 5
           and (settings.frameCapTarget or 0) == 0 then
            if fps >= (cfg.fpsCapThreshold or 200) then
                fpsCapWarned = true
                Notify('~b~Optimizer~s~: your FPS is uncapped. Capping it at your monitor refresh rate lowers CPU/GPU temps. See Advanced > Frame cap.')
            end
        end

        Wait(60000)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  PROBE REPORTS (from probe.lua running inside other resources)
-- ═══════════════════════════════════════════════════════════════════════════════

AddEventHandler('nayzeee-optimizer:probe:report', function(r)
    if type(r) ~= 'table' or type(r.res) ~= 'string' or r.side ~= 'client' then return end
    r.at = GetGameTimer()
    probeData[r.res] = r
    local mem = tonumber(r.mem)
    if mem then
        local h = probeMem[r.res]
        if not h then probeMem[r.res] = { t0 = r.at, m0 = mem } end
    end
end)

local function MemGrowthMBph(res, memKB)
    local h = probeMem[res]
    if not h or not memKB then return nil end
    local hours = (GetGameTimer() - h.t0) / 3600000
    if hours < (10 / 60) then return nil end
    return ((memKB - h.m0) / 1024) / hours
end

-- Builds the admin's own client resource table, graded.
local function BuildClientHealth(limit)
    local now = GetGameTimer()
    local maxAge = ((Config.Probe and Config.Probe.reportInterval) or 5) * 4000
    local rows = {}
    for name, r in pairs(probeData) do
        if now - r.at > maxAge then
            probeData[name] = nil
        else
            local win = tonumber(r.win) or 5
            local frames = math.max(1, tonumber(r.frames) or (fps * win))
            local ms = tonumber(r.ms) or 0
            local row = {
                name     = name,
                side     = 'client',
                load     = ms / frames,
                peakMs   = tonumber(r.peak) or 0,
                loops    = (tonumber(r.slices) or 0) / frames,
                eventsPs = (tonumber(r.events) or 0) / win,
                memMB    = (tonumber(r.mem) or 0) / 1024,
                memGrowth = MemGrowthMBph(name, tonumber(r.mem)),
                slicesPs = (tonumber(r.slices) or 0) / win,
            }
            row.grade, row.verdict, row.hints = NZGrade.resource(row)
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return a.load > b.load end)
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  CLIENT TELEMETRY (opt-in per player, feeds the server Health tab)
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local hc = Config.Health
    if not hc or not hc.enabled or not hc.clientTelemetry then return end
    local interval = (hc.clientReportInterval or 60) * 1000
    local sampleSec = hc.clientSampleSeconds or 5

    Wait(45000)

    while true do
        if settings.shareTelemetry and not benchmark.running and not isAfk and not isUnfocused then
            SampleFrames(sampleSec, function(sum)
                if not sum then return end
                lastClientGrade = NZGrade.bandDesc(sum.low1Fps, hc.thresholds and hc.thresholds.clientLow)
                local rows = BuildClientHealth(hc.maxResourcesPerReport or 40)
                local compact = {}
                for i, r in ipairs(rows) do
                    compact[i] = {
                        n = r.name,
                        l = math.floor(r.load * 1000 + 0.5) / 1000,
                        p = math.floor(r.peakMs * 10 + 0.5) / 10,
                        o = math.floor(r.loops * 10 + 0.5) / 10,
                        e = math.floor(r.eventsPs * 10 + 0.5) / 10,
                        m = math.floor(r.memMB * 10 + 0.5) / 10,
                        g = r.memGrowth and math.floor(r.memGrowth * 10 + 0.5) / 10 or nil,
                    }
                end
                TriggerServerEvent('nayzeee-optimizer:telemetry', {
                    fps = sum.avgFps, low = sum.low1Fps, maxFt = sum.maxFt,
                    tier = settings.specTier or '', gpu = settings.specGpu or '',
                    preset = settings.activePreset or '',
                    probes = CountProbes(),
                    res = compact,
                })
            end)
        end
        Wait(interval)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  ADMIN / HEALTH TAB
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nayzeee-optimizer:admin:result', function(result)
    isAdmin = result == true
    if menuOpen then SendNUIMessage({ action = 'admin', isAdmin = isAdmin }) end
end)

RegisterNetEvent('nayzeee-optimizer:health:data', function(payload)
    if menuOpen and type(payload) == 'table' then
        payload.action = 'healthServer'
        SendNUIMessage(payload)
    end
end)

RegisterNetEvent('nayzeee-optimizer:health:status', function(msg, kind)
    if menuOpen then SendNUIMessage({ action = 'healthStatus', message = tostring(msg), kind = kind or 'info' }) end
end)

RegisterNetEvent('nayzeee-optimizer:applyPreset', function(preset)
    if type(preset) ~= 'string' or not Config.Presets[preset] then return end
    if ApplyPreset(preset) then
        Notify(('~b~Optimizer~s~: an admin applied the ~y~%s~s~ profile to you.'):format(preset))
    end
end)

local function SendClientHealth()
    local rows = BuildClientHealth()
    local hc = Config.Health or {}
    SendNUIMessage({
        action = 'healthClient',
        rows = rows,
        probes = #rows,
        fps = fps,
        grade = lastClientGrade,
        pools = CountPools(),
    })
end

RegisterNUICallback('healthOpen', function(_, cb)
    cb('ok')
    if not isAdmin or healthOpen then return end
    healthOpen = true
    TriggerServerEvent('nayzeee-optimizer:health:request')
    SendClientHealth()
    -- Fresh frame-time grade for the admin's own client
    if not sampler.active then
        SampleFrames(4, function(sum)
            if sum then
                lastClientGrade = NZGrade.bandDesc(sum.low1Fps, Config.Health.thresholds and Config.Health.thresholds.clientLow)
                if healthOpen then
                    SendNUIMessage({ action = 'healthClientFrames', summary = sum, grade = lastClientGrade })
                end
            end
        end)
    end
    CreateThread(function()
        local tick = 0
        while healthOpen and menuOpen do
            Wait(5000)
            if not (healthOpen and menuOpen) then break end
            SendClientHealth()
            tick = tick + 1
            if tick % 3 == 0 then TriggerServerEvent('nayzeee-optimizer:health:request') end
        end
    end)
end)

RegisterNUICallback('healthClose', function(_, cb)
    healthOpen = false
    cb('ok')
end)

RegisterNUICallback('healthRefresh', function(_, cb)
    cb('ok')
    if isAdmin then
        TriggerServerEvent('nayzeee-optimizer:health:request')
        SendClientHealth()
    end
end)

RegisterNUICallback('healthAction', function(data, cb)
    cb('ok')
    if not isAdmin or type(data) ~= 'table' then return end
    TriggerServerEvent('nayzeee-optimizer:health:action', tostring(data.what or ''), data.arg)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  COMMANDS & KEYBINDS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterCommand(Config.Command, function()
    if menuOpen then CloseMenu() else OpenMenu() end
end, false)

if not Config.DisableKeybind then
    RegisterKeyMapping(Config.Command, 'Open FPS Optimizer', 'keyboard', Config.Key)
end

RegisterCommand('optimizersetup', function()
    CreateThread(function()
        settings.setupDone = false
        SaveSettings()
        if menuOpen then
            CloseMenu()
            Wait(100)
        end
        OpenMenu()
    end)
end, false)

RegisterCommand('optimizerunstuck', function()
    -- Last-resort recovery: always give the player back control.
    menuOpen = false
    healthOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0) and veh or ped
    FreezeEntityPosition(ent, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ent, true, true)
    SetEntityInvincible(ped, false)
    ClearFocus()
    NewLoadSceneStop()
    DoScreenFadeIn(500)
    fixInProgress = false
    if fixState then fixState.restored = true end

    Notify('~b~Optimizer~s~: control restored.')
end, false)

RegisterCommand('optimizerbench', function()
    StartBenchmark()
end, false)

-- ═══════════════════════════════════════════════════════════════════════════════
--  RESOURCE STOP: never leave the player with a stuck cursor or a blackout
-- ═══════════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if menuOpen then SetNuiFocus(false, false) end
    ApplyPersistentState(true)
    if fixInProgress then RestoreFixState(false) end
    if budgetsApplied then
        SetPedPopulationBudget(3)
        SetVehiclePopulationBudget(3)
    end
    ClearHdArea()
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  STARTUP
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(2000)
    LoadSettings()
    ApplyPersistentState()
    nuiReady = true
    sessionStart = GetGameTimer()
    lastInputTime = GetGameTimer()
    print('[NAYZEEE-OPTIMIZER] v1.1.0 loaded')
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  EXPORTS
-- ═══════════════════════════════════════════════════════════════════════════════

exports('GetSettings', function() return settings end)

exports('SetSetting', function(s, v)
    if SetSettingValidated(s, v) then
        settings.activePreset = ''
        ApplyPersistentState()
        SaveSettings()
        return true
    end
    return false
end)

exports('ApplyPreset', function(p) return ApplyPreset(p) end)

exports('GetFPS', function() return fps end)

exports('GetClientHealth', function() return BuildClientHealth() end)

exports('RunBenchmark', function() return StartBenchmark() end)
