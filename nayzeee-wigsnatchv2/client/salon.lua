-- The salon (client side).
-- Stylist: the Style Book, then a camera close on the client's head. Every move's geometry
-- (shared/salon.lua) is turned into points around the client's head bone and projected onto the
-- screen many times a second; the UI (web/js/salon.js) draws the guides and plays the move.
-- Client: sits in the closest chair, follows the steps, M for a mirror view, and gets the reveal.

Salon = Salon or {}
local SC = Config.Salon
local G = Salon.Geo
local HEAD_BONE = 31086

-- the head ellipsoid, as in first person cutting: radii (right, forward, up) and offset from the bone
local RADII = { x = 0.105, y = 0.125, z = 0.135 }
local CENTRE = { y = 0.015, z = 0.055 }
local HAIR = 1.07        -- the guides sit on the hair, a little off the scalp

Salon.Looks = {}
RegisterNetEvent('nz-wig:c:salonLooks', function(looks)
    Salon.Looks = type(looks) == 'table' and looks or {}
    NUI.Send('studio:looks', Salon.Looks)
end)

-- every style and in-between look the Wig Studio can set
function Salon.StudioList()
    local out = {}
    for _, s in ipairs(Config.SalonStyles) do out[#out + 1] = { id = s.id, label = s.label } end
    for id, label in pairs(SC.Looks or {}) do out[#out + 1] = { id = id, label = label, extra = true } end
    return out
end

-- shades: the closest GTA hair colour to each extension hair shade -------------------------------------

local shadeCache = {}
local function hexRgb(h)
    h = tostring(h or ''):gsub('#', '')
    return tonumber(h:sub(1, 2), 16) or 0, tonumber(h:sub(3, 4), 16) or 0, tonumber(h:sub(5, 6), 16) or 0
end
local function nearest(hex)
    local r, g, b = hexRgb(hex)
    local best, bestD = 0, math.huge
    for i = 0, GetNumHairColors() - 1 do
        local pr, pg, pb = GetPedHairRgbColor(i)
        local d = (pr - r) ^ 2 * 0.3 + (pg - g) ^ 2 * 0.59 + (pb - b) ^ 2 * 0.11
        if d < bestD then best, bestD = i, d end
    end
    return best
end
local function shadeDef(id)
    for _, s in ipairs(SC.Shades) do if s.id == id then return s end end
end
Salon.ShadeDef = shadeDef

-- the hair colour and highlight for a shade id, or nil (natural hair keeps its own colour)
function Salon.ShadeColour(id)
    if not id then return nil end
    if shadeCache[id] then return shadeCache[id][1], shadeCache[id][2] end
    local s = shadeDef(id)
    if not s then return nil end
    local c = nearest(s.rgb)
    local tip = s.tip and shadeDef(s.tip)
    local h = tip and nearest(tip.rgb) or c
    shadeCache[id] = { c, h }
    return c, h
end

-- head space -----------------------------------------------------------------------------------------

local function headFrame(ped)
    local c = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local h = math.rad(GetEntityHeading(ped))
    local fwd = vec3(-math.sin(h), math.cos(h), 0.0)
    local right = vec3(math.cos(h), math.sin(h), 0.0)
    local up = vec3(0.0, 0.0, 1.0)
    return c + fwd * CENTRE.y + up * CENTRE.z, fwd, right, up
end

local function toWorld(f, p)
    local k = p.s and HAIR or 1.0
    return f.c + f.right * (p.x * RADII.x * k) + f.fwd * (p.y * RADII.y * k) + f.up * (p.z * RADII.z * k)
end

local function visible(f, p, world, camPos)
    if not p.s then return true end
    local n = f.right * (p.x / RADII.x) + f.fwd * (p.y / RADII.y) + f.up * (p.z / RADII.z)
    local d = camPos - world
    return (n.x * d.x + n.y * d.y + n.z * d.z) > 0
end

-- camera ---------------------------------------------------------------------------------------------

local cam
local orbit = { yaw = 180.0, pitch = 10.0, dist = SC.Camera.Dist }
local want = nil   -- where the camera is easing to for the current move

local function placeCam(ped)
    local centre, fwd, right = headFrame(ped)
    if want then
        local dy = ((want.yaw - orbit.yaw + 540) % 360) - 180
        orbit.yaw = orbit.yaw + dy * 0.08
        orbit.pitch = orbit.pitch + (want.pitch - orbit.pitch) * 0.08
        orbit.dist = orbit.dist + (want.dist - orbit.dist) * 0.08
        if math.abs(dy) < 0.3 and math.abs(want.pitch - orbit.pitch) < 0.3 then want = nil end
    end
    local yaw, pitch = math.rad(orbit.yaw), math.rad(orbit.pitch)
    local flat = fwd * math.cos(yaw) + right * math.sin(yaw)
    local look = centre + vec3(0.0, 0.0, orbit.look or 0.0)
    local pos = look + flat * (orbit.dist * math.cos(pitch)) + vec3(0.0, 0.0, orbit.dist * math.sin(pitch) + SC.Camera.Height)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    local d = look - pos
    SetCamRot(cam, math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y))), 0.0, -math.deg(math.atan(d.x, d.y)), 2)
    return pos
