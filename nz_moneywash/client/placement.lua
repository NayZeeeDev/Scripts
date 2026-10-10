--[[ Placement — ghost preview, scroll to rotate, [E] to bolt it down ]]

Placement = { active = false }
local P = Config.Placement

local raycast = lib.raycast.fromCamera or lib.raycast.cam

local function blacklisted(pos)
    for _, z in ipairs(P.blacklist) do
        if #(pos - z.coords) < z.radius then return true end
    end
    return false
end

local function tooClose(pos, ignoreId)
    local spacing = ignoreId and 0.9 or P.minSpacing -- admins may pack config machines tighter
    for id, s in pairs(Render.stations) do
        if id ~= ignoreId and #(pos - vec3(s.data.x, s.data.y, s.data.z)) < spacing then return true end
    end
    return false
end

local function validate(hit, pos, normal, opts)
    local ped = PlayerPedId()
    if not hit then return false, 'Aim at the floor.' end
    if normal and normal.z < 0.85 then return false, 'The floor needs to be flat.' end
    if #(GetEntityCoords(ped) - pos) > (opts.moveId and 12.0 or P.maxDistance) then return false, 'Too far away.' end
    if not opts.moveId then -- admins can put config machines anywhere
        if P.interiorOnly and GetInteriorFromEntity(ped) == 0 then return false, 'Set this up indoors.' end
        if blacklisted(pos) then return false, 'Way too much attention here.' end
    end
    if tooClose(pos, opts.moveId) then return false, 'Too close to another machine.' end
    return true
end

-- opts.moveId: admin move of an existing machine instead of placing a kit
function Placement.run(stType, opts)
    opts = opts or {}
    Placement.active = true
    local model = U.hash(NZ.mainModel(stType, 'idle'))
    lib.requestModel(model, 10000)
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local ghost = CreateObject(model, start.x, start.y, start.z, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetModelAsNoLongerNeeded(model)

    local heading = GetEntityHeading(ped)
    local moving = opts.moveId and Render.data(opts.moveId)
    if moving then heading = moving.h end
    local pos, valid, reason = start, false, nil
    UI.hint('[E] Place   ·   [Scroll] Rotate   ·   [Shift] Fine   ·   [Backspace] Cancel')

    local confirmed = false
    while true do
        local hit, _, endCoords, normal = raycast(1 | 16, 4, (opts.moveId and 12.0 or P.maxDistance) + 2.0) -- ghost has no collision, rays pass through it
        if hit then pos = endCoords end
        valid, reason = validate(hit, pos, normal, opts)

        SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ghost, heading)
        SetEntityAlpha(ghost, valid and 190 or 80, false)
        local r, g, b = 8, 175, 162
        if not valid then r, g, b = 229, 72, 77 end
        DrawMarker(25, pos.x, pos.y, pos.z + 0.02, 0, 0, 0, 0, 0, 0, 1.4, 1.4, 1.0, r, g, b, 140, false, false, 2, false, nil, nil, false)

        DisableControlAction(0, 14, true)
        DisableControlAction(0, 15, true)
        DisableControlAction(0, 16, true)
        DisableControlAction(0, 17, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 38, true)

        local step = IsControlPressed(0, 21) and 1.0 or 7.5
        if IsDisabledControlJustPressed(0, 14) then heading = (heading - step) % 360 end
        if IsDisabledControlJustPressed(0, 15) then heading = (heading + step) % 360 end

        if IsDisabledControlJustPressed(0, 38) then
            if valid then confirmed = true break end
            UI.toast('Can\'t place', reason, 'error', 2500)
        end
        if IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then break end
        Wait(0)
    end

    U.deleteEnt(ghost)
    UI.hint(nil)

    if confirmed and opts.moveId then
        local res = lib.callback.await('nzmw:admin:move', false, opts.moveId, { x = pos.x, y = pos.y, z = pos.z }, heading)
        if not res or not res.ok then UI.err(res) else
            UI.toast('Machine moved', 'Saved. The config line is in the server console.', 'success', 7000)
        end
    elseif confirmed then
        local ok = UI.progress('Bolting the machine down', 6000)
        if ok then
            local res = lib.callback.await('nzmw:place', false, stType, { x = pos.x, y = pos.y, z = pos.z }, heading,
                GetInteriorFromEntity(PlayerPedId()) ~= 0)
            if not res or not res.ok then UI.err(res) else
                UI.toast('Set up', Config.Stages[stType].label .. ' is ready to run.', 'success')
            end
        end
    end
    Placement.active = false
end

RegisterNetEvent('nzmw:placement:start', function(stType)
    if Placement.active or U.busy or not Config.Placement.kits[stType] then return end
    CreateThread(function() Placement.run(stType) end)
end)
