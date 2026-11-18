if not NAYZEEE_LOCK_OK then return end

--[[
    Couple animations (Config.CoupleAnimations). pedA = selected character (stays on its mark),
    pedB = partner, placed from pedA with pedB.offset / pedB.rotation, or glued with AttachEntityToEntity
    when `attach` is set (tight embraces never drift). Both anims start on the SAME frame so they stay in sync.
]]

Couple = { active = nil }

local function animsPlaying(a, b, def)
    return IsEntityPlayingAnim(a, def.pedA.dict, def.pedA.clip, 3) and IsEntityPlayingAnim(b, def.pedB.dict, def.pedB.clip, 3)
end

local function startBoth(a, b, def)
    ClearPedTasksImmediately(a)
    ClearPedTasksImmediately(b)
    TaskPlayAnim(a, def.pedA.dict, def.pedA.clip, 8.0, -8.0, -1, def.pedA.flag or 1, 0.0, false, false, false)
    TaskPlayAnim(b, def.pedB.dict, def.pedB.clip, 8.0, -8.0, -1, def.pedB.flag or 1, 0.0, false, false, false)
end

function Couple.Play(pedA, pedB, coupleId)
    Couple.Stop()
    local def = NZ.CoupleById(coupleId)
    if not def or not DoesEntityExist(pedA) or not DoesEntityExist(pedB) then return false end
    if not (U.Anim(def.pedA.dict) and U.Anim(def.pedB.dict)) then return false end

    -- Both unarmed, no handheld props, no pending solo pose retries
    for _, p in ipairs({ pedA, pedB }) do
        U.StopPose(p)
        U.ClearProps(p)
        RemoveAllPedWeapons(p, true)
    end

    local b = def.pedB
    local off, rot = b.offset or vec3(0.6, 0.0, 0.0), b.rotation or vec3(0.0, 0.0, 0.0)
    if IsEntityAttached(pedB) then DetachEntity(pedB, false, false) end
    if b.attach then
        FreezeEntityPosition(pedB, false)
        -- bone index 0 = pedA root: B follows A's placement but not A's animated pelvis
        AttachEntityToEntity(pedB, pedA, 0, off.x, off.y, off.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
    else
        local p = GetOffsetFromEntityInWorldCoords(pedA, off.x, off.y, 0.0)
        local z = U.Ground(p.x, p.y, GetEntityCoords(pedA).z, off.z)
        SetEntityCoordsNoOffset(pedB, p.x, p.y, z, false, false, false)
        SetEntityHeading(pedB, (GetEntityHeading(pedA) + rot.z) % 360.0)
        FreezeEntityPosition(pedB, true)
    end

    startBoth(pedA, pedB, def)
    local token = {}
    Couple.active = { a = pedA, b = pedB, id = coupleId, attached = b.attach == true, token = token }
    -- Verify + restart BOTH together (a solo retry would desync the pair)
    CreateThread(function()
        for _ = 1, 5 do
            Wait(180)
            if not Couple.active or Couple.active.token ~= token then return end
            if not DoesEntityExist(pedA) or not DoesEntityExist(pedB) then return end
            if animsPlaying(pedA, pedB, def) then return end
            startBoth(pedA, pedB, def)
        end
    end)
    return true
end

-- Releases the pair; callers re-place pedB on its own mark (Actors.Refresh does)
function Couple.Stop()
    local c = Couple.active
    if not c then return end
    Couple.active = nil
    if DoesEntityExist(c.b) then
        if IsEntityAttached(c.b) then DetachEntity(c.b, false, false) end
        ClearPedTasks(c.b)
    end
    if DoesEntityExist(c.a) then ClearPedTasks(c.a) end
end
