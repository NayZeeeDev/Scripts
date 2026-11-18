--[[ Placement: props (players & admins), wall screens, claiming MLO props, remotes ]]

Placement = { active = false }

local DISABLE = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 47, 140, 141, 142, 143, 199, 200, 257, 263, 264, 10, 11, 19, 174, 175, 241, 242 }
local KEY = { place = 38, cancel = 177, cancel2 = 202, up = 10, down = 11, snap = 19, left = 174, right = 175, scrollUp = 241, scrollDown = 242, shift = 21 }

local function camDir()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx))
end

local function ray(dist, flags, ignore)
    local cam = GetFinalRenderedCamCoord()
    local dest = cam + camDir() * dist
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, flags, ignore or PlayerPedId(), 7)
    local _, hit, endC, normal, ent = GetShapeTestResult(h)
    return hit == 1, endC, normal, ent
end
Placement.ray = ray

local function hud(show, data)
    data = data or {}
    data.type = 'placement'
    data.show = show
    SendNUIMessage(data)
end

local function disable()
    for _, c in ipairs(DISABLE) do DisableControlAction(0, c, true) end
end

local function pressed(c) return IsDisabledControlJustPressed(0, c) end
local function held(c) return IsDisabledControlPressed(0, c) end

-- ─── prop placement (TVs and remotes) ─────────────────────────
--- opts: { model, title, maxDistance, from = vector3 (distance origin), floorOnly }
function Placement.prop(opts)
    if Placement.active then return nil end
    local hash = GetHashKey(opts.model)
    if not NZ.loadModel(hash) then NZ.notify('That model is not available on this server.', 'error') return nil end
    Placement.active = true

    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z - 20.0, false, false, false)
    SetEntityAlpha(ghost, 175, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutline(ghost, true)
    SetEntityDrawOutlineColor(8, 175, 162, 255)
    local mn, mx = GetModelDimensions(hash)

    local rot, zOff, snap = 0.0, 0.0, true
    local result
    local maxD = opts.maxDistance or Config.PlayerScreens.PlaceDistance

    local keys = {
        { key = 'E', label = 'Place' },
        { key = '⇅', label = 'Scroll · rotate' },
        { key = 'PgUp', label = 'Raise' },
        { key = 'PgDn', label = 'Lower' },
        { key = 'Alt', label = 'Wall snap' },
        { key = '⌫', label = 'Cancel' },
    }
    hud(true, { title = opts.title or _L('place_hint'), sub = opts.label or opts.model, keys = keys, valid = false })

    local lastValid, lastSnap
    while true do
        Wait(0)
        disable()
        local hit, pos, normal = ray(maxD + 6.0, 1 + 16, ghost)
        local fine = held(KEY.shift)
        if pressed(KEY.scrollUp) then rot = rot + (fine and 1.0 or 7.5) end
        if pressed(KEY.scrollDown) then rot = rot - (fine and 1.0 or 7.5) end
        if held(KEY.up) then zOff = zOff + (fine and 0.002 or 0.01) end
        if held(KEY.down) then zOff = zOff - (fine and 0.002 or 0.01) end
        if pressed(KEY.snap) then snap = not snap end

        local valid = false
        local heading, final = 0.0, nil
        if hit then
            local isWall = math.abs(normal.z) < 0.35 and snap and not opts.floorOnly
            if isWall then
                heading = GetHeadingFromVector_2d(-normal.x, -normal.y) + rot
                local n2 = vector3(normal.x, normal.y, 0.0)
                final = pos + n2 * (mx.y + 0.005) + vector3(0, 0, zOff)
            else
                heading = GetEntityHeading(ped) + rot
                final = pos + vector3(0, 0, -mn.z + zOff)
            end
            SetEntityCoordsNoOffset(ghost, final.x, final.y, final.z, false, false, false)
            SetEntityHeading(ghost, heading)
            local from = opts.from or GetEntityCoords(ped)
            valid = #(from - final) <= maxD and #(GetEntityCoords(ped) - final) <= Config.PlayerScreens.PlaceDistance + 1.0
            SetEntityDrawOutlineColor(valid and 8 or 229, valid and 175 or 72, valid and 162 or 77, 255)
        end
        if valid ~= lastValid or snap ~= lastSnap then
            lastValid, lastSnap = valid, snap
            hud(true, { title = opts.title or _L('place_hint'), sub = opts.label or opts.model, keys = keys, valid = valid, snap = snap })
        end

        if pressed(KEY.place) and valid then
            result = { coords = { x = final.x, y = final.y, z = final.z }, heading = heading % 360.0 }
            break
        end
        if pressed(KEY.cancel) or pressed(KEY.cancel2) then break end
    end

    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    hud(false)
    Placement.active = false
    return result
end

-- ─── wall screen designer ─────────────────────────────────────
local ASPECTS = { { 16 / 9, '16:9' }, { 21 / 9, '21:9' }, { 2.39, '2.39:1' }, { 4 / 3, '4:3' }, { 1.0, '1:1' }, { 9 / 16, '9:16' } }

function Placement.wall(opts)
    if Placement.active then return nil end
    Placement.active = true
    opts = opts or {}
    local w, aIdx, zOff, result = opts.width or 3.0, 1, 0.0, nil
    local keys = {
        { key = 'E', label = 'Create' },
        { key = '⇅', label = 'Scroll · size' },
        { key = '← →', label = 'Aspect' },
        { key = 'PgUp/Dn', label = 'Height' },
        { key = '⌫', label = 'Cancel' },
    }
    local last
    while true do
        Wait(0)
        disable()
        local fine = held(KEY.shift)
        if pressed(KEY.scrollUp) then w = math.min(40.0, w + (fine and 0.05 or 0.25)) end
        if pressed(KEY.scrollDown) then w = math.max(0.3, w - (fine and 0.05 or 0.25)) end
        if pressed(KEY.left) then aIdx = (aIdx - 2) % #ASPECTS + 1 end
        if pressed(KEY.right) then aIdx = aIdx % #ASPECTS + 1 end
        if held(KEY.up) then zOff = zOff + (fine and 0.005 or 0.03) end
        if held(KEY.down) then zOff = zOff - (fine and 0.005 or 0.03) end

        local h = w / ASPECTS[aIdx][1]
        local hit, pos, normal = ray(120.0, 1 + 16)
        local valid = hit and math.abs(normal.z) < 0.5
        local info = ('%.2fm × %.2fm · %s'):format(w, h, ASPECTS[aIdx][2])
        if info .. tostring(valid) ~= last then
            last = info .. tostring(valid)
            hud(true, { title = _L('place_wall_hint'), sub = info, keys = keys, valid = valid })
        end
        if valid then
            local n = vector3(normal.x, normal.y, 0.0)
            n = n / #n
            local heading = GetHeadingFromVector_2d(n.x, n.y)
            local c = pos + n * 0.02 + vector3(0, 0, zOff)
            -- viewer looks along -n, their right hand is (-n) × up
            local f = n * -1.0
            local r = vector3(f.y, -f.x, 0.0)
            local up = vector3(0, 0, 1)
            local tl = c - r * (w / 2) + up * (h / 2)
            local tr = c + r * (w / 2) + up * (h / 2)
            local bl = c - r * (w / 2) - up * (h / 2)
            local br = c + r * (w / 2) - up * (h / 2)
            DrawPoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z, 8, 175, 162, 70)
            DrawPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z, 8, 175, 162, 70)
            DrawPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 8, 175, 162, 70)
            DrawPoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 8, 175, 162, 70)
            DrawLine(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, 255, 255, 255, 230)
            DrawLine(tr.x, tr.y, tr.z, br.x, br.y, br.z, 255, 255, 255, 230)
            DrawLine(br.x, br.y, br.z, bl.x, bl.y, bl.z, 255, 255, 255, 230)
            DrawLine(bl.x, bl.y, bl.z, tl.x, tl.y, tl.z, 255, 255, 255, 230)
            if pressed(KEY.place) then
                result = { coords = { x = c.x, y = c.y, z = c.z }, heading = heading, wall = { w = w, h = h }, aspect = ASPECTS[aIdx][1] }
                break
            end
        end
        if pressed(KEY.cancel) or pressed(KEY.cancel2) then break end
    end
    hud(false)
    Placement.active = false
    return result