end

local function startCam(ped, yaw, pitch, dist)
    if cam then return end
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SC.Camera.Fov, false, 0)
    orbit.yaw, orbit.pitch, orbit.dist, orbit.look = yaw or 180.0, pitch or 10.0, dist or SC.Camera.Dist, 0.0
    want = nil
    placeCam(ped)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
end

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
    cam = nil
end

-- point the camera at a move's geometry: around to its side, up or down to its height
local function frame(points)
    local sx, sy, sz, n, low = 0, 0, 0, 0, false
    for _, p in ipairs(points) do
        sx, sy, sz, n = sx + p.x, sy + p.y, sz + p.z, n + 1
        if not p.s and p.z < -0.6 then low = true end
    end
    if n == 0 then return end
    sx, sy, sz = sx / n, sy / n, sz / n
    local yaw = math.deg(math.atan(sx, sy))
    if math.abs(sx) < 0.08 and math.abs(sy) < 0.08 then yaw = orbit.yaw end   -- the top: stay where you are
    local pitch = low and -6.0 or math.max(-12.0, math.min(62.0, math.deg(math.asin(math.max(-1, math.min(1, sz)))) * 0.85 + 6.0))
    want = { yaw = yaw, pitch = pitch, dist = low and SC.Camera.Dist * 1.55 or SC.Camera.Dist }
    orbit.look = low and -0.12 or 0.0
end

-- props + effects --------------------------------------------------------------------------------------

local FX = {
    spray = { asset = 'core', name = 'ent_sht_steam', scale = 0.18, z = 0.16 },
    steam = { asset = 'core', name = 'ent_sht_steam', scale = 0.3,  z = 0.05 },
    snip  = Config.Cutting.Particles and { asset = Config.Cutting.Particles.asset, name = Config.Cutting.Particles.name, scale = 0.6, z = 0.1 } or nil,
}
local TOOL_FX = {
    mousse = 'spray', heat_protect = 'spray', shine_spray = 'spray', moisturizer = 'spray',
    flat_iron = 'steam', curl_wand = 'steam', hot_water = 'steam', blow_dryer = 'spray', shears = 'snip',
}

local function fxOn(ped, tool)
    local f = FX[TOOL_FX[tool] or '']
    if not f or ped == 0 or not DoesEntityExist(ped) then return end
    if not pcall(lib.requestNamedPtfxAsset, f.asset, 1000) then return end
    UseParticleFxAssetNextCall(f.asset)
    StartParticleFxNonLoopedOnPedBone(f.name, ped, 0.0, 0.0, f.z, 0.0, 0.0, 0.0, GetPedBoneIndex(ped, HEAD_BONE), f.scale, false, false, false)
end

RegisterNetEvent('nz-wig:c:salonFx', function(clientSrc, tool)
    local S = Salon.session
    if S and S.other == clientSrc then return end   -- the stylist makes their own
    fxOn(PedOf(clientSrc), tool)
end)

-- the Style Book ----------------------------------------------------------------------------------------

local function itemLabel(name)
    for _, t in pairs(SC.Tools) do if t.item == name then return t.label end end
    if SC.Hair[name] then return SC.Hair[name].label end
    return name
end

