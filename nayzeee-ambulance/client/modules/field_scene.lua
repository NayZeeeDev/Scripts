--[[
    NAYZEEE AMBULANCE - Field resuscitation (client): the 7-step scene and IV cannulation

      F.Start(entity, target)          field resuscitation: orbit camera over the patient, open trauma
                                       case + sharps bin + patient monitor beside them, then
                                       1 pelvic binder (NZA.Proc 'binder') → 2-5 IO access (NZA.Proc 'io':
                                       site, drill, confirm, flush) → 6 resuscitate (NZA.Proc 'resus' + the
                                       'infuse' / 'infuse_rate' / 'infuse_stop' / 'txa' / 'field_foil'
                                       treats, IV stand with bags and pressure infuser) → 7 reassess
                                       (NZA.Treat 'field_report'). Steps that are done already or not
                                       allowed are skipped with a note; easy mode = progress bars.
      F.StartIV(entity, target, site)  IV cannulation on the forearm (NZA.Proc 'iv'), close-up camera.

    NUI app 'field' callbacks: result skip abort done close focus binderDrop phase drill needle hang
                               rate takedown txa foil nibp bags ivTq
    Net events handled: nza:field:resus (server pressure / clot model), nza:field:popped
    Camera focus keys (in the app): Config.Field.Keys.focus = { patient, site, stand, kit }
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Field = NZA.Field or {}
local F = NZA.Field
local APP = 'field'
local U = NZA.Util

local S = nil          -- running scene
local stands = {}      -- stands left behind after a scene { stand, bags, until, pos, entity }

local function L(key, ...) return NZA.L('field.' .. key, ...) end
local function cfg(section) return F.Cfg(section) end
local function vec(t, d)
    if type(t) == 'vector3' then return t end
    if type(t) == 'table' then return vector3(tonumber(t[1] or t.x) or 0.0, tonumber(t[2] or t.y) or 0.0, tonumber(t[3] or t.z) or 0.0) end
    return d or vector3(0.0, 0.0, 0.0)
end

local function errMsg(reason)
    if type(reason) == 'table' then return reason.msg or L('err_' .. tostring(reason.err or 'failed')) end
    local key = 'err_' .. tostring(reason or 'failed')
    local s = L(key)
    if s == 'field.' .. key then return L('err_failed') end
    return s
end

-- ════════════════════════════════════════════════════════════════════════
-- PROPS
-- ════════════════════════════════════════════════════════════════════════

local function spawnAt(key, pos, heading, group)
    local ok, ent = pcall(NZA.Props.Spawn, key, vector3(pos.x, pos.y, pos.z), { group = group or 'field_scene', heading = heading, ground = true, collision = false })
    return ok and ent or 0
end

local function spawnOn(key, entity, pos, rot, group)
    if not entity or entity == 0 then return 0 end
    local ok, ent = pcall(NZA.Props.Spawn, key, { attach = { entity = entity, bone = 0, pos = pos, rot = rot or vector3(0.0, 0.0, 0.0), collision = false } }, { group = group or 'field_scene', collision = false })
    return ok and ent or 0
end

local function del(ent) if ent and ent ~= 0 then NZA.Props.Delete(ent) end end

local function spawnKit(s)
    local p = cfg('Resus').props or {}
    local fr = s.frame
    local kit, sh = p.kit or { side = 0.68, along = 0.18 }, p.sharps or { side = 0.72, along = -0.38 }
    local face = vector3(-fr.side.x, -fr.side.y, 0.0)
    s.props.kit = spawnAt('kitcase_open', F.Spot(fr, kit.side, kit.along), F.HeadingY(face))
    s.props.sharps = spawnAt('sharps', F.Spot(fr, sh.side, sh.along), F.HeadingY(face))
end

local HOOKS = { vector3(0.073, 0.0, 1.766), vector3(-0.073, 0.0, 1.766), vector3(0.0, 0.06, 1.766) }

local function bloodModel(left, ml)
    local f = (ml and ml > 0) and (left or 0) / ml or 1
    if f > 0.87 then return 'bloodbag_100' elseif f > 0.62 then return 'bloodbag_75' elseif f > 0.37 then return 'bloodbag_50' elseif f > 0.1 then return 'bloodbag_25' end
    return 'bloodbag_0'
end

local function spawnStand(s)
    if s.props.stand and s.props.stand ~= 0 then return end
    local p = (cfg('Resus').props or {}).stand or { side = -0.62, along = 0.95 }
    local fr = s.frame
    s.props.stand = spawnAt('ivstand', F.Spot(fr, p.side, p.along), F.HeadingY(fr.axis))
    s.bagProps = s.bagProps or {}
    if s.props.stand ~= 0 then
        pcall(NZA.Anchors.Set, APP, 'stand', { entity = s.props.stand, offset = vector3(0.0, 0.0, 1.55) })
    end
end

local function freeHook(s, kind)
    local used = {}
    for _, b in pairs(s.bagProps or {}) do used[b.hook] = true end
    if kind == 'saline' and not used[1] then return 1 end
    if kind == 'blood' and not used[2] then return 2 end
    for i = 1, #HOOKS do if not used[i] then return i end end
    return 3
end

local function syncBags(s, list)
    if not s.props.stand or s.props.stand == 0 then return end
    s.bagProps = s.bagProps or {}
    local seen = {}
    for _, b in ipairs(list or {}) do
        if b.mine ~= false and (b.left or 0) > 0 and b.kind ~= 'txa' then
            seen[b.id] = true
            local bp = s.bagProps[b.id]
            local model = b.kind == 'blood' and bloodModel(b.left, b.ml) or 'ivbag_saline'
            if bp and bp.model ~= model then del(bp.ent); bp = nil; s.bagProps[b.id] = nil end
            if not bp then
                local hook = (s.bagHooks and s.bagHooks[b.id]) or freeHook(s, b.kind)
                s.bagHooks = s.bagHooks or {}
                s.bagHooks[b.id] = hook
                s.bagProps[b.id] = { ent = spawnOn(model, s.props.stand, HOOKS[hook], nil, 'field_stand'), model = model, hook = hook, kind = b.kind }
                if b.kind == 'saline' and (not s.props.infuser or s.props.infuser == 0) and hook == 1 then
                    s.props.infuser = spawnOn('pressure_infuser', s.props.stand, HOOKS[1], nil, 'field_stand')
                end
            end
        end
    end
    for id, bp in pairs(s.bagProps) do
        if not seen[id] then del(bp.ent); s.bagProps[id] = nil end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CAMERA & ANCHORS
-- ════════════════════════════════════════════════════════════════════════

local function ioSite(id)
    local def = (cfg('IO').sites or {})[id or '']
    if not def then return nil end
    return { bone = def.bone, offset = vec(def.offset), region = def.region }
end

local function accessBone(s)
    if s.site then local d = ioSite(s.site); if d then return d.bone, d.offset end end
    local a = s.access
    if a then
        if a.bone then local d = ioSite(a.bone); if d then return d.bone, d.offset end end
        local b = NZA.Const.RegionBone and NZA.Const.RegionBone[a.site or '']
        if b then return b, vector3(0.08, 0.0, 0.0) end
    end
    return 11816, vector3(0.0, 0.0, 0.0)
end

local function camFocus(s, what)
    if not s or s.ended then return end
    local rc = cfg('Resus')
    local cam, close = rc.camera or {}, rc.siteCamera or {}
    local ok = false
    if what == 'site' then
        local bone, off
        if s.mode == 'iv' then
            local d = (cfg('IV').sites or {})[s.ivSite or ''] or {}
            bone, off = d.bone or 28252, vector3(0.12, 0.0, 0.0)
            local c = cfg('IV').camera or {}
            ok = pcall(NZA.Cam.Orbit, { entity = s.entity, bone = bone, offset = off }, { dist = c.dist or 0.62, pitch = c.pitch or 64.0, fov = c.fov or 40.0, minDist = 0.3, maxDist = 2.5 })
        else
            if s.step == 'binder' or s.step == 'reassess' then bone, off = 11816, vector3(0.0, 0.0, 0.0) else bone, off = accessBone(s) end
            ok = pcall(NZA.Cam.Orbit, { entity = s.entity, bone = bone, offset = off }, { dist = close.dist or 1.05, pitch = close.pitch or 58.0, fov = close.fov or 42.0, minDist = 0.35, maxDist = 3.0 })
        end
    elseif what == 'stand' and s.props.stand and s.props.stand ~= 0 then
        ok = pcall(NZA.Cam.Orbit, { entity = s.props.stand, offset = vector3(0.0, 0.0, 1.3) }, { dist = 1.7, pitch = 16.0, fov = 44.0, minDist = 0.6, maxDist = 4.0 })
    elseif what == 'kit' and s.props.kit and s.props.kit ~= 0 then
        ok = pcall(NZA.Cam.Orbit, { entity = s.props.kit, offset = vector3(0.0, 0.0, 0.2) }, { dist = 1.3, pitch = 60.0, fov = 44.0, minDist = 0.5, maxDist = 3.0 })
    else
        what = 'patient'
        if s.mode == 'iv' then
            ok = pcall(NZA.Cam.Orbit, { entity = s.entity, bone = 24818 }, { dist = 1.9, pitch = 50.0, fov = 45.0 })
        else
            ok = pcall(NZA.Cam.Orbit, { entity = s.entity, bone = 11816 }, { dist = cam.dist or 2.6, pitch = cam.pitch or 62.0, fov = cam.fov or 46.0,
                minDist = cam.minDist or 0.7, maxDist = cam.maxDist or 5.0 })
        end
    end
    if ok then
        s.focus = what
        NZA.UI.Send(APP, 'focus', { what = what })
    end
end

local function trackAnchors(s)
    local fr = s.frame
    local map = {
        pelvis = { entity = s.entity, bone = 11816 },
        strapA = { coords = fr.pelvis - fr.side * 0.30 + vector3(0.0, 0.0, 0.04) },
        strapB = { coords = fr.pelvis + fr.side * 0.30 + vector3(0.0, 0.0, 0.04) },
    }
    if s.props.kit and s.props.kit ~= 0 then map.kit = { entity = s.props.kit, offset = vector3(0.0, 0.02, 0.18) } end
    for id, def in pairs(cfg('IO').sites or {}) do
        map[id] = { entity = s.entity, bone = def.bone, offset = vec(def.offset) }
    end
    local b, off = accessBone(s)
    map.access = { entity = s.entity, bone = b, offset = off }
    if s.props.stand and s.props.stand ~= 0 then map.stand = { entity = s.props.stand, offset = vector3(0.0, 0.0, 1.55) } end
    pcall(NZA.Anchors.Track, APP, map)
end

-- ════════════════════════════════════════════════════════════════════════
-- IO DRIVER / SYRINGE PROPS
-- ════════════════════════════════════════════════════════════════════════

local function drillPose(s)
    local d = s.drill
    if not d or not d.ent or d.ent == 0 or not DoesEntityExist(d.ent) then return end
    local site = ioSite(s.site)
    if not site then return end
    local w = d.want or {}
    local p = GetPedBoneCoords(s.entity, site.bone, site.offset.x, site.offset.y, site.offset.z)
    local rot = GetFinalRenderedCamRot(2)
    local yaw = math.rad(rot.z)
    local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local fwd = vector3(-math.sin(yaw), math.cos(yaw), 0.0)
    local horiz = right * (tonumber(w.dx) or 0.0) - fwd * (tonumber(w.dy) or 0.0)
    local tilt = math.tan(math.rad(U.clamp(tonumber(w.angle) or 0.0, 0.0, 60.0)))
    local dir = vector3(0.0, 0.0, -1.0) - horiz * tilt
    local len = #dir
    dir = len > 0.001 and dir / len or vector3(0.0, 0.0, -1.0)
    local lift = U.clamp(tonumber(w.lift) or 1.0, 0.0, 1.0) * 0.11 + 0.004
    local tip = p + vector3(0.0, 0.0, lift) + dir * ((tonumber(w.depth) or 0.0) / 1000.0)
    local pos = tip - dir * 0.108
    local target = { pos = pos, pitch = math.deg(math.asin(U.clamp(dir.z, -1.0, 1.0))), yaw = math.deg(math.atan(-dir.x, dir.y)) }
    d.cur = d.cur or target
    local k = 0.35
    d.cur.pos = d.cur.pos + (target.pos - d.cur.pos) * k
    d.cur.pitch = d.cur.pitch + (target.pitch - d.cur.pitch) * k
    local dy = ((target.yaw - d.cur.yaw + 540.0) % 360.0) - 180.0
    d.cur.yaw = d.cur.yaw + dy * k
    SetEntityCoordsNoOffset(d.ent, d.cur.pos.x, d.cur.pos.y, d.cur.pos.z, false, false, false)
    SetEntityRotation(d.ent, d.cur.pitch, 0.0, d.cur.yaw, 2, false)
end

local function startDrill(s)
    if s.drill then return end
    local site = ioSite(s.site)
    if not site then return end
    local p = GetPedBoneCoords(s.entity, site.bone, site.offset.x, site.offset.y, site.offset.z)
    local ok, ent = pcall(NZA.Props.Spawn, 'iodrill', vector3(p.x, p.y, p.z + 0.2), { group = 'field_scene', collision = false })
    if not ok or not ent or ent == 0 then return end
    local d = { ent = ent, want = { angle = 20, dx = 0.0, dy = 0.0, lift = 1.0, depth = 0 } }
    s.drill = d
    CreateThread(function()
        while S == s and s.drill == d and not s.ended do
            drillPose(s)
            Wait(0)
        end
    end)
end

local function stopDrill(s)
    if not s.drill then return end
    del(s.drill.ent)
    s.drill = nil
end

local function placeSyringe(s)
    del(s.props.syringe)
    local site = ioSite(s.site)
    if not site then return end
    local p = GetPedBoneCoords(s.entity, site.bone, site.offset.x, site.offset.y, site.offset.z)
    local ok, ent = pcall(NZA.Props.Spawn, 'syringe', vector3(p.x, p.y, p.z + 0.125), { group = 'field_scene', rot = vector3(-90.0, 0.0, 0.0), collision = false })
    s.props.syringe = ok and ent or 0
end

-- ════════════════════════════════════════════════════════════════════════
-- STEP PLUMBING
-- ════════════════════════════════════════════════════════════════════════

local function waitReq(s, ctx, timeout)
    local untilAt = timeout and (GetGameTimer() + timeout) or nil
    while not s.ended do
        if s.req.abort then return 'abort' end
        if s.req.result then return 'result' end
        if s.req.skip then return 'skip' end
        if s.req.done then return 'done' end
        if ctx and ctx.done() then return 'ended' end
        if untilAt and GetGameTimer() > untilAt then return 'timeout' end
        Wait(50)
    end
    return 'abort'
end

local function note(s, proc, status, reason, wait)
    s.req.skip, s.req.result = nil, nil
    NZA.UI.Send(APP, 'step', { proc = proc, status = status, reason = reason })
    if status == 'skip' then
        local why = waitReq(s, nil, wait or 1500)
        s.req.skip = nil
        return why ~= 'abort'
    end
    local why = waitReq(s, nil)
    s.req.skip = nil
    return why ~= 'abort'
end

local function easyFocus(s, on)
    -- the core progress bar needs the game keys: hand the mouse back while it runs
    if on then NZA.UI.SetFocus(APP, { focus = false, cursor = false }) else NZA.UI.SetFocus(APP, { focus = true, cursor = true }) end
    s.easyRunning = on
end

-- runs one NZA.Proc as a scene step; returns ok, outcome|reason, started
local function runProc(s, name, payload, easy, onRun)
    s.req.result, s.req.skip = nil, nil
    s.step = name
    local started = false
    if easy then
        NZA.UI.Send(APP, 'step', { proc = name, status = 'easy', reason = L('easy_text') })
        easyFocus(s, true)
    end
    local ok, a, b = pcall(NZA.Proc.Run, name, s.target, payload or {}, function(ctx)
        started = true
        s.ctx = ctx
        if onRun then onRun(ctx) end
        NZA.UI.Send(APP, 'step', { proc = name, status = 'run', data = ctx.data })
        local why = waitReq(s, ctx)
        if why == 'result' then
            local r = s.req.result
            s.req.result = nil
            ctx.finish(type(r) == 'table' and r or {})
        elseif why == 'skip' then
            s.req.skip = nil
            ctx.abort('silent')
        elseif why ~= 'ended' then
            ctx.abort('cancel')
        end
    end, { label = L('title_' .. name) })
    if easy then easyFocus(s, false) end
    s.ctx = nil
    if not ok then
        NZA.Warn(('field: %s failed: %s'):format(name, tostring(a)))
        return false, 'error', started
    end
    if easy and a then started = true end
    return a, b, started
end

local function record(s, proc, label, outcome, skipped, note2)
    s.results[#s.results + 1] = {
        proc = proc, label = label, skipped = skipped or nil,
        score = outcome and outcome.score or nil, grade = outcome and outcome.grade or nil, note = note2,
    }
end

local function stepOutcome(s, proc, ok, out, started, label)
    if ok and type(out) == 'table' and not out.failed then
        NZA.UI.Send(APP, 'outcome', { proc = proc, ok = true, outcome = out })
        record(s, proc, label, out)
        Wait(1300)
        return true
    end
    if not started then
        -- never started (missing item, no permission, wrong state): say why, wait for Continue
        if out == 'cancel' or out == 'silent' then return false end
        record(s, proc, label, nil, true, errMsg(out))
        return note(s, proc, 'blocked', errMsg(out)) and false
    end
    if out == 'silent' then
        record(s, proc, label, nil, true)
        return false
    end
    NZA.UI.Send(APP, 'outcome', { proc = proc, ok = false, outcome = type(out) == 'table' and out or nil, reason = type(out) == 'string' and out or nil })
    record(s, proc, label, type(out) == 'table' and out or nil, type(out) ~= 'table', type(out) == 'table' and out.msg or errMsg(out))
    Wait(1600)
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- THE STEPS
-- ════════════════════════════════════════════════════════════════════════

local function stepBinder(s)
    local p = s.plan
    local b = p.binder or {}
    local label = L('t_binder')
    s.step = 'binder'
    if b.on then record(s, 'binder', label, nil, true, L('skip_binder_on')); return note(s, 'binder', 'skip', L('skip_binder_on')) end
    if not b.perm then record(s, 'binder', label, nil, true, L('skip_binder_perm')); return note(s, 'binder', 'skip', L('skip_binder_perm')) end
    local ok, out, started = runProc(s, 'binder', {}, p.easy and p.easy.binder, function(ctx)
        ctx.data.count = F.ItemCount(cfg('Binder').item or 'pelvic_binder')
    end)
    del(s.props.flat); s.props.flat = 0
    if s.req.abort then return false end
    stepOutcome(s, 'binder', ok, out, started, label)
    return not s.req.abort
end

local function stepIO(s)
    local p = s.plan
    local label = L('t_io')
    s.step = 'io'
    if p.access then
        s.access = p.access
        local txt = L('skip_access', p.access.kind == 'io' and 'IO' or 'IV', U.RegionLabel(p.access.site or ''))
        record(s, 'io', label, nil, true, txt)
        return note(s, 'io', 'skip', txt)
    end
    if not p.ioPerm then
        record(s, 'io', label, nil, true, L('skip_io_perm'))
        return note(s, 'io', 'blocked', L('skip_io_perm'))
    end
    local ok, out, started = runProc(s, 'io', {}, p.easy and p.easy.io)
    stopDrill(s)
    del(s.props.syringe); s.props.syringe = 0
    if s.req.abort then return false end
    if ok and type(out) == 'table' and not out.failed then
        s.access = { kind = 'io', site = out.region, bone = out.site }
        s.site = out.site
        trackAnchors(s)
        record(s, 'io', L('t_io_site', L('site_' .. tostring(out.site))), out)
        NZA.UI.Send(APP, 'outcome', { proc = 'io', ok = true, outcome = out })
        Wait(1300)
        return not s.req.abort
    end
    stepOutcome(s, 'io', ok, out, started, label)
    return not s.req.abort
end

local function stepResus(s)
    local p = s.plan
    local label = L('t_resus')
    s.step = 'resus'
    if not s.access then
        record(s, 'resus', label, nil, true, L('blocked_no_access'))
        return note(s, 'resus', 'blocked', L('blocked_no_access'))
    end
    if not p.resusPerm then
        record(s, 'resus', label, nil, true, L('skip_resus_perm'))
        return note(s, 'resus', 'blocked', L('skip_resus_perm'))
    end
    spawnStand(s)
    trackAnchors(s)
    local ok, out, started = runProc(s, 'resus', {}, p.easy and p.easy.resus, function(ctx)
        s.resusToken = ctx.token
        local d = ctx.data
        if d and d.access then d.access.siteLabel = U.RegionLabel(d.access.site or '') end
        if d and d.infusions then syncBags(s, d.infusions) end
    end)
    s.resusToken = nil
    if NZA.Monitor then NZA.Monitor.Override(nil) end
    if s.req.abort then return false end
    if ok and type(out) == 'table' and not out.failed and p.easy and p.easy.resus then
        -- easy mode hung a bag on the server: show it on the stand
        local snap = NZA.Patient.Get(s.target)
        if snap then
            local list = {}
            for _, inf in ipairs(snap.infusions or {}) do
                list[#list + 1] = { id = inf.id, kind = inf.kind, ml = inf.ml, left = inf.left, mine = inf.by == GetPlayerServerId(PlayerId()) }
            end
            syncBags(s, list)
        end
    end
    stepOutcome(s, 'resus', ok, out, started, label)
    return not s.req.abort
end

local function stepReassess(s)
    s.step = 'reassess'
    NZA.UI.Send(APP, 'step', { proc = 'reassess', status = 'run', data = {} })
    camFocus(s, 'patient')
    local snap = NZA.Patient.Get(s.target)
    local okR = NZA.Treat.Do('field_report', s.target, {}, { silent = true })
    local p = s.plan
    local v0, v1 = p.vitals or {}, snap and snap.vitals or {}
    local devices = {}
    local d = snap and snap.devices or {}
    if d.binder then devices[#devices + 1] = L('dev_binder') end
    if type(d.iv) == 'table' then devices[#devices + 1] = ('%s %s'):format(d.iv.kind == 'io' and 'IO' or 'IV', U.RegionLabel(d.iv.site or '')) end
    local given = snap and snap.given or {}
    if (tonumber(given.saline) or 0) >= 1 then devices[#devices + 1] = L('dev_saline', math.floor(given.saline)) end
    if (tonumber(given.blood) or 0) >= 1 then devices[#devices + 1] = L('dev_blood', math.floor(given.blood)) end
    if snap and snap.meds and snap.meds.txa then devices[#devices + 1] = L('dev_txa') end
    if d.foil then devices[#devices + 1] = L('dev_foil') end
    local clot = snap and snap.meta and snap.meta.fieldClot
    if type(clot) == 'table' then devices[#devices + 1] = L('dev_clot', math.floor((clot.q or 0) * 100)) end
    local total, n = 0, 0
    for _, r in ipairs(s.results) do if r.score and not r.skipped then total = total + r.score; n = n + 1 end end
    local summary = {
        before = { bleed = p.bleed, map = v0.map, hr = v0.hr, spo2 = v0.spo2 },
        after = { bleed = snap and snap.bleedTotal or nil, map = v1.map, hr = v1.hr, spo2 = v1.spo2 },
        steps = s.results, devices = devices, grade = n > 0 and U.Grade(math.floor(total / n)) or nil,
        given = given, report = okR,
    }
    NZA.UI.Send(APP, 'summary', summary)
    s.req.done = nil
    waitReq(s, nil, 90000)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- SCENE LIFE CYCLE
-- ════════════════════════════════════════════════════════════════════════

local function medicPose(s)
    local me = PlayerPedId()
    TaskTurnPedToFaceEntity(me, s.entity, 600)
    Wait(550)
    if NZA.Anim.Kneel then pcall(NZA.Anim.Kneel, me) end
    local a = (s.mode == 'iv' and cfg('IV').anim) or cfg('Resus').anim
    if a and a.dict then
        SetTimeout(1400, function()
            if S == s and not s.ended then pcall(NZA.Anim.Play, me, a.dict, a.clip, { flag = 1, blendIn = 2.0 }) end
        end)
    end
end

local function keepStand(s)
    if not s.props.stand or s.props.stand == 0 then return end
    local running = false
    for _ in pairs(s.bagProps or {}) do running = true end
    if not running then
        del(s.props.stand); del(s.props.infuser)
        return
    end
    stands[#stands + 1] = {
        stand = s.props.stand, infuser = s.props.infuser, bags = s.bagProps, entity = s.entity,
        pos = GetEntityCoords(s.entity), untilAt = GetGameTimer() + (cfg('Resus').standKeep or 240) * 1000,
    }
    s.props.stand, s.props.infuser, s.bagProps = 0, 0, {}
end

local function cleanup(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    s.ended = true
    if s.ctx and not s.ctx.done() then pcall(s.ctx.abort, 'cancel') end
    if s.stopWatch then pcall(s.stopWatch) end
    stopDrill(s)
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    pcall(NZA.Anchors.Clear, APP)
    pcall(NZA.Cam.Stop)
    pcall(NZA.Anim.Stop, PlayerPedId())
    if s.tq then del(s.tq); s.tq = nil end
    keepStand(s)
    for k, ent in pairs(s.props) do
        if k ~= 'stand' and k ~= 'infuser' then del(ent) end
    end
    if s.mode == 'resus' and NZA.Monitor then
        NZA.Monitor.Override(nil)
        if cfg('Resus').keepMonitor ~= false then NZA.Monitor.Scene(false) else NZA.Monitor.Detach() end
    end
    if S == s then S = nil end
    if F.Busy() == s.mode then F.SetBusy(nil) end
end

-- the scene stops when the patient is gone / dies / walks off or the medic goes down
local function watchdog(s)
    CreateThread(function()
        while S == s and not s.ended do
            Wait(300)
            local ent = NZA.Target.Entity(s.target)
            local why = nil
            if ent == 0 then why = 'gone'
            elseif #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent)) > 7.0 then why = 'far'
            elseif NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then why = 'down'
            else
                local st = NZA.Target.State(s.target)
                if type(st) == 'table' and (st.st == 'dead' or (st.st == 'arrest' and s.mode == 'resus' and not s.ctx)) then why = st.st end
                if type(st) == 'table' and (st.carried or st.bag) then why = 'moved' end
            end
            if why then
                s.req.abort = why
                if why == 'arrest' then F.Toast(L('abort_arrest'), 'error') elseif why ~= 'far' then F.Toast(L('abort_' .. why), 'error') end
                break
            end
        end
    end)
end

local function sendVitals(s, snap)
    if not snap or S ~= s then return end
    local v = snap.vitals or {}
    NZA.UI.Send(APP, 'vitals', { map = v.map, hr = v.hr, spo2 = v.spo2, bleed = snap.bleedTotal, state = snap.state })
end

local function runScene(entity, target)
    local plan, err = lib.callback.await('nza:field:plan', false, target)
    if not plan then
        F.Toast(errMsg(err), 'error')
        return
    end
    local s = { mode = 'resus', entity = entity, target = target, plan = plan, props = {}, bagProps = {}, req = {}, results = {} }
    S = s
    if plan.access then s.access = plan.access end
    medicPose(s)
    s.frame = F.Frame(entity)
    spawnKit(s)
    if NZA.Monitor then
        if not NZA.Monitor.Attach(entity, target, { silent = true, scene = true }) then NZA.Monitor.Open(target) end
        NZA.Monitor.Scene(true)
    end
    camFocus(s, 'patient')
    NZA.UI.Open(APP, { mode = 'resus', plan = plan, keys = cfg('Keys'), locale = NZA.LocaleTable('field') }, { focus = true, cursor = true })
    trackAnchors(s)
    local okW, stop = pcall(NZA.Patient.Watch, target, function(snap) sendVitals(s, snap) end)
    if okW then s.stopWatch = stop end
    watchdog(s)

    stepBinder(s)
    if not s.req.abort then stepIO(s) end
    if not s.req.abort then stepResus(s) end
    if not s.req.abort then stepReassess(s) end
    if s.req.abort and s.req.abort ~= true and s.req.abort ~= 'user' then
        NZA.Debug('field scene aborted: ' .. tostring(s.req.abort))
    end
end

function F.Start(entity, target)
    if S or F.Busy() or (NZA.Proc.Active and NZA.Proc.Active()) then
        F.Toast(L('err_busy'), 'error')
        return false
    end
    target = target or (entity and NZA.Target.FromEntity(entity))
    if not target then return false end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return false end
    if not F.CanResus() then F.Toast(L('err_no_perm'), 'error') return false end
    F.SetBusy('resus')
    CreateThread(function()
        local ok, err = pcall(runScene, entity, target)
        if not ok then NZA.Warn('field scene failed: ' .. tostring(err)) end
        if S then cleanup(S) end
        if F.Busy() == 'resus' then F.SetBusy(nil) end
    end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- IV CANNULATION
-- ════════════════════════════════════════════════════════════════════════

local function runIV(entity, target, site)
    local s = { mode = 'iv', entity = entity, target = target, props = {}, req = {}, results = {} }
    S = s
    watchdog(s)
    local easy = NZA.Easy(cfg('IV').perm or 'iv')
    local ok, out = pcall(NZA.Proc.Run, 'iv', target, { site = site }, function(ctx)
        s.ctx = ctx
        local d = ctx.data or {}
        s.ivSite = d.site
        d.siteLabel = U.RegionLabel(d.site or '')
        medicPose(s)
        camFocus(s, 'site')
        local sd = (cfg('IV').sites or {})[d.site or ''] or {}
        NZA.UI.Open(APP, { mode = 'iv', plan = {}, keys = cfg('Keys'), locale = NZA.LocaleTable('field') }, { focus = true, cursor = true })
        pcall(NZA.Anchors.Track, APP, {
            tq = { entity = entity, bone = sd.tq or 40269, offset = vector3(0.12, 0.0, 0.0) },
            site = { entity = entity, bone = sd.bone or 28252, offset = vector3(0.12, 0.0, 0.0) },
        })
        NZA.UI.Send(APP, 'step', { proc = 'iv', status = 'run', data = d })
        local why = waitReq(s, ctx)
        if why == 'result' then
            local r = s.req.result
            s.req.result = nil
            local fine, res = ctx.finish(type(r) == 'table' and r or {})
            NZA.UI.Send(APP, 'outcome', { proc = 'iv', ok = fine and type(res) == 'table' and not res.failed, outcome = type(res) == 'table' and res or nil, reason = type(res) == 'string' and res or nil })
            Wait(2200)
        elseif why ~= 'ended' then
            ctx.abort(why == 'skip' and 'silent' or 'cancel')
        end
    end, { label = L('title_iv') })
    if not ok then NZA.Warn('field iv failed: ' .. tostring(out)) end
    if easy then NZA.Debug('field iv easy mode') end
end

function F.StartIV(entity, target, site)
    if S or F.Busy() or (NZA.Proc.Active and NZA.Proc.Active()) then
        F.Toast(L('err_busy'), 'error')
        return false
    end
    target = target or (entity and NZA.Target.FromEntity(entity))
    if not target then return false end
    entity = entity and entity ~= 0 and entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return false end
    F.SetBusy('iv')
    CreateThread(function()
        local ok, err = pcall(runIV, entity, target, site)
        if not ok then NZA.Warn('field iv failed: ' .. tostring(err)) end
        if S then cleanup(S) end
        if F.Busy() == 'iv' then F.SetBusy(nil) end
    end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function scene() return S and not S.ended and S or nil end

NZA.UI.On(APP, 'result', function(data, cb)
    local s = scene()
    if s and type(data) == 'table' and type(data.result) == 'table' then s.req.result = data.result end
    cb({ ok = s ~= nil })
end)

NZA.UI.On(APP, 'skip', function(_, cb)
    local s = scene()
    if s then s.req.skip = true end
    cb({ ok = s ~= nil })
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    local s = scene()
    if s then s.req.abort = 'user' end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'close', function(_, cb)
    local s = scene()
    if s then s.req.abort = 'user' end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'done', function(_, cb)
    local s = scene()
    if s then s.req.done = true end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'focus', function(data, cb)
    local s = scene()
    if s and type(data) == 'table' then camFocus(s, data.what) end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'binderDrop', function(_, cb)
    local s = scene()
    if not s or s.step ~= 'binder' then cb({ ok = false }) return end
    del(s.props.flat)
    local fr = s.frame
    local z = F.Ground(fr.pelvis) + 0.012
    local ok, ent = pcall(NZA.Props.Spawn, 'binder_flat', vector3(fr.pelvis.x, fr.pelvis.y, z), { group = 'field_scene', heading = F.HeadingX(fr.side), collision = false })
    s.props.flat = ok and ent or 0
    cb({ ok = true })
end)

NZA.UI.On(APP, 'phase', function(data, cb)
    local s = scene()
    if not s or type(data) ~= 'table' then cb({ ok = false }) return end
    if data.site and ioSite(data.site) then s.site = data.site end
    if data.phase == 'drill' then
        startDrill(s)
        trackAnchors(s)
        camFocus(s, 'site')
    elseif data.phase == 'confirm' or data.phase == 'flush' then
        stopDrill(s)
        placeSyringe(s)
    end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'drill', function(data, cb)
    local s = scene()
    if s and s.drill and type(data) == 'table' then s.drill.want = data end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'needle', function(_, cb)
    local s = scene()
    if not s then cb({ ok = false }) return end
    local ok, res = NZA.Treat.Do('io_needle', s.target, {}, { silent = true })
    cb({ ok = ok, needles = type(res) == 'table' and res.needles or nil, msg = type(res) == 'table' and res.msg or nil })
end)

NZA.UI.On(APP, 'hang', function(data, cb)
    local s = scene()
    if not s or type(data) ~= 'table' then cb({ ok = false }) return end
    local ok, res = NZA.Treat.Do('infuse', s.target, { kind = data.kind, serial = data.serial, rate = tonumber(data.rate) }, { silent = true })
    if ok and type(res) == 'table' then
        local inf = { id = res.id, kind = res.kind, ml = res.ml, left = res.left, rate = res.rate, bag = res.bag, mine = true }
        s.bags = s.bags or {}
        s.bags[res.id] = inf
        local list = {}
        for _, b in pairs(s.bags) do list[#list + 1] = b end
        syncBags(s, list)
        cb({ ok = true, inf = inf })
        return
    end
    cb({ ok = false, msg = type(res) == 'table' and res.msg or nil })
end)

NZA.UI.On(APP, 'rate', function(data, cb)
    local s = scene()
    if s and type(data) == 'table' and data.id then
        NZA.Treat.Do('infuse_rate', s.target, { id = data.id, rate = tonumber(data.rate) }, { silent = true })
    end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'takedown', function(data, cb)
    local s = scene()
    if not s or type(data) ~= 'table' then cb({ ok = false }) return end
    local ok, res = NZA.Treat.Do('infuse_stop', s.target, { id = data.id }, { silent = true })
    if ok then
        if s.bags and s.bags[data.id] then
            s.bags[data.id] = nil
        end
        if s.bagProps and s.bagProps[data.id] then del(s.bagProps[data.id].ent); s.bagProps[data.id] = nil end
    end
    cb({ ok = ok, msg = type(res) == 'table' and res.msg or nil })
end)

NZA.UI.On(APP, 'txa', function(data, cb)
    local s = scene()
    if not s then cb({ ok = false }) return end
    local ok, res = NZA.Treat.Do('txa', s.target, { seconds = type(data) == 'table' and tonumber(data.seconds) or 0 }, { silent = true })
    cb({ ok = ok, msg = type(res) == 'table' and res.msg or nil })
end)

NZA.UI.On(APP, 'foil', function(_, cb)
    local s = scene()
    if not s then cb({ ok = false }) return end
    local ok, res = NZA.Treat.Do('field_foil', s.target, {}, { silent = true })
    cb({ ok = ok, msg = type(res) == 'table' and res.msg or nil })
end)

NZA.UI.On(APP, 'nibp', function(_, cb)
    if NZA.Monitor then NZA.Monitor.Nibp() end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'bags', function(_, cb)
    local s = scene()
    if not s then cb({}) return end
    local res = lib.callback.await('nza:field:bags', false, s.target)
    if type(res) == 'table' then NZA.UI.Send(APP, 'bags', { counts = { saline = res.saline, txa = res.txa, foil = res.foil }, bags = res.bags }) end
    cb({ ok = res ~= nil })
end)

NZA.UI.On(APP, 'ivTq', function(data, cb)
    local s = scene()
    if not s or s.mode ~= 'iv' then cb({ ok = false }) return end
    local on = type(data) == 'table' and data.on == true
    if s.tq then del(s.tq); s.tq = nil end
    if on and cfg('IV').tourniquetProp ~= false then
        local sd = (cfg('IV').sites or {})[s.ivSite or ''] or {}
        local ok, ent = pcall(NZA.Props.Spawn, 'tourniquet_worn', { attach = { entity = s.entity, bone = sd.tq or 40269, pos = vector3(0.12, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0), collision = false } },
            { group = 'field_scene', collision = false })
        if ok and ent and ent ~= 0 then s.tq = ent end
    end
    cb({ ok = true })
end)

-- ════════════════════════════════════════════════════════════════════════
-- SERVER PUSHES (resuscitate step)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:field:resus', function(state)
    local s = scene()
    if not s or type(state) ~= 'table' or not s.resusToken or state.token ~= s.resusToken then return end
    NZA.UI.Send(APP, 'clot', state)
    if NZA.Monitor then NZA.Monitor.Override({ map = state.map, sys = state.sys, dia = state.dia }) end
    if type(state.bags) == 'table' then
        s.bags = {}
        for _, b in ipairs(state.bags) do if b.mine then s.bags[b.id] = b end end
        syncBags(s, state.bags)
    end
end)

RegisterNetEvent('nza:field:popped', function()
    local s = scene()
    if s and s.resusToken then NZA.UI.Send(APP, 'popped', {}) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- STANDS LEFT BEHIND, MEDIC DOWN, RESOURCE STOP
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(2000)
        if #stands > 0 then
            local me = GetEntityCoords(PlayerPedId())
            for i = #stands, 1, -1 do
                local st = stands[i]
                local gone = GetGameTimer() > st.untilAt or not DoesEntityExist(st.entity)
                    or #(GetEntityCoords(st.entity) - st.pos) > 2.0 or #(me - st.pos) > 60.0
                if gone then
                    for _, b in pairs(st.bags or {}) do del(b.ent) end
                    del(st.infuser); del(st.stand)
                    table.remove(stands, i)
                end
            end
        end
    end
end)

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and S then S.req.abort = 'down' end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if S then pcall(cleanup, S) end
    for _, st in ipairs(stands) do
        for _, b in pairs(st.bags or {}) do del(b.ent) end
        del(st.infuser); del(st.stand)
    end
    stands = {}
    if NZA.Props and NZA.Props.Clear then
        NZA.Props.Clear('field_scene')
        NZA.Props.Clear('field_stand')
    end
end)
