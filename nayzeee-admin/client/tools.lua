-- In-world tools. Each runs a frame loop only while active.
local Local = LocalActions
local tool -- 'inspector' | 'prop' | 'zone'

local function drawBox(entity, r, g, b)
    local model = GetEntityModel(entity)
    local min, max = GetModelDimensions(model)
    local corners = {
        GetOffsetFromEntityInWorldCoords(entity, min.x, min.y, min.z), GetOffsetFromEntityInWorldCoords(entity, max.x, min.y, min.z),
        GetOffsetFromEntityInWorldCoords(entity, max.x, max.y, min.z), GetOffsetFromEntityInWorldCoords(entity, min.x, max.y, min.z),
        GetOffsetFromEntityInWorldCoords(entity, min.x, min.y, max.z), GetOffsetFromEntityInWorldCoords(entity, max.x, min.y, max.z),
        GetOffsetFromEntityInWorldCoords(entity, max.x, max.y, max.z), GetOffsetFromEntityInWorldCoords(entity, min.x, max.y, max.z),
    }
    local edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
    for _, e in ipairs(edges) do
        local a, c = corners[e[1]], corners[e[2]]
        DrawLine(a.x, a.y, a.z, c.x, c.y, c.z, r, g, b, 255)
    end
end

local function hint(keys, title)
    NUI('toolHint', keys and { title = title, keys = keys } or false)
end

local function reopen(page, extra)
    SetTimeout(150, function() OpenPanel(page, extra) end)
end

-- ─── entity inspector ───────────────────────────────────────────────────
local entityTypes = { [1] = 'Ped', [2] = 'Vehicle', [3] = 'Object' }

local function entityInfo(e)
    local t = GetEntityType(e)
    local c = GetEntityCoords(e)
    local r = GetEntityRotation(e, 2)
    local model = GetEntityModel(e)
    local info = {
        type = entityTypes[t] or 'Unknown', handle = e, model = model,
        name = t == 2 and GetDisplayNameFromVehicleModel(model):lower() or nil,
        coords = { x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z), w = NZ.Round(GetEntityHeading(e)) },
        rotation = { x = NZ.Round(r.x), y = NZ.Round(r.y), z = NZ.Round(r.z) },
        health = GetEntityHealth(e), maxHealth = GetEntityMaxHealth(e),
        networked = NetworkGetEntityIsNetworked(e), netId = NetworkGetEntityIsNetworked(e) and NetworkGetNetworkIdFromEntity(e) or nil,
        owner = NetworkGetEntityIsNetworked(e) and GetPlayerServerId(NetworkGetEntityOwner(e)) or nil,
        frozen = IsEntityPositionFrozen(e), mission = IsEntityAMissionEntity(e), worldProp = SavedPropId and SavedPropId(e) or nil,
        distance = NZ.Round(#(GetEntityCoords(cache.ped) - c)),
    }
    if t == 1 and IsPedAPlayer(e) then
        local pl = NetworkGetPlayerIndexFromPed(e)
        info.player = { id = GetPlayerServerId(pl), name = GetPlayerName(pl) }
    elseif t == 2 then
        info.plate = GetVehicleNumberPlateText(e)
        info.engine = math.floor(GetVehicleEngineHealth(e))
        local d = GetPedInVehicleSeat(e, -1)
        if d ~= 0 and IsPedAPlayer(d) then info.driver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(d)) end
    end
    return info
end

