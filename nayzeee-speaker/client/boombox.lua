local P = Config.Actions.place
local placing = false
local ghost = nil          -- the see-through preview while placing
local pendingCarry = nil   -- the id the server handed us while its model loads
Carrying = nil             -- { id, item, prop } while you hold a boombox

-- controls that would fight the preview / the carry (weapon wheel and scroll, attack, aim, cover, melee;
-- carrying also blocks sprint, jump and getting into a vehicle)
local PLACE_LOCK = { 14, 15, 16, 17, 24, 25, 37, 44, 140, 141, 142, 257, 263 }
local CARRY_LOCK = { 21, 22, 23, 24, 25, 44, 140, 141, 142, 257, 263 }

-- the "set it down" animation; blocks for its length
local function setDown(ms, blendIn)
    local a = P.anim
    if not a or not Bridge.LoadAnimDict(a.dict) then return end
    ms = ms or a.duration
    local ped = PlayerPedId()
    TaskPlayAnim(ped, a.dict, a.clip, blendIn or 4.0, 4.0, ms, a.flag, 0, false, false, false)
    Wait(ms)
    StopAnimTask(ped, a.dict, a.clip, 2.0)
end

local function groundAt(c)
    local ok, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    return vector3(c.x, c.y, ok and z or c.z)
end

local function rotToDir(rot)
    local p, y = math.rad(rot.x), math.rad(rot.z)
    return vector3(-math.sin(y) * math.abs(math.cos(p)), math.cos(y) * math.abs(math.cos(p)), math.sin(p))
end

---------------------------------------------------------------- placement
local function placementLoop(item, cfg)
    local hash = Bridge.LoadModel(cfg.model)
    if not hash then return end
    local ped = PlayerPedId()
    ghost = CreateObject(hash, GetEntityCoords(ped), false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, 175, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutlineShader(1)
    SetEntityDrawOutline(ghost, true)

    local heading = GetEntityHeading(ped) + 180.0
    local started = GetGameTimer()
    local result, valid, spot = nil, false, nil
    local probe, shownValid, shownHeading = 0, nil, nil

    local hints = {
        { key = 'E', label = NZ.L('k_place') },
        { key = 'G', label = NZ.L('k_cancel') },
        { key = 'Scroll', label = NZ.L('k_rotate') },
    }
    if cfg.portable then table.insert(hints, 2, { key = 'H', label = NZ.L('k_hold') }) end
    ShowHints(hints)

    while not result do
        ped = PlayerPedId()
        -- where the camera points: an async ray, read back a frame later, so aiming never stalls a frame
        if probe == 0 then
            local cam = GetGameplayCamCoord()
            local dest = cam + rotToDir(GetGameplayCamRot(2)) * (P.distance + 6.0)
            probe = StartShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 1 | 16, ped, 7)
        end
        local status, hit, endC, normal = GetShapeTestResult(probe)
        if status ~= 1 then
            probe = 0
            if status == 2 and hit == 1 then
                spot = endC
                SetEntityCoords(ghost, endC.x, endC.y, endC.z, false, false, false, false)
                valid = #(endC - GetEntityCoords(ped)) <= P.distance and normal.z > 0.6 and not NZ.InBlacklistedZone(endC)
            else
                valid = false
            end
        end
        if heading ~= shownHeading then shownHeading = heading SetEntityHeading(ghost, heading) end
        if valid ~= shownValid then
            shownValid = valid
            if valid then SetEntityDrawOutlineColor(8, 175, 162, 255) else SetEntityDrawOutlineColor(229, 72, 77, 255) end
        end

        for i = 1, #PLACE_LOCK do DisableControlAction(0, PLACE_LOCK[i], true) end
        if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then heading = heading + 12.0 end
        if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then heading = heading - 12.0 end

        if IsControlJustPressed(0, P.keys.accept) or IsDisabledControlJustPressed(0, P.keys.accept) then
            if valid then result = 'place' else Notify(NZ.L('placement_far'), 'error') end
        elseif IsControlJustPressed(0, P.keys.cancel) then
            result = 'cancel'
        elseif cfg.portable and IsControlJustPressed(0, P.keys.hold) then
            result = 'hold'
        elseif GetGameTimer() - started > P.timeout or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
            result = 'cancel'
        end
        Wait(0)
    end

    SetEntityDrawOutline(ghost, false)
    DeleteEntity(ghost)
    ghost = nil
    HideHints()

    if result == 'cancel' then return Notify(NZ.L('placement_cancel'), 'inform') end
    if result == 'hold' then
        return TriggerServerEvent(RES .. ':place', item, GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId()), true)
    end
    TaskTurnPedToFaceCoord(PlayerPedId(), spot.x, spot.y, spot.z, 600)
    Wait(600)
    setDown()
    TriggerServerEvent(RES .. ':place', item, spot, heading % 360.0, false)
