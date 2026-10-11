-- ═══════════════════════════════════════════════════════════
--  CAMERAS — world props, live viewing, placement
-- ═══════════════════════════════════════════════════════════

Cameras = {
    list    = {},     -- [camId] = record from the server
    props   = {},     -- [camId] = entity handle
    viewing = nil,    -- the camera currently on screen
    cam     = nil,    -- the scripted GTA camera
    placing = false
}

local function modelFor(model)
    for _, m in ipairs(Config.Cameras.models or {}) do
        if m.model == model then return m end
    end
    return Config.Cameras.models and Config.Cameras.models[1] or nil
end

-- ═══════════════════════════════════════════════════════════
--  WORLD PROPS
-- ═══════════════════════════════════════════════════════════
local function dropProp(camId)
    local prop = Cameras.props[camId]
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    Cameras.props[camId] = nil
end

local function spawnProp(cam)
    if Cameras.props[cam.id] and DoesEntityExist(Cameras.props[cam.id]) then return end

    local model = joaat(cam.model)
    if not lib.requestModel(model, 4000) then return end

    local prop = CreateObject(model, cam.coords.x, cam.coords.y, cam.coords.z, false, false, false)
    SetEntityRotation(prop, cam.rot.x or 0.0, cam.rot.y or 0.0, cam.rot.z or 0.0, 2, true)
    FreezeEntityPosition(prop, true)
    SetEntityInvincible(prop, not Config.Cameras.destructible)
    SetModelAsNoLongerNeeded(model)

    -- a destroyed camera hangs dark and broken
    if cam.status == 'destroyed' then
        SetEntityAlpha(prop, 160, false)
    end

    Cameras.props[cam.id] = prop
end

--- @param rows table|nil the list pushed by the server; fetched when missing
local function refreshList(rows)
    if type(rows) ~= 'table' then rows = lib.callback.await('nz_mdt:cameras:world', false) end
    Cameras.list = {}
    for _, c in ipairs(rows or {}) do Cameras.list[c.id] = c end

    -- drop anything the server no longer knows about
    for camId in pairs(Cameras.props) do
        if not Cameras.list[camId] then dropProp(camId) end
    end
end

local function changed(a, b)
    if not a or not b then return false end
    if a.model ~= b.model or a.status ~= b.status then return true end
    local ac, bc, ar, br = a.coords or {}, b.coords or {}, a.rot or {}, b.rot or {}
    return ac.x ~= bc.x or ac.y ~= bc.y or ac.z ~= bc.z or ar.x ~= br.x or ar.z ~= br.z
end

RegisterNetEvent('nz_mdt:cameras:refresh', function(rows)
    if not Config.Cameras.enabled then return end
    local before = Cameras.list
    refreshList(rows)
    -- respawn only the props whose model, position or state actually changed
    for camId in pairs(Cameras.props) do
        if changed(before[camId], Cameras.list[camId]) then dropProp(camId) end
    end
end)

--- Spawn and despawn camera props as the player moves around.
CreateThread(function()
    if not Config.Cameras.enabled then return end

    Wait(4000)
    refreshList()

    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local range = Config.Cameras.spawnDistance or 40.0

        for camId, cam in pairs(Cameras.list) do
            local d = #(pos - vec3(cam.coords.x, cam.coords.y, cam.coords.z))
            if d <= range then
                if not Cameras.props[camId] then spawnProp(cam) end
            elseif Cameras.props[camId] then
                dropProp(camId)
            end
        end

        Wait((Config.Cameras.checkSeconds or 2) * 1000)
    end
end)