local function inspector()
    if tool then return false end
    if not Can('self.entity_inspector') then return false end
    tool = 'inspector'
    CloseUI()
    hint({ { 'E', 'Copy info' }, { 'F', 'Freeze' }, { 'G', 'Delete' }, { 'H', 'Copy coords' }, { 'Backspace', 'Exit' } }, 'Entity inspector')
    CreateThread(function()
        local last, lastSent = 0, 0
        while tool == 'inspector' do
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 177, true)
            local hit, entity, endCoords = lib.raycast.cam(1 | 2 | 4 | 8 | 16, 4, 60.0)
            local cur = (hit and entity and entity ~= 0 and DoesEntityExist(entity) and entity ~= cache.ped and GetEntityType(entity) ~= 0) and entity or 0
            if cur ~= 0 then
                drawBox(cur, 8, 175, 162)
                if cur ~= last or GetGameTimer() - lastSent > 500 then
                    last, lastSent = cur, GetGameTimer()
                    NUI('inspector', entityInfo(cur))
                end
                if IsControlJustPressed(0, 38) then
                    lib.setClipboard(json.encode(entityInfo(cur), { indent = true })); Notify('Entity info copied.', 'success')
                elseif IsControlJustPressed(0, 23) then
                    if NetworkGetEntityIsNetworked(cur) then NetworkRequestControlOfEntity(cur) end
                    FreezeEntityPosition(cur, not IsEntityPositionFrozen(cur))
                    last = 0
                elseif IsControlJustPressed(0, 74) then
                    local c = GetEntityCoords(cur)
                    lib.setClipboard(('vec4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(cur))); Notify('Coords copied.', 'success')
                elseif IsControlJustPressed(0, 47) and not (IsEntityAPed(cur) and IsPedAPlayer(cur)) then
                    if NetworkGetEntityIsNetworked(cur) then NetworkRequestControlOfEntity(cur) end
                    SetEntityAsMissionEntity(cur, true, true)
                    DeleteEntity(cur)
                    last = 0
                end
            elseif last ~= 0 then
                last = 0
                NUI('inspector', { none = true, coords = endCoords and { x = NZ.Round(endCoords.x), y = NZ.Round(endCoords.y), z = NZ.Round(endCoords.z) } or nil })
            end
            if IsDisabledControlJustPressed(0, 177) then break end
            Wait(0)
        end
        tool = nil
        NUI('inspector', false)
        hint(false)
    end)
    return true
end
Local.inspector = inspector
if Config.Commands.inspector and Config.Commands.inspector.enabled then
    RegisterCommand(Config.Commands.inspector.name, function() if Me.isStaff then if tool == 'inspector' then tool = nil elseif not tool then inspector() end end end, false)
    if Config.Commands.inspector.key ~= nil then RegisterKeyMapping(Config.Commands.inspector.name, 'Admin: entity inspector', 'keyboard', Config.Commands.inspector.key or '') end
end

-- ─── prop placement ─────────────────────────────────────────────────────
Local.placeProp = function(d)
    if tool or not Can('props.create') then return false end
    local t = (d.type == 'ped' or d.type == 'vehicle') and d.type or 'object'
    local model = joaat(d.model or '')
    if not IsModelInCdimage(model) then Notify('Model not found: ' .. tostring(d.model), 'error'); return false end
    if t == 'vehicle' and not IsModelAVehicle(model) then Notify('That model is not a vehicle.', 'error'); return false end
    if t == 'ped' and not IsModelAPed(model) then Notify('That model is not a ped.', 'error'); return false end
    if not lib.requestModel(model, 10000) then Notify('Model did not load: ' .. tostring(d.model), 'error'); return false end
    tool = 'prop'
    CloseUI()
    local ghost
    local c = GetEntityCoords(cache.ped)
    if t == 'ped' then ghost = CreatePed(4, model, c.x, c.y, c.z, 0.0, false, false)
    elseif t == 'vehicle' then ghost = CreateVehicle(model, c.x, c.y, c.z, 0.0, false, false)
    else ghost = CreateObjectNoOffset(model, c.x, c.y, c.z, false, false, false) end
    SetModelAsNoLongerNeeded(model)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    if t == 'ped' then SetBlockingOfNonTemporaryEvents(ghost, true) end

    hint({ { 'Scroll', 'Rotate' }, { 'Shift+Scroll', 'Height' }, { 'Ctrl+Scroll', 'Tilt' }, { 'G', 'Snap to ground' }, { 'Enter', 'Place' }, { 'Backspace', 'Cancel' } }, 'Place ' .. t)

    CreateThread(function()
        local rot, lift, tilt, placed = vec3(0, 0, GetEntityHeading(cache.ped)), 0.0, 0.0, false
        local snap = true
        while tool == 'prop' do
            for _, k in ipairs({ 14, 15, 16, 17, 24, 25, 177, 191, 201, 47 }) do DisableControlAction(0, k, true) end
            local hit, _, pos = lib.raycast.cam(1, 4, 25.0)
            if hit then
                local up = IsControlPressed(0, 21)
                local ctrl = IsControlPressed(0, 36)
                local wheel = (IsDisabledControlJustPressed(0, 15) and 1) or (IsDisabledControlJustPressed(0, 14) and -1) or 0
                if wheel ~= 0 then
                    if up then lift = lift + wheel * 0.05 elseif ctrl then tilt = tilt + wheel * 5.0 else rot = vec3(rot.x, rot.y, rot.z + wheel * 7.5) end
                end
                if IsDisabledControlJustPressed(0, 47) then snap = not snap end
                SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z + lift, false, false, false)
                if snap and t == 'object' and lift == 0.0 then PlaceObjectOnGroundProperly(ghost) end
                SetEntityRotation(ghost, tilt, 0.0, rot.z, 2, false)
                drawBox(ghost, 8, 175, 162)
                if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then placed = true; break end
            end
            if IsDisabledControlJustPressed(0, 177) then break end
            Wait(0)
        end
        local p = GetEntityCoords(ghost)
        local r = GetEntityRotation(ghost, 2)
        SetEntityAsMissionEntity(ghost, true, true)
        DeleteEntity(ghost)
        tool = nil
        hint(false)
        if placed then
            local ok, err = RPC('props:save', { name = d.name, type = t, model = d.model, frozen = d.frozen, collision = d.collision, anim = d.anim,
                pos = { x = NZ.Round(p.x), y = NZ.Round(p.y), z = NZ.Round(p.z), rx = NZ.Round(r.x), ry = NZ.Round(r.y), rz = NZ.Round(r.z) } })
            if ok then Notify('Prop placed.', 'success') else Notify(err, 'error') end
        end
        reopen('world', { tab = 'props' })
    end)
    return true
