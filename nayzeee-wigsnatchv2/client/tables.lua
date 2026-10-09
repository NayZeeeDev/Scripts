-- Wig tables on this client: the same system as the nayzeee-sneakers crafting tables.
--   * tables near you spawn as local objects: Dragons Lab's model if you have her pack, else the fallback
--   * place one from your inventory (ghost preview, scroll or arrow keys to turn, E to place), pick it back up
--   * "Use wig table" opens the table window (the sneakers shoe table window); making / dyeing a wig plays
--     out in stages at the table with skill checks, the hair on a foam head and a camera you switch with V

Tables = {}

local T = Config.Tables
local list = {}        -- [id] = { id, item, coords, heading, fixed, ownerSrc, surface }
local spawned = {}     -- [id] = entity
local byEnt = {}       -- [entity] = id
local surfaces = {}    -- [model] = table-top height (fallback; the real one is found with rays)
local warned = false
local bench = nil      -- the table entity the table window was opened from
Tables.busy = false

local function loadModel(model)
    return IsModelInCdimage(model) and pcall(lib.requestModel, model, 5000) or false
end

-- model and table-top height for a table item, or nil if nothing can be shown
local function modelFor(item)
    local def = T.Items[item]
    if def and IsModelInCdimage(def.model) then return def.model, T.Surface end
    if not warned then
        warned = true
        print(('^3[%s]^7 Dragons Lab Wig Crafting Table pack not found. Buy it from SasDragon at %s'):format(RESOURCE, T.Store))
    end
    if T.Fallback and IsModelInCdimage(T.Fallback) then return T.Fallback, T.FallbackSurface end
end

local function surfaceOf(model, given)
    if given then return given end
    if not surfaces[model] then
        local _, max = GetModelDimensions(model)
        surfaces[model] = max.z
    end
    return surfaces[model]
end

local function spawn(id)
    local t = list[id]
    local model, surface = modelFor(t.item)
    if not model or not loadModel(model) then return end
    if not list[id] or spawned[id] then return SetModelAsNoLongerNeeded(model) end
    local obj = CreateObjectNoOffset(model, t.coords.x, t.coords.y, t.coords.z, false, false, false)
    SetEntityHeading(obj, t.heading)
    FreezeEntityPosition(obj, true)
    t.surface = surfaceOf(model, surface)
    SetModelAsNoLongerNeeded(model)
    spawned[id], byEnt[obj] = obj, id
end

local function despawn(id)
    local obj = spawned[id]
    if not obj then return end
    if DoesEntityExist(obj) then DeleteEntity(obj) end
    spawned[id], byEnt[obj] = nil, nil
end

function Tables.Refresh()
    for id in pairs(spawned) do despawn(id) end
    list = {}
    for _, t in ipairs(lib.callback.await('nz-wig:tables', false) or {}) do list[t.id] = t end
end

function Tables.FromEntity(ent)
    local id = byEnt[ent]
    return id, id and list[id]
end

-- straight down onto the table: height of whatever of `ent` is under x, y (nil = nothing of it there)
local function topAt(ent, x, y, z)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(x, y, z + 1.2, x, y, z - 1.4, 511, PlayerPedId(), 0)
    local _, hit, at, _, e = GetShapeTestResult(ray)
    if hit == 1 and e == ent then return at.z end
end

-- walk from `from` along `dir` until the ray finds the table: the near edge and the table-top height there
local function edgeAlong(ent, from, dir, ground)
    for i = 1, 70 do
        local p = from + dir * (i * 0.05)
        local z = topAt(ent, p.x, p.y, ground + 1.0)
        if z and z > ground + 0.35 and z < ground + 1.6 then return vector3(p.x, p.y, z) end
    end
end

local function flat(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y)
    if len < 0.001 then return nil end
    return vector3(v.x / len, v.y / len, 0.0)
end