--- Watch for a camera being shot out.
CreateThread(function()
    if not Config.Cameras.enabled or not Config.Cameras.destructible then return end

    while true do
        local sleep = next(Cameras.props) and 1500 or 4000
        for camId, prop in pairs(Cameras.props) do
            if prop and DoesEntityExist(prop) then
                if IsEntityDead(prop) or HasEntityBeenDamagedByAnyPed(prop) then
                    local cam = Cameras.list[camId]
                    if cam and cam.status ~= 'destroyed' then
                        cam.status = 'destroyed'
                        SetEntityAlpha(prop, 160, false)
                        ClearEntityLastDamageEntity(prop)
                        TriggerServerEvent('nz_mdt:camera:destroyed', camId)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  LIVE VIEW
-- ═══════════════════════════════════════════════════════════
--- @param closing boolean the tablet is going away too, so do not hand focus back
function Cameras.stopView(closing)
    if not Cameras.viewing then return end

    RenderScriptCams(false, false, 0, true, true)
    if Cameras.cam then
        DestroyCam(Cameras.cam, true)
        Cameras.cam = nil
    end

    Cameras.viewing = nil
    ClearFocus()
    ClearTimecycleModifier()
    DisplayRadar(true)
    SendNUIMessage({ action = 'cameraView', on = false })

    -- hand control back to the tablet if it is still open behind the feed
    if MDT.isOpen and not closing then SetNuiFocus(true, true) end
end

function Cameras.view(cam)
    if not cam or not cam.coords then return end
    Cameras.stopView()

    local spec = modelFor(cam.model) or {}
    local offset = spec.offset or vec3(0.0, 0.0, -0.1)
    local rotOff = spec.rot or vec3(-10.0, 0.0, 180.0)

    local x = cam.coords.x + (offset.x or 0.0)
    local y = cam.coords.y + (offset.y or 0.0)
    local z = cam.coords.z + (offset.z or 0.0)

    -- stream the area in first or the feed shows an empty world
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(x, y, z)

    Cameras.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', x, y, z,
        (cam.rot.x or 0.0) + (rotOff.x or 0.0),
        (cam.rot.y or 0.0) + (rotOff.y or 0.0),
        (cam.rot.z or 0.0) + (rotOff.z or 0.0),
        62.0, false, 0)

    SetCamActive(Cameras.cam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.0)
    DisplayRadar(false)

    Cameras.viewing = cam
    SendNUIMessage({ action = 'cameraView', on = true, data = cam })

    -- release the cursor so the arrow keys reach the game and drive the camera
    SetNuiFocus(false, false)
end

-- controls the officer's body must not get while watching a feed
local FEED_BLOCK = { 30, 31, 32, 33, 34, 35, 21, 22, 23, 24, 25, 37, 44, 45, 140, 141, 142, 143, 199, 200, 257, 263, 264 }

--- Pan and tilt the live feed with the arrow keys.
CreateThread(function()
    while true do
        if Cameras.viewing and Cameras.cam then
            for i = 1, #FEED_BLOCK do DisableControlAction(0, FEED_BLOCK[i], true) end

            local rot = GetCamRot(Cameras.cam, 2)
            local pitch, yaw = rot.x, rot.z
            local moved = false

            if IsControlPressed(0, 174) then yaw = yaw + 1.2; moved = true end   -- left
            if IsControlPressed(0, 175) then yaw = yaw - 1.2; moved = true end   -- right
            if IsControlPressed(0, 172) then pitch = pitch + 0.8; moved = true end -- up
            if IsControlPressed(0, 173) then pitch = pitch - 0.8; moved = true end -- down

            if moved then
                SetCamRot(Cameras.cam, math.max(-75.0, math.min(25.0, pitch)), 0.0, yaw, 2)
            end

            -- zoom
            if IsControlPressed(0, 241) then
                SetCamFov(Cameras.cam, math.max(18.0, GetCamFov(Cameras.cam) - 1.2))
            end
            if IsControlPressed(0, 242) then
                SetCamFov(Cameras.cam, math.min(75.0, GetCamFov(Cameras.cam) + 1.2))
            end

            -- ESC is disabled above so it backs out of the feed instead of opening the pause menu
            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 199) then
                Cameras.stopView()
            end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

RegisterNUICallback('cameraOpen', function(data, cb)
    local res = lib.callback.await('nz_mdt:camera:get', false, data and data.id)
    if not res or not res.ok then
        lib.notify({ title = 'Cameras', description = res and res.msg or 'That feed is down.', type = 'error' })
        return cb({ ok = false })
    end
    Cameras.view(res.camera)
    cb({ ok = true })
end)

RegisterNUICallback('cameraClose', function(_, cb)
    Cameras.stopView()
    cb(1)
end)

