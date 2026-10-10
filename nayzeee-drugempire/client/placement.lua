--[[
    Placing equipment inside the RV: a ghost of the prop follows where you look.
    Scroll / Q E rotate, E place, Backspace or right mouse cancel. Server re-checks bounds.
]]

Placement = { active = false }

local function lookPoint(ghost)
    local cam = GetGameplayCamCoord()
    local dir = Util.rotToDir(GetGameplayCamRot(2))
    local to = cam + dir * 6.0
    local ray = StartShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, cache.ped, 4)
    local status, hit, pos
    repeat
        status, hit, pos = GetShapeTestResult(ray)
        if status == 1 then Wait(0) end
    until status ~= 1
    if hit == 1 then return pos end
    local p = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 1.2
    return vec3(p.x, p.y, RV.origin.z + RV.cfg.floor)
end

local function valid(pos)
    local o, cfg = RV.origin, RV.cfg
    local rx, ry, rz = pos.x - o.x, pos.y - o.y, pos.z - o.z
    if math.sqrt(rx * rx + ry * ry) > cfg.radius then return false end
    if rz < cfg.floor - 1.0 or rz > cfg.floor + 3.0 then return false end
    for _, obj in pairs(Stations.objects()) do
        local dx, dy = obj.x - rx, obj.y - ry
        if dx * dx + dy * dy < 0.45 * 0.45 then return false end
    end
    return true
end

function Placement.start(item)
    if Placement.active or not RV.inside or LocalPlayer.state.nzdeBusy then return end
    local kind, st
    for k, s in pairs(Config.Stations) do
        if s.item == item then kind, st = k, s break end
    end
    if not kind then return end
    Placement.active = true
    LocalPlayer.state:set('nzdeBusy', true, false)
    local ghost = Util.prop(st.model, GetEntityCoords(cache.ped), 0.0, { noCollision = true, fallback = st.fallback })
    SetEntityAlpha(ghost, 170, false)
    local heading = GetEntityHeading(cache.ped) + 180.0
    UI.textui({ { key = 'E', label = 'Place ' .. st.label }, { key = 'Scroll', label = 'Rotate' }, { key = 'Backspace', label = 'Cancel' } })

    local placed = false
    while true do
        DisableControlAction(0, 14, true) DisableControlAction(0, 15, true) -- weapon wheel scroll
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        DisableControlAction(0, 37, true) DisableControlAction(0, 44, true)
        if IsDisabledControlPressed(0, 14) or IsControlPressed(0, 52) then heading = heading - 4.0 end
        if IsDisabledControlPressed(0, 15) or IsDisabledControlPressed(0, 44) then heading = heading + 4.0 end
        local pos = lookPoint(ghost)
        local ok = valid(pos)
        SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ghost, heading)
        local c = ok and { 8, 175, 162 } or { 229, 72, 77 }
        DrawMarker(25, pos.x, pos.y, pos.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 0.9, c[1], c[2], c[3], 140, false, false, 2, false, nil, nil, false)
        if IsControlJustPressed(0, 38) and ok then
            local o = RV.origin
            local res, err = lib.callback.await('nzde:rv:place', false, item, pos.x - o.x, pos.y - o.y, pos.z - o.z, heading % 360.0)
            if res then placed = true break end
            UI.notify(err or 'You can\'t place that here', 'error')
        end
        if IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then break end
        Wait(0)
    end
    Util.delete(ghost)
    UI.hideTextui()
    LocalPlayer.state:set('nzdeBusy', false, false)
    Placement.active = false
    return placed
end

function Placement.menu()
    local list = lib.callback.await('nzde:rv:placeables', false)
    if not list or #list == 0 then
        UI.notify('You have no equipment on you. Order some in the Deliveries app.', 'info')
        return
    end
    local pick = UI.panel('place', { items = list })
    if pick and pick.item then Placement.start(pick.item) end
end

RegisterNetEvent('nzde:place', function(item)
    if GetInvokingResource() then return end
    Placement.start(item)
end)
