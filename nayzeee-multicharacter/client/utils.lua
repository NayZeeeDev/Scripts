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

-- Plays an anim or scenario definition on a ped. def = { dict, clip, flag } | { scenario }
function U.Pose(ped, def)
    if not def or not DoesEntityExist(ped) then return end
    ClearPedTasksImmediately(ped)
    if def.scenario then
        TaskStartScenarioInPlace(ped, def.scenario, 0, true)
    elseif def.dict and def.clip then
        if pcall(lib.requestAnimDict, def.dict, 5000) then
            TaskPlayAnim(ped, def.dict, def.clip, 8.0, -8.0, -1, def.flag or 1, 0.0, false, false, false)
            RemoveAnimDict(def.dict)
        end
    end
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