local function staticBook()
    local styles = {}
    for _, s in ipairs(Config.SalonStyles) do
        local steps = {}
        for i, st in ipairs(s.steps) do steps[i] = { text = st.text, phase = st.phase, opt = st.opt, moves = #st.moves } end
        styles[#styles + 1] = {
            id = s.id, label = s.label, cat = s.cat, level = s.level or 1, days = s.days, desc = s.desc,
            hair = s.hair, extra = s.extra, options = s.options, steps = steps,
        }
    end
    local shades = {}
    for i, sh in ipairs(SC.Shades) do
        local c, h = Salon.ShadeColour(sh.id)
        local r, g, b = GetPedHairRgbColor(c or 0)
        local tr, tg, tb = GetPedHairRgbColor(h or c or 0)
        shades[i] = { id = sh.id, label = sh.label, rgb = sh.rgb, game = ('rgb(%d,%d,%d)'):format(r, g, b), tip = sh.tip and ('rgb(%d,%d,%d)'):format(tr, tg, tb) or nil }
    end
    local hair = {}
    for id, h in pairs(SC.Hair) do hair[id] = { label = h.label, kind = h.kind } end
    return { styles = styles, cats = Config.SalonCats, shades = shades, hair = hair }
end

local function open(entity)
    local sid = entity and ServerIdOf(entity)
    local data = lib.callback.await('nz-wig:salonBook', false, sid)
    if not data then return end
    if data.error then return CB.Notify(data.error, 'error') end
    local static = staticBook()
    data.live = data.styles   -- what the server says about each style (look on this model, locked)
    for k, v in pairs(static) do data[k] = v end
    -- labels for every item the book can mention
    local labels = {}
    for name in pairs(data.have or {}) do labels[name] = itemLabel(name) end
    for name in pairs(SC.Hair) do labels[name] = itemLabel(name) end
    data.labels = labels
    NUI.CloseApp()
    NUI.app = 'salonbook'
    NUI.Send('salon:book', data)
    NUI.Refocus()
end
Salon.OpenBook = open

RegisterNUICallback('salonBookClose', function(_, cb)
    if NUI.app == 'salonbook' then NUI.app = nil NUI.Refocus() end
    cb(1)
end)

RegisterNUICallback('salonNeeds', function(d, cb)
    local style = d and Salon.Style(d.style)
    if not style then return cb(false) end
    local need = Salon.Needs(style, d.opts or {})
    cb({ tools = need.tools, uses = need.uses, hair = need.hair, extra = need.extra, moves = need.moves, minutes = Salon.Minutes(style, d.opts or {}) })
end)

RegisterNUICallback('salonStart', function(d, cb)
    if NUI.app == 'salonbook' then NUI.app = nil NUI.Refocus() end
    if type(d) == 'table' and d.target then
        TriggerServerEvent('nz-wig:s:salonRequest', d.target, d.style, d.opts or {}, d.hair, d.extra, tonumber(d.price) or 0)
    end
    cb(1)
end)

-- the stylist's session ---------------------------------------------------------------------------------

local S

local function free()
    return not Snatch.busy and not NUI.app and not Restrain.tied and not Restrain.held and not Restrain.acting and not S and not Salon.sitting
end

local function setProp(tool)
    local def = SC.Tools[tool or 'hands'] or {}
    if S.propTool == tool then return end
    S.prop = DeleteProp(S.prop)
    S.propTool = tool
    S.prop = AttachProp(def.prop or nil)
end

local function geometry(i)
    local m = S.moves[i]
    local geo = Salon.GeoOf(S.moves, i)
    local g = geo and G.Build(geo)
    if not g then return nil end
    local list = G.Slice(g.list, m.from, m.limit)
    local out = { kind = g.kind, list = list }
    -- dabs on a path: every n-th point along it
    if m.a == 'dab' and g.kind == 'paths' then
        local pts = {}
        for _, path in ipairs(list) do
            for k = m.every or 4, #path, m.every or 4 do pts[#pts + 1] = path[k] end
        end
        out = { kind = 'points', list = G.Slice(pts, nil, m.limit and m.limit * 3 or nil) }
    end
    return out
end

local function flatten(g)
    -- everything the camera should frame, as one list of points
    local pts = {}
    if not g then return pts end
    for _, it in ipairs(g.list) do
        if g.kind == 'points' then pts[#pts + 1] = it
        else for _, p in ipairs(it) do pts[#pts + 1] = p end end
    end
    return pts
end

-- a braid carried on over several moves: all of its stitches, so the braid grows the whole way down
local function chainOf(i)
    local m = S.moves[i]
    if m.cont then return nil end
    local n = m.stitches or 6
    for k = i + 1, #S.moves do
        local nx = S.moves[k]
        if nx.a ~= 'braid' or not nx.cont then break end
        n = n + (nx.stitches or 6)
    end
    return n
end

-- the work that stays on the head after a move: parts, rows, braids, spots, tracks
local function keep(i, k)
    if type(k) ~= 'table' or not S.geo then return end
    local m = S.moves[i]
    local list = S.geo.list
    local col = (m.feed or k.c == 'feed') and S.colour.feed or S.colour.hair
    if k.k == 'part' or k.k == 'row' or k.k == 'track' then
        if S.geo.kind ~= 'paths' then return end
        S.decor[#S.decor + 1] = { k = k.k, paths = list, c = col }
    elseif k.k == 'braid' then
        if S.geo.kind ~= 'paths' then return end
        local upto = math.max(1, math.min(#list, (tonumber(k.path) or 0) + 1))
        local d = { k = 'braid', paths = G.Slice(list, 1, upto), t = math.max(0, math.min(1, tonumber(k.t) or 1)), c = S.colour.hair }
        local last = S.decor[#S.decor]
        if m.cont and last and last.k == 'braid' then S.decor[#S.decor] = d else S.decor[#S.decor + 1] = d end
    elseif k.k == 'dab' and S.geo.kind == 'points' and type(k.hit) == 'table' then
        local pts = {}
        for _, h in ipairs(k.hit) do
            local p = list[(tonumber(h) or -1) + 1]
            if p then pts[#pts + 1] = p end
        end
        if #pts > 0 then S.decor[#S.decor + 1] = { k = 'dab', points = pts, m = type(k.m) == 'string' and k.m or 'gel', c = col } end
    end
    -- keep it to the last few dozen pieces
    while #S.decor > 40 do table.remove(S.decor, 1) end
end

local function startMove(i)
    S.i = i
    local m = S.moves[i]
    S.geo = geometry(i)
    setProp(m.tool)
    frame(flatten(S.geo))
    local st = S.style.steps[m.step]
    local def = SC.Tools[m.tool or 'hands'] or {}
    NUI.Send('salon:move', {
        i = i, total = #S.moves, a = m.a, tool = m.tool or 'hands', toolLabel = def.label, text = m.text,
        step = m.stepNo, steps = S.stepCount, stepText = st.text, phase = st.phase,
        seq = m.seq, stitches = m.stitches, strands = m.strands, cont = m.cont, feed = m.feed, slice = m.slice,
        mark = m.mark, turns = m.turns, dir = m.dir, band = m.band, n = m.n, heat = m.heat, cover = m.cover,
        kind = S.geo and S.geo.kind, count = S.geo and #S.geo.list or 0, chain = m.a == 'braid' and chainOf(i) or nil,
    })
end

local function project()
    local other = PedOf(S.other)
    if other == 0 or not S.geo then return end
    local c, fwd, right, up = headFrame(other)
    local f = { c = c, fwd = fwd, right = right, up = up }
    local camPos = GetCamCoord(cam)
    local function pt(p)
        local w = toWorld(f, p)
        local on, x, y = GetScreenCoordFromWorldCoord(w.x, w.y, w.z)
        local vis = on and visible(f, p, w, camPos)
        return { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, vis and 1 or 0 }
    end
    local out = {}
    for k, it in ipairs(S.geo.list) do
        if S.geo.kind == 'points' then out[k] = pt(it)
        elseif S.geo.kind == 'pairs' then out[k] = { pt(it[1]), pt(it[2]) }
        else
            local path = {}
            for j, p in ipairs(it) do path[j] = pt(p) end
            out[k] = path
        end
    end
    -- the head itself, for the UI's sense of scale
    local _, hx, hy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z)
    local top = c + up * RADII.z
    local _, tx, ty = GetScreenCoordFromWorldCoord(top.x, top.y, top.z)
    -- the work so far, projected the same way
    local dec = {}
    for k, d in ipairs(S.decor) do
        local e = { k = d.k, c = d.c, t = d.t, m = d.m }
        if d.paths then
            e.ps = {}
            for j, path in ipairs(d.paths) do
                local pp = {}
                for q, p in ipairs(path) do pp[q] = pt(p) end
                e.ps[j] = pp
            end
        else
            e.p = {}
            for j, p in ipairs(d.points) do e.p[j] = pt(p) end
        end
        dec[k] = e
    end
    NUI.Send('salon:geo', { i = S.i, g = out, head = { hx, hy, tx, ty }, dec = dec })
end

local function loop()
    local lastSend = 0
    while S do
        local me = PlayerPedId()
        local other = PedOf(S.other)
        if other == 0 or not DoesEntityExist(other) then
            TriggerServerEvent('nz-wig:s:salonCancel', S.id)
            break
        end
        DisableAllControlActions(0)
        EnableControlAction(0, 249, true) -- push to talk
        -- Q / E walk the camera around the head, W / S height (A / D are the braiding keys)
        if IsDisabledControlPressed(0, 44) then orbit.yaw = orbit.yaw - 1.6 want = nil end
        if IsDisabledControlPressed(0, 38) then orbit.yaw = orbit.yaw + 1.6 want = nil end
        if IsDisabledControlPressed(0, 32) then orbit.pitch = math.min(70.0, orbit.pitch + 1.0) want = nil end
        if IsDisabledControlPressed(0, 33) then orbit.pitch = math.max(-30.0, orbit.pitch - 1.0) want = nil end
        placeCam(other)
        local now = GetGameTimer()
        if now - lastSend > 33 then lastSend = now project() end
        local a = S.anim
        if a and not IsEntityPlayingAnim(me, a.dict, a.clip, 3) then LoopAnim(a, me) end
        Wait(0)
    end
end

RegisterNetEvent('nz-wig:c:salonStart', function(d)
    if S then return end
    local style = Salon.Style(d.style)
    local other = PedOf(d.other)
    if not style or other == 0 then return TriggerServerEvent('nz-wig:s:salonCancel', d.id) end
    local me = PlayerPedId()
    NUI.CloseApp()
    FaceEntity(me, other)
    FreezeEntityPosition(me, true)
    local moves, steps = Salon.Moves(style, d.opts or {})
    S = { id = d.id, other = d.other, name = d.name, style = style, opts = d.opts or {}, moves = moves, stepCount = #steps, shade = d.shade, decor = {} }
    Salon.session = S
    Snatch.busy = true
    S.anim = LoopAnim(SC.Anim, me) and SC.Anim or (LoopAnim(SC.Fallback, me) and SC.Fallback or nil)
    startCam(other, 180.0, 12.0, SC.Camera.Dist)

    local sh = d.shade and Salon.ShadeDef(d.shade)
    local c, h = Salon.ShadeColour(d.shade)
    local function rgb(i) local r, g, b = GetPedHairRgbColor(i or 0) return ('rgb(%d,%d,%d)'):format(r, g, b) end
    local nat = GetPedHairColor(other)
    S.colour = { hair = c and rgb(c) or rgb(nat), feed = c and rgb(c) or rgb(nat) }
    NUI.Send('salon:start', {
        id = d.id, name = d.name, label = style.label, max = d.max, steps = #steps,
        colour = c and rgb(c) or rgb(nat), tip = h and rgb(h) or nil, shade = sh and sh.label or nil,
        feedColour = S.colour.feed,
    })
    NUI.Cursor(true)
    startMove(1)
    CreateThread(loop)
end)

RegisterNUICallback('salonMoveDone', function(d, cb)
    cb(1)
    if not S or type(d) ~= 'table' or tonumber(d.i) ~= S.i then return end
    keep(S.i, d.keep)
    TriggerServerEvent('nz-wig:s:salonMove', S.id, S.i, math.floor(tonumber(d.score) or 0))
    if S.i < #S.moves then startMove(S.i + 1)
    else NUI.Send('salon:wait', {}) end
end)

RegisterNUICallback('salonAct', function(d, cb)
    cb(1)
    if not S then return end
    local tool = S.moves[S.i] and S.moves[S.i].tool or 'hands'
    fxOn(PedOf(S.other), tool)
    TriggerServerEvent('nz-wig:s:salonFx', S.id, tool)
end)

-- the UI asks the camera to turn to what's next (it was round the back)
RegisterNUICallback('salonFocus', function(d, cb)
    cb(1)
    if not S or not S.geo or type(d) ~= 'table' then return end
    local k, j = (tonumber(d.k) or 0) + 1, (tonumber(d.j) or 0) + 1
    local it = S.geo.list[k]
    if not it then return end
    local p = it
    if S.geo.kind == 'paths' then p = it[j] or it[1]
    elseif S.geo.kind == 'pairs' then p = it[math.min(2, math.max(1, j - 1))] or it[1] end
    if p and p.x then
        local dist = want and want.dist or orbit.dist
        frame({ p })
        if want then want.dist = dist end
    end
end)

RegisterNUICallback('salonZoom', function(d, cb)
    if S then
        orbit.dist = Clamp(orbit.dist + (tonumber(d and d.delta) or 0) * 0.05, SC.Camera.MinDist, SC.Camera.MaxDist)
        want = nil
    end
    cb(1)
end)

RegisterNUICallback('salonStop', function(_, cb)
    if S then TriggerServerEvent('nz-wig:s:salonCancel', S.id) end
    if Salon.sitting then TriggerServerEvent('nz-wig:s:salonCancel', Salon.sitting.id) end
    cb(1)
end)

local function endStylist()
    if not S then return end
    S.prop = DeleteProp(S.prop)
    S = nil
    Salon.session = nil
    Snatch.busy = false
    NUI.Cursor(false)
    stopCam()
    local me = PlayerPedId()
    FreezeEntityPosition(me, false)
    ClearPedSecondaryTask(me)
    ClearPedTasks(me)
end

-- the client's side ---------------------------------------------------------------------------------------

local function closestChair(ped)
    local pc = GetEntityCoords(ped)
    local best, bestD, bestCfg
    for model, cfg in pairs(SC.Chairs) do
        local obj = GetClosestObjectOfType(pc.x, pc.y, pc.z, SC.ChairRange, model, false, false, false)
        if obj ~= 0 then
            local d = #(GetEntityCoords(obj) - pc)
            if not bestD or d < bestD then best, bestD, bestCfg = obj, d, cfg end
        end
    end
    return best, bestCfg
end

local mirror = false
local function mirrorLoop(id)
    CreateThread(function()
        while Salon.sitting and Salon.sitting.id == id do
            local me = PlayerPedId()
            -- X gets up (stops the appointment), M is the mirror
            if IsControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 73) then
                TriggerServerEvent('nz-wig:s:salonCancel', id)
                break
            end
            if IsControlJustPressed(0, 244) or IsDisabledControlJustPressed(0, 244) then
                mirror = not mirror
                if mirror then startCam(me, 0.0, 6.0, 0.95) else stopCam() end
                NUI.Send('salon:mirror', { on = mirror })
            end
            if mirror and cam then
                DisableControlAction(0, 1, true) DisableControlAction(0, 2, true)
                if IsControlPressed(0, 34) or IsDisabledControlPressed(0, 34) then orbit.yaw = orbit.yaw - 1.2 end
                if IsControlPressed(0, 35) or IsDisabledControlPressed(0, 35) then orbit.yaw = orbit.yaw + 1.2 end
                placeCam(me)
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('nz-wig:c:salonSit', function(d)
    local me = PlayerPedId()
    Salon.sitting = d
    Snatch.busy = true
    NUI.CloseApp()
    local chair, cfg = closestChair(me)
    if chair then
        local c = GetEntityCoords(chair)
        local h = GetEntityHeading(chair) + (cfg.h or 180.0)
        TaskStartScenarioAtPosition(me, SC.SitScenario, c.x, c.y, c.z + (cfg.z or 0.5), h, 0, true, true)
    else
        FreezeEntityPosition(me, true)
        TaskStandStill(me, -1)
    end
    Salon.sitting.chair = chair ~= nil
    local style = Salon.Style(d.style)
    local steps = {}
    if style then
        local _, list = Salon.Moves(style, d.opts or {})
        for i, si in ipairs(list) do steps[i] = style.steps[si].text end
    end
    NUI.Send('salon:sit', { id = d.id, name = d.name, label = d.label, total = d.total, steps = steps, price = d.price })
    mirror = false
    mirrorLoop(d.id)
end)

RegisterNetEvent('nz-wig:c:salonProgress', function(p)
    if not Salon.sitting or Salon.sitting.id ~= p.id then return end
    local style = Salon.Style(Salon.sitting.style)
    local stepNo = 1
    if style then
        local _, list = Salon.Moves(style, Salon.sitting.opts or {})
        for i, si in ipairs(list) do if si == p.step then stepNo = i end end
    end
    NUI.Send('salon:progress', { idx = p.idx, total = p.total, step = stepNo })
end)

RegisterNetEvent('nz-wig:c:salonLook', function(id, look)
    if not Salon.sitting or Salon.sitting.id ~= id or type(look) ~= 'table' then return end
    Hair.Preview(look, nil)
end)

-- the reveal: the camera turns slowly around your new hair
local function reveal(r)
    local me = PlayerPedId()
    stopCam()
    startCam(me, 25.0, 8.0, 0.95)
    NUI.Send('salon:reveal', r)
    local untilT = GetGameTimer() + 7000
    CreateThread(function()
        while GetGameTimer() < untilT and cam do
            orbit.yaw = orbit.yaw + 0.45
            placeCam(me)
            Wait(0)
        end
        stopCam()
    end)
end

RegisterNetEvent('nz-wig:c:salonEnd', function(r)
    if S and S.id == r.id then
        endStylist()
        NUI.Send('salon:end', r)
    end
    if Salon.sitting and Salon.sitting.id == r.id then
        local wasChair = Salon.sitting.chair
        Salon.sitting = nil
        Snatch.busy = false
        mirror = false
        local me = PlayerPedId()
        FreezeEntityPosition(me, false)
        if r.done then
            reveal(r)
            SetTimeout(7200, function() if not Salon.sitting then ClearPedTasks(PlayerPedId()) end end)
        else
            stopCam()
            Hair.Apply()   -- a halfway look goes back
            ClearPedTasks(me)
            NUI.Send('salon:sitEnd', r)
        end
        if wasChair and not r.done then ClearPedTasksImmediately(me) end
    end
end)

-- asking ---------------------------------------------------------------------------------------------------

local function hasHead(entity)
    local m = ModelKey(GetEntityModel(entity))
    return m ~= nil and ModelEnabled(m)
end

Salon.TargetOptions = {}
if SC.Enabled then
    Salon.TargetOptions[1] = {
        name = 'nzwig_salon', label = SC.Label, icon = SC.Icon, distance = SC.Range,
        canInteract = function(e) return free() and hasHead(e) end,
        onSelect = function(e) open(e) end,
    }
end

-- the rat-tail comb from the inventory: do the hair of whoever is in front
RegisterNetEvent('nz-wig:c:salonUse', function()
    if not free() then return end
    local ped = ClosestInFront(SC.Range)
    if not ped then return CB.Notify(L('no_one_close'), 'error') end
    open(ped)
end)

-- browse the Style Book without anyone in front (see every style and what it needs)
RegisterCommand('stylebook', function() if free() then open(nil) end end, false)

-- take your braids / sew-in out
local function takedown()
    local st = Hair.state and Hair.state.style
    if not st then return CB.Notify(L('salon_no_style'), 'error') end
    if not free() then return end
    local ok = lib.alertDialog({ header = L('salon_takedown_title'), content = L('salon_takedown_body', st.label), centered = true, cancel = true })
    if ok ~= 'confirm' then return end
    if lib.progressCircle({ duration = 8000, label = L('salon_taking_down'), position = 'bottom', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mp_safehouseshower@female@', clip = 'shower_idle_a', flag = 49 } }) then
        TriggerServerEvent('nz-wig:s:salonTakedown')
    end
end
RegisterCommand('takedown', takedown, false)
RegisterNUICallback('takedown', function(_, cb) cb(1) SetTimeout(200, takedown) end)

function Salon.Cleanup()
    if S then endStylist() end
    if Salon.sitting then FreezeEntityPosition(PlayerPedId(), false) stopCam() end
end