end

RegisterNetEvent(RES .. ':client:place', function(item)
    local cfg = Config.Boomboxes[item]
    if not cfg or placing or Carrying then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if NZ.InBlacklistedZone(GetEntityCoords(ped)) then return Notify(NZ.L('blacklisted_zone'), 'error') end
    placing = true
    if P.selectLocation then
        placementLoop(item, cfg)
    else
        local o = P.offset
        local spot = groundAt(GetOffsetFromEntityInWorldCoords(ped, o.x, o.y, o.z))
        setDown()
        TriggerServerEvent(RES .. ':place', item, spot, (GetEntityHeading(ped) + o.w) % 360.0, false)
    end
    placing = false
end)

---------------------------------------------------------------- carrying
local function stopCarryLocal()
    if not Carrying then return end
    local c = Carrying
    Carrying = nil
    HideHints()
    local a = Config.Boomboxes[c.item] and Config.Boomboxes[c.item].attach
    if a then StopAnimTask(PlayerPedId(), a.dict, a.clip, 2.0) end
    if c.prop and DoesEntityExist(c.prop) then
        DetachEntity(c.prop, true, false)
        DeleteEntity(c.prop)
    end
end

local function dropCarried(pack)
    if not Carrying then return end
    local id = Carrying.id
    local ped = PlayerPedId()
    if pack then
        stopCarryLocal()
        return TriggerServerEvent(RES .. ':pack', id)
    end
    local spot = groundAt(GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.55, 0.0))
    local heading = (GetEntityHeading(ped) + 180.0) % 360.0
    stopCarryLocal()
    if not IsEntityDead(ped) then setDown(700, 6.0) end
    TriggerServerEvent(RES .. ':drop', id, spot, heading)
end

RegisterNetEvent(RES .. ':client:startCarry', function(id, item)
    local cfg = Config.Boomboxes[item]
    if not cfg or not cfg.attach or Carrying or pendingCarry then return end
    pendingCarry = id
    local hash = Bridge.LoadModel(cfg.model)
    -- the server can take it back (stopCarry) while the model loads
    if pendingCarry ~= id then
        if hash then SetModelAsNoLongerNeeded(hash) end
        return
    end
    pendingCarry = nil
    if not hash then return end

    local a = cfg.attach
    local ped = PlayerPedId()
    local prop = CreateObject(hash, GetEntityCoords(ped), true, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone),
        a.offset.x, a.offset.y, a.offset.z, a.rotation.x, a.rotation.y, a.rotation.z,
        true, true, false, true, 1, true)
    Carrying = { id = id, item = item, prop = prop }
    ShowHints({ { key = Config.Actions.dropKey, label = NZ.L('k_drop') }, { key = Config.Carplay.key, label = NZ.L('t_open') } })

    CreateThread(function()
        local hasDict = Bridge.LoadAnimDict(a.dict)
        local checkAt = 0
        while Carrying and Carrying.id == id do
            local t = GetGameTimer()
            if t >= checkAt then
                checkAt = t + 250
                ped = PlayerPedId()
                if IsEntityDead(ped) or IsPedRagdoll(ped) and GetEntityHealth(ped) <= 0 then
                    -- dying in a blacklisted zone sends it back to the inventory instead of leaving it there
                    dropCarried(NZ.InBlacklistedZone(GetEntityCoords(ped)))
                    break
                end
                -- ragdolls, ladders and vaulting knock the hold animation off: put it back
                if hasDict and not IsPedRagdoll(ped) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
                end
            end
            for i = 1, #CARRY_LOCK do DisableControlAction(0, CARRY_LOCK[i], true) end
            Wait(0)
        end
    end)
end)

RegisterNetEvent(RES .. ':client:stopCarry', function(id)
    if pendingCarry == id then pendingCarry = nil end
    if Carrying and Carrying.id == id then stopCarryLocal() end
end)

RegisterCommand('+nzspk_drop', function() if Carrying then CreateThread(function() dropCarried(false) end) end end, false)
RegisterCommand('-nzspk_drop', function() end, false)
RegisterKeyMapping('+nzspk_drop', 'Speaker: put down boombox', 'keyboard', Config.Actions.dropKey)

