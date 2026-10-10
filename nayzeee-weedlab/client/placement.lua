--[[
    Placing equipment inside a lab: a ghost of the prop follows where you look.
    Scroll / Q E rotate, E place, Backspace or right mouse cancel. The server re-checks
    level, the lab's limits, the bounds and the spacing.
]]

Placement = { active = false }

local function lookPoint()
    local cam = GetGameplayCamCoord()
    local dir = Util.rotToDir(GetGameplayCamRot(2))
    local to = cam + dir * 7.0
    local ray = StartShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, cache.ped, 4)
    local status, hit, pos
    repeat
        status, hit, pos = GetShapeTestResult(ray)
        if status == 1 then Wait(0) end
    until status ~= 1
    if hit == 1 then return pos end
    local p = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 1.2
    return vec3(p.x, p.y, Labs.origin.z + (Labs.cfg.floor or 0.0))
end

local function valid(kind, pos)
    local o, cfg = Labs.origin, Labs.cfg
    local rx, ry, rz = pos.x - o.x, pos.y - o.y, pos.z - o.z
    if not Utils.inBounds(cfg, rx, ry, rz) then return false end
    local e = Config.Equipment[kind]
    if e.overlap then return true end
    for _, obj in pairs(Stations.objects()) do
        local oe = Config.Equipment[obj.type]
        if oe and not oe.overlap then
            local min = (e.footprint or 0.4) * 0.5 + (oe.footprint or 0.4) * 0.5
            local dx, dy = obj.x - rx, obj.y - ry
            if dx * dx + dy * dy < (min * 0.85) ^ 2 then return false end
        end
    end
    return true
end

function Placement.start(item)
    if Placement.active or not Labs.inside or LocalPlayer.state.nzwlBusy then return end
    local kind, e = Utils.equipmentOf(item)
    if not kind then return end
    Placement.active = true
    LocalPlayer.state:set('nzwlBusy', true, false)
    local ghost = Util.prop(e.model, GetEntityCoords(cache.ped), 0.0, { noCollision = true, fallback = e.fallback })
    SetEntityAlpha(ghost, 170, false)
    local heading = GetEntityHeading(cache.ped) + 180.0
    UI.textui({ { key = 'E', label = 'Place ' .. e.label }, { key = 'Scroll', label = 'Rotate' }, { key = 'Backspace', label = 'Cancel' } })

    local placed = false
    while true do
        DisableControlAction(0, 14, true) DisableControlAction(0, 15, true)
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        DisableControlAction(0, 37, true) DisableControlAction(0, 44, true)
        if IsDisabledControlPressed(0, 14) or IsControlPressed(0, 52) then heading = heading - 4.0 end
        if IsDisabledControlPressed(0, 15) or IsDisabledControlPressed(0, 44) then heading = heading + 4.0 end
        local pos = lookPoint()
        local ok = valid(kind, pos)
        SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ghost, heading)
        local c = ok and { 8, 175, 162 } or { 229, 72, 77 }
        local fp = math.max(0.4, e.footprint or 0.6)
        DrawMarker(25, pos.x, pos.y, pos.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, fp, fp, fp, c[1], c[2], c[3], 140, false, false, 2, false, nil, nil, false)
        if kind == 'rack' then
            -- show the area the light will cover
            local a = Config.Equipment.rack.area
            for _, s in ipairs({ { -1, -1, 1, -1 }, { 1, -1, 1, 1 }, { 1, 1, -1, 1 }, { -1, 1, -1, -1 } }) do
                local x1, y1 = Utils.rotate(s[1] * a.x, s[2] * a.y, heading)
                local x2, y2 = Utils.rotate(s[3] * a.x, s[4] * a.y, heading)
                DrawLine(pos.x + x1, pos.y + y1, pos.z + 0.03, pos.x + x2, pos.y + y2, pos.z + 0.03, 8, 175, 162, 220)
            end
        end
        if IsControlJustPressed(0, 38) and ok then
            local o = Labs.origin
            local res, err = lib.callback.await('nzwl:lab:place', false, item, pos.x - o.x, pos.y - o.y, pos.z - o.z, heading % 360.0)
            if res then placed = true break end
            UI.notify(err or 'You can\'t place that here', 'error')
        end
        if IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then break end
        Wait(0)
    end
    Util.delete(ghost)
    UI.hideTextui()
    LocalPlayer.state:set('nzwlBusy', false, false)
    Placement.active = false
    return placed
end

function Placement.menu()
    local list = lib.callback.await('nzwl:lab:placeables', false)
    if not list or #list == 0 then
        UI.notify('You have no equipment on you. The hardware store sells it.', 'info')
        return
    end
    local L = Config.Labs[Labs.lab]
    local pick = UI.panel('place', { items = list, lab = L.label, maxGrow = L.maxGrow, maxObjects = L.maxObjects, objects = Utils.count(Stations.objects()) })
    if pick and pick.item then Placement.start(pick.item) end
end

RegisterNetEvent('nzwl:place', function(item)
    if GetInvokingResource() then return end
    Placement.start(item)
end)
