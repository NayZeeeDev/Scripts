--[[
    NAYZEEE BILLING - Register placement (admin)
    Two raycast modes, started from the Billing Admin page:
      prop   restaurants without a till: a ghost till prop follows the crosshair, rotate / raise it and place it
      point  restaurants that already have a till: a line + ball mark the spot, the cylinder shows the third-eye radius
]]

Placing = false

local CFG = Config.Registers.Placement
local COLOR_OK = { 15, 212, 196 }
local COLOR_BAD = { 229, 72, 77 }

local Keys = {
    confirm = { 38, 191, 24 },          -- E, Enter, left mouse
    cancel = { 177, 194, 200, 25 },     -- Backspace, Backspace (alt), Esc, right mouse
    scrollUp = 241, scrollDown = 242,
    left = 174, right = 175, up = 172, down = 173,
    fine = 21,                          -- Shift
}
local Blocked = { 24, 25, 14, 15, 16, 17, 37, 44, 140, 141, 142, 199, 200, 257, 263, 264, 38, 191, 177, 194, 172, 173, 174, 175, 241, 242, 261, 262 }

local function pressed(list)
    for _, k in ipairs(list) do if IsDisabledControlJustPressed(0, k) then return true end end
    return false
end

local function direction(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

-- Crosshair raycast from the gameplay camera (world + objects), ignoring the ghost prop
local function raycast(ignore)
    local from = GetGameplayCamCoord()
    local to = from + direction(GetGameplayCamRot(2)) * (CFG.Distance + 8.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 17, ignore or PlayerPedId(), 4)  -- 1 world + 16 objects
    local _, hit, coords = GetShapeTestResult(ray)
    return hit == 1, coords
end

local function marker(kind, c, sx, sy, sz, col, alpha)
    DrawMarker(kind, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sx, sy, sz, col[1], col[2], col[3], alpha, false, false, 2, false, nil, nil, false)
end

local function help(job, mode, radius)
    local lines = {
        ('**%s** · %s'):format(job.label, mode == 'prop' and L('place.prop', 'Place till') or L('place.point', 'Mark register')),
        L('place.keys', '[E] Place  ·  [Backspace] Cancel'),
        mode == 'prop' and L('place.keys_prop', '[Scroll / ← →] Rotate  ·  [↑ ↓] Height  ·  [Shift] Fine')
            or L('place.keys_point', '[Scroll] Radius ({radius} m)  ·  [Shift] Fine', { radius = ('%.2f'):format(radius) }),
    }
    lib.showTextUI(table.concat(lines, '  \n'), { position = 'left-center' })
end

--[[
    job = { mode = 'prop'|'point', id? (move), label, society, radius, model? }
    Returns the placement table or nil when cancelled
]]
local function place(job)
    local ped = PlayerPedId()
    local radius = Shared.Clamp(tonumber(job.radius) or CFG.DefaultRadius or 1.0, 0.5, 10.0)
    local heading = (tonumber(job.heading) or GetEntityHeading(ped)) % 360
    local lift = 0.0
    local ghost, minZ

    if job.mode == 'prop' then
        local model = joaat(job.model)
        if not IsModelInCdimage(model) or not pcall(lib.requestModel, model, 5000) then
            ClientBridge.Notify(Config.UI.Title, L('error.prop_missing', 'That prop could not be loaded'), 'error')
            return nil
        end
        local min = GetModelDimensions(model)
        minZ = min.z
        local p = GetEntityCoords(ped)
        ghost = CreateObject(model, p.x, p.y, p.z - 50.0, false, false, false)
        SetEntityAlpha(ghost, 175, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        SetEntityInvincible(ghost, true)
        SetModelAsNoLongerNeeded(model)
    end

    local lastHelp
    local result
    while true do
        Wait(0)
        for _, k in ipairs(Blocked) do DisableControlAction(0, k, true) end
        local fine = IsDisabledControlPressed(0, Keys.fine)

        local hit, at = raycast(ghost)
        local origin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.35)
        local valid = hit and #(origin - at) <= CFG.Distance
        local col = valid and COLOR_OK or COLOR_BAD

        if job.mode == 'prop' then
            local step = fine and 1.0 or 7.5
            if IsDisabledControlJustPressed(0, Keys.scrollUp) then heading = (heading + step) % 360 end
            if IsDisabledControlJustPressed(0, Keys.scrollDown) then heading = (heading - step) % 360 end
            if IsDisabledControlPressed(0, Keys.left) then heading = (heading + (fine and 0.5 or 2.0)) % 360 end
            if IsDisabledControlPressed(0, Keys.right) then heading = (heading - (fine and 0.5 or 2.0)) % 360 end
            if IsDisabledControlPressed(0, Keys.up) then lift = math.min(lift + (fine and 0.002 or 0.01), 1.5) end
            if IsDisabledControlPressed(0, Keys.down) then lift = math.max(lift - (fine and 0.002 or 0.01), -1.5) end
            if hit then
                SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z - minZ + lift, false, false, false)
                SetEntityHeading(ghost, heading)
                SetEntityAlpha(ghost, valid and 190 or 110, false)
            end
            DrawLine(origin.x, origin.y, origin.z, at.x, at.y, at.z, col[1], col[2], col[3], 200)
            marker(25, vector3(at.x, at.y, at.z + 0.01), radius * 2.0, radius * 2.0, 1.0, col, 90)
        else
            local step = fine and 0.05 or 0.25
            if IsDisabledControlJustPressed(0, Keys.scrollUp) then radius = math.min(radius + step, 10.0) end
            if IsDisabledControlJustPressed(0, Keys.scrollDown) then radius = math.max(radius - step, 0.5) end
            -- line from the player to the spot, a ball on the spot, a cylinder for the third-eye radius
            DrawLine(origin.x, origin.y, origin.z, at.x, at.y, at.z, col[1], col[2], col[3], 220)
            marker(28, at, 0.07, 0.07, 0.07, col, 235)
            marker(1, vector3(at.x, at.y, at.z - radius * 0.5), radius * 2.0, radius * 2.0, radius, col, 55)
        end

        local h = ('%s:%.2f'):format(job.mode, radius)
        if h ~= lastHelp then help(job, job.mode, radius) lastHelp = h end

        if pressed(Keys.cancel) then break end
        if pressed(Keys.confirm) then
            if valid then
                local c = job.mode == 'prop' and GetEntityCoords(ghost) or at
                result = { coords = { x = c.x, y = c.y, z = c.z }, heading = heading, model = job.mode == 'prop' and job.model or nil, radius = radius }
                break
            end
            PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
    end

    lib.hideTextUI()
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    return result
end

RegisterNUICallback('placeRegister', function(job, cb)
    cb('ok')
    if Placing or type(job) ~= 'table' or (job.mode ~= 'prop' and job.mode ~= 'point') then return end
    if job.mode == 'prop' and type(job.model) ~= 'string' then return end
    CreateThread(function()
        if not lib.callback.await('nayzeee-billing:isAdmin', false) then return end
        Placing = true
        CloseBilling()
        Wait(150)
        local spot = place(job)
        Placing = false
        if not spot then
            ClientBridge.Notify(Config.UI.Title, L('place.cancelled', 'Placement cancelled'), 'info')
        else
            local ok, err = Rpc(job.id and 'admin:moveRegister' or 'admin:addRegister', {
                id = job.id, label = job.label, society = job.society, radius = spot.radius, placement = spot,
            })
            if ok then
                ClientBridge.Notify(Config.UI.Title, job.id and L('place.moved', 'Register moved') or L('place.added', 'Register added'), 'success')
            else
                ClientBridge.Notify(Config.UI.Title, err, 'error')
            end
        end
        OpenBilling('admin', { registers = true })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Placing then lib.hideTextUI() end
end)
