-- First person haircuts (client side).
-- The camera moves in close to the client's head and orbits it. The cursor is the tool:
-- a ray from the cursor hits an ellipsoid around the head, and where it lands decides the
-- region (top / back / left / right / brows / beard). Work is sent to the server in batches.

Cutting = { session = nil, sitting = nil, prop = nil }

local CC = Config.Cutting
local HEAD_BONE = 31086

-- head ellipsoid, in metres (right, forward, up) and offset from the head bone
local RADII = { x = 0.105, y = 0.125, z = 0.135 }
local CENTRE = { y = 0.015, z = 0.055 }

local cam
local S -- the running session (barber side)

-- math -----------------------------------------------------------------------------------------

local function headFrame(ped)
    local c = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local h = math.rad(GetEntityHeading(ped))
    local fwd = vec3(-math.sin(h), math.cos(h), 0.0)
    local right = vec3(math.cos(h), math.sin(h), 0.0)
    local up = vec3(0.0, 0.0, 1.0)
    local centre = c + fwd * CENTRE.y + up * CENTRE.z
    return centre, fwd, right, up
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

-- ray vs head ellipsoid. returns the hit point in head-local unit coords (x right, y forward, z up) and in world
local function hitHead(ped, origin, dir)
    local centre, fwd, right, up = headFrame(ped)
    local o = origin - centre
    -- into unit-sphere space
    local lo = vec3(dot(o, right) / RADII.x, dot(o, fwd) / RADII.y, dot(o, up) / RADII.z)
    local ld = vec3(dot(dir, right) / RADII.x, dot(dir, fwd) / RADII.y, dot(dir, up) / RADII.z)
    local a = dot(ld, ld)
    local b = 2.0 * dot(lo, ld)
    local c = dot(lo, lo) - 1.0
    local disc = b * b - 4.0 * a * c
    if disc < 0 then return nil end
    local t = (-b - math.sqrt(disc)) / (2.0 * a)
    if t < 0 then return nil end
    local p = lo + ld * t
    local world = centre + right * (p.x * RADII.x) + fwd * (p.y * RADII.y) + up * (p.z * RADII.z)
    return p, world
end

-- which part of the head a unit-sphere point is on
local function regionOf(p)
    if p.y > 0.45 then
        -- the face side
        if p.z > 0.62 then return 'top' end
        if p.z > 0.12 and p.z <= 0.62 and math.abs(p.x) < 0.8 then return 'brows' end
        if p.z < -0.35 and math.abs(p.x) < 0.75 then return 'beard' end
        return nil
    end
    if p.z > 0.55 then return 'top' end
    if p.y < -0.3 then return 'back' end
    if p.x > 0.45 then return 'right' end
    if p.x < -0.45 then return 'left' end
    return 'top'
end
Cutting.RegionOf = regionOf

-- camera ---------------------------------------------------------------------------------------------

local orbit = { yaw = 0.0, pitch = 8.0, dist = CC.Camera.Dist }

local function placeCam(ped)
    local centre, fwd, right = headFrame(ped)
    local yaw, pitch = math.rad(orbit.yaw), math.rad(orbit.pitch)
    local flat = fwd * math.cos(yaw) + right * math.sin(yaw)
    local pos = centre + flat * (orbit.dist * math.cos(pitch)) + vec3(0.0, 0.0, orbit.dist * math.sin(pitch) + CC.Camera.Height)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    local d = centre - pos
    local heading = -math.deg(math.atan(d.x, d.y))
    local p = math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
    SetCamRot(cam, p, 0.0, heading, 2)
end

local function startCam(ped)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, CC.Camera.Fov, false, 0)
    orbit.yaw, orbit.pitch, orbit.dist = 0.0, 8.0, CC.Camera.Dist
    placeCam(ped)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
end

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    cam = nil
end

-- the cursor ray ---------------------------------------------------------------------------------------

local function cursorRay()
    local x, y = GetNuiCursorPosition()
    local w, h = GetActiveScreenResolution()
    if not x or w == 0 then return nil end
    local sx, sy = x / w, y / h
    local world, normal = GetWorldCoordFromScreenCoord(sx, sy)
    if not world or (normal.x == 0 and normal.y == 0 and normal.z == 0) then return nil end
    return world, normal, sx, sy
end

-- sounds + particles ------------------------------------------------------------------------------------