-- ═══════════════════════════════════════════════════════════
--  PLACEMENT
-- ═══════════════════════════════════════════════════════════
--- Drag a ghost camera around and drop it where the officer wants.
local function placementLoop(model)
    local hash = joaat(model)
    if not lib.requestModel(hash, 5000) then return nil end

    local ghost = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    SetModelAsNoLongerNeeded(hash)

    local heading = GetEntityHeading(PlayerPedId())
    local pitch = -10.0
    local distance = 2.5
    local result = nil

    lib.showTextUI(
        '[LMB] Place  ·  [RMB] Cancel  \n' ..
        '[Scroll] Distance  ·  [Q/E] Turn  \n' ..
        '[Arrow Up/Down] Tilt')

    while true do
        local ped = PlayerPedId()
        local cam = GetGameplayCamCoord()
        local rot = GetGameplayCamRot(2)

        -- project a point out in front of the camera
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        local cosx = math.abs(math.cos(rx))
        local dir = vec3(-math.sin(rz) * cosx, math.cos(rz) * cosx, math.sin(rx))
        local target = cam + (dir * distance)

        SetEntityCoordsNoOffset(ghost, target.x, target.y, target.z, false, false, false)
        SetEntityRotation(ghost, pitch, 0.0, heading, 2, true)

        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 25, true)   -- aim
        DisableControlAction(0, 44, true)   -- Q
        DisableControlAction(0, 38, true)   -- E
        DisableControlAction(0, 140, true)  -- melee
        DisableControlAction(0, 200, true)  -- pause (ESC cancels instead)

        if IsDisabledControlJustPressed(0, 24) then
            result = {
                coords = { x = target.x, y = target.y, z = target.z },
                rot    = { x = pitch, y = 0.0, z = heading }
            }
            break
        end

        if IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustReleased(0, 200) then break end

        if IsControlPressed(0, 15) then distance = math.min(9.0, distance + 0.08) end
        if IsControlPressed(0, 14) then distance = math.max(0.8, distance - 0.08) end
        if IsDisabledControlPressed(0, 44) then heading = heading + 1.6 end
        if IsDisabledControlPressed(0, 38) then heading = heading - 1.6 end
        if IsControlPressed(0, 172) then pitch = math.min(25.0, pitch + 0.7) end
        if IsControlPressed(0, 173) then pitch = math.max(-75.0, pitch - 0.7) end

        Wait(0)
    end

    lib.hideTextUI()
    if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    return result
end

RegisterNUICallback('cameraPlace', function(data, cb)
    if Cameras.placing then return cb({ ok = false }) end
    Cameras.placing = true

    -- close the MDT so the officer can see where they are putting it
    local wasOpen = MDT.isOpen
    if wasOpen then MDT.close() end
    Wait(250)

    local spot = placementLoop(data and data.model or 'prop_cctv_cam_01a')
    Cameras.placing = false

    if not spot then
        lib.notify({ title = 'Cameras', description = 'Placement cancelled.', type = 'inform' })
        if wasOpen then MDT.open('cameras') end
        return cb({ ok = false })
    end

    local res = lib.callback.await('nz_mdt:camera:place', false, {
        label       = data.label,
        model       = data.model,
        departments = data.departments,
        coords      = spot.coords,
        rot         = spot.rot
    })

    lib.notify({
        title       = 'Cameras',
        description = res and res.msg or 'That did not go through.',
        type        = (res and res.ok) and 'success' or 'error'
    })

    if res and res.ok then refreshList() end
    if wasOpen then MDT.open('cameras') end
    cb(res or { ok = false })
end)

RegisterNUICallback('cameraMove', function(data, cb)
    if Cameras.placing then return cb({ ok = false }) end
    Cameras.placing = true

    local wasOpen = MDT.isOpen
    if wasOpen then MDT.close() end
    Wait(250)

    local spot = placementLoop(data and data.model or 'prop_cctv_cam_01a')
    Cameras.placing = false

    if not spot then
        if wasOpen then MDT.open('cameras') end
        return cb({ ok = false })
    end

    local res = lib.callback.await('nz_mdt:camera:update', false, data.id, {
        coords = spot.coords, rot = spot.rot
    })

    lib.notify({
        title       = 'Cameras',
        description = res and res.msg or 'That did not go through.',
        type        = (res and res.ok) and 'success' or 'error'
    })

    if res and res.ok then refreshList() end
    if wasOpen then MDT.open('cameras') end
    cb(res or { ok = false })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Cameras.stopView()
    for camId in pairs(Cameras.props) do dropProp(camId) end
    lib.hideTextUI()
end)
