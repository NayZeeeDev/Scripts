-- ═══════════════════════════════════════════════════════════════
--  CARRY SYSTEM - bags on shoulder, crates/coffins box-carry
--  The SERVER decides who is carrying what (claimCarry), so two
--  players can never grab the same bag.
-- ═══════════════════════════════════════════════════════════════

local function carryAnimFor(kind)
    local a = Config.CarryAnims[kind] or Config.CarryAnims.bodybag
    return { dict = a.Dict, clip = a.Clip, bone = a.Bone, offset = a.Offset, rot = a.Rot }
end

function RequestControl(entity, ms)
    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + (ms or 2000)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
    end
    return NetworkHasControlOfEntity(entity)
end

local function carryHint()
    ShowHint(('[%s] Drop  •  Third-eye: crate / barrel / trunk / grave / water'):format(Config.DropKey or 'G'))
end

function StartCarrying(entity, kind)
    if Carrying.entity or IsBusy() then return end
    if IsPedInAnyVehicle(cache.ped, false) then return end
    local netId = NetOf(entity)

    -- ask the server first: is anyone else holding it?
    local claim = lib.callback.await('nayzeee-bodybag:claimCarry', false, netId)
    if claim ~= true then return Config.Notify(claim or 'Couldn\'t grab it - try again', 'error') end

    local a = carryAnimFor(kind)
    SetNetworkIdCanMigrate(netId, true)
    if not RequestControl(entity, 3000) then
        TriggerServerEvent('nayzeee-bodybag:server:releaseCarry', netId)
        return Config.Notify('Couldn\'t grab it - try again', 'error')
    end

    FreezeEntityPosition(entity, false)
    lib.requestAnimDict(a.dict, 5000)
    AttachEntityToEntity(entity, cache.ped, GetPedBoneIndex(cache.ped, a.bone),
        a.offset.x, a.offset.y, a.offset.z, a.rot.x, a.rot.y, a.rot.z, true, true, false, true, 1, true)
    if not IsEntityAttachedToEntity(entity, cache.ped) then
        FreezeEntityPosition(entity, true)
        TriggerServerEvent('nayzeee-bodybag:server:releaseCarry', netId)
        return Config.Notify('Couldn\'t grab it - try again', 'error')
    end

    Carrying = { entity = entity, netId = netId, kind = kind }
    carryHint()

    -- anim upkeep + control disables + auto-drop
    CreateThread(function()
        while Carrying.entity == entity do
            if not DoesEntityExist(entity) then
                StopCarrying(false)
                break
            end
            local ped = cache.ped
            if (Config.Carry.DropOnDeath and IsPedDeadOrDying(ped, true))
                or (Config.Carry.DropOnRagdoll and IsPedRagdoll(ped)) then
                StopCarrying(true)
                Config.Notify('You dropped it!', 'error')
                break
            end
            if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, 51, 0, false, false, false)
            end
            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 44, true)  -- cover
            DisableControlAction(0, 23, true)  -- enter vehicle
            Wait(0)
        end
    end)
end

-- dropProp = true  -> put it down on the ground in front of you
-- handoff  = true  -> the server already took it (loaded/dumped/trunked), don't release the claim
function StopCarrying(dropProp, handoff)
    local ent, netId = Carrying.entity, Carrying.netId
    if not ent then return end
    Carrying = { entity = nil, netId = nil, kind = nil }
    HideHint()

    if DoesEntityExist(ent) then
        -- ownership can migrate while attached - MUST re-own before detach or it silently fails
        RequestControl(ent, 1500)
        DetachEntity(ent, true, true)
        if dropProp then
            local c = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.0, 0.0)
            SetEntityCoords(ent, c.x, c.y, c.z - 0.5, false, false, false, false)
            PlaceObjectOnGroundProperly(ent)
            FreezeEntityPosition(ent, true)
        end
    end
    ClearPedTasks(cache.ped)
    if netId and not handoff then TriggerServerEvent('nayzeee-bodybag:server:releaseCarry', netId) end
