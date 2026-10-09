local P = Config.Actions.place
local placing = false
Carrying = nil            -- { id, item, prop }

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < 5000 do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer()
    while not HasAnimDictLoaded(dict) and GetGameTimer() - t < 3000 do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function placeAnim()
    local a = P.anim
    if not a or not loadDict(a.dict) then return end
    local ped = PlayerPedId()
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, 4.0, a.duration, a.flag, 0, false, false, false)
    Wait(a.duration)
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
    local hash = loadModel(cfg.model)
    if not hash then return end
    local ped = PlayerPedId()
    local ghost = CreateObject(hash, GetEntityCoords(ped), false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, 175, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutlineShader(1)
    SetEntityDrawOutline(ghost, true)

    local heading = GetEntityHeading(ped) + 180.0
    local started = GetGameTimer()
    local result, valid, spot = nil, false, nil

    local hints = {
        { key = 'E', label = NZ.L('k_place') },
        { key = 'G', label = NZ.L('k_cancel') },
        { key = 'Scroll', label = NZ.L('k_rotate') },
    }
    if cfg.portable then table.insert(hints, 2, { key = 'H', label = NZ.L('k_hold') }) end
    ShowHints(hints)

    while not result do
        ped = PlayerPedId()
        local cam = GetGameplayCamCoord()
        local dest = cam + rotToDir(GetGameplayCamRot(2)) * (P.distance + 6.0)
        local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 1 | 16, ped, 7)
        local _, hit, endC, normal = GetShapeTestResult(h)

        if hit == 1 then
            spot = endC
            SetEntityCoords(ghost, endC.x, endC.y, endC.z, false, false, false, false)
            valid = #(endC - GetEntityCoords(ped)) <= P.distance and normal.z > 0.6 and not NZ.InBlacklistedZone(endC)
        else
            valid = false
        end
        SetEntityHeading(ghost, heading)
        if valid then SetEntityDrawOutlineColor(8, 175, 162, 255) else SetEntityDrawOutlineColor(229, 72, 77, 255) end

        for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 37, 44, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
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
    HideHints()

    if result == 'cancel' then return Notify(NZ.L('placement_cancel'), 'inform') end
    if result == 'hold' then
        return TriggerServerEvent(RES .. ':place', item, GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId()), true)
    end
    TaskTurnPedToFaceCoord(PlayerPedId(), spot.x, spot.y, spot.z, 600)
    Wait(600)
    placeAnim()
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
        placeAnim()
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
    local ped = PlayerPedId()
    local a = Config.Boomboxes[c.item] and Config.Boomboxes[c.item].attach
    if a then StopAnimTask(ped, a.dict, a.clip, 2.0) end
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
    if not IsEntityDead(ped) then
        local a = P.anim
        if a and loadDict(a.dict) then
            TaskPlayAnim(ped, a.dict, a.clip, 6.0, 4.0, 700, a.flag, 0, false, false, false)
            Wait(700)
            StopAnimTask(ped, a.dict, a.clip, 2.0)
        end
    end
    TriggerServerEvent(RES .. ':drop', id, spot, heading)
end

RegisterNetEvent(RES .. ':client:startCarry', function(id, item)
    local cfg = Config.Boomboxes[item]
    if not cfg or not cfg.attach or Carrying then return end
    local ped = PlayerPedId()
    local hash = loadModel(cfg.model)
    if not hash then return end
    local a = cfg.attach
    local prop = CreateObject(hash, GetEntityCoords(ped), true, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone),
        a.offset.x, a.offset.y, a.offset.z, a.rotation.x, a.rotation.y, a.rotation.z,
        true, true, false, true, 1, true)
    Carrying = { id = id, item = item, prop = prop }
    ShowHints({ { key = Config.Actions.dropKey, label = NZ.L('k_drop') }, { key = Config.Carplay.key, label = NZ.L('t_open') } })

    CreateThread(function()
        local hasDict = loadDict(a.dict)
        while Carrying and Carrying.id == id do
            ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedRagdoll(ped) and GetEntityHealth(ped) <= 0 then
                dropCarried(NZ.InBlacklistedZone(GetEntityCoords(ped)))
                break
            end
            if hasDict and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) and not IsPedRagdoll(ped) then
                TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
            end
            for _, c in ipairs({ 21, 22, 23, 24, 25, 44, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
            Wait(0)
        end
    end)
end)

RegisterNetEvent(RES .. ':client:stopCarry', function(id)
    if Carrying and Carrying.id == id then stopCarryLocal() end
end)

RegisterCommand('+nzspk_drop', function() if Carrying then CreateThread(function() dropCarried(false) end) end end, false)
RegisterCommand('-nzspk_drop', function() end, false)
RegisterKeyMapping('+nzspk_drop', 'Speaker: put down boombox', 'keyboard', Config.Actions.dropKey)

---------------------------------------------------------------- interaction on placed boomboxes
local function emitterOf(entity)
    local id = entity and Entity(entity).state.nzspk
    return id and Emitters[id]
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
    -- no target resource: [E] prompt on the closest boombox
    CreateThread(function()
        while true do
            local near, best = nil, Config.Actions.useRange
            local me = GetEntityCoords(PlayerPedId())
            for _, e in pairs(Emitters) do
                if e.kind == 'boombox' and e.state == 'placed' then
                    local ent, pos = LocateEmitter(e)
                    if pos and #(me - pos) < best then near, best = { e = e, pos = pos }, #(me - pos) end
                end
            end
            if not near or UI.open or Carrying then
                Wait(500)
            else
                local t = GetGameTimer()
                while GetGameTimer() - t < 500 do
                    local p = near.pos + vector3(0.0, 0.0, 0.6)
                    SetDrawOrigin(p.x, p.y, p.z, 0)
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(NZ.L('prompt'))
                    SetTextScale(0.32, 0.32) SetTextFont(4) SetTextCentre(true) SetTextOutline()
                    EndTextCommandDisplayText(0.0, 0.0)
                    ClearDrawOrigin()
                    if IsControlJustPressed(0, 38) then OpenUI(near.e.id) break end
                    Wait(0)
                end
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if Carrying and Carrying.prop and DoesEntityExist(Carrying.prop) then DeleteEntity(Carrying.prop) end
    if Bridge.Target then
        local names = {}
        for _, o in ipairs(options) do names[#names + 1] = o.name end
        Bridge.RemoveModelTarget(models, names)
    end
end)