-- old way, from the model's size (used when the table has no collision to find)
local function workSpotFromModel(ent, t)
    local min, max = GetModelDimensions(GetEntityModel(ent))
    if #(max - min) < 0.2 then min, max = vector3(-0.9, -0.4, 0.0), vector3(0.9, 0.4, 0.93) end
    local rel = GetOffsetFromEntityGivenWorldCoords(ent, GetEntityCoords(PlayerPedId()))
    local side = rel.y < (min.y + max.y) / 2 and -1 or 1
    local x = math.max(min.x + 0.45, math.min(max.x - 0.45, rel.x))
    local edge = side < 0 and min.y or max.y
    local surface = t and t.surface or T.Surface or 0.93
    local edgeAt = GetOffsetFromEntityInWorldCoords(ent, x, edge, surface)
    local inward = flat(GetOffsetFromEntityInWorldCoords(ent, x, edge - side, 0.0) - GetOffsetFromEntityInWorldCoords(ent, x, edge, 0.0))
    return edgeAt, inward
end

-- where the player stands and where the work sits, on whichever side of the table the player is on.
-- The table top is found with rays (so it works whatever her model's size, origin or the things
-- standing on it). Returns stand, work, heading, and two flat directions: `along` the table and
-- `out` from the work towards the player.
function Tables.WorkSpot(ent)
    local _, t = Tables.FromEntity(ent)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local ground = pos.z - math.max(0.0, GetEntityHeightAboveGround(ped))
    if ground > pos.z - 0.5 then ground = pos.z - 1.0 end

    -- work from the long side you're on, across from you (at the ends, the nearest spot along it),
    -- marching in from outside the table until the rays find its edge
    local min, max = GetModelDimensions(GetEntityModel(ent))
    local sized = #(max - min) > 0.2
    local rel = GetOffsetFromEntityGivenWorldCoords(ent, pos)
    local cy = sized and (min.y + max.y) / 2 or 0.0
    local side = rel.y < cy and -1 or 1
    local lo, hi = sized and min.x + 0.45 or -0.5, sized and max.x - 0.45 or 0.5
    if lo > hi then lo, hi = (lo + hi) / 2, (lo + hi) / 2 end
    local x = math.max(lo, math.min(hi, rel.x))
    local from = GetOffsetFromEntityInWorldCoords(ent, x, cy + side * 2.5, 0.0)
    local tries = {
        { from, flat(GetOffsetFromEntityInWorldCoords(ent, x, cy, 0.0) - from) },
        { pos, flat(GetEntityCoords(ent) - pos) },
        { pos, flat(GetEntityForwardVector(ped)) },
    }

    local edge, inward
    for _, try in ipairs(tries) do
        if try[2] then
            edge = edgeAlong(ent, try[1], try[2], ground)
            if edge then inward = try[2] break end
        end
    end
    if not edge then edge, inward = workSpotFromModel(ent, t) end

    -- the work goes a little way in from the edge, at the table-top height found at the edge
    -- (her tables have things standing on them, so a higher hit further in is ignored)
    local work = edge + inward * 0.24
    local z = topAt(ent, work.x, work.y, ground + 1.0)
    work = vector3(work.x, work.y, ((z and math.abs(z - edge.z) < 0.04) and z or edge.z) + 0.003)
    local stand = vector3(edge.x - inward.x * 0.42, edge.y - inward.y * 0.42, pos.z)
    local heading = GetHeadingFromVector_2d(inward.x, inward.y)
    local out = inward * -1.0
    local along = vector3(-out.y, out.x, 0.0)
    return stand, work, heading, along, out
end

-- the table you're standing at
function Tables.Nearest(range)
    local pos, best, bestD = GetEntityCoords(PlayerPedId()), nil, range or (T.InteractDistance + 1.0)
    for ent in pairs(byEnt) do
        local d = #(pos - GetEntityCoords(ent))
        if d < bestD then best, bestD = ent, d end
    end
    return best
end

-- the wig shown on the foam head: the hairstyle's own prop if it's streamed, else the generic wig
function Tables.WigModel(hair)
    local TP = Config.TableProps
    if hair and hair.m and hair.d then
        local built = HairProps.Model(hair.m, hair.d)   -- made by hairkit from the server's own hair
        if built then return built end
        local mapped = TP.HairPropMap and TP.HairPropMap[('%s:%d'):format(hair.m, hair.d)]
        if mapped and IsModelInCdimage(GetHashKey(mapped)) then return GetHashKey(mapped) end
        if TP.HairProps then
            local own = GetHashKey(TP.HairProps:format(hair.m, hair.d))
            if IsModelInCdimage(own) then return own end
        end
    end
    return TP.Wig and TP.Wig.model or nil