end

-- server removed the thing we're holding (acid, admin, etc)
RegisterNetEvent('nayzeee-bodybag:client:containerGone', function(netId)
    if Carrying.netId == netId then StopCarrying(false, true) end
end)

-- real keybind: registered once, can never miss a press or die with a thread
lib.addKeybind({
    name = 'nz_drop',
    description = 'Drop carried body bag / crate / coffin',
    defaultKey = Config.DropKey or 'G',
    onPressed = function()
        if Carrying.entity then CreateThread(function() StopCarrying(true) end) end
    end,
})

-- ═══════════════════════════════════════════════════════════════
--  CEMETERY GRAVE HOLE - snap the carried container into the hole
-- ═══════════════════════════════════════════════════════════════
function PlaceInGraveHole()
    local ent = Carrying.entity
    if not ent or IsBusy() then return end
    if not Progress('Lowering into the grave...', 4000) then return end
    StopCarrying(false)
    if DoesEntityExist(ent) then
        RequestControl(ent, 1500)
        local hc = Config.Burial.Cemetery.Coords
        SetEntityCoordsNoOffset(ent, hc.x, hc.y, hc.z, false, false, false)
        SetEntityHeading(ent, Config.Burial.Cemetery.HoleHeading or 0.0)
        FreezeEntityPosition(ent, true)
    end
    Config.Notify('Lowered into the grave. Grab your shovel to fill it in.', 'inform')
end

-- ═══════════════════════════════════════════════════════════════
--  WATER DUMP - third-eye zones with throw animation
-- ═══════════════════════════════════════════════════════════════
local function dumpAtSpot()
    local kind, netId, ent = Carrying.kind, Carrying.netId, Carrying.entity
    if not ent or IsBusy() then return end
    if Config.WaterDump.RequireCrate and kind == 'bodybag' then
        return Config.Notify('The bag will float... you need a weighted crate', 'error')
    end
    if not Progress('Heaving it toward the water...', 4000) then return end

    -- server checks we're really at a dump spot and takes the body
    if not lib.callback.await('nayzeee-bodybag:waterDump', false, netId) then
        return Config.Notify('You can\'t dump it here', 'error')
    end

    -- throw
    lib.requestAnimDict('weapons@projectile@')
    TaskPlayAnim(cache.ped, 'weapons@projectile@', 'throw_m_fb_stand', 8.0, -8.0, 1200, 48, 0, false, false, false)
    Wait(400)

    Carrying = { entity = nil, netId = nil, kind = nil }
    HideHint()
    if DoesEntityExist(ent) then
        RequestControl(ent, 1000)
        DetachEntity(ent, true, true)
        FreezeEntityPosition(ent, false)
        local fwd = GetEntityForwardVector(cache.ped)
        ApplyForceToEntity(ent, 1, fwd.x * Config.WaterDump.ThrowForce, fwd.y * Config.WaterDump.ThrowForce,
            Config.WaterDump.ThrowLift, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
    end
    Wait(1500)
    ClearPedTasks(cache.ped)
end

CreateThread(function()
    for i, zone in ipairs(Config.WaterDump.Zones) do
        exports.ox_target:addSphereZone({
            coords = zone.coords,
            radius = zone.radius or 4.0,
            name = 'nz_dump_' .. i,
            options = {
                {
                    name = 'nz_dump_body_' .. i,
                    icon = 'fas fa-water',
                    label = 'Dump Body Here',
                    canInteract = function() return Carrying.entity ~= nil end,
                    onSelect = dumpAtSpot,
                },
            },
        })
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  CLEANUP on resource stop (no waiting allowed here)
-- ═══════════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Carrying.entity then return end
    if DoesEntityExist(Carrying.entity) then DetachEntity(Carrying.entity, true, true) end
    ClearPedTasks(cache.ped)
    HideHint()
end)
