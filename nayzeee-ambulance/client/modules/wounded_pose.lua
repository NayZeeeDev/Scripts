--[[
    NAYZEEE AMBULANCE - Wounded (client): downed poses, crawling, getting up

    Driven by wounded.lua (no events of its own):
      NZA.Wounded.Pose.Enter(mode, fromAlive)   mode 'wounded' | 'unconscious' | 'arrest' | 'dead'
                                                fromAlive → short ragdoll first (Config.WoundedUI.ragdollMs)
      NZA.Wounded.Pose.SetMode(mode)            conscious ↔ unconscious while down
      NZA.Wounded.Pose.Refresh()                injuries changed → maybe a better-fitting pose
      NZA.Wounded.Pose.Tick(ped, dt, crawl, turn)   per frame from the control loop; returns false
                                                when crawling stopped because strength ran out
      NZA.Wounded.Pose.Reapply(now)             after a core resurrect (ped stood up)
      NZA.Wounded.Pose.Exit(how)                'getup' | 'none' | 'respawn'
      NZA.Wounded.Pose.GetUp(again)             get-up sequence (Config.WoundedUI.poses.getUp)
      NZA.Wounded.Pose.Suspend(name, on)        another module animates the downed player
      NZA.Wounded.Pose.IsCrawling() / Stamina() / Suspended() / RecentlyGotUp()
      NZA.Wounded.Pose.Resolve(kind) / Load(dict)   first existing anim of a Config pose list

    The pose is only (re)applied while the player is not held by anyone: attached to an
    entity, carried / on a stretcher / in a body bag (state bag), in a vehicle, swimming,
    or while any module suspended it. When dropped from a carry above the ground the body
    falls naturally (short ragdoll) before settling again.
    Poses are picked from Config.WoundedUI.poseRules (worst injury) when conscious and
    'still' when unconscious, in arrest or dead. Crawling uses the animation's root motion
    and moves the ped itself (with a forward obstacle probe) when the clip has none.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded
W.Pose = W.Pose or {}
local P = W.Pose
local U = NZA.Util

local active = false
local mode = nil
local current = nil          -- { kind, dict, clip }
local suspended = {}
local ragdollUntil = 0
local wasHeld = false
local loopGen = 0
local resolved = {}
local loaded = {}

local crawling = false
local crawlEntry = nil
local crawlStart = 0
local crawlFrom = nil
local rootMotion = nil
local groundOffset = 0.0
local stamina = 1.0
local restUntil = 0

local lastGetUp = 0
local getUpGen = 0

local FALLBACK_STILL = { dict = 'dead', clip = 'dead_a' }
local ARM_REGIONS = { l_upper_arm = true, l_lower_arm = true, r_upper_arm = true, r_lower_arm = true }

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG / ANIM LOADING
-- ════════════════════════════════════════════════════════════════════════

local function uiCfg()
    return type(Config.WoundedUI) == 'table' and Config.WoundedUI or {}
end

local function poseList(kind)
    local poses = uiCfg().poses
    local list = type(poses) == 'table' and poses[kind] or nil
    return type(list) == 'table' and list or {}
end

local function crawlCfg()
    local c = uiCfg().crawl
    return type(c) == 'table' and c or {}
end

function P.Resolve(kind)
    if resolved[kind] ~= nil then return resolved[kind] or nil end
    for _, e in ipairs(poseList(kind)) do
        if type(e) == 'table' and type(e.dict) == 'string' and type(e.clip) == 'string' and DoesAnimDictExist(e.dict) then
            resolved[kind] = e
            return e
        end
    end
    resolved[kind] = false
    return nil
end

function P.Load(dict)
    if loaded[dict] and HasAnimDictLoaded(dict) then return true end
    local ok = pcall(lib.requestAnimDict, dict, 3000)
    if ok and HasAnimDictLoaded(dict) then
        loaded[dict] = true
        return true
    end
    return false
end

local function unloadAll()
    if active then return end
    for dict in pairs(loaded) do RemoveAnimDict(dict) end
    loaded = {}
end
P.UnloadAll = unloadAll

local function contains(list, value)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- POSE CHOICE
-- ════════════════════════════════════════════════════════════════════════

local function worstInjury()
    local snap = W.S and W.S.snap
    local list = snap and snap.injuries
    if type(list) ~= 'table' then return nil end
    local worst = nil
    for _, inj in ipairs(list) do
        if type(inj) == 'table' and inj.type and inj.region then
            if not worst or (tonumber(inj.severity) or 1) > (tonumber(worst.severity) or 1) then worst = inj end
        end
    end
    return worst
end

local function chooseKind()
    if mode ~= 'wounded' then return 'still' end
    local worst = worstInjury()
    if worst then
        for _, rule in ipairs(type(uiCfg().poseRules) == 'table' and uiCfg().poseRules or {}) do
            local okT = rule.types == nil or contains(rule.types, worst.type)
            local okR = rule.regions == nil or contains(rule.regions, worst.region)
            if okT and okR and rule.pose and P.Resolve(rule.pose) then return rule.pose end
        end
    end
    local def = uiCfg().defaultPose or 'writhe'
    if P.Resolve(def) then return def end
    return 'still'
end

local function entryFor(kind)
    return P.Resolve(kind) or P.Resolve('still') or FALLBACK_STILL
end

-- ════════════════════════════════════════════════════════════════════════
-- HELD / BLOCKED
-- ════════════════════════════════════════════════════════════════════════

function P.Suspend(name, on)
    if type(name) ~= 'string' then return end
    suspended[name] = on and true or nil
    if on then
        current = nil
        if crawling then crawling = false end
    elseif active then
        wasHeld = true
    end
end

function P.Suspended()
    return next(suspended) ~= nil
end

local function blocked(ped)
    if next(suspended) ~= nil then return true end
    if IsPedInAnyVehicle(ped, false) then return true end
    if W.Held and W.Held(ped) then return true end
    if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then return true end
    return false
end

local function heightAboveGround(ped)
    local c = GetEntityCoords(ped)
    local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 0.5, false)
    if ok then return c.z - gz end
    return 0.0
end

-- ════════════════════════════════════════════════════════════════════════
-- APPLY
-- ════════════════════════════════════════════════════════════════════════

local function play(ped, e, blendIn, flag, duration)
    if not P.Load(e.dict) then return false end
    TaskPlayAnim(ped, e.dict, e.clip, blendIn or 2.0, -2.0, duration or -1, flag or 1, 0.0, false, false, false)
    return true
end

function P.Ensure(ped, force)
    if not active or crawling then return end
    local now = GetGameTimer()
    if blocked(ped) then
        wasHeld = true
        current = nil
        return
    end
    if wasHeld then
        wasHeld = false
        -- dropped from a shoulder / stretcher: let the body fall naturally first
        if heightAboveGround(ped) > 0.9 then
            SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
            ragdollUntil = now + 1300
            return
        end
        force = true
    end
    if now < ragdollUntil then return end
    if IsPedFalling(ped) or (IsPedRagdoll(ped) and GetEntitySpeed(ped) > 0.6 and now < ragdollUntil + 4000) then return end

    local kind = chooseKind()
    local e = entryFor(kind)
    local playing = IsEntityPlayingAnim(ped, e.dict, e.clip, 3)
    if force or not current or current.dict ~= e.dict or current.clip ~= e.clip or not playing then
        local blend = (current and playing) and 1.5 or 2.0
        if play(ped, e, blend, 1) then
            current = { kind = kind, dict = e.dict, clip = e.clip }
        end
    end
end

local function startLoop()
    loopGen = loopGen + 1
    local gen = loopGen
    CreateThread(function()
        while active and gen == loopGen do
            P.Ensure(PlayerPedId(), false)
            Wait(400)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- CRAWL
-- ════════════════════════════════════════════════════════════════════════

local function armFactor()
    local snap = W.S and W.S.snap
    if not snap or type(snap.injuries) ~= 'table' then return 1.0 end
    local splints = {}
    local dev = snap.devices or {}
    for _, r in ipairs(type(dev.splints) == 'table' and dev.splints or {}) do splints[r] = true end
    for _, inj in ipairs(snap.injuries) do
        if type(inj) == 'table' and inj.type == 'fracture' and ARM_REGIONS[inj.region] and not splints[inj.region] then
            return tonumber(crawlCfg().armPenalty) or 0.6
        end
    end
    return 1.0
end

local function drainFactor()
    local snap = W.S and W.S.snap
    local tunnel = snap and type(snap.fx) == 'table' and tonumber(snap.fx.tunnel) or 0
    local pen = tonumber(crawlCfg().lossPenalty) or 0.6
    local mult = U.lerp(1.0, pen, U.clamp(tunnel, 0, 1))
    return 1.0 / math.max(0.2, mult)
end

local function crawlSpeed()
    local base = tonumber(Config.Wounded and Config.Wounded.crawlSpeed) or 1.0
    return base * armFactor()
end

local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
    if ok then return gz end
    return nil
end

local function startCrawl(ped)
    crawlEntry = P.Resolve('crawl')
    if not crawlEntry then return false end
    if not play(ped, crawlEntry, 2.0, 1) then return false end
    crawling = true
    current = nil
    crawlStart = GetGameTimer()
    crawlFrom = GetEntityCoords(ped)
    rootMotion = nil
    local gz = groundZ(crawlFrom.x, crawlFrom.y, crawlFrom.z)
    groundOffset = gz and U.clamp(crawlFrom.z - gz, 0.05, 0.6) or 0.25
    return true
end

local function stopCrawl(ped)
    if not crawling then return end
    crawling = false
    if crawlEntry then StopAnimTask(ped, crawlEntry.dict, crawlEntry.clip, 2.0) end
    current = nil
    P.Ensure(ped, true)
end

local function manualStep(ped, dt)
    local fwd = GetEntityForwardVector(ped)
    local c = GetEntityCoords(ped)
    local spd = (tonumber(crawlCfg().speed) or 0.32) * crawlSpeed()
    -- something in the way?
    local fx, fy, fz = c.x, c.y, c.z + 0.15
    local tx, ty, tz = fx + fwd.x * 0.7, fy + fwd.y * 0.7, fz
    local handle = StartExpensiveSynchronousShapeTestLosProbe(fx, fy, fz, tx, ty, tz, 1 + 16, ped, 4)
    local _, hit = GetShapeTestResult(handle)
    if hit == 1 or hit == true then return end
    local nx, ny = c.x + fwd.x * spd * dt, c.y + fwd.y * spd * dt
    local gzNew = groundZ(nx, ny, c.z)
    local gzCur = groundZ(c.x, c.y, c.z)
    if not gzNew or not gzCur or math.abs(gzNew - gzCur) > 0.45 then return end
    SetEntityCoordsNoOffset(ped, nx, ny, gzNew + groundOffset, false, false, false)
end

local function crawlStep(ped, dt)
    local e = crawlEntry
    if not e then return end
    if not IsEntityPlayingAnim(ped, e.dict, e.clip, 3) then play(ped, e, 2.0, 1) end
    local now = GetGameTimer()
    if rootMotion == nil and now - crawlStart > 800 then
        local moved = #(GetEntityCoords(ped) - crawlFrom)
        rootMotion = moved > 0.15
    end
    if rootMotion then
        SetEntityAnimSpeed(ped, e.dict, e.clip, U.clamp(crawlSpeed(), 0.3, 2.0) + 0.0)
    elseif rootMotion == false then
        manualStep(ped, dt)
    end
end

function P.Tick(ped, dt, want, turn)
    if not active then return nil end
    local cc = crawlCfg()
    local now = GetGameTimer()
    local free = not blocked(ped) and now >= ragdollUntil and not IsPedRagdoll(ped)

    if turn ~= 0 and free and mode == 'wounded' then
        SetEntityHeading(ped, GetEntityHeading(ped) + turn * (tonumber(cc.turnSpeed) or 70.0) * dt)
    end

    local staminaSec = math.max(3, tonumber(cc.stamina) or 22)
    local recoverSec = math.max(1, tonumber(cc.recover) or 6)

    if want and free and mode == 'wounded' and stamina > 0 and now >= restUntil then
        if not crawling and not startCrawl(ped) then return false end
        crawlStep(ped, dt)
        stamina = math.max(0, stamina - dt / staminaSec * drainFactor())
        if stamina <= 0 then
            restUntil = now + 1500
            stopCrawl(ped)
            if W.Flash then W.Flash('warn', NZA.L('wounded.k_tired')) end
            return false
        end
        return true
    end

    if crawling then stopCrawl(ped) end
    if now >= restUntil then stamina = math.min(1, stamina + dt / recoverSec) end
    if want and now < restUntil then return false end
    return nil
end

function P.IsCrawling()
    return crawling
end

function P.Stamina()
    return stamina
end

-- ════════════════════════════════════════════════════════════════════════
-- ENTER / EXIT
-- ════════════════════════════════════════════════════════════════════════

function P.Enter(m, fromAlive)
    local wasActive = active
    mode = m
    active = true
    local ped = PlayerPedId()
    SetPedCanRagdollFromPlayerImpact(ped, false)
    if crawling and m ~= 'wounded' then stopCrawl(ped) end
    if fromAlive and not IsPedInAnyVehicle(ped, false) and not blocked(ped) then
        local ms = math.floor(tonumber(uiCfg().ragdollMs) or 1800)
        if ms > 0 then
            if not IsPedRagdoll(ped) then SetPedToRagdoll(ped, ms, ms, 0, false, false, false) end
            ragdollUntil = GetGameTimer() + ms
        end
    end
    if not wasActive then
        stamina = 1.0
        startLoop()
    end
    current = nil
    P.Ensure(ped, true)
end

function P.SetMode(m)
    if not active or m == mode then return end
    mode = m
    local ped = PlayerPedId()
    if crawling and m ~= 'wounded' then stopCrawl(ped) end
    current = nil
    P.Ensure(ped, true)
end

function P.Refresh()
    if not active or crawling or not current then return end
    if chooseKind() ~= current.kind then P.Ensure(PlayerPedId(), true) end
end

function P.Reapply(now)
    if not active then return end
    if now then ragdollUntil = 0 end
    current = nil
    P.Ensure(PlayerPedId(), true)
end

function P.GetUp(again)
    lastGetUp = GetGameTimer()
    getUpGen = getUpGen + 1
    local gen = getUpGen
    CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) or IsEntityAttached(ped) then return end
        local seq = {}
        for _, e in ipairs(poseList('getUp')) do
            if type(e) == 'table' and e.dict and e.clip and DoesAnimDictExist(e.dict) then seq[#seq + 1] = e end
        end
        if #seq == 0 then
            ClearPedTasks(ped)
            return
        end
        for i, e in ipairs(seq) do
            if gen ~= getUpGen or active then return end
            local ms = math.floor(tonumber(e.ms) or 1500)
            if P.Load(e.dict) then
                TaskPlayAnim(ped, e.dict, e.clip, (i == 1 and not again) and 2.0 or 4.0, -4.0, ms, 0, 0.0, false, false, false)
                Wait(ms)
            end
        end
        if gen == getUpGen and not active then
            ClearPedTasks(ped)
            unloadAll()
        end
    end)
end

function P.RecentlyGotUp()
    return GetGameTimer() - lastGetUp < 3000
end

function P.Exit(how)
    local ped = PlayerPedId()
    local wasCrawling = crawling
    active = false
    loopGen = loopGen + 1
    crawling = false
    mode = nil
    current = nil
    wasHeld = false
    ragdollUntil = 0
    stamina, restUntil = 1.0, 0
    suspended = {}
    SetPedCanRagdollFromPlayerImpact(ped, true)
    if wasCrawling and crawlEntry then StopAnimTask(ped, crawlEntry.dict, crawlEntry.clip, 2.0) end
    if how == 'getup' then
        P.GetUp(false)
    elseif how == 'none' then
        ClearPedTasks(ped)
        unloadAll()
    end
end
