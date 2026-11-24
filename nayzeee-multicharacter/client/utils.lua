if not NAYZEEE_LOCK_OK then return end

--[[
    Client helpers: NUI, fades, streaming, poses (+ handheld props), ground snapping and entity tracking.
    Every lobby entity goes through U.Track so Scene.Teardown() can delete all of them in one pass.
]]

U = {}

local tracked = {}          -- [entity] = true
local dicts = {}            -- [dict] = refcount (kept loaded until U.ReleaseAnims)
local poseSeq = {}          -- [ped] = sequence id of the last U.Pose call (cancels stale retries)
local props = {}            -- [ped] = { prop entities }

-- ── NUI / fades ──────────────────────────────────────────────────────────
function U.Send(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

-- ── UI-owned screen transitions ──────────────────────────────────────────
-- Veil: an opaque black layer in the UI. It covers the loading-screen hand-off (no hard cut, no world flash)
-- and dissolves over the live scene in `ms`.
function U.Veil(on, ms) U.Send('veil', { on = on, ms = ms or 0 }) end

-- Freeze: the UI paints the current game frame (FiveM game-view texture) over everything, so a scene can be
-- rebuilt underneath without a cut to black. Returns false when the client can't capture -> caller fades instead.
U.freezeAck = {}
local freezeSeq = 0
function U.Freeze()
    if not Main.nuiReady then return false end
    freezeSeq = freezeSeq + 1
    local id = freezeSeq
    U.freezeAck[id] = nil
    U.Send('freeze', { id = id })
    local deadline = GetGameTimer() + 700
    while U.freezeAck[id] == nil and GetGameTimer() < deadline do Wait(0) end
    local ok = U.freezeAck[id] == true
    U.freezeAck[id] = nil
    if not ok then U.Send('unfreeze', { ms = 0 }) end   -- cancels a capture that answers late
    return ok
end

function U.Unfreeze(ms) U.Send('unfreeze', { ms = ms or 900 }) end

function U.FadeOut(ms)
    ms = ms or 400
    if IsScreenFadedOut() then return end
    if not IsScreenFadingOut() then DoScreenFadeOut(ms) end
    local deadline = GetGameTimer() + ms + 1500
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
end

function U.FadeIn(ms)
    if IsScreenFadedIn() and not IsScreenFadingOut() then return end
    DoScreenFadeIn(ms or 400)
end

-- ── streaming ────────────────────────────────────────────────────────────
-- Accepts a model name or hash. Returns the hash once loaded, false when it does not exist.
function U.Model(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not hash or not IsModelInCdimage(hash) then return false end
    if HasModelLoaded(hash) then return hash end
    local ok = pcall(lib.requestModel, hash, 8000)
    return ok and hash or false
end

-- Anim dicts stay loaded while the lobby is open. Unloading right after TaskPlayAnim lets the
-- game evict the dict before the task starts, so the pose silently never plays.
function U.Anim(dict)
    if not dict then return false end
    if dicts[dict] then
        dicts[dict] = dicts[dict] + 1
        return true
    end
    if not DoesAnimDictExist(dict) then return false end
    if not pcall(lib.requestAnimDict, dict, 5000) then return false end
    dicts[dict] = 1
    return true
end

function U.ReleaseAnims()
    for dict in pairs(dicts) do RemoveAnimDict(dict) end
    dicts, poseSeq = {}, {}
end

-- ── tracking ─────────────────────────────────────────────────────────────
function U.Track(ent)
    if ent and ent ~= 0 then tracked[ent] = true end
    return ent
end

function U.Delete(ent)
    if not ent then return end
    tracked[ent], poseSeq[ent] = nil, nil
    if props[ent] then U.ClearProps(ent) end
    if DoesEntityExist(ent) then
        if IsEntityAttached(ent) then DetachEntity(ent, false, false) end
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

-- Deletes every tracked entity (Scene.Teardown)
function U.DeleteAll()
    for ent in pairs(tracked) do
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    end
    tracked, props, poseSeq = {}, {}, {}
end

-- ── peds ─────────────────────────────────────────────────────────────────
-- Local-only lobby ped: frozen, invincible, deaf to the world. pedType 28 = animal.
function U.Ped(model, at, pedType)
    local hash = U.Model(model)
    if not hash then
        hash = U.Model(`mp_m_freemode_01`)
        pedType = 4
    end
    local ped = CreatePed(pedType or 4, hash, at.x, at.y, at.z, at.w or 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    U.Track(ped)
    SetEntityCoordsNoOffset(ped, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(ped, at.w or 0.0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedConfigFlag(ped, 185, true)     -- no ragdoll from impacts (kept from v1)
    SetPedCanBeTargetted(ped, false)
    SetPedCanEvasiveDive(ped, false)
    SetPedDiesWhenInjured(ped, false)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    SetEntityCanBeDamaged(ped, false)
    FreezeEntityPosition(ped, true)
    return ped
end

function U.Head(ped)
    local b = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)   -- SKEL_Head
    if b.x == 0.0 and b.y == 0.0 then
        local p = GetEntityCoords(ped)
        return vec3(p.x, p.y, p.z + 0.65)
    end
    return b
end

function U.HidePlayer(at)
    local ped = PlayerPedId()
    if at then
        SetEntityCoordsNoOffset(ped, at.x, at.y, at.z, false, false, false)
        SetEntityHeading(ped, at.w or 0.0)
    end
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)
    RemoveAllPedWeapons(ped, true)
end

function U.ShowPlayer()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    ResetEntityAlpha(ped)
    SetPedAoBlobRendering(ped, true)
    NetworkSetEntityInvisibleToNetwork(ped, false)
end

-- ── ground snapping (contract §6.3) ──────────────────────────────────────
-- Ped coords are the root (≈ hips), Config.Scene.footHeight above the surface the feet stand on.
local FLAGS = 1 | 16   -- world + objects (peds and vehicles are ignored: a ped next to a car never lands on its roof)

local function probe(x, y, from, to)
    local h = StartExpensiveSynchronousShapeTestLosProbe(x, y, from, x, y, to, FLAGS, PlayerPedId(), 7)
    local _, hit, at = GetShapeTestResult(h)
    if hit == true or hit == 1 then return at.z end
end

-- Top surface under x,y near z (nil when nothing solid was found)
function U.Floor(x, y, z)
    local found = probe(x, y, z + 1.2, z - 3.0) or probe(x, y, z + 4.0, z - 3.0)
    if found then return found end
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.2, false)
    if ok and gz > z - 3.0 then return gz end
end

-- Root height for a human ped standing at x,y (z when snapping is off or nothing was found)
function U.Ground(x, y, z, extra)
    if Config.Scene.snapToGround == false then return z end
    local floor = U.Floor(x, y, z)
    if not floor then return z end
    return floor + (Config.Scene.footHeight or 1.0) + (extra or 0.0)
end

-- vec4 with a grounded root height
function U.Snap(v, extra)
    return vec4(v.x, v.y, U.Ground(v.x, v.y, v.z, extra), v.w or 0.0)
end

-- Waits for collision under a point (the player ped must be near it)
function U.Collision(x, y, z, ms)
    local ped = PlayerPedId()
    local deadline = GetGameTimer() + (ms or 5000)
    repeat
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    until HasCollisionLoadedAroundEntity(ped) or GetGameTimer() > deadline
end

-- ── poses ────────────────────────────────────────────────────────────────
-- def = Config.Poses entry ({ anim = {dict, clip, flag} | scenario, props })
--     | plain anim ({ dict, clip, flag })
local function animOf(def)
    if def.anim then return def.anim end
    if def.dict then return def end
end

local function playing(ped, def)
    if def.scenario then return IsPedUsingScenario(ped, def.scenario) or IsPedActiveInScenario(ped) end
    local a = animOf(def)
    return a and IsEntityPlayingAnim(ped, a.dict, a.clip, 3)
end

local function start(ped, def, keepTasks)
    if not keepTasks then ClearPedTasksImmediately(ped) end
    if def.scenario then
        TaskStartScenarioInPlace(ped, def.scenario, 0, false)
    else
        local a = animOf(def)
        TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, a.flag or 1, 0.0, false, false, false)
    end
end

function U.ClearProps(ped)
    local list = props[ped]
    if not list then return end
    for _, o in ipairs(list) do
        tracked[o] = nil
        if DoesEntityExist(o) then
            DetachEntity(o, true, false)
            SetEntityAsMissionEntity(o, true, true)
            DeleteEntity(o)
        end
    end
    props[ped] = nil
end

function U.AttachProps(ped, list)
    if not list or #list == 0 then return end
    props[ped] = props[ped] or {}
    for _, p in ipairs(list) do
        local hash = U.Model(p.model)
        if hash then
            local c = GetEntityCoords(ped)
            local o = CreateObject(hash, c.x, c.y, c.z + 0.2, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            SetEntityCollision(o, false, false)
            local pos, rot = p.pos or vec3(0.0, 0.0, 0.0), p.rot or vec3(0.0, 0.0, 0.0)
            AttachEntityToEntity(o, ped, GetPedBoneIndex(ped, p.bone or 28422), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
                true, true, false, true, 1, true)
            U.Track(o)
            table.insert(props[ped], o)
        end
    end
end

-- Plays a pose / anim / scenario on a ped, attaches its props, then verifies and retries:
-- freshly created or just-cleared peds sometimes drop the first task.
-- opts.keepProps = do not clear current props, opts.keepTasks = no ClearPedTasksImmediately
function U.Pose(ped, def, opts)
    if not def or not DoesEntityExist(ped) then return false end
    opts = opts or {}
    if not def.scenario then
        local a = animOf(def)
        if not (a and a.dict and a.clip) or not U.Anim(a.dict) then return false end
    end
    if not opts.keepProps then U.ClearProps(ped) end
    local my = (poseSeq[ped] or 0) + 1
    poseSeq[ped] = my
    start(ped, def, opts.keepTasks)
    if def.props then U.AttachProps(ped, def.props) end
    CreateThread(function()
        for _ = 1, 6 do
            Wait(150)
            if poseSeq[ped] ~= my or not DoesEntityExist(ped) then return end
            if playing(ped, def) then return end
            start(ped, def, opts.keepTasks)
        end
    end)
    return true
end

-- True once the ped plays the pose (waits up to ms)
function U.WaitPose(ped, def, ms)
    local deadline = GetGameTimer() + (ms or 800)
    while GetGameTimer() < deadline do
        if not DoesEntityExist(ped) then return false end
        if playing(ped, def) then return true end
        Wait(50)
    end
    return false
end

-- Cancels pending pose retries for a ped (before handing it to another task)
function U.StopPose(ped, clear)
    poseSeq[ped] = (poseSeq[ped] or 0) + 1
    if clear and DoesEntityExist(ped) then ClearPedTasksImmediately(ped) end
end

-- ── misc ─────────────────────────────────────────────────────────────────
function U.Dist2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Unsigned 32-bit hash (natives may return signed or unsigned values)
function U.Hash(v)
    if type(v) == 'string' then v = tonumber(v) or joaat(v) end
    return v and (math.tointeger(v) or 0) & 0xFFFFFFFF or 0
end
