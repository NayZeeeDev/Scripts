--[[
    NAYZEEE BILLING - Register placement (admin)
    Started from the Billing Admin page:
      prop   restaurants without a till: the till prop follows your crosshair (or hold it in your hands) and you place it
      point  restaurants that already have a till: aim the ball at the till, that spot becomes the third-eye target
]]

Placing = false

local CFG = Config.Registers.Placement
local COLOR = { 15, 212, 196 }
local COLOR_BAD = { 229, 72, 77 }

local K = {
    place = 38,          -- E
    hold = 74,           -- H
    cancel = 47,         -- G
    cancelAlt = 177,     -- Backspace
    scrollUp = 241, scrollDown = 242,
    fine = 21,           -- Shift
}
local Blocked = { 24, 25, 14, 15, 16, 17, 37, 44, 47, 58, 74, 140, 141, 142, 177, 199, 200, 241, 242, 257, 261, 262, 263, 264, 38 }
local CARRY = { dict = 'anim@heists@box_carry@', anim = 'idle', bone = 60309, pos = vector3(0.025, 0.08, 0.255), rot = vector3(-145.0, 290.0, 0.0) }

local function dbg(...) if Config.Registers.Debug then print('^5[NAYZEEE-BILLING placement]^7', ...) end end

local function loadModel(model)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return false end
    RequestModel(model)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function direction(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

-- Synchronous line test (1 world + 16 objects), ignoring one entity
local function ray(from, to, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 17, ignore or 0, 4)
    local _, hit, coords = GetShapeTestResult(h)
    return hit == 1, coords
end

local function crosshair(ignore)
    local from = GetGameplayCamCoord()
    return ray(from, from + direction(GetGameplayCamRot(2)) * (CFG.Distance + 8.0), ignore)
end

local function marker(kind, c, sx, sy, sz, col, alpha)
    DrawMarker(kind, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sx, sy, sz, col[1], col[2], col[3], alpha, false, false, 2, false, nil, nil, false)
end

-- Bottom-centre key bar (NUI)
local lastHud
local function hud(keys)
    local key = json.encode(keys)
    if key == lastHud then return end
    lastHud = key
    UI.Send('placeHud', { keys = keys })
end
local function hideHud() lastHud = nil UI.Send('placeHud', false) end

--[[
    job = { mode = 'prop'|'point', id? (move), label, society, radius, model?, heading? }
    Returns the placement table or nil when cancelled
]]
local function place(job)
    local ped = PlayerPedId()
    local radius = Shared.Clamp(tonumber(job.radius) or CFG.DefaultRadius or 1.0, 0.5, 10.0)
    local heading = (tonumber(job.heading) or GetEntityHeading(ped)) % 360
    local ghost, minZ, holding, holdRot = nil, 0.0, false, 0.0
    local model = job.mode == 'prop' and joaat(job.model) or nil

    if model then
        if not loadModel(model) then
            ClientBridge.Notify(Config.UI.Title, L('error.prop_missing', 'That prop could not be loaded: {model}', { model = job.model }), 'error')
            dbg('model failed to load', job.model)
            return nil
        end
        minZ = (GetModelDimensions(model)).z
        local _, at = crosshair(ped)
        local p = at or GetEntityCoords(ped)
        ghost = CreateObject(model, p.x, p.y, p.z, false, false, false)
        SetModelAsNoLongerNeeded(model)
        if not ghost or ghost == 0 then
            ClientBridge.Notify(Config.UI.Title, L('error.prop_missing', 'That prop could not be loaded: {model}', { model = job.model }), 'error')
            return nil
        end
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        SetEntityInvincible(ghost, true)
        SetEntityVisible(ghost, true, false)
        SetEntityLodDist(ghost, 500)
        dbg('ghost created', ghost, job.model)
    end

    local function release()
        if not holding then return end
        holding = false
        DetachEntity(ghost, true, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        StopAnimTask(ped, CARRY.dict, CARRY.anim, 1.0)
        RemoveAnimDict(CARRY.dict)
    end

    local result
    while true do
        Wait(0)
        for _, k in ipairs(Blocked) do DisableControlAction(0, k, true) end
        local fine = IsDisabledControlPressed(0, K.fine)
        local origin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.35)
        local valid, spot = false, nil

        if job.mode == 'prop' then
            local step = fine and 1.0 or 7.5
            local delta = (IsDisabledControlJustPressed(0, K.scrollUp) and step or 0) - (IsDisabledControlJustPressed(0, K.scrollDown) and step or 0)
            if holding then holdRot = (holdRot + delta) % 360 else heading = (heading + delta) % 360 end

            if IsDisabledControlJustPressed(0, K.hold) then
                if holding then release()
                else
                    holding, holdRot = true, 0.0
                    if loadDict(CARRY.dict) then TaskPlayAnim(ped, CARRY.dict, CARRY.anim, 8.0, -8.0, -1, 49, 0, false, false, false) end
                    FreezeEntityPosition(ghost, false)
                    AttachEntityToEntity(ghost, ped, GetPedBoneIndex(ped, CARRY.bone), CARRY.pos.x, CARRY.pos.y, CARRY.pos.z,
                        CARRY.rot.x, CARRY.rot.y, CARRY.rot.z, true, true, false, true, 1, true)
                end
            end

            if holding then
                -- Carried: E drops it straight down onto whatever is under it (counter, desk, floor)
                if not IsEntityPlayingAnim(ped, CARRY.dict, CARRY.anim, 3) and HasAnimDictLoaded(CARRY.dict) then
                    TaskPlayAnim(ped, CARRY.dict, CARRY.anim, 8.0, -8.0, -1, 49, 0, false, false, false)
                end
                local p = GetEntityCoords(ghost)
                local hit, below = ray(p + vector3(0.0, 0.0, 0.15), p - vector3(0.0, 0.0, 2.5), ghost)
                if hit then
                    valid = true
                    spot = vector3(below.x, below.y, below.z - minZ)
                    marker(28, below, 0.05, 0.05, 0.05, COLOR, 200)
                end
            else
                local hit, at = crosshair(ghost)
                valid = hit and #(origin - at) <= CFG.Distance
                if hit then
                    spot = vector3(at.x, at.y, at.z - minZ)
                    SetEntityCoordsNoOffset(ghost, spot.x, spot.y, spot.z, false, false, false)
                    SetEntityHeading(ghost, heading)
                end
            end

            hud({
                { k = 'E', l = L('place.key_place', 'Place'), off = not valid },
                { k = 'H', l = holding and L('place.key_aim', 'Aim with crosshair') or L('place.key_hold', 'Hold in hand') },
                { k = 'G', l = L('place.key_cancel', 'Cancel') },
                { k = 'Scroll', l = L('place.key_rotate', 'Rotate'), wide = true },
            })
        else
            local step = fine and 0.05 or 0.25
            if IsDisabledControlJustPressed(0, K.scrollUp) then radius = math.min(radius + step, 10.0) end
            if IsDisabledControlJustPressed(0, K.scrollDown) then radius = math.max(radius - step, 0.5) end
            local hit, at = crosshair(ped)
            valid = hit and #(origin - at) <= CFG.Distance
            spot = at
            if hit then
                local col = valid and COLOR or COLOR_BAD
                -- ball with a ring around it on the spot the third eye will target
                DrawLine(origin.x, origin.y, origin.z, at.x, at.y, at.z, col[1], col[2], col[3], 160)
                marker(28, at, 0.14, 0.14, 0.14, col, 215)
                marker(27, at, 0.46, 0.46, 0.46, col, 235)
            end
            hud({
                { k = 'E', l = L('place.key_place', 'Place'), off = not valid },
                { k = 'G', l = L('place.key_cancel', 'Cancel') },
                { k = 'Scroll', l = L('place.key_radius', 'Radius {r} m', { r = ('%.2f'):format(radius) }), wide = true },
            })
        end

        if IsDisabledControlJustPressed(0, K.cancel) or IsDisabledControlJustPressed(0, K.cancelAlt) then break end
        if IsDisabledControlJustPressed(0, K.place) then
            if valid and spot then
                -- carried tills face the way you are facing (plus any scroll rotation)
                local h = (job.mode == 'prop' and holding) and (GetEntityHeading(ped) + holdRot) % 360 or heading
                result = { coords = { x = spot.x, y = spot.y, z = spot.z }, heading = h, model = job.mode == 'prop' and job.model or nil, radius = radius }
                dbg('placed', json.encode(result))
                break
            end
            PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
    end

    release()
    hideHud()
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    return result
end

RegisterNUICallback('placeRegister', function(job, cb)
    cb('ok')
    if Placing or type(job) ~= 'table' or (job.mode ~= 'prop' and job.mode ~= 'point') then return end
    if job.mode == 'prop' and type(job.model) ~= 'string' then
        ClientBridge.Notify(Config.UI.Title, L('error.pick_prop', 'Pick a prop first'), 'error')
        return
    end
    CreateThread(function()
        if not lib.callback.await('nayzeee-billing:isAdmin', false) then return end
        Placing = true
        CloseBilling()
        Wait(150)
        local ok, spot = pcall(place, job)
        Placing = false
        hideHud()
        if not ok then
            print('^1[NAYZEEE-BILLING]^7 Placement error: ' .. tostring(spot))
            ClientBridge.Notify(Config.UI.Title, L('place.failed', 'Placement failed - see F8'), 'error')
        elseif not spot then
            ClientBridge.Notify(Config.UI.Title, L('place.cancelled', 'Placement cancelled'), 'info')
        else
            local saved, err = Rpc(job.id and 'admin:moveRegister' or 'admin:addRegister', {
                id = job.id, label = job.label, society = job.society, radius = spot.radius, placement = spot,
            })
            if saved then
                ClientBridge.Notify(Config.UI.Title, job.id and L('place.moved', 'Register moved') or L('place.added', 'Register added'), 'success')
            else
                ClientBridge.Notify(Config.UI.Title, err, 'error')
            end
        end
        OpenBilling('admin', { registers = true })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Placing then hideHud() end
end)
