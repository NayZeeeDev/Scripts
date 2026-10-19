--[[
    NAYZEEE AMBULANCE - Check Breathing (server)          NZA.Proc 'breathing' (perm assess)

    Start: turns the live patient into what a medic can see and hear:
      * a breath schedule from the real respiratory rate and breathing pattern
        (normal / laboured / shallow / agonal gasps / apnoea), depth of every breath
      * 'What you see' signs: dusky lips & nail beds (SpO2 < 90), accessory muscles
        (laboured), gurgling (fluid in the airway / drowning), stridor or snoring (airway),
        asymmetric chest movement (big pneumo/haemothorax), shallow / agonal breathing,
        flail segment (comminuted rib fractures)
      * the breath sound of each of the 6 lung zones (R/L upper, mid, lower) and its air
        entry: vesicular, reduced, absent (pneumothorax / haemothorax side), crackles
        (drowning), wheeze (smoke), stridor / gurgling (airway), silence (apnoea).
        Chest drains and intubation change what you hear (an oesophageal tube: no air entry
        on either side, the belly gurgles; a mainstem tube: the left side goes quiet).
      Schedule and zones go to the client obfuscated (NZA.Assess.Encode).
    Stethoscope: Config.Items.stethoscope enables step 2 (never consumed).

    Finish: scores the breath count against the schedule, the listening coverage and the
    call, records findings (NZA.Findings: breathing, haemothorax_suspected_<side>,
    pneumothorax_suspected_<side>, aspiration_suspected, bronchospasm_suspected,
    airway_compromise, apnoea, tube_oesophageal) and returns the result card.

    Client result payload (ctx.finish):
      { nonce, countStart = ms, countMs = ms, taps = { ms, ... }, noRise = bool,
        listened = { ru = s, rm = s, rl = s, lu = s, lm = s, ll = s }, call = 'normal'|'reduced_l'|
        'reduced_r'|'absent_l'|'absent_r'|'crackles'|'wheeze'|'airway'|'none' }
    Registers: NZA.Proc 'breathing'. Uses: NZA.Assess.*, NZA.Findings.*
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
local A = NZA.Assess
local U = NZA.Util

local sessions = {}

local ZONES = { 'ru', 'rm', 'rl', 'lu', 'lm', 'll' }
local SOUND = { vesicular = 0, reduced = 1, absent = 2, crackles = 3, wheeze = 4, stridor = 5, gurgle = 6, silent = 7 }
local CALLS = { normal = true, reduced_l = true, reduced_r = true, absent_l = true, absent_r = true,
    crackles = true, wheeze = true, airway = true, none = true }

local function bc()
    return (Config.Assess and Config.Assess.Breathing) or {}
end

local function rnd(a, b) return a + math.random() * (b - a) end
local function clamp(n, a, b) if n < a then return a elseif n > b then return b end return n end
local function L(key, ...) return NZA.L('assess.' .. key, ...) end

-- ════════════════════════════════════════════════════════════════════════
-- TRUTH
-- ════════════════════════════════════════════════════════════════════════

local function sideKey(side) return side == 'left' and 'l' or 'r' end

local function describe(p)
    local c = bc()
    local v = p.vitals or {}
    local cond = p.conditions or {}
    local dev = p.devices or {}
    local rr = math.floor((tonumber(v.rr) or 14) + 0.5)
    local pattern = v.breathing or 'normal'
    local apnoea = p.state == 'arrest' or p.state == 'dead' or rr <= 0 or pattern == 'absent'
    local intubated = dev.intubated == true
    local airway = v.airway or 'clear'
    if intubated then airway = 'secured' end

    local zones = {}
    for _, z in ipairs(ZONES) do zones[z] = { sound = apnoea and 'silent' or 'vesicular', entry = apnoea and 0 or 1 } end
    local drained = type(dev.chestDrain) == 'table' and dev.chestDrain or {}
    local sides = { l = { state = 'normal', conds = {} }, r = { state = 'normal', conds = {} } }

    local function set(z, sound, entry)
        local cur = zones[z]
        -- keep the worse of two problems on the same zone
        local rank = { vesicular = 0, crackles = 1, wheeze = 1, stridor = 1, gurgle = 1, reduced = 2, absent = 3, silent = 4 }
        if (rank[sound] or 0) >= (rank[cur.sound] or 0) then cur.sound = sound end
        cur.entry = math.min(cur.entry, entry)
    end

    if not apnoea then
        -- pneumothorax: air on top, the whole side goes quiet
        local pn = cond.pneumothorax
        if pn and pn.side then
            local s = sideKey(pn.side)
            local isDrained = drained[pn.side] or pn.decompressed
            local big = pn.tension or (tonumber(pn.size) or 0) >= (c.pneumoAbsent or 30)
            if isDrained then big = false end
            if big then
                set(s .. 'u', 'absent', 0.04); set(s .. 'm', 'absent', 0.06); set(s .. 'l', 'absent', 0.1)
                sides[s].state = 'absent'
            elseif not isDrained or (tonumber(pn.size) or 0) > 10 then
                set(s .. 'u', 'reduced', 0.35); set(s .. 'm', 'reduced', 0.45); set(s .. 'l', 'reduced', 0.6)
                if sides[s].state ~= 'absent' then sides[s].state = 'reduced' end
            end
            sides[s].conds[#sides[s].conds + 1] = 'pneumothorax'
        end
        -- haemothorax: blood pools low, the base goes silent first
        local hx = cond.haemothorax
        if hx and hx.side then
            local s = sideKey(hx.side)
            local ml = tonumber(hx.ml) or 0
            if ml >= (c.haemoAbsent or 1000) then
                set(s .. 'l', 'absent', 0.03); set(s .. 'm', 'absent', 0.12); set(s .. 'u', 'reduced', 0.45)
                sides[s].state = 'absent'
            elseif ml >= 300 then
                set(s .. 'l', 'absent', 0.15); set(s .. 'm', 'reduced', 0.5)
                if sides[s].state ~= 'absent' then sides[s].state = 'reduced' end
            elseif ml >= 80 then
                set(s .. 'l', 'reduced', 0.6)
                if sides[s].state == 'normal' then sides[s].state = 'reduced' end
            end
            if ml >= 80 then sides[s].conds[#sides[s].conds + 1] = 'haemothorax' end
        end
    end

    local hyp = cond.hypoxia
    local water = hyp and hyp.cause == 'drowning' and (tonumber(hyp.water) or 0) or 0
    local crackles = not apnoea and water >= (c.drowningCrackles or 150)
    local wheeze = not apnoea and hyp ~= nil and hyp.cause == 'smoke'
    local aw = cond.airway
    local stridor = not apnoea and airway ~= 'secured' and ((aw and (aw.kind == 'obstructed' or aw.kind == 'swelling')) or airway == 'obstructed' or airway == 'snoring')
    local gurgle = not apnoea and airway ~= 'secured' and (airway == 'gurgling' or water >= (c.drowningCrackles or 150) * 2)

    if crackles then
        for _, s in ipairs({ 'r', 'l' }) do
            set(s .. 'l', 'crackles', 0.65); set(s .. 'm', 'crackles', 0.75)
        end
    end
    if wheeze then
        for _, z in ipairs(ZONES) do set(z, 'wheeze', 0.7) end
    end
    if stridor then
        set('ru', 'stridor', 0.5); set('lu', 'stridor', 0.5)
    elseif gurgle then
        set('ru', 'gurgle', 0.6); set('lu', 'gurgle', 0.6)
    end
    if not apnoea and (pattern == 'shallow' or pattern == 'agonal') then
        for _, z in ipairs(ZONES) do zones[z].entry = zones[z].entry * (pattern == 'agonal' and 0.4 or 0.6) end
    end

    -- a misplaced tube (meta.tube from the intubation module; devices.intubated stays true)
    local tube = type(p.meta) == 'table' and p.meta.tube or nil
    local epigastric = false
    if not apnoea and intubated and type(tube) == 'table' then
        if tube.placed == 'oesophagus' then
            -- the air goes into the stomach: no air entry over either lung, the belly gurgles
            epigastric = true
            for _, z in ipairs(ZONES) do zones[z].sound, zones[z].entry = 'absent', 0 end
            sides.l.state, sides.r.state = 'absent', 'absent'
        elseif tube.mainstem then
            -- too deep: the tip sits in the right main bronchus and the left lung barely fills
            set('lu', 'absent', 0.05); set('lm', 'absent', 0.08); set('ll', 'reduced', 0.3)
            sides.l.state = 'absent'
        end
    end

    -- the expected call (and acceptable secondary calls)
    local call, also, same = 'normal', {}, nil
    local function sideCall()
        local best, worst = nil, 0
        for _, s in ipairs({ 'r', 'l' }) do
            local w = sides[s].state == 'absent' and 2 or (sides[s].state == 'reduced' and 1 or 0)
            if w > worst then best, worst = s, w end
        end
        return best, worst
    end
    local sSide, sLevel = sideCall()
    if apnoea then
        call = 'none'
    elseif epigastric then
        -- both sides are silent on ventilation: either side call is right, 'airway' is close
        call, same = 'absent_l', { absent_r = true }
        also.reduced_l, also.reduced_r, also.airway = true, true, true
    elseif sLevel > 0 then
        call = (sLevel == 2 and 'absent_' or 'reduced_') .. sSide
        also[(sLevel == 2 and 'reduced_' or 'absent_') .. sSide] = true
        local other = sSide == 'r' and 'l' or 'r'
        if sides[other].state ~= 'normal' then also[(sides[other].state == 'absent' and 'absent_' or 'reduced_') .. other] = true end
        if crackles then also.crackles = true end
        if wheeze then also.wheeze = true end
        if stridor or gurgle then also.airway = true end
    elseif stridor or gurgle then
        call = 'airway'
        if crackles then also.crackles = true end
    elseif crackles then
        call = 'crackles'
        if wheeze then also.wheeze = true end
    elseif wheeze then
        call = 'wheeze'
    end

    -- what you see
    local look = {}
    local function see(key, tone, ...) look[#look + 1] = { key = key, tone = tone, text = L('see_' .. key, ...) } end
    local spo2 = tonumber(v.spo2) or 98
    if (v.avpu or 'A') == 'U' then see('unresponsive', 'bad') end
    if not apnoea then
        if spo2 < 90 then see('dusky', 'bad') end
        if pattern == 'labored' or rr > 26 or spo2 < 86 then see('accessory', 'warn') end
        if pattern == 'agonal' then see('agonal', 'bad') end
        if pattern == 'shallow' then see('shallow', 'warn') end
        if gurgle then see('gurgling', 'bad') end
        if stridor then see(airway == 'snoring' and 'snoring' or 'stridor', 'bad') end
        if epigastric then see('epigastric', 'bad')
        elseif sLevel == 2 then see('asym', 'warn', L('side_' .. sSide)) end
        for _, inj in pairs(p.injuries) do
            if inj.type == 'fracture' and inj.fracture and inj.fracture.bone == 'ribs' and (inj.severity or 1) >= 3
                and (inj.fracture.kind == 'comminuted' or inj.fracture.displaced) then
                see('flail', 'bad')
                break
            end
        end
        if #look == 0 then see('calm', 'ok') end
    elseif spo2 < 90 or p.state ~= 'alive' then
        see('dusky', 'bad')
    end

    return {
        rr = apnoea and 0 or rr, pattern = apnoea and 'absent' or pattern, apnoea = apnoea,
        zones = zones, sides = sides, call = call, also = also, same = same, look = look,
        crackles = crackles, wheeze = wheeze, stridor = stridor, gurgle = gurgle, epigastric = epigastric,
    }
end

local function buildBreaths(t, seconds)
    local list, total = {}, 0
    if t.apnoea then return list, 0 end
    local period = 60000 / math.max(2, t.rr)
    local depth = ({ normal = 0.7, labored = 1.0, shallow = 0.35, agonal = 0.85 })[t.pattern] or 0.7
    while total < seconds * 1000 and #list < 200 do
        local iv
        if t.pattern == 'agonal' then iv = period * rnd(0.6, 1.8) else iv = period * (1 + (math.random() - 0.5) * 0.16) end
        iv = clamp(math.floor(iv + 0.5), 900, 4000)
        list[#list + 1] = { iv = iv, d = clamp(depth * rnd(0.85, 1.12), 0.1, 1) }
        total = total + iv
    end
    return list, total
end

local function breathTimes(s, from, to)
    local out = {}
    if s.total <= 0 then return out end
    local base = math.floor(from / s.total) * s.total
    local guard = 0
    while base < to and guard < 8 do
        local acc = base
        for i = 1, #s.breaths do
            acc = acc + s.breaths[i].iv
            if acc >= from and acc < to then out[#out + 1] = acc end
            if acc >= to then break end
        end
        base = base + s.total
        guard = guard + 1
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- SCORING
-- ════════════════════════════════════════════════════════════════════════

local function callLabel(call) return L('call_' .. tostring(call or 'skip')) end

local function score(s, t, res)
    local c = bc()
    local fb = {}
    local function add(tone, key, ...) fb[#fb + 1] = { tone = tone, text = L(key, ...) } end
    local window = (c.countSeconds or 15) * 1000
    local factor = 60000 / window
    local out = { counted = nil, expected = 0, coverage = 0, callOk = false, callPartial = false }
    local pts = 0

    -- ── look & count (35 + 10)
    if res.noRise then
        if t.apnoea then
            pts = pts + 45
            out.counted = 0
            add('ok', 'fb_norise_ok')
        else
            add('bad', 'fb_norise_wrong')
        end
    else
        local cs = tonumber(res.countStart) or -1
        local cms = clamp(tonumber(res.countMs) or 0, 0, window + 1500)
        local taps = {}
        if type(res.taps) == 'table' then
            for i = 1, math.min(#res.taps, 120) do
                local x = tonumber(res.taps[i])
                if x and cs >= 0 and x >= cs and x <= cs + window + 600 then taps[#taps + 1] = x end
            end
        end
        if cms <= 0 then
            add('bad', 'fb_no_breath_count')
        elseif t.apnoea then
            out.counted = math.floor(#taps * factor + 0.5)
            add('bad', 'fb_counted_apnoea', out.counted)
        else
            local breaths = breathTimes(s, cs, cs + window)
            out.expected = #breaths
            out.counted = math.floor(#taps * factor + 0.5)
            local trueRate = #breaths * factor
            local err = math.abs(out.counted - trueRate) / math.max(trueRate, 12)
            pts = pts + 35 * clamp(1 - err * 2.2, 0, 1)
            if err <= 0.12 then add('ok', 'fb_rr_ok', out.counted, t.rr)
            else add(err <= 0.3 and 'warn' or 'bad', 'fb_rr_off', out.counted, t.rr) end
            -- timing: a tap within 0.7 s of a rise
            local used, hits = {}, 0
            for _, x in ipairs(taps) do
                for i, b in ipairs(breaths) do
                    if not used[i] and math.abs(x - (b + 400)) <= 700 then used[i] = true; hits = hits + 1; break end
                end
            end
            local precision = #taps > 0 and hits / #taps or 0
            local recall = #breaths > 0 and hits / #breaths or 0
            pts = pts + 10 * precision * recall
        end
    end

    -- ── listen (20)
    local listened = type(res.listened) == 'table' and res.listened or {}
    local need = c.listenSeconds or 1.8
    local n, left, right = 0, 0, 0
    for _, z in ipairs(ZONES) do
        if (tonumber(listened[z]) or 0) >= need then
            n = n + 1
            if z:sub(1, 1) == 'l' then left = left + 1 else right = right + 1 end
        end
    end
    out.coverage = n
    out.sidesDone = (left >= 2 and 1 or 0) + (right >= 2 and 1 or 0)
    if s.stetho then
        pts = pts + 20 * (n / 6)
        if out.sidesDone < 2 and not t.apnoea then add('warn', 'fb_both_sides') end
    elseif not t.apnoea then
        add('info', 'fb_no_stetho')
    end

    -- ── call (35)
    local call = CALLS[res.call] and res.call or nil
    if call and (call == t.call or (t.same and t.same[call])) then
        out.callOk = true
        pts = pts + 35
        if call ~= 'normal' then add('ok', 'fb_call_ok', callLabel(call)) end
    elseif call and t.also[call] then
        out.callPartial = true
        pts = pts + 20
        add('warn', 'fb_call_partial', callLabel(t.call))
    else
        add('bad', 'fb_call_wrong', callLabel(t.call))
    end
    -- calling something without listening to that side is a guess
    if call and call:match('_[lr]$') and s.stetho then
        local side = call:sub(-1)
        local heard = 0
        for _, z in ipairs(ZONES) do
            if z:sub(1, 1) == side and (tonumber(listened[z]) or 0) >= need then heard = heard + 1 end
        end
        if heard == 0 then
            pts = pts - 10
            add('warn', 'fb_guess')
        end
    end

    if t.apnoea and not res.noRise and call ~= 'none' then add('bad', 'fb_apnoea_missed') end
    return clamp(math.floor(pts + 0.5), 0, 100), fb, out
end

-- ════════════════════════════════════════════════════════════════════════
-- FINDINGS
-- ════════════════════════════════════════════════════════════════════════

local function addFindings(src, p, t, res, out, easy)
    local F = NZA.Findings
    local recorded = {}
    local function add(key, data, text)
        data.source = 'breathing'
        data.by = src
        F.Add(p.pid, key, data)
        recorded[#recorded + 1] = text
    end
    local call = res.call
    local credit = easy or out.callOk or out.callPartial

    if t.apnoea then
        if easy or res.noRise or call == 'none' then add('apnoea', { text = L('finding_apnoea') }, L('finding_apnoea')) end
        return recorded
    end
    -- a side call finds the conditions on that side (correct or partially correct)
    for _, s in ipairs({ 'r', 'l' }) do
        local sideName = s == 'r' and 'right' or 'left'
        local named = call == ('absent_' .. s) or call == ('reduced_' .. s)
        if t.sides[s].state ~= 'normal' and (easy or (credit and named)) then
            for _, name in ipairs(t.sides[s].conds) do
                local key = name .. '_suspected_' .. sideName
                local text = L('finding_' .. name, L('side_' .. s))
                add(key, { cond = name, side = sideName, group = 'chest', text = L('finding_reduced_side', L('side_' .. s)) }, text)
            end
        end
    end
    if t.crackles and (easy or (credit and (call == 'crackles' or t.call == 'crackles'))) then
        add('aspiration_suspected', { cond = 'hypoxia', group = 'chest', text = L('finding_crackles') }, L('finding_aspiration'))
    end
    if t.wheeze and (easy or (credit and (call == 'wheeze' or t.call == 'wheeze'))) then
        add('bronchospasm_suspected', { cond = 'hypoxia', group = 'chest', text = L('finding_wheeze') }, L('finding_bronchospasm'))
    end
    if (t.stridor or t.gurgle) and (easy or (credit and (call == 'airway' or t.call == 'airway'))) then
        add('airway_compromise', { cond = 'airway', group = 'neck', text = L(t.stridor and 'finding_stridor' or 'finding_gurgle') }, L('finding_airway'))
    end
    -- same key as the intubation module's capnography check, so the exam offers the re-tube route
    if t.epigastric and (easy or (credit and (call == 'absent_l' or call == 'absent_r' or call == 'airway'))) then
        add('tube_oesophageal', { cond = 'hypoxia', group = 'chest', text = L('finding_tube_oes') }, L('finding_tube_oes'))
    end
    local rate = easy and t.rr or out.counted
    if rate then
        F.Add(p.pid, 'breathing', { source = 'breathing', by = src, rate = rate, call = easy and t.call or call })
    end
    return recorded
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function hasStethoscope(src)
    local c = bc()
    if c.requireStethoscope == false then return true end
    local item = Config.Items and Config.Items.stethoscope
    if not item then return true end
    return NZA.Core.CheckItems(src, { [item] = 1 }) == true
end

local function onStart(src, p, payload)
    local c = bc()
    local t = describe(p)
    local breaths, total = buildBreaths(t, math.max(90, (c.maxTime or 300) * 0.5))
    local stetho = hasStethoscope(src)
    local seed = A.Seed()
    local values = { #breaths }
    for i = 1, #breaths do values[#values + 1] = breaths[i].iv end
    for i = 1, #breaths do values[#values + 1] = breaths[i].d * 1000 end
    for _, z in ipairs(ZONES) do
        values[#values + 1] = SOUND[t.zones[z].sound] or 0
        values[#values + 1] = t.zones[z].entry * 1000
    end
    sessions[src] = { pid = p.pid, truth = t, breaths = breaths, total = total, stetho = stetho, started = os.time() }
    return true, {
        k = seed,
        s = A.Encode(seed, values),
        look = t.look,
        stetho = stetho,
        countSeconds = c.countSeconds or 15,
        listenSeconds = c.listenSeconds or 1.8,
        noBreathAfter = c.noBreathAfter or 6,
        minTime = c.minTime or 10,
        keys = c.keys,
        patient = { name = p.name, sex = p.sex, npc = p.kind == 'npc' },
    }
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
    local t = s.truth
    local easy = type(session) == 'table' and session.easy == true
    local pts, fb, out
    if easy then
        pts = tonumber(Config.EasyMode and Config.EasyMode.score) or 78
        fb = { { tone = 'info', text = L('fb_easy') } }
        out = { counted = t.rr, coverage = 6, callOk = true }
        result.call = t.call
    end
    -- only whitelisted call ids reach scoring, NZA.Findings and the result rows
    if not CALLS[result.call] then result.call = nil end
    if not easy then
        pts, fb, out = score(s, t, result)
    end
    local recorded = addFindings(src, p, t, result, out, easy)
    local grade = U.Grade(pts)
    local summary = t.apnoea and L('summary_apnoea') or L('summary_breathing', t.rr, callLabel(t.call))
    local outcome = {
        score = pts, grade = grade, seconds = os.time() - s.started, easy = easy or nil,
        title = L('breath_result_title'),
        msg = summary,
        rows = {
            rate = { you = out.counted ~= nil and tostring(out.counted) or '--', patient = t.apnoea and L('none_word') or tostring(t.rr),
                     unit = L('per_min'), ok = out.counted ~= nil and math.abs(out.counted - t.rr) <= math.max(3, t.rr * 0.12) },
            pattern = { patient = L('pattern_' .. t.pattern) },
            call = { you = callLabel(result.call), patient = callLabel(t.call), ok = out.callOk, partial = out.callPartial },
            zones = { you = tostring(out.coverage or 0), total = 6, stetho = s.stetho },
        },
        zones = (function()
            local z = {}
            for _, k in ipairs(ZONES) do z[k] = t.zones[k].sound end
            return z
        end)(),
        feedback = fb,
        recorded = recorded,
        apnoea = t.apnoea or nil,
    }
    outcome.record = {
        summary = summary, score = pts, grade = grade, seconds = outcome.seconds, easy = easy or nil,
        found = { rate = out.counted, call = result.call, zones = out.coverage },
        truth = { rr = t.rr, pattern = t.pattern, call = t.call },
    }
    A.Outcome(src, nonce, outcome)
    A.Record(src, p, 'breathing', outcome)
    A.Bill(src, p, 'breathing')
    return outcome
end

local function onAbort(src)
    sessions[src] = nil
end

local function register()
    if not (NZA.Proc and NZA.Proc.Register) then return false end
    local c = bc()
    NZA.Proc.Register('breathing', {
        perm = (Config.Assess and Config.Assess.Interact and Config.Assess.Interact.perm) or 'assess',
        maxDist = 3.0,
        minTime = c.minTime or 10,
        maxTime = c.maxTime or 300,
        consume = 'finish',
        states = { alive = true, wounded = true, arrest = true, dead = true },
        record = (Config.Assess or {}).Records ~= false,
        easyTime = c.easyTime or 7,
        onStart = onStart,
        onFinish = onFinish,
        onAbort = onAbort,
    })
    return true
end

if not register() then
    CreateThread(function()
        Wait(0)
        if not register() then NZA.Warn('NZA.Proc missing - Check Breathing is not available') end
    end)
end

NZA.Bus.On('player:unloaded', function(src) sessions[src] = nil end)