local function ptfx(ped, region)
    local p = CC.Particles
    if not p or ped == 0 or not DoesEntityExist(ped) then return end
    if not pcall(lib.requestNamedPtfxAsset, p.asset, 1000) then return end
    UseParticleFxAssetNextCall(p.asset)
    local z = region == 'beard' and -0.06 or (region == 'brows' and 0.06 or 0.14)
    StartParticleFxNonLoopedOnPedBone(p.name, ped, 0.0, 0.05, z, 0.0, 0.0, 0.0, GetPedBoneIndex(ped, HEAD_BONE), p.scale or 0.8, false, false, false)
end

-- other players watching
RegisterNetEvent('nz-wig:c:cutFx', function(clientSrc, region)
    if S and S.other == clientSrc then return end -- the barber spawns their own
    ptfx(PedOf(clientSrc), region)
end)

-- the session (barber) ----------------------------------------------------------------------------------

local function availableFor(tool, region)
    if not S or not region or not S.regions[region] then return false end
    local def = CC.Tools[tool]
    if not def or not def.Regions[region] then return false end
    if tool == 'razor' and region == 'top' and not S.short and ((S.work.top or {}).clippers or 0) < 100 then return false end
    return ((S.work[region] or {})[tool] or 0) < 100
end

-- what the barber should do next (the line in the progress bar)
local function objective()
    if not S then return nil end
    local tool = S.tool
    local def = CC.Tools[tool]
    local best, bestLeft
    for _, r in ipairs({ 'top', 'left', 'right', 'back', 'brows', 'beard' }) do
        if availableFor(tool, r) then
            local left = 100 - ((S.work[r] or {})[tool] or 0)
            if not best or left < bestLeft then best, bestLeft = r, left end
        end
    end
    return { tool = tool, mode = def.Mode, region = best, text = best and L('obj_' .. def.Mode .. '_' .. best) or L('obj_switch') }
end

local function pushHud(hover)
    if not S then return end
    NUI.Send('cut:update', { tool = S.tool, hover = hover, work = S.work, objective = objective(), holding = S.holding })
end

local function queueWork(region, tool, amount)
    S.local_[region] = S.local_[region] or {}
    S.local_[region][tool] = (S.local_[region][tool] or 0) + amount
    -- optimistic local progress, the server's snapshot corrects it
    S.work[region][tool] = math.min(100, (S.work[region][tool] or 0) + amount)
end

