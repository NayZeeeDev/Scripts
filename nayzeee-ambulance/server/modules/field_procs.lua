--[[
    NAYZEEE AMBULANCE - Field resuscitation (server): the procedures with a score

    Procedures (NZA.Proc, one server session each - easy mode = progress bar):
      'binder'  perm Binder.perm   item Binder.item (finish)   payload {}
                result { tension = 0..120, attempts }           → devices.binder, meta.binderQ,
                pelvic base bleed x (1 - bleedBonus * quality), over-tight = pain
      'io'      perm IO.perm       item IO.item (finish, +1 per extra needle via the 'io_needle' treat)
                result { site = 'l_tibia'|'r_tibia'|'l_humerus'|'r_humerus', angle, overshoot,
                         lido = { ml, rate }, flush = { ml, rate }, aspirated }
                                                                → devices.iv = { site, kind = 'io', at, by }
      'iv'      perm IV.perm       item IV.item (finish)        payload { site? }
                result { site = 'l_lower_arm'|'r_lower_arm', attempts, angle, secured }
                                                                → devices.iv = { site, kind = 'iv', gauge, at, by }
      'resus'   perm Infusion.perm (needs IV / IO access)       payload {}
                The server runs a haemodynamic model for the step: the response to the fluids
                actually running (rate x Resus.response[kind], time constant tau) is put on the
                core vitals with NZA.Physiology.SetModifier(pid, 'field_resus', ...), so every
                monitor shows the same field MAP and the model reads it back. Clot firmness grows while that MAP sits in Resus.band; fluids that
                push it popMargin above the band for popAfter s pop the clot (base bleed x
                popFactor). Finish needs a firm clot: target injuries' base bleed x (1 - clotFactor * q).
                Easy mode: hangs one saline bag (item reserved) and forms the clot at the easy score.

    Net events: S→C nza:field:resus (state)  { token, map, sys, dia, response, firm, state, pops,
                inBand, eta, flow, bleed, mods = { txa, cold, foil, dilution }, bags }
                S→C nza:field:popped ()  the clot gave way
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Field = NZA.Field or {}
local F = NZA.Field
local Core = NZA.Core
local U = NZA.Util

local function L(key, ...) return NZA.L('field.' .. key, ...) end
local function cfg(section) return (Config.Field or {})[section] or {} end
local function fail(key, ...) return false, { err = key, msg = L('err_' .. key, ...) } end
local function items(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = key and Config.Items and Config.Items[key]
        if name and n > 0 then out[name] = (out[name] or 0) + n end
    end
    return out
end

local LIVE = { alive = true, wounded = true, arrest = true }

-- Resus.kitTools: the trauma kit carries the binder, the IO driver + needles, lidocaine and the
-- flush syringes. No separate items, and those steps run by themselves (auto).
local function kitTools() return cfg('Resus').kitTools ~= false end
local function autoData(minTime)
    if not kitTools() then return nil, nil end
    return true, math.floor(((tonumber(minTime) or 5) + 1.5) * 1000)
end
local PELVIC = { pelvic = true, femoral = true }

local function responsive(p)
    local a = p.vitals and p.vitals.avpu or 'U'
    return p.state ~= 'arrest' and (a == 'A' or a == 'V')
end

local function speak(src, p, key, ms)
    if responsive(p) then Core.Speech(src, p.name, L(key), ms or 3200) end
end

local function hasItem(src, key)
    local name = key and Config.Items and Config.Items[key]
    if not name then return false end
    return Core.B('Inv.HasItem', src, name, 1) == true
end

local function takeItem(src, key)
    local name = key and Config.Items and Config.Items[key]
    if not name then return false end
    return Core.TakeItems(src, { [name] = 1 }) == true
end

-- ════════════════════════════════════════════════════════════════════════
-- PELVIC BINDER
-- ════════════════════════════════════════════════════════════════════════

local function pelvicInjuries(p)
    local out = {}
    for id, inj in pairs(p.injuries or {}) do
        local organ = inj.internal and inj.internal.organ
        if inj.region == 'pelvis' or (organ and PELVIC[organ]) then out[#out + 1] = id end
    end
    return out
end

NZA.Proc.Register('binder', {
    perm = cfg('Binder').perm or 'binder', maxDist = 3.5, label = L('title_binder'),
    minTime = cfg('Binder').minTime or 5, maxTime = cfg('Binder').maxTime or 240, easyTime = cfg('Binder').easyTime or 6,
    consume = 'finish', states = LIVE,
    items = function()
        local key = cfg('Binder').item
        if not key or kitTools() then return {} end
        return items({ [key] = 1 })
    end,
    onStart = function(src, p)
        if p.devices.binder then return fail('binder_on') end
        local auto, autoMs = autoData(cfg('Binder').minTime or 5)
        local indicated, why = F.BinderIndicated(p)
        local main
        for _, id in ipairs(pelvicInjuries(p)) do
            local inj = p.injuries[id]
            if not main or F.Bleed(p, inj) > F.Bleed(p, main) then main = inj end
        end
        return true, {
            indicated = indicated, why = why, band = cfg('Binder').band or { 60, 80 },
            injury = F.Summary(p, main or F.MainInjury(p)), bleed = F.TotalBleed(p),
            auto = auto, autoMs = autoMs,
        }
    end,
    onFinish = function(src, p, s, result)
        local bc = cfg('Binder')
        if p.devices.binder then return { failed = true, score = 0, msg = L('err_binder_on') } end
        local band = bc.band or { 60, 80 }
        local mid = (band[1] + band[2]) / 2
        local half = math.max(1, (band[2] - band[1]) / 2)
        local tension = s.easy and mid or U.clamp(tonumber(result.tension) or 0, 0, 120)
        if not s.easy and (tension < band[1] - 0.5 or tension > band[2] + 0.5) then
            return { failed = true, score = 0, msg = L('binder_not_in_band', math.floor(tension)) }
        end
        local q = U.clamp(1 - math.abs(tension - mid) / half * 0.5, 0.4, 1)
        if s.easy then q = ((Config.EasyMode and Config.EasyMode.score) or 78) / 100 end
        NZA.Patients.SetDevice(p.pid, 'binder', true)
        NZA.Patients.SetMeta(p.pid, 'binderQ', { q = U.round(q, 2), tension = math.floor(tension), by = src, at = os.time() })
        local factor = 1 - (bc.bleedBonus or 0.25) * q
        local tight = tension > mid + half * 0.6
        for _, id in ipairs(pelvicInjuries(p)) do
            local inj = p.injuries[id]
            local patch = { fieldBinder = factor, bleedBase = (inj.bleedBase or 0) * factor }
            if tight then patch.pain = math.min(100, (inj.pain or 0) + (bc.tightPain or 12)) end
            NZA.Patients.UpdateInjury(p.pid, id, patch)
        end
        if tight then speak(src, p, 'say_binder_tight') end
        F.Bill(src, p, 'binder')
        local attempts = math.max(1, math.floor(tonumber(result.attempts) or 1))
        local score = math.floor(100 - math.abs(tension - mid) * 2 - (attempts - 1) * 12 + 0.5)
        score = U.clamp(math.min(score, result.score or 100), 0, 100)
        if s.easy then score = result.score end
        return {
            score = score, tension = math.floor(tension), tight = tight,
            msg = L('ok_binder', math.floor(tension)), record = L('rec_binder', math.floor(tension)),
        }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- INTRAOSSEOUS ACCESS (site → drill → confirm → flush)
-- ════════════════════════════════════════════════════════════════════════

local function roll(range)
    if type(range) ~= 'table' then return tonumber(range) or 3 end
    local a, b = tonumber(range[1]) or 2, tonumber(range[2]) or tonumber(range[1]) or 4
    return U.round(a + math.random() * (b - a), 1)
end

local function layersFor(kind)
    local def = (cfg('IO').layers or {})[kind] or {}
    return { soft = roll(def.soft or { 5, 9 }), cortex = roll(def.cortex or { 2.5, 4 }),
             marrow = roll(def.marrow or { 10, 16 }), far = roll(def.far or { 2.5, 3.5 }) }
end

NZA.Proc.Register('io', {
    perm = cfg('IO').perm or 'iv', maxDist = 3.5, label = L('title_io'),
    minTime = cfg('IO').minTime or 14, maxTime = cfg('IO').maxTime or 420, easyTime = cfg('IO').easyTime or 10,
    consume = 'finish', states = LIVE,
    items = function()
        local key = cfg('IO').item
        if key == false or kitTools() then return {} end
        return items({ [key or 'io_kit'] = 1 })
    end,
    onStart = function(src, p)
        if F.Access(p) then return fail('has_access') end
        local io = cfg('IO')
        local auto, autoMs = autoData(io.minTime or 14)
        local sites = F.Sites(p, io.sites)
        local any = false
        for _, st in pairs(sites) do if st.ok then any = true end end
        if not any then return fail('no_site') end
        return true, {
            sites = sites, layers = { tibia = layersFor('tibia'), humerus = layersFor('humerus') },
            maxAngle = io.maxAngle or 15, bendAngle = io.bendAngle or 26, attempts = io.attempts or 3,
            speed = io.speed, pxPerDeg = io.pxPerDeg or 3.2, tremor = io.tremor or 7,
            aspirateMl = io.aspirateMl or 1.0,
            lidoMl = io.lidoMl or 2, lidoRate = io.lidoRate or { 0.08, 0.45 },
            flushMl = io.flushMl or 10, flushRate = io.flushRate or { 1.5, 6 },
            lidocaine = kitTools() or (io.lidocaine and hasItem(src, io.lidocaine)) or false,
            responsive = responsive(p), injury = F.Summary(p, F.MainInjury(p)), bleed = F.TotalBleed(p),
            auto = auto, autoMs = autoMs,
        }
    end,
    onFinish = function(src, p, s, result)
        local io = cfg('IO')
        local needles = F.Needles[s.token] or 1
        F.Needles[s.token] = nil
        if F.Access(p) then return { failed = true, score = 0, msg = L('err_has_access') } end
        local sites = io.sites or {}
        local siteId = type(result.site) == 'string' and sites[result.site] and result.site or nil
        if s.easy and not siteId then
            for id, def in pairs(sites) do
                if not F.SiteContra(p, def.region) and (not siteId or id < siteId) then siteId = id end
            end
        end
        if not siteId then return { failed = true, score = 0, msg = L('err_no_site') } end
        local site = sites[siteId]
        local contra = F.SiteContra(p, site.region)
        if contra then return { failed = true, score = 0, msg = L('err_site_' .. contra) } end

        NZA.Patients.SetDevice(p.pid, 'iv', { site = site.region, kind = 'io', bone = siteId, at = os.time(), by = src })

        local notes = {}
        local lido = type(result.lido) == 'table' and result.lido or {}
        local flush = type(result.flush) == 'table' and result.flush or {}
        local lr, fr = io.lidoRate or { 0.08, 0.45 }, io.flushRate or { 1.5, 6 }
        local lidoMl = U.clamp(tonumber(lido.ml) or 0, 0, (io.lidoMl or 2) + 0.5)
        if s.easy then lidoMl = io.lidoMl or 2 end
        local gaveLido = false
        if lidoMl >= 1.0 and (kitTools() or (io.lidocaine and hasItem(src, io.lidocaine) and takeItem(src, io.lidocaine))) then
            gaveLido = true
            NZA.Patients.GiveMed(p.pid, 'lidocaine', { region = site.region, dose = lidoMl, route = 'io', by = src })
            if not s.easy and (tonumber(lido.rate) or 0) > (lr[2] or 0.45) * 1.25 then
                speak(src, p, 'say_lido_fast')
                notes[#notes + 1] = L('note_lido_fast')
            end
        end
        if (tonumber(flush.ml) or 0) >= 1 or s.easy then
            if not kitTools() and io.saline and hasItem(src, io.saline) then takeItem(src, io.saline) end
            local rate = tonumber(flush.rate) or 0
            if not gaveLido then
                speak(src, p, 'say_flush_pain')
                notes[#notes + 1] = L('note_no_lido')
            elseif not s.easy and rate > (fr[2] or 6) * 1.25 then
                speak(src, p, 'say_flush_fast')
                notes[#notes + 1] = L('note_flush_fast')
            end
        end

        local score = U.clamp(tonumber(result.score) or 0, 0, 100)
        if not s.easy then
            score = math.min(score, 100 - (needles - 1) * 15)
            if not result.aspirated then score = math.min(score, 70) end
        end
        score = U.clamp(math.floor(score + 0.5), 0, 100)
        F.Bill(src, p, 'io')
        local label = L('site_' .. siteId)
        return {
            score = score, site = siteId, region = site.region, needles = needles,
            msg = L('ok_io', label) .. (#notes > 0 and (' · ' .. table.concat(notes, ' · ')) or ''),
            record = L('rec_io', label, needles),
        }
    end,
    onAbort = function(src, p, s)
        if s and s.token then F.Needles[s.token] = nil end
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- IV CANNULATION (forearm)
-- ════════════════════════════════════════════════════════════════════════

local function pickArm(p, wanted)
    local sites = cfg('IV').sites or { l_lower_arm = true, r_lower_arm = true }
    if wanted and sites[wanted] and not F.SiteContra(p, wanted) then return wanted end
    local order = { 'r_lower_arm', 'l_lower_arm' }
    if wanted == 'l_lower_arm' then order = { 'l_lower_arm', 'r_lower_arm' } end
    for _, id in ipairs(order) do
        if sites[id] and not F.SiteContra(p, id) then return id end
    end
    return nil
end

-- a forearm has 2-3 veins; one straight, well-filled segment is the target
local function veinMap()
    local veins = {}
    local n = math.random(2, 3)
    for i = 1, n do
        local y = 0.22 + (i - 1) * (0.56 / math.max(1, n - 1)) + (math.random() - 0.5) * 0.08
        veins[i] = {
            y = U.round(y, 3), bend = U.round((math.random() - 0.5) * 0.18, 3),
            width = U.round(0.6 + math.random() * 0.5, 2), depth = U.round(2.5 + math.random() * 3.0, 1),
            seed = math.random(1, 9999),
        }
    end
    local best = math.random(1, n)
    veins[best].width = U.round(1.0 + math.random() * 0.25, 2)
    veins[best].bend = U.round(veins[best].bend * 0.3, 3)
    return { veins = veins, best = best, spot = U.round(0.35 + math.random() * 0.3, 3) }
end

-- skin tone of the 3D forearm close-up: the same per-patient pick as the suture close-up
local function skinTone(p)
    local tones = cfg('IV').skinTones or (Config.Suture and Config.Suture.skinTones) or { 0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88 }
    local h, s = 5381, tostring(p.pid or p.name or '')
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return tones[(h % #tones) + 1] or 0.3
end

NZA.Proc.Register('iv', {
    perm = cfg('IV').perm or 'iv', maxDist = 3.0, label = L('title_iv'),
    minTime = cfg('IV').minTime or 12, maxTime = cfg('IV').maxTime or 360, easyTime = cfg('IV').easyTime or 8,
    consume = 'finish', states = LIVE,
    items = function() return items({ [cfg('IV').item or 'iv_kit'] = 1 }) end,
    onStart = function(src, p, payload)
        if F.Access(p) then return fail('has_access') end
        local arm = pickArm(p, type(payload) == 'table' and payload.site or nil)
        if not arm then return fail('no_arm') end
        local c = cfg('IV')
        local map = veinMap()
        return true, {
            site = arm, map = map, angle = c.angle or { 15, 30 }, attempts = c.attempts or 2, gauge = c.gauge or 18,
            tourniquetFill = c.tourniquetFill or 3, flash = c.flash or 0.9,
            responsive = responsive(p), name = p.name, injury = F.Summary(p, F.MainInjury(p)), bleed = F.TotalBleed(p),
            tone = skinTone(p), sex = p.sex,
        }
    end,
    onFinish = function(src, p, s, result)
        local c = cfg('IV')
        if F.Access(p) then return { failed = true, score = 0, msg = L('err_has_access') } end
        local site = s.data and s.data.site or pickArm(p)
        if not site or F.SiteContra(p, site) then return { failed = true, score = 0, msg = L('err_no_arm') } end
        local attempts = U.clamp(math.floor(tonumber(result.attempts) or 1), 1, 9)
        if not s.easy and (result.failed or attempts > (c.attempts or 2)) then
            speak(src, p, 'say_iv_miss')
            return { failed = true, score = U.clamp(tonumber(result.score) or 0, 0, 30), msg = L('iv_failed'), record = L('rec_iv_failed', attempts) }
        end
        NZA.Patients.SetDevice(p.pid, 'iv', { site = site, kind = 'iv', gauge = c.gauge or 18, at = os.time(), by = src })
        F.Bill(src, p, 'iv')
        local score = U.clamp(tonumber(result.score) or 0, 0, 100)
        if not s.easy then score = math.min(score, 100 - (attempts - 1) * 18) end
        local label = U.RegionLabel(site)
        return {
            score = math.floor(score + 0.5), site = site,
            msg = L('ok_iv', c.gauge or 18, label), record = L('rec_iv', c.gauge or 18, label, attempts),
        }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- RESUSCITATE (permissive hypotension while the clot firms)
-- ════════════════════════════════════════════════════════════════════════

F.Resus = F.Resus or {}       -- [token] = model state

local function resusCfg() return cfg('Resus') end

local function targetsOf(p)
    local out = {}
    for _, inj in ipairs(F.TargetInjuries(p)) do out[inj.id] = inj.bleedBase or 0 end
    return out
end

local function newModel(src, p, s)
    local map = p.vitals and p.vitals.map or 0
    return {
        token = s.token, src = src, pid = p.pid, easy = s.easy, firm = 0, response = 0, pops = 0, highFor = 0,
        inBand = 0, high = 0, low = 0, startMap = map, startBleed = F.TotalBleed(p), targets = targetsOf(p),
        lastPush = 0, startedAt = os.time(),
    }
end

-- what the fluids running right now do to the pressure (mmHg at equilibrium)
local function fluidDrive(p)
    local r = resusCfg().response or {}
    local drive, flow = 0, 0
    for _, inf in ipairs(p.infusions or {}) do
        if not inf.paused and (inf.left or 0) > 0 then
            local k = inf.kind == 'blood' and (r.blood or 0.30) or inf.kind == 'plasma' and (r.plasma or 0.26)
                or inf.kind == 'txa' and 0 or (r.saline or 0.16)
            drive = drive + (inf.rate or 0) * k
            flow = flow + (inf.rate or 0)
        end
    end
    return drive, flow
end

local function modsOf(p)
    local sp = resusCfg().speed or {}
    local m, info = 1, {}
    if p.meds and p.meds.txa and p.meds.txa > os.time() then m = m * (sp.txa or 1.3); info.txa = true end
    local temp = tonumber(p.temp) or 37
    if temp < 35 then
        if p.devices.foil then m = m * (sp.foil or 0.85); info.foil = true else m = m * (sp.cold or 0.6) end
        info.cold = true
    end
    local total = (p.blood or 0) + (p.fluid or 0)
    local dil = total > 0 and (p.fluid or 0) / total or 0
    if dil > (sp.dilutionAt or 0.2) then m = m * (sp.dilution or 0.7); info.dilution = true end
    info.dil = U.round(dil * 100, 0)
    return m, info
end

local function popClot(r, p)
    local rc = resusCfg()
    r.firm, r.pops, r.highFor = 0, r.pops + 1, 0
    for id, orig in pairs(r.targets) do
        local inj = p.injuries[id]
        if inj then
            local cap = (orig > 0 and orig or (inj.bleedBase or 0)) * (rc.maxPop or 1.8)
            NZA.Patients.UpdateInjury(p.pid, id, { bleedBase = math.min(cap, (inj.bleedBase or 0) * (rc.popFactor or 1.35)) })
        end
    end
    NZA.Patients.Touch(p, true)
    TriggerClientEvent('nza:field:popped', r.src)
end

-- the fluid response on the core vitals (every monitor and the HUDs see it); ttl drops it by itself
local MOD_KEY = 'field_resus'

local function setPressure(r)
    if not (NZA.Physiology and type(NZA.Physiology.SetModifier) == 'function') then return end
    NZA.Physiology.SetModifier(r.pid, MOD_KEY, { sys = r.response * 1.3, dia = r.response * 0.85, hr = 0, ttl = 3 })
end

local function clearPressure(r)
    if not (r and r.pid and NZA.Physiology and type(NZA.Physiology.SetModifier) == 'function') then return end
    NZA.Physiology.SetModifier(r.pid, MOD_KEY, nil)
end

local function stepModel(r, p, dt)
    local rc = resusCfg()
    local band = rc.band or { 60, 70 }
    local resp = rc.response or {}
    local sp = rc.speed or {}
    local drive, flow = fluidDrive(p)
    local k = 1 - math.exp(-dt / math.max(0.5, resp.tau or 6))
    r.response = r.response + (drive - r.response) * k
    setPressure(r)
    -- the vitals already carry the response (MAP offset = response, sys x 1.3, dia x 0.85)
    local v = p.vitals or {}
    local map = math.floor((v.map or 0) + 0.5)
    local sys = math.floor((v.sys or 0) + 0.5)
    local dia = math.floor((v.dia or 0) + 0.5)

    local state, factor = 'band', 1
    if p.state == 'arrest' or p.state == 'dead' then
        state, factor = 'arrest', 0
    elseif map < (rc.lowMap or 52) then
        state, factor = 'low', 0
        r.low = r.low + dt
    elseif map < band[1] then
        state, factor = 'below', sp.below or 0.35
    elseif map <= band[2] then
        state, factor = 'band', 1
        r.inBand = r.inBand + dt
    elseif r.response < (resp.own or 4) then
        state, factor = 'own', sp.own or 0.8
        r.inBand = r.inBand + dt
    else
        state, factor = 'high', sp.high or 0.25
        r.high = r.high + dt
    end
    if state == 'high' and map > band[2] + (rc.popMargin or 6) then
        r.highFor = r.highFor + dt
        if r.highFor >= (rc.popAfter or 3) and r.firm >= 8 then
            popClot(r, p)
            state = 'popped'
        end
    else
        r.highFor = math.max(0, r.highFor - dt * 0.5)
    end
    local mods, info = modsOf(p)
    local rate = 100 / math.max(4, rc.hold or 24)
    if state ~= 'popped' then r.firm = math.min(100, r.firm + rate * factor * mods * dt) end
    local speed = rate * factor * mods
    r.last = {
        token = r.token, map = map, sys = sys, dia = dia, response = U.round(r.response, 1),
        firm = U.round(r.firm, 1), state = r.firm >= 100 and 'firm' or state, pops = r.pops,
        warn = r.highFor > 0.1 and U.round((rc.popAfter or 3) - r.highFor, 1) or nil,
        eta = speed > 0 and math.ceil((100 - r.firm) / speed) or nil,
        flow = math.floor(flow + 0.5), bleed = F.TotalBleed(p), mods = info,
        bags = F.InfusionsOf(p, r.src), maxRate = F.MaxRate(p),
        txa = info.txa or false, foil = p.devices.foil and true or false,
    }
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        local dt = math.min(3, (now - last) / 1000)
        last = now
        for token, r in pairs(F.Resus) do
            local s = NZA.Proc.Session(token)
            local p = NZA.Patients.Get(r.pid)
            if not s or not p then
                F.Resus[token] = nil
                clearPressure(r)
            elseif not r.easy then
                local ok, err = pcall(stepModel, r, p, dt)
                if not ok then
                    NZA.Warn('field: resus model failed: ' .. tostring(err))
                elseif r.last then
                    TriggerClientEvent('nza:field:resus', r.src, r.last)
                end
            end
        end
    end
end)

NZA.Bus.On('proc:started', function(src, p, name, s)
    if name ~= 'resus' or not p or not s then return end
    F.Resus[s.token] = newModel(src, p, s)
end)

NZA.Bus.On('proc:aborted', function(src, p, name)
    if name ~= 'resus' then return end
    for token, r in pairs(F.Resus) do
        if r.src == src and not NZA.Proc.Session(token) then
            F.Resus[token] = nil
            clearPressure(r)
        end
    end
end)

NZA.Proc.Register('resus', {
    perm = cfg('Infusion').perm or 'iv', maxDist = 4.0, label = L('title_resus'),
    minTime = resusCfg().minTime or 18, maxTime = resusCfg().maxTime or 600, easyTime = resusCfg().easyTime or 10,
    consume = 'finish', states = { alive = true, wounded = true },
    items = function(src, p)
        -- easy mode hangs one saline bag for you; the minigame hangs bags through the 'infuse' treat
        if NZA.Staff.Easy(src, cfg('Infusion').perm or 'iv') then
            return items({ [cfg('Infusion').saline or 'saline_bag'] = 1 })
        end
        return {}
    end,
    onStart = function(src, p)
        if not F.Access(p) then return fail('no_access') end
        local rc = resusCfg()
        return true, {
            band = rc.band or { 60, 70 }, hold = rc.hold or 24, lowMap = rc.lowMap or 52,
            popMargin = rc.popMargin or 6, autoContinue = rc.autoContinue or 1.6,
            access = F.Access(p), maxRate = F.MaxRate(p), infusion = cfg('Infusion'), txaPush = cfg('TXA').push or 10,
            counts = F.Counts(src), bags = F.BloodBags(src, p), blood = F.BloodModule(),
            infusions = F.InfusionsOf(p, src), txaActive = p.meds and p.meds.txa and p.meds.txa > os.time() or false,
            foilOn = p.devices.foil and true or false, injury = F.Summary(p, F.MainInjury(p)), bleed = F.TotalBleed(p),
            temp = U.round(tonumber(p.temp) or 37, 1),
        }
    end,
    onFinish = function(src, p, s, result)
        local rc = resusCfg()
        local r = F.Resus[s.token]
        F.Resus[s.token] = nil
        clearPressure(r)
        local easyScore = (Config.EasyMode and Config.EasyMode.score) or 78
        local targets = r and r.targets or targetsOf(p)
        if s.easy then
            local ic = cfg('Infusion')
            local a = F.Access(p)
            NZA.Patients.AddInfusion(p.pid, {
                kind = 'saline', ml = ic.salineMl or 500, warm = ic.warm == true, by = src,
                rate = math.floor((ic.gravity or 60) * ((a and a.kind == 'io') and (ic.ioFactor or 0.45) or 1)),
            })
        elseif not r or r.firm < 99.5 then
            return { failed = true, score = U.clamp(math.floor((r and r.firm or 0) * 0.4), 0, 40), msg = L('resus_not_firm') }
        end
        local score
        if s.easy then
            score = easyScore
        else
            local elapsed = math.max(1, s.elapsed or 1)
            local ideal = rc.hold or 24
            score = 100 - r.pops * 20 - math.max(0, elapsed - ideal * 2.5) * 0.4 - math.min(20, r.high * 0.8) - math.min(15, r.low * 0.6)
            if r.last and r.last.mods and r.last.mods.txa then score = score + 5 end
            score = U.clamp(math.floor(math.min(score, result.score or 100) + 0.5), 0, 100)
        end
        local q = U.clamp(score / 100, 0.4, 1)
        local factor = 1 - (rc.clotFactor or 0.55) * q
        for id in pairs(targets) do
            local inj = p.injuries[id]
            if inj then NZA.Patients.UpdateInjury(p.pid, id, { bleedBase = (inj.bleedBase or 0) * factor }) end
        end
        NZA.Patients.SetMeta(p.pid, 'fieldClot', { firm = 100, q = U.round(q, 2), pops = r and r.pops or 0, at = os.time(), by = src })
        NZA.Patients.Touch(p, true)
        F.Bill(src, p, 'resus')
        return {
            score = score, pops = r and r.pops or 0, bleedBefore = r and r.startBleed or nil, bleed = F.TotalBleed(p),
            msg = L('ok_resus', math.floor((1 - factor) * 100)), record = L('rec_resus', math.floor((1 - factor) * 100), r and r.pops or 0),
        }
    end,
    onAbort = function(src, p, s)
        if s and s.token then
            clearPressure(F.Resus[s.token])
            F.Resus[s.token] = nil
        end
    end,
})