end

-- the table window was opened at this table
function Tables.Bench() return bench and DoesEntityExist(bench) and bench or nil end

if not T.Enabled then return end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, t in pairs(list) do
            local d = #(pos - t.coords)
            if d < T.StreamDistance and not spawned[id] then spawn(id)
            elseif d > T.StreamDistance + 10.0 and spawned[id] then despawn(id) end
        end
        Wait(1000)
    end
end)

CB.OnLoaded(Tables.Refresh)
CreateThread(function() if CB.IsLoaded() then Tables.Refresh() end end)

RegisterNetEvent('nz-wig:c:tableAdded', function(t) list[t.id] = t end)

RegisterNetEvent('nz-wig:c:tableRemoved', function(id)
    if bench and byEnt[bench] == id then bench = nil end
    despawn(id)
    list[id] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    for id in pairs(spawned) do despawn(id) end
end)

-- animations ------------------------------------------------------------------------------------

local PUTDOWN = { dict = 'pickup_object', clip = 'putdown_low', flag = 0 }
local PICKUP = { dict = 'pickup_object', clip = 'pickup_low', flag = 0 }
local WORK = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 }

local function face(ent)
    TaskTurnPedToFaceEntity(PlayerPedId(), ent, 600)
    Wait(650)
end

-- interactions ------------------------------------------------------------------------------------

local function free()
    return not Tables.busy and not Snatch.busy and not NUI.app and not Restrain.tied and not Restrain.held and not Restrain.acting
end

local function mine(t)
    return t and not t.fixed and t.ownerSrc == GetPlayerServerId(PlayerId())
end

local function pickUp(ent)
    if Tables.busy then return end
    local id = Tables.FromEntity(ent)
    if not id then return end
    Tables.busy = true
    face(ent)
    PlayAnim(PICKUP, 1000)
    Wait(600)
    lib.callback.await('nz-wig:pickUpTable', false, id)
    Wait(400)
    Tables.busy = false
end

-- the stages of every job, for the table window
local function stageList()
    local out = {}
    for kind, list in pairs(T.Stages) do
        local l = {}
        for i, st in ipairs(list) do l[i] = { label = st.label, time = st.time, check = T.SkillChecks and st.check and true or false } end
        out[kind] = l
    end
    return out
end

-- "Use wig table": the table window (the same window as the sneakers shoe table)
local function open(ent)
    local _, t = Tables.FromEntity(ent)
    if not free() or not t then return end
    local data = lib.callback.await('nz-wig:bench', false)
    if not data or not free() then return end
    bench = ent
    data.styles = { f = Crafting.Styles('f'), m = Crafting.Styles('m') }
    data.shots = lib.callback.await('nz-wig:shots', false) or {}
    data.palette = HairPalette()
    data.views = Tables.ViewInfo()
    data.stages = stageList()
    data.speed = T.SpeedPerLevel
    data.myModel = GetEntityModel(PlayerPedId()) == Config.Models.male.model and 'm' or 'f'
    NUI.Side('bench', data)
end

local options = {
    { name = 'nzwig_table_use', label = L('table_use'), icon = 'fa-solid fa-scissors', distance = T.InteractDistance,
      canInteract = function(e) return byEnt[e] ~= nil and free() end, onSelect = open },
    { name = 'nzwig_table_pickup', label = L('table_pickup'), icon = 'fa-solid fa-hand-holding', distance = T.InteractDistance,
      canInteract = function(e) local _, t = Tables.FromEntity(e) return mine(t) and free() end, onSelect = pickUp },
}