local function flush()
    if not S then return end
    local batch = {}
    for r, tools in pairs(S.local_) do
        for t, w in pairs(tools) do
            if w > 0 then batch[#batch + 1] = { r = r, t = t, w = math.floor(w * 10) / 10 } end
        end
    end
    S.local_ = {}
    if #batch > 0 then TriggerServerEvent('nz-wig:s:cutWork', S.id, batch) end
end

RegisterNetEvent('nz-wig:c:cutProgress', function(id, work)
    if not S or S.id ~= id then return end
    -- keep local work that hasn't been sent yet
    for r, tools in pairs(work) do
        S.work[r] = S.work[r] or {}
        for t, v in pairs(tools) do
            local pending = (S.local_[r] or {})[t] or 0
            S.work[r][t] = math.min(100, v + pending)
        end
    end
    pushHud(S.hover)
end)

local function setTool(tool)
    if not S or not S.toolSet[tool] or S.tool == tool then return end
    S.tool = tool
    S.prop = DeleteProp(S.prop)
    S.prop = AttachProp(CC.Props[tool] or nil)
    NUI.Send('cut:tool', { tool = tool })
    pushHud(S.hover)
end

RegisterNUICallback('cutTool', function(d, cb) setTool(d and d.tool) cb(1) end)
RegisterNUICallback('cutMouse', function(d, cb)
    if S then
        local down = d and d.down == true
        if down and not S.holding then S.clicked = true end
        S.holding = down
    end
    cb(1)
end)
RegisterNUICallback('cutZoom', function(d, cb)
    if S then orbit.dist = Clamp(orbit.dist + (tonumber(d and d.delta) or 0) * 0.04, CC.Camera.MinDist, CC.Camera.MaxDist) end
    cb(1)
end)
RegisterNUICallback('cutFinish', function(_, cb)
    if S then flush() TriggerServerEvent('nz-wig:s:cutFinish', S.id) end
    cb(1)
end)
RegisterNUICallback('cutCancel', function(_, cb)
    if S then TriggerServerEvent('nz-wig:s:cutCancel', S.id) end
    cb(1)
end)

local function loop()
    local other = PedOf(S.other)
    local lastFlush, lastHud, lastSnip, strokeDir, strokeTravel, lastY = 0, 0, 0, 0, 0.0, nil
    local hoverRegion

    while S do
        local now = GetGameTimer()
        local me = PlayerPedId()
        other = PedOf(S.other)
        if other == 0 or not DoesEntityExist(other) then
            TriggerServerEvent('nz-wig:s:cutCancel', S.id)
            break
        end

        -- lock the barber in place, use A / D / W / S to walk the camera around the head
        DisableAllControlActions(0)
        EnableControlAction(0, 249, true) -- push to talk
        if IsDisabledControlPressed(0, 34) then orbit.yaw = orbit.yaw - 1.6 end
        if IsDisabledControlPressed(0, 35) then orbit.yaw = orbit.yaw + 1.6 end
        if IsDisabledControlPressed(0, 32) then orbit.pitch = math.min(70.0, orbit.pitch + 1.0) end
        if IsDisabledControlPressed(0, 33) then orbit.pitch = math.max(-25.0, orbit.pitch - 1.0) end
        placeCam(other)

        local origin, dir, _, sy = cursorRay()
        local p, world
        if origin then p, world = hitHead(other, origin, dir) end
        local region = p and regionOf(p) or nil
        local ok = region and availableFor(S.tool, region)

        if world then
            local col = ok and { 8, 175, 162 } or { 229, 72, 77 }
            DrawMarker(28, world.x, world.y, world.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.012, 0.012, 0.012, col[1], col[2], col[3], 220, false, false, 2, false, nil, nil, false)
        end

        local def = CC.Tools[S.tool]
        if ok then
            if def.Mode == 'click' then
                if S.clicked and now - lastSnip > 140 then
                    lastSnip = now
                    queueWork(region, S.tool, def.Work)
                    NUI.Send('cut:fx', { tool = S.tool })
                    ptfx(other, region)
                end
            elseif def.Mode == 'hold' then
                if S.holding then
                    queueWork(region, S.tool, def.Work * GetFrameTime())
                    if now - lastSnip > 380 then lastSnip = now ptfx(other, region) end
                end
            elseif def.Mode == 'stroke' then
                -- up and down strokes: every change of direction after enough travel is one stroke
                if S.holding and sy and lastY then
                    local dy = sy - lastY
                    if math.abs(dy) > 0.0015 then
                        local d = dy > 0 and 1 or -1
                        if d ~= strokeDir then
                            if strokeTravel > 0.035 then
                                queueWork(region, S.tool, def.Work)
                                NUI.Send('cut:fx', { tool = S.tool })
                                ptfx(other, region)
                            end
                            strokeDir, strokeTravel = d, 0.0
                        else
                            strokeTravel = strokeTravel + math.abs(dy)
                        end
                    end
                end
            end
        end
        S.clicked = false
        lastY = sy
        S.hover = region

        if now - lastFlush > 250 then lastFlush = now flush() end
        if now - lastHud > 120 or region ~= hoverRegion then
            lastHud, hoverRegion = now, region
            pushHud(ok and region or (region and ('x:' .. region)) or nil)
        end

        -- (number keys to switch tools are handled in the NUI)
        if not IsEntityPlayingAnim(me, CC.Anim.dict, CC.Anim.clip, 3) then LoopAnim(CC.Anim, me) end
        Wait(0)
    end
end

RegisterNetEvent('nz-wig:c:cutStart', function(d)
    if S then return end
    local other = PedOf(d.other)
    if other == 0 then return TriggerServerEvent('nz-wig:s:cutCancel', d.id) end
    local me = PlayerPedId()
    NUI.CloseApp()
    FaceEntity(me, other)
    FreezeEntityPosition(me, true)

    local toolSet = {}
    for _, t in ipairs(d.tools) do toolSet[t] = true end
    S = {
        id = d.id, other = d.other, name = d.name, tools = d.tools, toolSet = toolSet, regions = d.regions,
        short = d.short, forced = d.forced, work = d.work or {}, local_ = {}, holding = false,
    }
    for r in pairs(d.regions) do S.work[r] = S.work[r] or { scissors = 0, clippers = 0, razor = 0 } end
    Cutting.session = S
    Snatch.busy = true
    S.tool = d.tools[1]
    S.prop = AttachProp(CC.Props[S.tool] or nil)
    LoopAnim(CC.Anim, me)
    startCam(other)

    local tools = {}
    for _, id in ipairs(d.tools) do
        local t = CC.Tools[id]
        tools[#tools + 1] = { id = id, label = t.Label, icon = t.Icon, mode = t.Mode, key = t.Key }
    end
    NUI.Send('cut:start', { id = d.id, name = d.name, tools = tools, tool = S.tool, regions = d.regions, forced = d.forced, max = d.max, work = S.work })
    NUI.Cursor(true)
    pushHud(nil)
    CreateThread(loop)
end)

local function endBarber()
    if not S then return end
    S.prop = DeleteProp(S.prop)
    S = nil
    Cutting.session = nil
    Snatch.busy = false
    NUI.Cursor(false)
    stopCam()
    local me = PlayerPedId()
    FreezeEntityPosition(me, false)
    ClearPedSecondaryTask(me)
end

-- the session (client sitting still) -------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:cutSit', function(d)
    local me = PlayerPedId()
    Cutting.sitting = d.id
    Snatch.busy = true
    NUI.CloseApp()
    local b = PedOf(d.other)
    if b ~= 0 and not LocalPlayer.state[ST.held] then
        -- turn away a little so the barber can reach
        FaceEntity(me, b)
    end
    if not LocalPlayer.state[ST.held] and not LocalPlayer.state[ST.tied] then
        FreezeEntityPosition(me, true)
        TaskStandStill(me, -1)
    end
    NUI.Send('cut:sit', { name = d.name, forced = d.forced })
end)

RegisterNUICallback('cutLeave', function(_, cb)
    if Cutting.sitting then TriggerServerEvent('nz-wig:s:cutCancel', Cutting.sitting) end
    cb(1)
end)

RegisterNetEvent('nz-wig:c:cutEnd', function(r)
    if S and S.id == r.id then
        endBarber()
        NUI.Send('cut:end', r)
    end
    if Cutting.sitting == r.id then
        Cutting.sitting = nil
        Snatch.busy = false
        local me = PlayerPedId()
        if not LocalPlayer.state[ST.held] and not LocalPlayer.state[ST.tied] then
            FreezeEntityPosition(me, false)
            ClearPedTasks(me)
        end
        NUI.Send('cut:sitEnd', r)
    end
end)

-- asking --------------------------------------------------------------------------------------------------

local OX = GetResourceState('ox_inventory') == 'started'

-- ox_inventory can tell us on the client; with anything else the server checks on request
local function hasTool()
    if not OX then return true end
    for _, id in ipairs(ToolOrder) do
        local t = CC.Tools[id]
        if t and (exports.ox_inventory:Search('count', t.Item) or 0) > 0 then return true end
    end
    return false
end

local function hasHead(entity)
    local m = ModelKey(GetEntityModel(entity))
    return m ~= nil and ModelEnabled(m)
end

local function free()
    return not Snatch.busy and not NUI.app and not Restrain.tied and not Restrain.held and not Restrain.acting
end

function Cutting.Request(entity, forced)
    local sid = ServerIdOf(entity)
    if not sid then return end
    if Config.IsInNoSnatchZone(GetEntityCoords(PlayerPedId())) then return CB.Notify(L('no_zone'), 'error') end
    TriggerServerEvent('nz-wig:s:cutRequest', sid, forced == true)
end

Cutting.TargetOptions = {}
if CC.Enabled then
    Cutting.TargetOptions[#Cutting.TargetOptions + 1] = {
        name = 'nzwig_cut', label = CC.Label, icon = CC.Icon, distance = CC.Range,
        canInteract = function(e) return free() and hasHead(e) and hasTool() end,
        onSelect = function(e) Cutting.Request(e, false) end,
    }
    Cutting.TargetOptions[#Cutting.TargetOptions + 1] = {
        name = 'nzwig_cut_force', label = CC.ForceLabel, icon = 'fa-solid fa-user-slash', distance = CC.Range,
        canInteract = function(e) return free() and hasHead(e) and hasTool() and CB.Helpless(e, ServerIdOf(e)) end,
        onSelect = function(e) Cutting.Request(e, true) end,
    }
end

-- using a tool from the inventory: whoever is in front, forced if they can't fight back
RegisterNetEvent('nz-wig:c:useTool', function()
    if not free() then return end
    local ped = ClosestInFront(CC.Range)
    if not ped then return CB.Notify(L('no_one_close'), 'error') end
    Cutting.Request(ped, CB.Helpless(ped, ServerIdOf(ped)))
end)

function Cutting.Cleanup()
    if S then endBarber() end
    if Cutting.sitting then FreezeEntityPosition(PlayerPedId(), false) end
end
