if not NAYZEEE_LOCK_OK then return end

U = {}

function U.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function U.FadeOut(ms)
    if IsScreenFadedOut() then return end
    DoScreenFadeOut(ms or 400)
    local deadline = GetGameTimer() + (ms or 400) + 1500
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
end

function U.FadeIn(ms)
    DoScreenFadeIn(ms or 400)
end

function U.Model(hash)
    if not IsModelInCdimage(hash) then return false end
    return pcall(lib.requestModel, hash, 8000)
end

-- Anim dicts stay loaded while the selection is open (unloading right after TaskPlayAnim
-- lets the game evict the dict before the task starts, so the pose silently never plays)
local dicts, poseSeq = {}, {}

local function playing(ped, def)
    if def.scenario then return IsPedUsingScenario(ped, def.scenario) or IsPedActiveInScenario(ped) end
    return IsEntityPlayingAnim(ped, def.dict, def.clip, 3)
end

local function start(ped, def)
    ClearPedTasksImmediately(ped)
    if def.scenario then
        TaskStartScenarioInPlace(ped, def.scenario, 0, false)
    else
        TaskPlayAnim(ped, def.dict, def.clip, 8.0, -8.0, -1, def.flag or 1, 0.0, false, false, false)
    end
end

-- Plays an anim or scenario definition on a ped. def = { dict, clip, flag } | { scenario }
function U.Pose(ped, def)
    if not def or not DoesEntityExist(ped) then return end
    if not def.scenario then
        if not (def.dict and def.clip) then return end
        if not dicts[def.dict] then
            if not pcall(lib.requestAnimDict, def.dict, 5000) then return end
            dicts[def.dict] = true
        end
    end
    local my = (poseSeq[ped] or 0) + 1
    poseSeq[ped] = my
    start(ped, def)
    -- Freshly created / just-cleared peds sometimes drop the first task: verify and retry
    CreateThread(function()
        for _ = 1, 5 do
            Wait(120)
            if poseSeq[ped] ~= my or not DoesEntityExist(ped) then return end
            if playing(ped, def) then return end
            start(ped, def)
        end
    end)
end

-- Selection closed: let the game unload every pose dict again
function U.ReleasePoses()
    for dict in pairs(dicts) do RemoveAnimDict(dict) end
    dicts, poseSeq = {}, {}
end

function U.PoseById(id)
    if not id then return nil end
    for _, p in ipairs(Config.Poses) do if p.id == id then return p end end
end

-- Local-only preview ped: frozen, invincible, ignores the world
function U.PreviewPed(model, coords)
    if not U.Model(model) then model = `mp_m_freemode_01`; U.Model(model) end
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedConfigFlag(ped, 185, true)   -- no ragdoll from impacts
    SetPedCanBeTargetted(ped, false)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDefaultComponentVariation(ped)
    return ped
end

function U.Delete(ent)
    if ent then poseSeq[ent] = nil end
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

function U.Head(ped)
    local b = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    if b.x == 0.0 and b.y == 0.0 then
        local p = GetEntityCoords(ped)
        return vec3(p.x, p.y, p.z + 0.65)
    end
    return b
end
