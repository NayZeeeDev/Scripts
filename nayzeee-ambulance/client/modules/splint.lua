--[[
    NAYZEEE AMBULANCE - Splints (client): field splinting minigame, worn splint props, splinted-leg walk

    Procedure 'splint' (NZA.Proc.Run) → NUI app 'splint' (mode 'proc') over a straight-down game camera on
    the broken limb (side camera when the limb is upright). World anchors streamed to the app:
        prox / dist  the joints at both ends of the limb segment (NZA.Const.LimbJoints)
        cms          toes / fingers (Config.Splint.Splint.cmsBones) for the circulation-motor-sensation check
        core         the chest, so the app keeps its labels on the free side of the limb
    NUI callbacks: splint:finish (result) · splint:abort · splint:done · splint:close (core)
    Patient options (NZA.Interact): nza_splint 'Splint the fracture' (order 44), nza_splint_remove
        'Take the splint off' (order 45). Picks the fracture / region with a context menu when several.
    Examination route (NZA.ExamRoutes): 'splint' for limb fractures without a splint or cast.
    Radial (NZA.RadialItems, parent 'patient'): 'splint_apply' on the nearest patient with a fracture.
    Worn splints: every client draws Config.Splint.Props.attach pieces on every ped (players and NPC
        patients) whose 'nza' state bag lists splints, within Config.Splint.Props.range.
    Splinted leg (local player): walk only, slower walk (Config.Splint.Effects).
    Net event handled: nza:splint:pose (on) - sit down / get up while a medic splints you.
    Lua API: NZA.Splint.Run(entity, target, injuryId?, region?) → ok, outcome
             NZA.Splint.HudSet(kind, data|nil)  (mobility card shared by the crutch / chair files)
             NZA.Splint.Locale() · NZA.Splint.Busy() · NZA.Splint.RefreshWorn()
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint
local U = NZA.Util
local APP = 'splint'

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function toast(key, kind, ...)
    NZA.UI.Toast({ title = L('title'), message = L(key, ...), type = kind or 'info' })
end
SP.Toast = toast

function SP.Locale()
    return NZA.LocaleTable('splint')
end

local function deviceFor(region)
    local d = (C('Splint').regions or {})[region]
    if d == 'leg' or d == 'arm' then return d end
    return nil
end
SP.DeviceFor = deviceFor

local function isFracture(inj)
    return type(inj) == 'table' and (inj.type == 'fracture' or type(inj.fracture) == 'table')
end

local function covered(inj)
    local t = inj.treat or {}
    return t.dressed or t.bandaged or t.sutured or t.packed
end

local function splintMap(snap)
    local d = type(snap) == 'table' and snap.devices or nil
    local s = type(d) == 'table' and d.splints or nil
    local out = {}
    if type(s) ~= 'table' then return out end
    for k, v in pairs(s) do
        if type(k) == 'string' then out[k] = true elseif type(v) == 'string' then out[v] = true end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- MOBILITY HUD (crutches / wheelchair share the 'splint' app in 'hud' mode)
-- ════════════════════════════════════════════════════════════════════════

local session = nil
local busy = false
local huds = {}          -- kind → data
local hudOpen = false

local function topHud()
    return huds.chair or huds.push or huds.crutch
end

local function hudShow()
    if session then return end
    local h = topHud()
    if not h then
        if hudOpen then
            hudOpen = false
            if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
        end
        return
    end
    if not hudOpen or not NZA.UI.IsOpen(APP) then
        hudOpen = true
        NZA.UI.Open(APP, { mode = 'hud', hud = h, locale = SP.Locale() }, { focus = false })
    else
        NZA.UI.Send(APP, 'hud', h)
    end
end

function SP.HudSet(kind, data)
    if type(kind) ~= 'string' then return end
    huds[kind] = data
    hudShow()
end

function SP.Busy()
    return busy or session ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function boneCoords(ped, bone)
    return GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
end

local function stopMedicAnim()
    local me = PlayerPedId()
    if NZA.Anim and NZA.Anim.Stop then pcall(NZA.Anim.Stop, me) else ClearPedTasks(me) end
end

local function medicAnim(s)
    local me = PlayerPedId()
    local a = C('Splint').anim
    local low = s.entity and DoesEntityExist(s.entity) and (GetEntityCoords(s.entity).z - GetEntityCoords(me).z) < -0.35
    if s.upright and not low then
        NZA.Anim.Play(me, 'mini@repair', 'fixing_a_ped', { flag = 49 })
    elseif type(a) == 'table' and a.dict then
        NZA.Anim.Play(me, a.dict, a.clip, { flag = a.flag or 1 })
    elseif NZA.Anim.Kneel then
        NZA.Anim.Kneel(me)
    end
end

local function frameCamera(s)
    local cam = C('Splint').camera or {}
    local ped = s.entity
    local P, D = boneCoords(ped, s.j1), boneCoords(ped, s.j2)
    local d = D - P
    local len = #d
    s.segLen = math.max(0.12, len)
    s.upright = math.abs(d.z) > len * 0.55
    if not s.upright then
        local fov = tonumber(cam.fov) or 50.0
        local fill = U.clamp(tonumber(cam.fill) or 0.38, 0.15, 0.8)
        local h = s.segLen / (fill * 2.0 * math.tan(math.rad(fov / 2.0)))
        h = U.clamp(h, tonumber(cam.minHeight) or 0.6, tonumber(cam.maxHeight) or 3.2)
        local ux, uy = P.x - D.x, P.y - D.y
        local heading = math.deg(math.atan(-ux, uy))
        local mid = (P + D) / 2.0
        NZA.Cam.TopDown(vector3(mid.x, mid.y, mid.z), h, {
            heading = heading, fov = fov, minHeight = cam.minHeight or 0.6, maxHeight = cam.maxHeight or 3.2, ease = 700,
        })
        s.fov = fov
    else
        local up = cam.upright or {}
        NZA.Cam.Close(ped, s.region, { dist = up.dist or 1.35, pitch = up.pitch or 8.0, fov = up.fov or 44.0, orbit = true })
        s.fov = tonumber(up.fov) or 44.0
    end
    s.camOn = true
end

local function endSession(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if session == s then session = nil end
    pcall(NZA.Anchors.Clear, APP)
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    hudOpen = false
    if s.camOn and NZA.Cam.Stop then NZA.Cam.Stop(500) end
    if s.animOn then stopMedicAnim() end
    SetTimeout(250, hudShow)
end

local function waitFor(s, check, timeout)
    local deadline = timeout and (GetGameTimer() + timeout) or nil
    while not check() do
        Wait(50)
        if s.ended or s.closed or s.abortReq then return false end
        if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then return false end
        if deadline and GetGameTimer() > deadline then return false end
    end
    return true
end

local function runner(ctx, entity, target)
    local s = { ctx = ctx, entity = entity, target = target }
    session = s
    ctx.onEnd(function(outcome)
        s.ended = true
        if not outcome then endSession(s) end
    end)
    local data = ctx.data or {}
    s.region = data.region
    local joints = NZA.Const.LimbJoints[s.region or '']
    if not joints or not entity or entity == 0 or not DoesEntityExist(entity) then
        ctx.abort('error')
        endSession(s)
        return
    end
    s.j1, s.j2 = joints[1], joints[2]
    s.cms = (C('Splint').cmsBones or {})[s.region] or joints[2]

    local me = PlayerPedId()
    TaskTurnPedToFaceEntity(me, entity, 700)
    -- a standing player patient sits down first (server sent the pose)
    if target and target.kind == 'player' then Wait(900) else Wait(400) end
    if s.ended then return end

    frameCamera(s)
    s.animOn = true
    pcall(medicAnim, s)

    NZA.Anchors.Track(APP, {
        prox = { entity = entity, bone = s.j1 },
        dist = { entity = entity, bone = s.j2 },
        cms = { entity = entity, bone = s.cms },
        core = { entity = entity, bone = 24818 },
    })

    local open = {}
    for k, v in pairs(data) do open[k] = v end
    open.mode = 'proc'
    open.fov = s.fov
    open.segLen = s.segLen
    open.upright = s.upright
    open.keys = C('Splint').keys or {}
    open.locale = SP.Locale()
    NZA.UI.Open(APP, open, { focus = true, cursor = true })

    local got = waitFor(s, function() return s.result ~= nil end)
    if s.ended then return end
    if not got or not s.result then
        ctx.abort(s.closed and 'cancel' or 'silent')
        endSession(s)
        return
    end
    local fine, outcome = ctx.finish(s.result)
    if not fine then
        endSession(s)
        return
    end
    SP.RefreshWorn()
    NZA.UI.Send(APP, 'result', outcome or {})
    local deadline = GetGameTimer() + 30000
    while not s.closed and not s.doneReq and GetGameTimer() < deadline do
        Wait(100)
        if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
    end
    endSession(s)
end

function SP.Run(entity, target, injId, region)
    if C('Splint').enabled == false then return false end
    if busy or session then
        toast('err_busy', 'error')
        return false
    end
    if type(target) ~= 'table' then target = NZA.Target.FromEntity(entity) end
    if not target then return false end
    entity = entity or NZA.Target.Entity(target)
    busy = true
    local okOut, outcomeOut = false, nil
    local ok, err = pcall(function()
        okOut, outcomeOut = NZA.Proc.Run('splint', target, { injury = injId, region = region }, function(ctx)
            runner(ctx, entity, target)
        end, { label = L('title'), anim = C('Splint').anim })
    end)
    if not ok then NZA.Warn('splint failed: ' .. tostring(err)) end
    if session then endSession(session) end
    busy = false
    return okOut, outcomeOut
end

NZA.UI.On(APP, 'finish', function(data, cb)
    cb({ ok = true })
    local s = session
    if s and not s.result and type(data) == 'table' then s.result = data end
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    local s = session
    if s then s.abortReq = true end
end)

NZA.UI.On(APP, 'done', function(_, cb)
    cb({ ok = true })
    local s = session
    if s then s.doneReq = true end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    local s = session
    if s then s.closed = true end
    hudOpen = false
end)

-- ════════════════════════════════════════════════════════════════════════
-- PICK THE FRACTURE
-- ════════════════════════════════════════════════════════════════════════

local function eligible(inj, snap)
    if not isFracture(inj) or not deviceFor(inj.region) then return false end
    local t = inj.treat or {}
    if t.splinted or t.cast then return false end
    if splintMap(snap)[inj.region] then return false end
    return true
end

local function needsCover(inj)
    local f = type(inj.fracture) == 'table' and inj.fracture or {}
    return f.kind == 'open' and C('Splint').requireDressedOpen and not NZA.Easy(C('Splint').perm or 'splint') and not covered(inj)
end

local function pickAndRun(entity, target)
    if SP.Busy() then toast('err_busy', 'error') return end
    local ok, snap = pcall(NZA.Patient.Get, target)
    if not ok or type(snap) ~= 'table' then toast('err_generic', 'error') return end
    local list = {}
    for _, inj in ipairs(snap.injuries or {}) do
        if eligible(inj, snap) then list[#list + 1] = inj end
    end
    if #list == 0 then toast('err_nothing', 'error') return end
    if #list == 1 then
        if needsCover(list[1]) then toast('err_cover_first', 'error') return end
        SP.Run(entity, target, list[1].id)
        return
    end
    local options = {}
    for _, inj in ipairs(list) do
        local f = type(inj.fracture) == 'table' and inj.fracture or {}
        local boneKey = 'core.bone_' .. tostring(f.bone)
        local bone = f.bone and NZA.L(boneKey) or nil
        if bone == boneKey then bone = nil end
        local kind = NZA.L('core.fracture_' .. tostring(f.kind or 'closed'))
        options[#options + 1] = {
            title = U.RegionLabel(inj.region),
            description = bone and (bone .. ' · ' .. kind) or kind,
            icon = 'bone',
            onSelect = function()
                if needsCover(inj) then toast('err_cover_first', 'error') return end
                CreateThread(function() SP.Run(entity, target, inj.id) end)
            end,
        }
    end
    lib.registerContext({ id = 'nza_splint_pick', title = L('pick_title'), options = options })
    lib.showContext('nza_splint_pick')
end
SP.PickAndRun = pickAndRun

local function removeSplint(entity, target)
    local st = NZA.Target.State(entity) or {}
    local list = {}
    for region in pairs(type(st.splints) == 'table' and st.splints or {}) do list[#list + 1] = region end
    table.sort(list)
    if #list == 0 then toast('err_no_splint', 'error') return end
    if #list == 1 then
        NZA.Treat.Do('splint_remove', target, { region = list[1] })
        SP.RefreshWorn()
        return
    end
    local options = {}
    for _, region in ipairs(list) do
        options[#options + 1] = {
            title = U.RegionLabel(region), icon = 'splint',
            onSelect = function()
                CreateThread(function()
                    NZA.Treat.Do('splint_remove', target, { region = region })
                    SP.RefreshWorn()
                end)
            end,
        }
    end
    lib.registerContext({ id = 'nza_splint_remove', title = L('remove_title'), options = options })
    lib.showContext('nza_splint_remove')
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS · EXAM ROUTE · RADIAL
-- ════════════════════════════════════════════════════════════════════════

local function hasTag(st, tag)
    if type(st) ~= 'table' or type(st.tags) ~= 'table' then return false end
    for _, t in ipairs(st.tags) do if t == tag then return true end end
    return false
end

local icons = C('Interact').icons or {}

if C('Splint').enabled ~= false and C('Interact').splint ~= false then
    NZA.Interact.Add({
        name = 'nza_splint', label = L('opt_splint'), icon = icons.splint or 'splint', order = 44,
        perm = C('Splint').perm or 'splint', states = { alive = true, wounded = true },
        distance = tonumber(C('Interact').distance) or 2.2,
        canInteract = function(_, _, st)
            if type(st) ~= 'table' or st.carried or st.bag then return false end
            return hasTag(st, 'fracture')
        end,
        onSelect = function(entity, target) pickAndRun(entity, target) end,
    })
end

if C('Interact').remove ~= false then
    NZA.Interact.Add({
        name = 'nza_splint_remove', label = L('opt_remove'), icon = icons.remove or 'splint', order = 45,
        perm = C('Splint').removePerm or 'splint', states = { alive = true, wounded = true, arrest = true, dead = true },
        distance = tonumber(C('Interact').distance) or 2.2,
        canInteract = function(_, _, st)
            return type(st) == 'table' and type(st.splints) == 'table' and next(st.splints) ~= nil and not st.bag
        end,
        onSelect = function(entity, target) removeSplint(entity, target) end,
    })
end

local LIMB_REGIONS = {}
for region in pairs(C('Splint').regions or {}) do LIMB_REGIONS[#LIMB_REGIONS + 1] = region end
table.sort(LIMB_REGIONS)

NZA.ExamRoutes = NZA.ExamRoutes or {}
if C('Splint').enabled ~= false then
    table.insert(NZA.ExamRoutes, {
        id = 'splint', label = L('route'), icon = 'splint', perm = C('Splint').perm or 'splint', order = 25,
        types = { 'fracture' }, regions = LIMB_REGIONS,
        items = Config.Items and Config.Items[C('Splint').item or 'splint'] and { [Config.Items[C('Splint').item or 'splint']] = 1 } or nil,
        available = function(inj, snap)
            if not deviceFor(inj.region or '') then return false end
            local t = inj.treat or {}
            if t.cast then return false end
            if t.splinted or splintMap(snap)[inj.region] then return false, L('route_done') end
            if needsCover(inj) then return false, L('route_cover_first') end
            return true
        end,
        run = function(target, inj)
            CreateThread(function() SP.Run(NZA.Target.Entity(target), target, inj.id) end)
        end,
    })
end

-- nearest patient (player or NPC ped with an 'nza' bag) matching filter(st)
local function nearestPatient(range, filter)
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local best, bestD = nil, range
    local function consider(ped)
        if ped == me or not DoesEntityExist(ped) then return end
        local d = #(GetEntityCoords(ped) - mc)
        if d > bestD then return end
        local st = NZA.Target.State(ped)
        if type(st) == 'table' and (not filter or filter(st)) then best, bestD = ped, d end
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) then consider(ped) end
    end
    return best
end
SP.NearestPatient = nearestPatient

NZA.RadialItems = NZA.RadialItems or {}
if C('Radial').enabled ~= false and C('Splint').enabled ~= false then
    table.insert(NZA.RadialItems, {
        id = 'splint_apply', parent = 'patient', label = L('radial_splint'), icon = 'splint', order = 44,
        perm = C('Splint').perm or 'splint',
        canShow = function()
            if SP.Busy() or (NZA.Proc.Active and NZA.Proc.Active()) then return false end
            return nearestPatient(tonumber(C('Radial').range) or 3.0, function(st)
                return (st.st == 'alive' or st.st == 'wounded') and hasTag(st, 'fracture') and not st.carried and not st.bag
            end) ~= nil
        end,
        onSelect = function()
            local ped = nearestPatient(tonumber(C('Radial').range) or 3.0, function(st)
                return (st.st == 'alive' or st.st == 'wounded') and hasTag(st, 'fracture')
            end)
            if not ped then toast('err_no_patient', 'error') return end
            local target = NZA.Target.FromEntity(ped)
            if not target then return end
            CreateThread(function() pickAndRun(ped, target) end)
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- WORN SPLINT PROPS (every ped in range whose state bag lists splints)
-- ════════════════════════════════════════════════════════════════════════

local worn = {}           -- [ped] = { sig, props = { entity } }
local wornWake = false

local function clearWorn(ped)
    local w = worn[ped]
    if not w then return end
    for _, ent in ipairs(w.props) do NZA.Props.Delete(ent) end
    worn[ped] = nil
end

local function spawnWorn(ped, regions)
    local list = {}
    local attach = C('Props').attach or {}
    for _, region in ipairs(regions) do
        for _, piece in ipairs(attach[region] or {}) do
            if not DoesEntityExist(ped) then break end
            local ent = NZA.Props.Spawn(piece.prop or 'splint_leg', {
                attach = { entity = ped, bone = piece.bone, pos = piece.pos or vector3(0.0, 0.0, 0.0), rot = piece.rot or vector3(0.0, 0.0, 0.0), collision = false },
            }, { group = 'splint_worn', network = false, collision = false, timeout = 4000 })
            if ent and ent ~= 0 then list[#list + 1] = ent end
        end
    end
    return list
end

function SP.RefreshWorn()
    wornWake = true
end

local function wornTick()
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local range = tonumber(C('Props').range) or 45.0
    local seen = {}
    local function consider(ped, bag)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end
        if type(bag) ~= 'table' or bag.bag or type(bag.splints) ~= 'table' or next(bag.splints) == nil then return end
        if #(GetEntityCoords(ped) - mc) > range then return end
        local regions = {}
        for region, v in pairs(bag.splints) do
            if v and (C('Props').attach or {})[region] then regions[#regions + 1] = region end
        end
        if #regions == 0 then return end
        table.sort(regions)
        local sig = table.concat(regions, ',')
        seen[ped] = true
        local w = worn[ped]
        if w then
            local alive = w.sig == sig
            for _, ent in ipairs(w.props) do
                if not DoesEntityExist(ent) or not IsEntityAttachedToEntity(ent, ped) then alive = false break end
            end
            if alive then return end
            clearWorn(ped)
        end
        worn[ped] = { sig = sig, props = spawnWorn(ped, regions) }
    end
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        local ply = Player(GetPlayerServerId(pl))
        consider(ped, ply and ply.state and ply.state.nza)
    end
    for _, ped in ipairs(NZA.Scan.Peds()) do
        local bag = Entity(ped).state.nza
        if bag then consider(ped, bag) end
    end
    for ped in pairs(worn) do
        if not seen[ped] then clearWorn(ped) end
    end
end

CreateThread(function()
    while true do
        if C('Props').enabled ~= false then
            local ok, err = pcall(wornTick)
            if not ok then NZA.Debug('splint worn props: ' .. tostring(err)) end
        end
        local t = 0
        while t < 1000 and not wornWake do Wait(100) t = t + 100 end
        wornWake = false
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SPLINTED LIMB (local player)
-- ════════════════════════════════════════════════════════════════════════

local legClipOn = false

CreateThread(function()
    while true do
        local fx = C('Effects')
        local snap = NZA.Self.Get and NZA.Self.Get() or nil
        local leg, arm = false, false
        if fx.enabled ~= false and type(snap) == 'table' and NZA.Self.State() == 'alive' then
            local map = splintMap(snap)
            for region in pairs(map) do
                if region:find('_leg') then leg = true elseif region:find('_arm') then arm = true end
            end
        end
        local mobility = SP.CrutchesOn and SP.CrutchesOn() or false
        local seated = SP.InChair and SP.InChair() or false
        local wantClip = leg and type(fx.legClipset) == 'string' and fx.legClipset ~= '' and not mobility and not seated
        if wantClip and not legClipOn then
            NZA.Self.SetMoveOverride('splint_leg', fx.legClipset)
            legClipOn = true
        elseif not wantClip and legClipOn then
            NZA.Self.SetMoveOverride('splint_leg', nil)
            legClipOn = false
        end
        if (leg or (arm and fx.armNoAim)) and not seated then
            local untilT = GetGameTimer() + 1000
            local ped = PlayerPedId()
            local blend = tonumber(fx.maxMoveBlend) or 1.0
            local rate = tonumber(fx.moveRate) or 0.88
            while GetGameTimer() < untilT do
                if leg and not mobility then
                    SetPedMaxMoveBlendRatio(ped, blend)
                    SetPedMoveRateOverride(ped, rate)
                    DisableControlAction(0, 22, true)
                    if blend <= 1.0 then DisableControlAction(0, 21, true) end
                end
                if arm and fx.armNoAim then
                    DisableControlAction(0, 25, true)
                    DisablePlayerFiring(PlayerId(), true)
                end
                Wait(0)
            end
        else
            Wait(1000)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT POSE (a medic splints you while you stand)
-- ════════════════════════════════════════════════════════════════════════

local posed = nil

local function releasePose()
    if not posed then return end
    posed = nil
    local ped = PlayerPedId()
    if NZA.Self.State() == 'alive' then
        if NZA.Anim and NZA.Anim.Stop then pcall(NZA.Anim.Stop, ped) else ClearPedTasks(ped) end
    end
end

RegisterNetEvent('nza:splint:pose', function(on)
    local pp = C('Splint').patientPose
    if not pp then return end
    if not on then releasePose() return end
    local ped = PlayerPedId()
    if NZA.Self.State() ~= 'alive' or IsPedInAnyVehicle(ped, false) or (SP.InChair and SP.InChair()) then return end
    local a = IsPedMale(ped) and pp.m or pp.f or pp.m
    if type(a) ~= 'table' or not a.dict then return end
    local token = GetGameTimer()
    posed = token
    NZA.Anim.Play(ped, a.dict, a.clip, { flag = 1 })
    local limit = GetGameTimer() + ((tonumber(C('Splint').maxTime) or 480) + 15) * 1000
    CreateThread(function()
        while posed == token do
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            if NZA.Self.State() ~= 'alive' or GetGameTimer() > limit then
                if posed == token then releasePose() end
                break
            end
            Wait(0)
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' then releasePose() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ped in pairs(worn) do clearWorn(ped) end
    if legClipOn then NZA.Self.SetMoveOverride('splint_leg', nil) end
    releasePose()
    if session then endSession(session) end
end)
