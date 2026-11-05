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

-- Synchronous line test, ignoring one entity. Returns hit, coords, surface normal, entity
local function probe(from, to, flags, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore or 0, 4)
    local _, hit, coords, normal, entity = GetShapeTestResult(h)
    return hit == 1, coords, normal, entity
end

-- Is this hit the till being placed? (compares the handle, and model + position as a fallback)
local function isGhost(entity, ghost)
    if not ghost or not entity or entity == 0 then return false end
    if entity == ghost then return true end
    return DoesEntityExist(entity) and GetEntityModel(entity) == GetEntityModel(ghost) and #(GetEntityCoords(entity) - GetEntityCoords(ghost)) < 0.05
end

--[[
    Where the crosshair points. Returns hit, coords, surface normal.
    With a till being placed, two rays are cast: one against the map only (1), which can never hit the till,
    and one against props (16) that skips the till. The nearer real hit wins, so the till snaps onto walls,
    counters and floors instead of landing on itself.
]]
local function crosshair(ghost)
    local ped = PlayerPedId()
    local cam = GetGameplayCamCoord()
    local to = cam + direction(GetGameplayCamRot(2)) * (CFG.Distance + 8.0)
    if not ghost then
        local hit, at, normal = probe(cam, to, 17, ped)
        return hit, at, normal
    end
    local hitMap, atMap, nMap = probe(cam, to, 1, ped)
    local hitObj, atObj, nObj, entity = probe(cam, to, 16, ghost)
    if hitObj and isGhost(entity, ghost) then hitObj = false end
    if hitMap and hitObj then
        if #(atObj - cam) < #(atMap - cam) then return true, atObj, nObj end
        return true, atMap, nMap
    end
    if hitObj then return true, atObj, nObj end
    return hitMap, atMap, nMap
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
    local ghost, minZ, reach, last = nil, 0.0, 0.25, nil

    if job.mode == 'prop' then
        local model = joaat(job.model)
        if not loadModel(model) then
            ClientBridge.Notify(Config.UI.Title, L('error.prop_missing', 'That prop could not be loaded: {model}', { model = job.model }), 'error')
            dbg('model failed to load', job.model)
            return nil
        end
        local min, max = GetModelDimensions(model)
        minZ = min.z
        -- how far the till sticks out sideways from its origin, used to push it out of walls
        reach = math.max(math.abs(min.x), math.abs(max.x), math.abs(min.y), math.abs(max.y)) + 0.02
        local _, at = crosshair(nil)
        local p = at and vector3(at.x, at.y, at.z - minZ) or GetEntityCoords(ped)
        last = p
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
        local hit, at, normal = crosshair(ghost)
        local valid = hit and #(origin - at) <= CFG.Distance
        local spot
        if Config.Registers.Debug and GetGameTimer() % 1000 < 17 then dbg(('hit=%s at=%s normal=%s'):format(tostring(hit), tostring(at), tostring(normal))) end

        if job.mode == 'prop' then
            local step = fine and 1.0 or 7.5
            if up then heading = (heading + step) % 360 end
            if down then heading = (heading - step) % 360 end
            if hit then
                -- snap: flat on top of floors / counters / tables; against a wall it's pushed out so it never clips in
                local onTop = normal and normal.z >= 0.65
                if onTop then
                    last = vector3(at.x, at.y, at.z - minZ)
                else
                    last = vector3(at.x + normal.x * reach, at.y + normal.y * reach, at.z - minZ)
                end
                valid = valid and onTop
                if valid then spot = last end
            else
                valid = false   -- aiming at nothing: the till stays where it last snapped
            end
            SetEntityCoordsNoOffset(ghost, last.x, last.y, last.z, false, false, false)
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