---------------------------------------------------------------- interaction on placed boomboxes
-- target resources ask every option's canInteract every frame you aim at a prop: the state bag
-- read behind it is remembered for a moment instead of repeated six times a frame
local lastEnt, lastId, lastAt = nil, nil, 0

local function emitterOf(entity)
    if not entity or entity == 0 then return nil end
    local t = GetGameTimer()
    if entity ~= lastEnt or t - lastAt > 500 then
        lastEnt, lastAt = entity, t
        lastId = Entity(entity).state.nzspk
    end
    return lastId and Emitters[lastId]
end

local function canPickup(e)
    return Config.Actions.pickup == 'anyone' or IsMine(e)
end

local models = {}
for _, cfg in pairs(Config.Boomboxes) do models[#models + 1] = joaat(cfg.model) end

local options = {
    { name = 'nzspk_open', label = NZ.L('t_open'), icon = 'fa-solid fa-music',
      canInteract = function(ent) return emitterOf(ent) ~= nil end,
      action = function(ent) local e = emitterOf(ent) if e then OpenUI(e.id) end end },
    { name = 'nzspk_play', label = NZ.L('t_play'), icon = 'fa-solid fa-play',
      canInteract = function(ent) local e = emitterOf(ent) return e and e.track and not e.playing end,
      action = function(ent) local e = emitterOf(ent) if e then TriggerServerEvent(RES .. ':toggle', e.id) end end },
    { name = 'nzspk_pause', label = NZ.L('t_pause'), icon = 'fa-solid fa-pause',
      canInteract = function(ent) local e = emitterOf(ent) return e and e.playing end,
      action = function(ent) local e = emitterOf(ent) if e then TriggerServerEvent(RES .. ':pause', e.id) end end },
    { name = 'nzspk_stop', label = NZ.L('t_stop'), icon = 'fa-solid fa-volume-xmark',
      canInteract = function(ent) local e = emitterOf(ent) return e and e.track ~= nil end,
      action = function(ent) local e = emitterOf(ent) if e then TriggerServerEvent(RES .. ':stop', e.id) end end },
    { name = 'nzspk_carry', label = NZ.L('t_carry'), icon = 'fa-solid fa-person-walking-luggage',
      canInteract = function(ent)
          local e = emitterOf(ent)
          return e and Config.Boomboxes[e.item] and Config.Boomboxes[e.item].portable and canPickup(e) and not Carrying
      end,
      action = function(ent) local e = emitterOf(ent) if e then TriggerServerEvent(RES .. ':carry', e.id) end end },
    { name = 'nzspk_take', label = NZ.L('t_take'), icon = 'fa-solid fa-hand-holding',
      canInteract = function(ent) local e = emitterOf(ent) return e and canPickup(e) end,
      action = function(ent) local e = emitterOf(ent) if e then TriggerServerEvent(RES .. ':pack', e.id) end end },
}

if Bridge.Target then
    Bridge.AddModelTarget(models, options)
else
    -- no target resource: [E] prompt on the closest placed boombox, looked for twice a second
    local reach = Config.Actions.useRange
    CreateThread(function()
        while true do
            local near, nearPos, best = nil, nil, reach
            if not UI.open and not Carrying and not placing then
                local me = GetEntityCoords(PlayerPedId())
                for _, e in pairs(Emitters) do
                    local c = e.kind == 'boombox' and e.state == 'placed' and e.coords
                    -- the snapshot coords rule out every far one before any native is called
                    if c and #(me - c) < best + 1.0 then
                        local _, pos = LocateEmitter(e)
                        local d = pos and #(me - pos)
                        if d and d < best then near, nearPos, best = e, pos, d end
                    end
                end
            end
            if not near then
                Wait(500)
            else
                local id, at, text = near.id, nearPos + vector3(0.0, 0.0, 0.6), NZ.L('prompt')
                local t = GetGameTimer()
                while GetGameTimer() - t < 500 and not UI.open do
                    Bridge.DrawPrompt(at, text)
                    if IsControlJustPressed(0, 38) then OpenUI(id) break end
                    Wait(0)
                end
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    stopCarryLocal()
    if Bridge.Target then
        local names = {}
        for _, o in ipairs(options) do names[#names + 1] = o.name end
        Bridge.RemoveModelTarget(models, names)
    end
end)
