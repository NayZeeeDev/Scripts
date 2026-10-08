--[[ Carrying heavy loot (paintings, TVs, registers, gold crates). One control thread only while carrying. ]]

Carry = { entity = nil }

local DICT, CLIP = 'anim@heists@box_carry@', 'idle'

---@param model string|number
---@param opts? { pos?: vector3, rot?: vector3, bone?: number, existing?: number }
function Carry.start(model, opts)
    if Carry.entity then return nil end
    opts = opts or {}
    local ped = cache.ped
    local obj
    if opts.existing and DoesEntityExist(opts.existing) then
        obj = opts.existing
        FreezeEntityPosition(obj, false)
        SetEntityCollision(obj, false, false)
    else
        obj = Props.attach(ped, model, opts.bone or 28422, opts.pos or vec3(0.0, -0.05, -0.1), opts.rot or vec3(0.0, 0.0, 0.0))
    end
    if not obj then return nil end
    if opts.existing then
        AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, opts.bone or 28422),
            (opts.pos or vec3(0.0, -0.05, -0.1)).x, (opts.pos or vec3(0.0, -0.05, -0.1)).y, (opts.pos or vec3(0.0, -0.05, -0.1)).z,
            0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    Carry.entity = obj
    lib.requestAnimDict(DICT)
    TaskPlayAnim(ped, DICT, CLIP, 8.0, 8.0, -1, 49, 0, false, false, false)

    CreateThread(function()
        while Carry.entity do
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- jump
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            DisableControlAction(0, 23, true) -- enter vehicle
            if not IsEntityPlayingAnim(cache.ped, DICT, CLIP, 3) then
                TaskPlayAnim(cache.ped, DICT, CLIP, 8.0, 8.0, -1, 49, 0, false, false, false)
            end
            if IsEntityDead(cache.ped) or IsPedRagdoll(cache.ped) then Carry.drop() end
            Wait(0)
        end
    end)
    return obj
end

--- removes the carried object (delivered)
function Carry.stop()
    local obj = Carry.entity
    Carry.entity = nil
    StopAnimTask(cache.ped, DICT, CLIP, 1.0)
    if obj and DoesEntityExist(obj) then
        DetachEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

--- drops the carried object on the ground (cancelled)
function Carry.drop()
    local obj = Carry.entity
    Carry.entity = nil
    StopAnimTask(cache.ped, DICT, CLIP, 1.0)
    if obj and DoesEntityExist(obj) then
        DetachEntity(obj, true, true)
        SetEntityCollision(obj, true, true)
        PlaceObjectOnGroundProperly(obj)
        SetTimeout(30000, function() if DoesEntityExist(obj) then DeleteEntity(obj) end end)
    end
end

--- nearest vehicle whose trunk is within reach, for "place loot in vehicle"
function Carry.trunkVehicle(maxDist)
    local pc = GetEntityCoords(cache.ped)
    local veh = lib.getClosestVehicle(pc, 8.0, false)
    if not veh then return nil end
    local min, max = GetModelDimensions(GetEntityModel(veh))
    local back = GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.4, 0.0)
    if #(pc - back) <= (maxDist or 2.2) then return veh end
    -- vans: allow the side door too
    local side = GetOffsetFromEntityInWorldCoords(veh, max.x + 0.4, 0.0, 0.0)
    if #(pc - side) <= (maxDist or 2.2) then return veh end
    return nil
end
