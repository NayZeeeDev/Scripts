--[[
    NAYZEEE AMBULANCE - Check Pulse (server)                 NZA.Proc 'pulse' (perm assess)

    Start: builds the patient's pulse from the live vitals - one beat schedule (with heart
    rate variability, atrial fibrillation chaos, pulse deficit at the wrist, pulsus
    paradoxus with a tamponade) and the amplitude of every beat at the carotid and at the
    radial artery (absent under Config.Assess.Pulse.radialMinSys / carotidMinSys, absent
    distal of a tourniquet, nothing at all in cardiac arrest). The client gets that
    schedule obfuscated (NZA.Assess.Encode) plus the pressure band of each site. It never
    receives the heart rate, rhythm or strength: those are only returned in the outcome.

    Finish: re-scores everything from the raw taps against the schedule kept here
    (rate counted vs beats really felt in the window, tap timing, rhythm, strength,
    "no pulse" calls), records findings (NZA.Findings: pulse, no_radial_pulse, pulseless,
    irregular_pulse, tamponade_suspected), logs the record and returns the result card.

    Client result payload (ctx.finish):
      { nonce, site = 'carotid'|'radial', countStart = ms, countMs = ms, taps = { ms, ... },
        rhythm = 'regular'|'irregular', strength = 'weak'|'normal'|'bounding',
        none = { carotid = bool, radial = bool }, pressure = 0..1 (time in band while counting),
        palp = { carotid = s, radial = s } }
    Registers: NZA.Proc 'pulse'. Uses: NZA.Assess.*, NZA.Findings.*
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
local A = NZA.Assess
local U = NZA.Util

local sessions = {}     -- [src] = session data (truth kept server side)

local function pc()
    return (Config.Assess and Config.Assess.Pulse) or {}
end

local function rnd(a, b) return a + math.random() * (b - a) end
local function clamp(n, a, b) if n < a then return a elseif n > b then return b end return n end

local PULSELESS = { vf = true, vt = true, pea = true, asystole = true }
local STRENGTH_AMP = { weak = 0.40, normal = 0.72, bounding = 1.0 }
local FELT = 0.12

-- ════════════════════════════════════════════════════════════════════════
-- TRUTH
-- ════════════════════════════════════════════════════════════════════════

local function describe(p)
    local c = pc()
    local v = p.vitals or {}
    local sys = tonumber(v.sys) or 120
    local rhythm = v.rhythm or 'sinus'
    local pulseless = p.state == 'arrest' or p.state == 'dead' or PULSELESS[rhythm] or (tonumber(v.hr) or 0) <= 0
    local tq = p.devices.tourniquet or {}
    local rBlock = tq.r_upper_arm or tq.r_lower_arm
    local lBlock = tq.l_upper_arm or tq.l_lower_arm
    local side = 'right'
    if rBlock and not lBlock then side = 'left' end
    local blocked = (side == 'right' and rBlock) or (side == 'left' and lBlock)
    local strength = 'normal'
    if pulseless then
        strength = 'none'
    elseif sys < (c.weakSys or 90) or (tonumber(v.map) or 90) < 65 then
        strength = 'weak'
    elseif sys > (c.boundingSys or 160) then
        strength = 'bounding'
    end
    local tam = p.conditions.tamponade
    return {
        hr = pulseless and 0 or math.floor((tonumber(v.hr) or 75) + 0.5),
        rr = tonumber(v.rr) or 16,
        sys = sys,
        rhythm = rhythm,
        pulseless = pulseless and true or false,
        regular = rhythm ~= 'afib',
        strength = strength,
        side = side,
        tourniquet = blocked and true or false,
        carotid = (not pulseless) and sys >= (c.carotidMinSys or 60),
        radial = (not pulseless) and (not blocked) and sys >= (c.radialMinSys or 80),
        paradoxus = tam ~= nil and (tonumber(tam.ml) or 0) >= 40,
    }
end

local function buildBeats(t, seconds)
    local beats = {}
    local total = 0
    local hr = t.hr > 0 and t.hr or 60
    local period = 60000 / hr
    local base = STRENGTH_AMP[t.strength] or 0.7
    local rrPeriod = 60000 / math.max(6, t.rr > 0 and t.rr or 14)
    while total < seconds * 1000 and #beats < 400 do
        local iv
        if t.regular then
            iv = period * (1 + (math.random() - 0.5) * 0.06)
        else
            iv = period * rnd(0.55, 1.45)
        end
        iv = clamp(math.floor(iv + 0.5), 230, 2800)
        local c = base * rnd(0.92, 1.08)
        local r = c * 0.85
        if not t.regular then
            local fill = clamp(iv / period, 0.45, 1.2)
            c = c * (0.6 + 0.4 * fill)
            if iv < period * 0.78 then r = 0 else r = c * 0.8 end
        end
        if t.paradoxus then
            local phase = (total % rrPeriod) / rrPeriod
            if phase < 0.42 then
                c = c * 0.62
                r = r * 0.35
            end
        end
        if t.pulseless or not t.carotid then c = 0 end
        if t.pulseless or not t.radial then r = 0 end
        beats[#beats + 1] = { iv = iv, c = clamp(c, 0, 1), r = clamp(r, 0, 1) }
        total = total + iv
    end
    return beats, total
end

local function band(center, half)
    local lo = clamp(center - half, 0.08, 0.9)
    local hi = clamp(center + half, lo + 0.08, 0.95)
    return { math.floor(lo * 1000 + 0.5) / 1000, math.floor(hi * 1000 + 0.5) / 1000 }
end

-- beats felt at a site inside [from, to) ms of the (cycled) schedule
local function beatTimes(s, site, from, to)
    local out = {}
    local key = site == 'carotid' and 'c' or 'r'
    if s.total <= 0 then return out end
    local cycle = math.floor(from / s.total)
    local base = cycle * s.total
    local guard = 0
    while base < to and guard < 8 do
        local acc = base
        for i = 1, #s.beats do
            local b = s.beats[i]
            acc = acc + b.iv
            -- the pulse is felt ~120 ms after the beat of the schedule
            if acc >= from and acc < to and b[key] >= FELT then out[#out + 1] = acc end
            if acc >= to then break end
        end
        base = base + s.total
        guard = guard + 1
    end
    return out
end

local function siteRate(s, site)
    local key = site == 'carotid' and 'c' or 'r'
    local n = 0
    for i = 1, #s.beats do if s.beats[i][key] >= FELT then n = n + 1 end end
    if s.total <= 0 then return 0 end
    return math.floor(n * 60000 / s.total + 0.5)
end

-- ════════════════════════════════════════════════════════════════════════
-- SCORING
-- ════════════════════════════════════════════════════════════════════════

local function L(key, ...) return NZA.L('assess.' .. key, ...) end

local function label(kind, value)
    if value == nil or value == '' then return '--' end
    return L(kind .. '_' .. tostring(value))
end

local function score(s, t, res)
    local c = pc()
    local fb = {}
    local function add(tone, key, ...) fb[#fb + 1] = { tone = tone, text = L(key, ...) } end

    local site = res.site == 'carotid' and 'carotid' or 'radial'
    local none = type(res.none) == 'table' and res.none or {}
    local calledNone = none[site] == true
    local countMs = clamp(tonumber(res.countMs) or 0, 0, (c.countSeconds or 15) * 1000 + 1500)
    local countStart = tonumber(res.countStart) or -1
    local window = (c.countSeconds or 15) * 1000
    local factor = 60000 / window

    -- taps (track ms) inside the count window
    local taps = {}
    if type(res.taps) == 'table' then
        for i = 1, math.min(#res.taps, 240) do
            local x = tonumber(res.taps[i])
            if x and countStart >= 0 and x >= countStart and x <= countStart + window + 400 then taps[#taps + 1] = x end
        end
        table.sort(taps)
    end

    local present = (site == 'carotid' and t.carotid) or (site == 'radial' and t.radial)
    local out = {
        site = site,
        counted = nil, expected = 0, hits = 0, extra = 0,
        rhythmOk = false, strengthOk = false, noneOk = nil,
    }
    local pts = 0

    -- ── pulseless / absent calls
    if t.pulseless then
        if none.carotid then
            pts = 100
            out.noneOk = true
            add('ok', 'fb_pulseless_ok')
            if (tonumber(res.palp and res.palp.carotid) or 0) > 12 then
                pts = 88
                add('warn', 'fb_pulseless_slow')
            end
        elseif calledNone and site == 'radial' then
            pts = 55
            out.noneOk = true
            add('warn', 'fb_pulseless_radial')
        else
            pts = 0
            out.noneOk = false
            add('bad', 'fb_pulseless_missed', math.floor(#taps * factor + 0.5))
        end
        out.counted = #taps > 0 and math.floor(#taps * factor + 0.5) or 0
        return math.floor(pts + 0.5), fb, out
    end

    if none.radial and not t.radial then
        add('ok', t.tourniquet and 'fb_radial_tq' or 'fb_radial_absent_ok')
        out.noneOk = true
    elseif none.radial and t.radial then
        add('bad', 'fb_radial_absent_wrong')
        out.noneOk = false
        pts = pts - 15
    elseif site == 'radial' and not t.radial and countMs > 0 then
        add('bad', 'fb_radial_absent_missed')
    end
    if none.carotid and t.carotid then
        add('bad', 'fb_carotid_absent_wrong')
        out.noneOk = false
        return 0, fb, out
    end

    if not present then
        -- counted on a site with nothing to feel
        if countMs > 0 then
            out.counted = math.floor(#taps * factor + 0.5)
            add('bad', 'fb_nothing_felt', #taps)
        end
        if none.radial and not t.radial and t.carotid then
            add('warn', 'fb_go_carotid')
            pts = pts + 30
        end
        return clamp(math.floor(pts + 0.5), 0, 100), fb, out
    end

    -- ── rate (40)
    local beats = (countStart >= 0 and countMs > 0) and beatTimes(s, site, countStart, countStart + window) or {}
    out.expected = #beats
    out.counted = math.floor(#taps * factor + 0.5)
    local trueRate = #beats * factor
    if countMs > 0 then
        local err = math.abs(out.counted - trueRate) / math.max(trueRate, 40)
        pts = pts + 40 * clamp(1 - err * 2.5, 0, 1)
        if err <= 0.08 then
            add('ok', 'fb_rate_ok', out.counted, siteRate(s, site))
        else
            add(err <= 0.2 and 'warn' or 'bad', 'fb_rate_off', out.counted, siteRate(s, site))
        end
        -- tap timing (20): greedy match within the window
        local tol = (c.tapWindow or 0.25) * 1000
        local used = {}
        local hits = 0
        for _, x in ipairs(taps) do
            local best, bestD = nil, tol + 1
            for i, b in ipairs(beats) do
                if not used[i] then
                    local d = math.abs((x - 120) - b)
                    if d < bestD then best, bestD = i, d end
                end
            end
            if best and bestD <= tol then
                used[best] = true
                hits = hits + 1
            end
        end
        out.hits = hits
        out.extra = #taps - hits
        local precision = #taps > 0 and hits / #taps or 0
        local recall = #beats > 0 and hits / #beats or 0
        pts = pts + 20 * precision * recall
        if out.extra >= 3 then add('warn', 'fb_extra_taps', out.extra) end
        if #beats - hits >= 3 then add('warn', 'fb_missed_beats', #beats - hits) end
    else
        add('bad', 'fb_no_count')
    end

    -- ── rhythm (15)
    local truthRhythm = t.regular and 'regular' or 'irregular'
    out.rhythmOk = res.rhythm == truthRhythm
    if out.rhythmOk then
        pts = pts + 15
        if not t.regular then add('ok', 'fb_irregular_ok') end
    else
        add('bad', 'fb_rhythm_wrong', label('rhythm', truthRhythm))
    end

    -- ── strength (15)
    out.strengthOk = res.strength == t.strength
    if out.strengthOk then
        pts = pts + 15
    elseif res.strength and ((res.strength == 'normal') or (t.strength == 'normal')) then
        pts = pts + 6
        add('warn', 'fb_strength_wrong', label('strength', t.strength))
    else
        add('bad', 'fb_strength_wrong', label('strength', t.strength))
    end

    -- ── technique (10): kept the pressure in the band while counting
    local inBand = clamp(tonumber(res.pressure) or 0, 0, 1)
    pts = pts + 10 * inBand
    if inBand < 0.6 and countMs > 0 then add('warn', 'fb_pressure') end

    if t.paradoxus then add('warn', 'fb_paradoxus') end
    if not t.regular and site == 'radial' then add('info', 'fb_deficit') end

    return clamp(math.floor(pts + 0.5), 0, 100), fb, out
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function onStart(src, p, payload)
    local c = pc()
    local t = describe(p)
    local beats, total = buildBeats(t, math.max(90, (c.maxTime or 240) * 0.5))
    local seed = A.Seed()
    local values = { #beats }
    for i = 1, #beats do values[#values + 1] = beats[i].iv end
    for i = 1, #beats do values[#values + 1] = beats[i].c * 1000 end
    for i = 1, #beats do values[#values + 1] = beats[i].r * 1000 end

    local half = ({ weak = 0.09, normal = 0.14, bounding = 0.19, none = 0.12 })[t.strength] or 0.14
    sessions[src] = {
        pid = p.pid, truth = t, beats = beats, total = total,
        started = os.time(), startedMs = GetGameTimer(),
    }
    return true, {
        k = seed,
        s = A.Encode(seed, values),
        sites = {
            carotid = { band = band(rnd(0.42, 0.56), half) },
            radial = { band = band(rnd(0.28, 0.42), half * 0.85), side = t.side },
        },
        start = c.startSite == 'carotid' and 'carotid' or 'radial',
        countSeconds = c.countSeconds or 15,
        absentAfter = c.absentAfter or 5,
        minTime = c.minTime or 8,
        tapWindow = c.tapWindow or 0.25,
        keys = c.keys,
        patient = { name = p.name, sex = p.sex, npc = p.kind == 'npc' },
    }
end

local function truthRows(t, s, res, out)
    local site = out.site or 'radial'
    local rate = t.pulseless and 0 or siteRate(s, site)
    local rateText = t.pulseless and L('none_word') or tostring(rate)
    return {
        rate = { you = out.counted ~= nil and tostring(out.counted) or '--', patient = rateText, unit = L('bpm'),
                 ok = (not t.pulseless) and out.counted ~= nil and math.abs(out.counted - rate) <= math.max(6, rate * 0.08) or (t.pulseless and out.noneOk == true),
                 apical = (not t.pulseless and not t.regular and rate ~= t.hr) and t.hr or nil },
        rhythm = { you = label('rhythm', res.rhythm), patient = t.pulseless and '--' or label('rhythm', t.regular and 'regular' or 'irregular'), ok = out.rhythmOk },
        strength = { you = label('strength', res.strength), patient = label('strength', t.strength), ok = out.strengthOk },
        site = { you = L('site_' .. site .. (site == 'radial' and ('_' .. (t.side or 'right')) or '')),
                 carotid = t.carotid and true or false, radial = t.radial and true or false },
    }
end

local function addFindings(src, p, t, res, out, easy)
    local F = NZA.Findings
    local recorded = {}
    local function add(key, data, text)
        data.source = 'pulse'
        data.by = src
        F.Add(p.pid, key, data)
        recorded[#recorded + 1] = text
    end
    if t.pulseless then
        if easy or out.noneOk then add('pulseless', { cond = 'arrest', text = L('finding_pulseless') }, L('finding_pulseless')) end
        return recorded
    end
    local none = type(res.none) == 'table' and res.none or {}
    if (easy or none.radial) and not t.radial then
        add('no_radial_pulse', { text = L('finding_no_radial') }, L('finding_no_radial'))
    end
    if (easy or (out.rhythmOk and res.rhythm == 'irregular')) and not t.regular then
        add('irregular_pulse', { text = L('finding_irregular') }, L('finding_irregular'))
    end
    if t.paradoxus and (easy or (out.strengthOk or res.strength == 'weak')) and p.conditions.tamponade then
        add('tamponade_suspected', { cond = 'tamponade', group = 'chest', text = L('finding_paradoxus') }, L('finding_tamponade'))
    end
    local site = out.site or 'radial'
    local rate = out.counted
    if rate and rate > 0 then
        F.Add(p.pid, 'pulse', {
            source = 'pulse', by = src, rate = rate, site = site,
            rhythm = easy and (t.regular and 'regular' or 'irregular') or res.rhythm,
            strength = easy and t.strength or res.strength,
        })
    end
    return recorded
end

local function onFinish(src, p, session, result)
    local s = sessions[src]
    sessions[src] = nil
    if type(result) ~= 'table' then result = {} end
    local nonce = result.nonce
    if not s or s.pid ~= p.pid then
        local o = { score = 0, error = 'session', msg = L('err_session') }
        A.Outcome(src, nonce, o)
        return o
    end
    -- re-read the vitals NOW only for the record; the check is judged on what was felt
    local t = s.truth
    local easy = (type(session) == 'table' and session.easy == true)
    local pts, fb, out
    if easy then
        out = { site = t.radial and 'radial' or 'carotid', counted = siteRate(s, t.radial and 'radial' or 'carotid'), noneOk = true, rhythmOk = true, strengthOk = true }
        pts = tonumber(Config.EasyMode and Config.EasyMode.score) or 78
        fb = { { tone = 'info', text = L('fb_easy') } }
        result.rhythm = t.regular and 'regular' or 'irregular'
        result.strength = t.strength
        result.site = out.site
        if t.pulseless then out.counted = 0 end
    else
        pts, fb, out = score(s, t, result)
    end

    local recorded = addFindings(src, p, t, result, out, easy)
    local rows = truthRows(t, s, result, out)
    local grade = U.Grade(pts)
    local seconds = os.time() - s.started
    local summary
    if t.pulseless then
        summary = L('summary_pulseless')
    else
        summary = L('summary_pulse', rows.rate.patient, rows.rhythm.patient, rows.strength.patient, rows.site.you)
    end
    local outcome = {
        score = pts, grade = grade, seconds = seconds, easy = easy or nil,
        title = L('pulse_result_title'),
        msg = summary,
        rows = rows,
        feedback = fb,
        recorded = recorded,
        pulseless = t.pulseless or nil,
    }
    outcome.record = {
        summary = summary, score = pts, grade = grade, seconds = seconds, easy = easy or nil,
        found = { rate = out.counted, rhythm = result.rhythm, strength = result.strength, site = out.site },
        truth = { hr = t.hr, rhythm = t.rhythm, strength = t.strength, carotid = t.carotid, radial = t.radial },
    }
    A.Outcome(src, nonce, outcome)
    A.Record(src, p, 'pulse', outcome)
    A.Bill(src, p, 'pulse')
    return outcome
end

local function onAbort(src)
    sessions[src] = nil
end

local function register()
    if not (NZA.Proc and NZA.Proc.Register) then return false end
    local c = pc()
    NZA.Proc.Register('pulse', {
        perm = (Config.Assess and Config.Assess.Interact and Config.Assess.Interact.perm) or 'assess',
        maxDist = 3.0,
        minTime = c.minTime or 8,
        maxTime = c.maxTime or 240,
        consume = 'finish',
        states = { alive = true, wounded = true, arrest = true, dead = true },
        record = (Config.Assess or {}).Records ~= false,
        easyTime = c.easyTime or 6,
        onStart = onStart,
        onFinish = onFinish,
        onAbort = onAbort,
    })
    return true
end

if not register() then
    CreateThread(function()
        Wait(0)
        if not register() then NZA.Warn('NZA.Proc missing - Check Pulse is not available') end
    end)
end

NZA.Bus.On('player:unloaded', function(src) sessions[src] = nil end)