end

-- ─── zone point creator ─────────────────────────────────────────────────
Local.zoneTool = function(d)
    if tool or not Can('zones.create') then return false end
    tool = 'zone'
    CloseUI()
    local points = {}
    for _, p in ipairs(d.points or {}) do points[#points + 1] = vec3(p.x, p.y, p.z) end
    local thickness = tonumber(d.thickness) or 10.0
    hint({ { 'E', 'Add point' }, { 'Z', 'Undo' }, { 'Enter', 'Finish' }, { 'Backspace', 'Cancel' } }, 'Zone points')
    CreateThread(function()
        local done = false
        while tool == 'zone' do
            for _, k in ipairs({ 24, 25, 177, 191, 201, 20 }) do DisableControlAction(0, k, true) end
            local hit, _, pos = lib.raycast.cam(1 | 16, 4, 60.0)
            if hit then
                DrawMarker(28, pos.x, pos.y, pos.z, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.25, 8, 175, 162, 200, false, false, 2, false, nil, nil, false)
                if IsControlJustPressed(0, 38) then points[#points + 1] = pos end
            end
            if IsDisabledControlJustPressed(0, 20) and #points > 0 then points[#points] = nil end
            local n = #points
            for i = 1, n do
                local a, b = points[i], points[i % n + 1]
                DrawLine(a.x, a.y, a.z, a.x, a.y, a.z + thickness, 8, 175, 162, 255)
                if n > 1 then
                    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 8, 175, 162, 255)
                    DrawLine(a.x, a.y, a.z + thickness, b.x, b.y, b.z + thickness, 8, 175, 162, 255)
                end
            end
            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
                if n >= 3 then done = true; break else Notify('Add at least 3 points.', 'error') end
            end
            if IsDisabledControlJustPressed(0, 177) then break end
            Wait(0)
        end
        tool = nil
        hint(false)
        local out
        if done then
            out = {}
            for _, p in ipairs(points) do out[#out + 1] = { x = NZ.Round(p.x), y = NZ.Round(p.y), z = NZ.Round(p.z) } end
        end
        reopen('world', { tab = 'zones', zonePoints = out, zoneDraft = d.draft })
    end)
    return true
end

-- ─── go to world prop ───────────────────────────────────────────────────
Local.gotoCoords = function(d)
    if not Can('self.teleport') then return false end
    local x, y, z = tonumber(d.x), tonumber(d.y), tonumber(d.z)
    if not x or not y then return false end
    CreateThread(function() TeleportTo(x, y, z, nil, z == nil) end)
    return true
end

-- panel map: set a waypoint where staff clicked
Local.waypoint = function(d)
    if not Me.isStaff or not tonumber(d.x) or not tonumber(d.y) then return false end
    SetNewWaypoint(d.x + 0.0, d.y + 0.0)
    return true
end

-- stop whatever in-world tool is running (resource stop / duty off)
function StopTool() tool = nil end