CreateThread(function()
    local models = {}
    for _, def in pairs(T.Items) do models[#models + 1] = def.model end
    if T.Fallback then models[#models + 1] = T.Fallback end
    if CB.Target ~= 'none' then
        CB.AddModel(models, options)
        return
    end
    -- no target resource: [E] at the table
    local shown = false
    while true do
        local ent = free() and Tables.Nearest(T.InteractDistance) or nil
        if ent then
            if not shown then lib.showTextUI('[E] ' .. L('table_use')) shown = true end
            if IsControlJustReleased(0, 38) then open(ent) end
            Wait(0)
        else
            if shown then lib.hideTextUI() shown = false end
            Wait(500)
        end
    end
end)

-- pick the table back up from the window
RegisterNUICallback('tablePickUp', function(_, cb)
    cb(1)
    local ent = Tables.Bench()
    local _, t = Tables.FromEntity(ent or 0)
    if not ent or not mine(t) then return end
    NUI.CloseSide()
    pickUp(ent)
end)

-- placing a table -----------------------------------------------------------------------------------

local NO_ATTACK = { 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17, 174, 175, 199, 200 }

RegisterNetEvent('nz-wig:c:placeTable', function(item)
    local ped = PlayerPedId()
    if not free() or IsPedInAnyVehicle(ped, false) then return end
    local model = modelFor(item)
    if not model then return CB.Notify(L('table_no_model'), 'error') end
    if not loadModel(model) then return end
    Tables.busy = true

    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0)
    local heading = GetEntityHeading(ped)
    local ghost = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityHeading(ghost, heading)
    NUI.Send('hint', { show = true, text = L('table_place_hint') })

    local place, valid = false, false
    while true do
        Wait(0)
        for _, c in ipairs(NO_ATTACK) do DisableControlAction(0, c, true) end
        local hit, _, coords, normal = lib.raycast.cam(1, 4, 7.0)
        if hit then pos = coords end
        valid = hit and normal.z > 0.85 and #(pos - GetEntityCoords(ped)) < 5.0
        SetEntityCoords(ghost, pos.x, pos.y, pos.z, false, false, false, false)
        SetEntityHeading(ghost, heading)
        SetEntityAlpha(ghost, valid and 200 or 90, false)

        if IsDisabledControlPressed(0, 15) then heading = heading + 7.5 end    -- scroll up
        if IsDisabledControlPressed(0, 14) then heading = heading - 7.5 end    -- scroll down
        if IsDisabledControlPressed(0, 174) then heading = heading + 1.5 end   -- arrow left
        if IsDisabledControlPressed(0, 175) then heading = heading - 1.5 end   -- arrow right
        heading = heading % 360.0
        if IsDisabledControlJustPressed(0, 38) then                           -- E places it
            if valid then place = true break end
            CB.Notify(L('table_cant_place'), 'error')
        end
        if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then break end   -- RMB / Backspace
    end

    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(model)
    NUI.Send('hint', { show = false })
    if place then
        TaskTurnPedToFaceCoord(ped, pos.x, pos.y, pos.z, 600)
        Wait(600)
        PlayAnim(PUTDOWN, 1000)
        Wait(700)
        lib.callback.await('nz-wig:placeTable', false, item, pos, heading)
    end
    Tables.busy = false
end)

-- camera views ---------------------------------------------------------------------------------------

local cam
local VIEWS = { 'three', 'first', 'close' }

local function validView(v) for _, x in ipairs(VIEWS) do if x == v then return true end end end

local function getView()
    local v = GetResourceKvpString('nzwig:view')
    if T.Camera.Switch and validView(v) then return v end
    return validView(T.Camera.Default) and T.Camera.Default or 'three'
end

local function setView(v) if validView(v) then SetResourceKvp('nzwig:view', v) end end

local function nextView(v)
    for i, x in ipairs(VIEWS) do if x == v then return VIEWS[i % #VIEWS + 1] end end
    return VIEWS[1]
end

local function dofLoop()
    CreateThread(function()
        while cam do
            SetUseHiDof()
            Wait(0)
        end
    end)
end

-- point the camera at `target` from `pos`; glides over if a camera is already up
local function shot(pos, target, fov, ms)
    ms = ms or 700
    local old = cam
    local new = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov or 50.0, false, 2)
    PointCamAtCoord(new, target.x, target.y, target.z)
    SetCamUseShallowDofMode(new, true)
    SetCamNearDof(new, 0.05)
    SetCamFarDof(new, #(pos - target) + 0.8)
    SetCamDofStrength(new, 0.65)
    cam = new
    if old then
        SetCamActiveWithInterp(new, old, ms, 1, 1)
        SetTimeout(ms + 100, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(new, true)
        RenderScriptCams(true, true, ms, true, false)
        dofLoop()
    end
end

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 600, true, false)
    DestroyCam(cam, false)
    cam = nil
end

-- the three ways to shoot the work at a table. { pos, look, fov }
-- (the foam head stands about 34 cm tall, so the shots look at the wig on it, not the table top)
local function tableShots(stand, work, along, out)
    local ped = PlayerPedId()
    local eye = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) + GetEntityForwardVector(ped) * 0.14 + vector3(0.0, 0.0, 0.03)
    local up = vector3(0.0, 0.0, 1.0)
    return {
        -- 3/4: over your shoulder, a step back and to the side, so you see yourself and the whole table
        three = { stand + along * 1.45 + out * 0.6 + up * 1.7, work - along * 0.05 + up * 0.16, 50.0 },
        -- first person: your own eyes, looking down at your hands and the head
        first = { eye, work + up * 0.14, 48.0 },
        -- close-up: across the table from the far side, the head up front and you working behind it
        close = { work - out * 0.55 + along * 0.3 + up * 0.32, work + up * 0.2, 40.0 },
    }
end

local function viewLabel(v) return L('view_' .. v) end

-- inside the work loop: V switches to the next view
local function pollView(current, shots)
    if not T.Camera.Switch then return current end
    DisableControlAction(0, 0, true)
    if IsDisabledControlJustPressed(0, 0) then
        current = nextView(current)
        local s = shots[current]
        if s then shot(s[1], s[2], s[3]) end
        setView(current)
        CB.Notify(viewLabel(current), 'info', 1500)
    end
    return current
end

-- the table window shows the camera choice
function Tables.ViewInfo()
    if not T.Camera.Switch then return nil end
    local out = { current = getView(), label = L('view_label'), list = {} }
    for _, v in ipairs(VIEWS) do out.list[#out.list + 1] = { id = v, label = viewLabel(v) } end
    return out
end

-- props on the table and in your hand -------------------------------------------------------------

local function handProp(name)
    return AttachLocalProp(Config.TableProps[name])
end

local function tableProp(model, at, heading, alpha)
    if not model or not loadModel(model) then return nil end
    local obj = CreateObjectNoOffset(model, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(obj, heading)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    if alpha then SetEntityAlpha(obj, alpha, false) end
    SetModelAsNoLongerNeeded(model)
    return obj
end

local function playWork()
    LoopAnim(WORK)
end

local function walkTo(stand, heading)
    local ped = PlayerPedId()
    TaskGoStraightToCoord(ped, stand.x, stand.y, stand.z, 1.0, 3000, heading, 0.05)
    local timeout = GetGameTimer() + 3000
    while #(GetEntityCoords(ped).xy - stand.xy) > 0.25 and GetGameTimer() < timeout do Wait(50) end
    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
end

local function cancelPressed()
    return IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177)   -- X / Backspace
end

-- run a job at the table: kind = 'make' { m, d, t, length, lace, c, h } | 'craft' { keys } | 'dye' { key, c, h }
local function run(ent, kind, req, view)
    if Tables.busy then return end
    local tableId = Tables.FromEntity(ent)
    if not tableId then return end
    local ok, token, stages, info = lib.callback.await('nz-wig:tableStart', false, tableId, kind, req)
    if not ok then
        if token then CB.Notify(token, 'error') end
        return
    end
    Tables.busy = true

    local stand, work, heading, along, out = Tables.WorkSpot(ent)
    walkTo(stand, heading)
    if not T.Camera.Switch or not validView(view) then view = getView() end
    setView(view)

    -- what sits on the table while you work: the bald foam head facing you, the wig taking shape on
    -- it, the wefts / bundles going in beside it (used up as you go), the dye bottle when colouring
    local props, build = {}, nil
    local TP = Config.TableProps
    local head = TP.Head and tableProp(TP.Head.model, work, heading + 180.0)
    local wigModel = Tables.WigModel(info)
    if head and wigModel and loadModel(wigModel) then
        local p = TP.Head.point
        build = CreateObject(wigModel, work.x, work.y, work.z + 0.3, false, false, false)
        SetEntityCollision(build, false, false)
        AttachEntityToEntity(build, head, 0, p.x, p.y, p.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        SetModelAsNoLongerNeeded(wigModel)
        if kind ~= 'dye' then SetEntityAlpha(build, 0, false) end
    end
    -- the hair goes on the side of the head towards the middle of the table (her tables have things on the ends)
    local mid = GetEntityCoords(ent) - work
    local side = (along.x * mid.x + along.y * mid.y) < -0.1 and -1.0 or 1.0
    if kind ~= 'dye' and TP.Bundle then
        for i = 1, math.min(6, (info and info.wefts) or Config.Workshop.BundlesPerWig) do
            props[#props + 1] = tableProp(TP.Bundle.model, work + along * (side * (0.15 + i * 0.045)) + out * 0.08, heading + (i % 2) * 6.0)
        end
    end
    if kind == 'dye' and TP.DyeBottle then props[#props + 1] = tableProp(TP.DyeBottle.model, work + along * (side * 0.2) + out * 0.06, heading + 40.0) end
    if head then props[#props + 1] = head end

    local shots = tableShots(stand, work, along, out)
    local s = shots[view]
    shot(s[1], s[2], s[3])
    playWork()

    local results, cancelled = {}, false
    local hint = T.Camera.Switch and L('table_work_hint_v') or L('table_work_hint')
    for i, st in ipairs(stages) do
        local tool = st.prop and handProp(st.prop) or nil
        NUI.Send('stage', { label = st.label, step = i, steps = #stages, time = st.time, hint = hint })
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < st.time do
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            local f = ((i - 1) + (GetGameTimer() - t0) / st.time) / #stages
            -- the wig takes shape on the head while the wefts / bundles get used up
            if kind ~= 'dye' then
                if build then SetEntityAlpha(build, math.floor(255 * math.min(1, f * 1.15)), false) end
                local n = #props - (head and 1 or 0)
                for k = 1, n do
                    local b = props[k]
                    if b then SetEntityAlpha(b, math.floor(255 * math.max(0, math.min(1, (1 - f) * n - (k - 1)))), false) end
                end
            end
            if cancelPressed() then cancelled = true break end
            view = pollView(view, shots)
            if not IsEntityPlayingAnim(PlayerPedId(), WORK.dict, WORK.clip, 3) then playWork() end
        end
        NUI.Send('stage', { hide = true })
        if tool then DeleteEntity(tool) end
        if cancelled then break end
        if st.check then
            results[i] = lib.skillCheck(st.check) == true
            CB.Notify(results[i] and L('table_check_passed') or L('table_check_failed'), results[i] and 'success' or 'warning', 1500)
        end
    end

    if cancelled then
        lib.callback.await('nz-wig:tableCancel', false)
        CB.Notify(L('table_cancelled'), 'info')
    else
        local done, res = lib.callback.await('nz-wig:tableFinish', false, token, results)
        if done and res then
            if build then ResetEntityAlpha(build) end
            NUI.Send('result', res)
            Wait(1800)
        end
    end

    if build then DeleteEntity(build) end
    for _, p in ipairs(props) do if p then DeleteEntity(p) end end
    stopCam()
    ClearPedTasks(PlayerPedId())
    Tables.busy = false
end

-- table window → table jobs
function Tables.Job(kind, req, view)
    local ent = Tables.Bench() or Tables.Nearest()
    if not ent then return CB.Notify(L('table_needed'), 'error') end
    bench = nil
    CreateThread(function() run(ent, kind, req, view) end)
end

RegisterNUICallback('benchClose', function(_, cb)
    bench = nil
    NUI.CloseSide()
    cb(1)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    if cam then RenderScriptCams(false, false, 0, true, false) DestroyCam(cam, false) end
end)
