--[[
    NAYZEEE BILLING - Register placement (admin)
    Started from the Billing Admin page:
      prop   restaurants without a till: the till prop follows your crosshair, scroll rotates it, E places it
      point  restaurants that already have a till: aim the ball at the till, that spot becomes the third-eye target
]]

Placing = false

local CFG = Config.Registers.Placement
local COLOR = { 15, 212, 196 }
local COLOR_BAD = { 229, 72, 77 }

local K = {
    place = 38,                        -- E
    cancel = { 47, 177 },              -- G, Backspace
    -- the mouse wheel reports through the weapon-wheel controls in gameplay (241/242 only fire in menus)
    scrollUp = { 15, 17, 241 },
    scrollDown = { 14, 16, 242 },
    fine = 21,                         -- Shift
}
-- Weapon wheel, attack/aim, cover, pause, and the keys used above
local Blocked = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 47, 99, 100, 115, 116, 140, 141, 142, 177, 199, 200, 241, 242, 257, 261, 262, 263, 264 }

local function dbg(...) if Config.Registers.Debug then print('^5[NAYZEEE-BILLING placement]^7', ...) end end

local function anyPressed(list)
    for _, k in ipairs(list) do if IsDisabledControlJustPressed(0, k) then return true end end
    return false
end

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

local function direction(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

-- Synchronous line test against the world and objects (flags 1 + 16), ignoring one entity
local function ray(from, to, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 17, ignore or 0, 4)
    local _, hit, coords, _, entity = GetShapeTestResult(h)
    return hit == 1, coords, entity
end

--[[
    Where the crosshair points.
    point mode: the ray ignores your character.
    prop mode:  the ray ignores the till being placed (so it can't land on itself and stall), and starts just past
                your character instead of at the camera, so it can't stop on you either.
    Returns hit, coords, and a fallback spot along the aim line for when nothing is hit (aiming at the sky / too far)
]]
local function crosshair(ghost)
    local ped = PlayerPedId()
    local cam = GetGameplayCamCoord()
    local dir = direction(GetGameplayCamRot(2))
    local to = cam + dir * (CFG.Distance + 8.0)
    local from, ignore = cam, ped
    if ghost then
        local pedPos = GetEntityCoords(ped)
        local along = math.max(0.0, (pedPos.x - cam.x) * dir.x + (pedPos.y - cam.y) * dir.y + (pedPos.z - cam.z) * dir.z)
        from, ignore = cam + dir * (along + 0.45), ghost
    end
    local hit, at = ray(from, to, ignore)
    return hit, at, cam + dir * math.min(CFG.Distance, 4.0)
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
    local ghost, minZ = nil, 0.0

    if job.mode == 'prop' then
        local model = joaat(job.model)
        if not loadModel(model) then
            ClientBridge.Notify(Config.UI.Title, L('error.prop_missing', 'That prop could not be loaded: {model}', { model = job.model }), 'error')
            dbg('model failed to load', job.model)
            return nil
        end
        minZ = (GetModelDimensions(model)).z
        local _, at = crosshair(nil)
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
        SetEntityRotation(ghost, 0.0, 0.0, heading, 2, true)
        dbg('ghost created', ghost, job.model)
    end

    local result
    while true do
        Wait(0)
        for _, k in ipairs(Blocked) do DisableControlAction(0, k, true) end
        local fine = IsDisabledControlPressed(0, K.fine)
        local origin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.35)
        local up, down = anyPressed(K.scrollUp), anyPressed(K.scrollDown)
        local hit, at, aim = crosshair(ghost)
        local valid = hit and #(origin - at) <= CFG.Distance
        local spot
        if Config.Registers.Debug and GetGameTimer() % 1000 < 17 then dbg(('hit=%s at=%s ghost=%s'):format(tostring(hit), tostring(at), tostring(ghost))) end

        if job.mode == 'prop' then
            local step = fine and 1.0 or 7.5
            if up then heading = (heading + step) % 360 end
            if down then heading = (heading - step) % 360 end
            -- follow the crosshair every frame: on the surface you aim at, or floating on the aim line when nothing is hit
            local p = hit and vector3(at.x, at.y, at.z - minZ) or aim
            if hit then spot = p end
            SetEntityCoordsNoOffset(ghost, p.x, p.y, p.z, false, false, false)
            SetEntityRotation(ghost, 0.0, 0.0, heading, 2, true)
            hud({
                { k = 'E', l = L('place.key_place', 'Place'), off = not valid },
                { k = 'G', l = L('place.key_cancel', 'Cancel') },
                { k = 'Scroll', l = L('place.key_rotate', 'Rotate'), wide = true },
            })
        else
            local step = fine and 0.05 or 0.25
            if up then radius = math.min(radius + step, 10.0) end
            if down then radius = math.max(radius - step, 0.5) end
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

        if anyPressed(K.cancel) then break end
        if IsDisabledControlJustPressed(0, K.place) then
            if valid and spot then
                result = { coords = { x = spot.x, y = spot.y, z = spot.z }, heading = heading, model = job.mode == 'prop' and job.model or nil, radius = radius }
                dbg('placed', json.encode(result))
                break
            end
            PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
    end

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