end

-- ─── claim a prop that already exists in the map / an MLO ─────
function Placement.existing()
    if Placement.active then return nil end
    Placement.active = true
    local keys = { { key = 'E', label = 'Use this screen' }, { key = '⌫', label = 'Cancel' } }
    local outlined, result, last
    while true do
        Wait(0)
        disable()
        local hit, _, _, ent = ray(60.0, 16)
        local def = (hit and ent and ent ~= 0 and GetEntityType(ent) == 3) and Props.Get(GetEntityModel(ent)) or nil
        if outlined and outlined ~= ent then SetEntityDrawOutline(outlined, false) outlined = nil end
        if def then
            if outlined ~= ent then
                SetEntityDrawOutline(ent, true)
                SetEntityDrawOutlineColor(8, 175, 162, 255)
                outlined = ent
            end
        end
        local sub = def and def.label .. ' · ' .. def.model or 'Aim at a supported screen prop'
        if sub ~= last then
            last = sub
            hud(true, { title = 'Use existing prop', sub = sub, keys = keys, valid = def ~= nil })
        end
        if def and pressed(KEY.place) then
            local c = GetEntityCoords(ent)
            local r = GetEntityRotation(ent, 2)
            result = { model = def.model, coords = { x = c.x, y = c.y, z = c.z }, heading = r.z % 360.0, pitch = r.x, roll = r.y }
            break
        end
        if pressed(KEY.cancel) or pressed(KEY.cancel2) then break end
    end
    if outlined then SetEntityDrawOutline(outlined, false) end
    hud(false)
    Placement.active = false
    return result
end

-- ─── player placing a TV from an item ─────────────────────────
RegisterNetEvent('nztv:place', function(data)
    CreateThread(function()
        if Panel.isOpen then Panel.close() end
        local res = Placement.prop({ model = data.model, label = data.label, title = _L('place_hint') })
        if not res then return end
        local remote
        if Config.Remote.Enabled and Config.Remote.AutoPlace then
            Wait(200)
            remote = Placement.prop({
                model = Config.Remote.Model, label = 'Put the remote somewhere easy to find', title = _L('place_remote_hint'),
                maxDistance = 6.0, from = vector3(res.coords.x, res.coords.y, res.coords.z), floorOnly = true,
            })
            if remote then remote = { x = remote.coords.x, y = remote.coords.y, z = remote.coords.z, h = remote.heading } end
        end
        NZ.call('place', { item = data.item, coords = res.coords, heading = res.heading, remote = remote })
    end)
end)
