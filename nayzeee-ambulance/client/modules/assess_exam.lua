--[[
    NAYZEEE AMBULANCE - Examine Patient (client)                       NUI app 'exam'

    The medic kneels, the camera goes above the patient (Config.Assess.Exam.camera) and the
    8 body groups (NZA.Const.Groups) get labels anchored to bones. A live medic snapshot
    (NZA.Patient.Watch) is turned into what a medic can actually see:
      * per group: status Healthy / Minor / Serious / Critical / Treated
      * per injury: type, severity and plain findings (bleeding word, retained projectile
        suspected, contamination, deformity / open fracture, burn depth & area, X-ray results,
        treatments already done)
      * hidden problems (internal bleeding, haemothorax, pneumothorax, tamponade, airway) only
        appear once a check found them (patient.meta.findings, server NZA.Findings)
      * the next treatment(s) from NZA.ExamRoutes with the items you carry (have / need)
      * a General card: consciousness, skin, lips, last pulse / breathing result, devices
    Patient speech subtitles on open and when you touch a painful region (Config.Assess.Speech).

    NZA.ExamRoutes (any client module appends at file top level)
        { id, label, icon, perm, order,
          types = { 'laceration', ... } (injury types, or condition names for suspected
                   conditions: 'haemothorax', 'pneumothorax', 'tamponade', 'airway', 'hypoxia'),
          regions = nil | { 'chest', ... },
          items = { [Config.Items.x] = n },
          available = function(inj, snap) return bool, reasonText end,
              -- false + reason → shown greyed with the reason; false + nil → hidden
          run = function(target, inj, snap) end }
        Suspected conditions are passed as inj = { id = 'c:<finding key>', type = <condition>,
        condition = true, region = 'chest'|'neck', side = 'left'|'right'|nil, severity, finding }.
        The route with id 'stopbleed' is used by the "Stop bleeding" button.

    NUI callbacks: exam:touch { group }, exam:treat { id, route }, exam:action { action, group }, exam:close
    Callbacks used: nza:assess:exam (target)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Assess = NZA.Assess or {}
NZA.Assess.Start = NZA.Assess.Start or {}
NZA.ExamRoutes = NZA.ExamRoutes or {}
local A = NZA.Assess

local APP = 'exam'
local exam = nil   -- active session

local GROUP_BONE = {
    head = 31086, neck = 39317, chest = 24818, abdomen = 24816,
    l_arm = 61163, r_arm = 28252, l_leg = 63931, r_leg = 36864,
}
local GROUP_REGION = { head = 'head', neck = 'neck', chest = 'chest', abdomen = 'abdomen',
    l_arm = 'l_upper_arm', r_arm = 'r_upper_arm', l_leg = 'l_upper_leg', r_leg = 'r_upper_leg' }
local OPEN_TYPES = { gunshot = true, shrapnel = true, stab = true, laceration = true, abrasion = true, burn = true }
local PENETRATING = { gunshot = true, shrapnel = true, stab = true }
local TREAT_KEYS = { 'tourniquet', 'packed', 'bandaged', 'irrigated', 'anesthetized', 'sutured', 'dressed', 'extracted',
    'splinted', 'reduced', 'cast', 'cooled', 'debrided', 'grafted', 'coiled', 'drained' }
local COND_GROUP = { haemothorax = 'chest', pneumothorax = 'chest', tamponade = 'chest', hypoxia = 'chest', airway = 'neck', arrest = nil }

local function L(key, ...) return NZA.L('assess.' .. key, ...) end
local function has(list, v)
    if type(list) ~= 'table' then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- VIEW (what the medic can see)
-- ════════════════════════════════════════════════════════════════════════

local function bleedInfo(ml, controlled)
    ml = tonumber(ml) or 0
    if ml < 0.05 then return L('bleed_none'), 'dim' end
    if controlled and ml < 3 then return L('bleed_controlled'), 'teal' end
    if ml < 1 then return L('bleed_ooze'), 'dim' end
    if ml < 10 then return L('bleed_steady'), 'amber' end
    if ml < 60 then return L('bleed_heavy'), 'red' end
    return L('bleed_arterial'), 'red'
end

local function totalBleedWord(total)
    total = tonumber(total) or 0
    if total < 1 then return 'none' end
    if total < 10 then return 'light' end
    if total < 60 then return 'moderate' end
    if total < 150 then return 'heavy' end
    return 'massive'
end

local function boneLabel(bone)
    local k = 'core.bone_' .. tostring(bone)
    local s = NZA.L(k)
    if s == k then return (tostring(bone):gsub('_', ' ')) end
    return s
end

local function organLabel(organ)
    local k = 'core.organ_' .. tostring(organ)
    local s = NZA.L(k)
    if s == k then return tostring(organ) end
    return s
end

local function ago(snap, at)
    local now = tonumber(snap.updated) or 0
    local d = math.max(0, now - (tonumber(at) or now))
    if d < 60 then return L('ago_now') end
    return L('ago_min', math.floor(d / 60))
end

local function findingsFor(snap)
    return type(snap.meta) == 'table' and type(snap.meta.findings) == 'table' and snap.meta.findings or {}
end

-- internal injuries are only shown once something found them
local function internalKnown(inj, fs)
    if inj.treat and (inj.treat.coiled or inj.treat.xrayMarked) then return true end
    for key, f in pairs(fs) do
        if type(f) == 'table' then
            if f.injury == inj.id then return true end
            if key == ('internal_suspected_' .. inj.region) then return true end
            local R = NZA.Const.Region[inj.region]
            if R and key == ('internal_suspected_' .. R.group) then return true end
        end
    end
    return false
end

local function injuryFindings(inj, snap, fs)
    local out = {}
    local function add(text, tone) out[#out + 1] = { text = text, tone = tone or '' } end
    local t, treat = inj.type, inj.treat or {}
    local controlled = treat.tourniquet or treat.packed or treat.bandaged or treat.sutured
    local word, tone = bleedInfo(inj.bleed, controlled)
    local settled = (inj.status == 'treated' or inj.status == 'healing') and (tonumber(inj.bleed) or 0) < 1
    if t ~= 'contusion' and t ~= 'internal' and not settled then add(word, tone) end

    if t == 'gunshot' then
        if treat.extracted then add(L('f_extracted'), 'teal')
        elseif inj.exit == false or (inj.retained or 0) > 0 then add(L('f_no_exit'), 'amber')
        else add(L('f_exit')) end
    elseif t == 'shrapnel' and (inj.retained or 0) > 0 and not treat.extracted then
        add(L('f_fragments'), 'amber')
    end
    if (inj.retained or 0) > 0 and (treat.xray or treat.xrayMarked) and not treat.extracted then
        add(L('f_xray_retained', inj.retained, inj.retainedDepth or 0), 'amber')
    end
    if (t == 'laceration' or t == 'stab') and (inj.length or 0) > 0 then
        add(L((inj.depth or 0) >= 15 and 'f_size_deep' or 'f_size', inj.length))
    end
    if OPEN_TYPES[t] and t ~= 'burn' then
        local c = inj.contamination or 0
        if treat.irrigated then add(L('f_irrigated'), 'teal')
        elseif c >= 60 then add(L('f_dirty'), 'amber')
        elseif c >= 30 then add(L('f_some_dirt'))
        else add(L('f_clean')) end
    end
    if t == 'fracture' and inj.fracture then
        local fr = inj.fracture
        if fr.kind == 'open' then add(L('f_open_fracture'), 'red') end
        if fr.displaced then add(L('f_deformed', fr.angle or 10), 'amber') end
        if not fr.displaced and fr.kind ~= 'open' then
            local R = NZA.Const.Region[inj.region]
            add(L(R and R.limb == 'leg' and 'f_swelling_leg' or 'f_swelling'))
        end
        if treat.xray or treat.xrayMarked then
            add(L('f_xray_fracture', L('frac_' .. tostring(fr.kind)), boneLabel(fr.bone)), 'teal')
        end
    end
    if t == 'burn' and inj.burn then
        local b = inj.burn
        add(L('f_burn_' .. math.max(1, math.min(3, b.degree or 1)), b.area or 0), (b.degree or 1) >= 3 and 'red' or ((b.degree or 1) == 2 and 'amber' or ''))
        if (b.soot or 0) > 40 and not treat.cooled then add(L('f_soot')) end
    end
    if t == 'contusion' then add(L('f_bruise')) end
    if t == 'abrasion' and (inj.contamination or 0) >= 40 and not treat.irrigated then add(L('f_grit')) end
    if t == 'internal' then
        local organ = inj.internal and inj.internal.organ
        if treat.coiled then add(L('f_coiled'), 'teal')
        else add(L('f_internal', organ and (treat.xrayMarked or treat.coiled) and organLabel(organ) or L('f_internal_unknown')), 'red') end
    end
    -- possible hidden damage behind a penetrating wound
    if PENETRATING[t] and (inj.region == 'abdomen' or inj.region == 'pelvis' or inj.region == 'back') then
        local hidden = false
        for _, other in ipairs(snap.injuries or {}) do
            if other.type == 'internal' and other.region == inj.region and not internalKnown(other, fs) then hidden = true end
        end
        if hidden or (inj.severity or 1) >= 2 then add(L('f_check_internal'), 'amber') end
    end
    if PENETRATING[t] and (inj.region == 'chest' or inj.region == 'back') then
        add(L('f_check_chest'), 'amber')
    end
    -- tourniquet time
    local tq = snap.devices and snap.devices.tourniquet and snap.devices.tourniquet[inj.region]
    if tq and treat.tourniquet then
        local mins = math.floor(math.max(0, (tonumber(snap.updated) or 0) - (tonumber(tq) or 0)) / 60)
        add(L('f_tq_time', mins), mins >= 60 and 'red' or (mins >= 30 and 'amber' or 'teal'))
    end
    return out
end

local function doneList(inj)
    local out = {}
    local treat = inj.treat or {}
    for _, k in ipairs(TREAT_KEYS) do
        if treat[k] then out[#out + 1] = L('treat_' .. k) end
    end
    return out
end

local function routesFor(inj, snap, counts)
    local out = {}
    for _, r in ipairs(NZA.ExamRoutes) do
        if type(r) == 'table' and r.id and r.run then
            local typeOk = r.types == nil or has(r.types, inj.type)
            local regionOk = r.regions == nil or has(r.regions, inj.region)
            if typeOk and regionOk and (r.perm == nil or NZA.Perm(r.perm)) then
                local avail, reason = true, nil
                if type(r.available) == 'function' then
                    local ok, a, b = pcall(r.available, inj, snap)
                    if ok then avail, reason = a and true or false, b else avail = false end
                end
                if avail or reason then
                    local items, allHave = {}, true
                    if type(r.items) == 'table' then
                        for name, need in pairs(r.items) do
                            if counts[name] == nil then counts[name] = A.ItemCount(name) end
                            local haveN = counts[name]
                            local needN = tonumber(need) or 1
                            items[#items + 1] = { label = A.ItemLabel(name), have = haveN, need = needN, ok = haveN >= needN }
                            if haveN < needN then allHave = false end
                        end
                        table.sort(items, function(a, b) return a.label < b.label end)
                    end
                    out[#out + 1] = {
                        id = r.id, label = r.label or r.id, icon = r.icon, order = tonumber(r.order) or 50,
                        avail = avail, ok = avail and allHave, reason = (not avail and reason) or (not allHave and L('route_missing')) or nil,
                        items = items,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.avail ~= b.avail then return a.avail end
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)
    while #out > 4 do table.remove(out) end
    return out
end

local function conditionInjuries(snap, fs)
    local list = {}
    local conds = snap.conditions or {}
    for key, f in pairs(fs) do
        if type(f) == 'table' and f.cond and conds[f.cond] ~= nil and COND_GROUP[f.cond] then
            local c = conds[f.cond]
            local sev = 3
            if (f.cond == 'pneumothorax' and c.tension) or (f.cond == 'haemothorax' and (tonumber(c.ml) or 0) >= 1000)
                or (f.cond == 'tamponade' and (tonumber(c.ml) or 0) >= 120) or (f.cond == 'airway' and c.kind == 'obstructed') then
                sev = 4
            end
            local group = f.group or COND_GROUP[f.cond]
            list[#list + 1] = {
                id = 'c:' .. key, type = f.cond, condition = true, region = GROUP_REGION[group] or 'chest', group = group,
                side = f.side, severity = sev, status = 'open', finding = f, treat = {},
            }
        end
    end
    return list
end

local function sevStatus(sev)
    if sev >= 4 then return 'critical' end
    if sev >= 3 then return 'serious' end
    if sev >= 1 then return 'minor' end
    return 'healthy'
end

local function painFactor(snap)
    local f = 1.0
    local meds = snap.meds or {}
    local now = tonumber(snap.updated) or 0
    if (tonumber(meds.morphine) or 0) > now then f = f * 0.4 end
    if (tonumber(meds.painkillers) or 0) > now then f = f * 0.7 end
    return f
end

local function buildView(snap)
    local fs = findingsFor(snap)
    local counts = {}
    local groups = {}
    for _, g in ipairs(NZA.Const.Groups) do
        groups[g.name] = { status = 'healthy', worst = 0, injuries = {}, notes = {}, pain = 0, treated = 0 }
    end
    local toTreat = 0
    local pf = painFactor(snap)

    local function push(gname, iv, sev, active, pain)
        local g = groups[gname]
        if not g then return end
        g.injuries[#g.injuries + 1] = iv
        if active then
            if sev > g.worst then g.worst = sev end
            toTreat = toTreat + 1
        else
            g.treated = g.treated + 1
        end
        g.pain = math.max(g.pain, math.floor((pain or 0) * pf + 0.5))
    end

    for _, inj in ipairs(snap.injuries or {}) do
        local R = NZA.Const.Region[inj.region]
        if R and (inj.type ~= 'internal' or internalKnown(inj, fs)) then
            local active = inj.status == 'open' or inj.status == 'controlled' or inj.status == nil
            local iv = {
                id = inj.id, region = inj.region, regionLabel = NZA.Util.RegionLabel(inj.region),
                type = inj.type, typeLabel = NZA.Util.InjuryLabel(inj.type),
                icon = (NZA.Const.InjuryTypes[inj.type] or {}).icon,
                severity = inj.severity or 1, sevLabel = L('sev_' .. (inj.severity or 1)),
                status = inj.status or 'open', statusLabel = L('status_' .. (inj.status or 'open')),
                findings = injuryFindings(inj, snap, fs),
                done = doneList(inj),
                routes = active and routesFor(inj, snap, counts) or {},
                heal = inj.heal and math.floor(inj.heal) or 0,
            }
            push(R.group, iv, inj.severity or 1, active, inj.pain)
        end
    end

    for _, ci in ipairs(conditionInjuries(snap, fs)) do
        local f = ci.finding
        local label = L('cond_' .. ci.type)
        if ci.side then label = L('cond_side', label, L('side_' .. (ci.side == 'left' and 'l' or 'r'))) end
        local findings = {}
        if f.text then findings[#findings + 1] = { text = f.text, tone = 'amber' } end
        findings[#findings + 1] = { text = L('found_by', L('source_' .. tostring(f.source or 'exam')), ago(snap, f.at)), tone = 'dim' }
        local iv = {
            id = ci.id, region = ci.region, regionLabel = NZA.Util.RegionLabel(ci.region),
            type = ci.type, typeLabel = label, suspected = true, icon = ci.type == 'airway' and 'wind' or 'lungs',
            severity = ci.severity, sevLabel = L('suspected'),
            status = 'open', statusLabel = L('suspected'),
            findings = findings, done = {},
            routes = routesFor(ci, snap, counts),
        }
        push(ci.group, iv, ci.severity, true, 50)
    end

    -- group notes (visible without a check)
    local conds = snap.conditions or {}
    local v = snap.vitals or {}
    if conds.concussion and (v.avpu ~= 'U') then
        local n = groups.head.notes
        n[#n + 1] = { text = L((conds.concussion.grade or 1) >= 2 and 'n_concussion_2' or 'n_concussion_1'), tone = 'amber' }
        if groups.head.worst < 2 then groups.head.worst = 2 end
    end
    if v.pupils and v.pupils ~= 'normal' then
        local n = groups.head.notes
        n[#n + 1] = { text = L('n_pupils_' .. tostring(v.pupils)), tone = 'red' }
        if groups.head.worst < 3 then groups.head.worst = 3 end
    end
    if conds.spinal and not (snap.devices and snap.devices.collar) then
        local g = conds.spinal.level == 'cervical' and 'neck' or 'chest'
        local n = groups[g].notes
        n[#n + 1] = { text = L('n_spinal_' .. tostring(conds.spinal.level or 'cervical')), tone = 'red' }
        if groups[g].worst < 3 then groups[g].worst = 3 end
    end
    -- a hidden abdominal bleed makes the belly tense
    for _, inj in ipairs(snap.injuries or {}) do
        if inj.type == 'internal' and not internalKnown(inj, fs) and (inj.severity or 1) >= 2 then
            local R = NZA.Const.Region[inj.region]
            local g = R and groups[R.group]
            if g and not g.rigid then
                g.rigid = true
                g.notes[#g.notes + 1] = { text = L('n_rigid'), tone = 'amber' }
                if g.worst < 2 then g.worst = 2 end
            end
        end
    end

    local out = {}
    for name, g in pairs(groups) do
        local status = sevStatus(g.worst)
        if g.worst == 0 and g.treated > 0 then status = 'treated' end
        table.sort(g.injuries, function(a, b)
            if (#a.routes > 0) ~= (#b.routes > 0) then return #a.routes > 0 end
            if a.severity ~= b.severity then return a.severity > b.severity end
            return tostring(a.id) < tostring(b.id)
        end)
        out[name] = { status = status, statusLabel = L('gs_' .. status), injuries = g.injuries, notes = g.notes, pain = g.pain }
    end

    -- general observations
    local general = {}
    local function gen(icon, text, tone) general[#general + 1] = { icon = icon, text = text, tone = tone or '' } end
    local avpu = v.avpu or 'A'
    gen('brain', L('avpu_' .. avpu), avpu == 'A' and '' or (avpu == 'V' and 'amber' or 'red'))
    local loss = (tonumber(snap.lossPct) or 0) / 100
    if snap.state == 'dead' then
        gen('alert', L('g_dead'), 'red')
    else
        if loss >= 0.30 then gen('drop', L('g_skin_shock'), 'red')
        elseif loss >= 0.15 then gen('drop', L('g_skin_pale'), 'amber')
        elseif (tonumber(snap.temp) or 37) < 35 then gen('thermo', L('g_cold'), 'amber')
        else gen('drop', L('g_skin_ok'), '') end
        if (tonumber(v.spo2) or 98) < 90 then gen('lungs', L('g_blue_lips'), 'red') end
        if snap.state == 'arrest' or (tonumber(v.rr) or 14) <= 0 then gen('lungs', L('g_no_breathing_visible'), 'red')
        elseif (tonumber(v.rr) or 14) > 28 then gen('lungs', L('g_fast_breathing'), 'amber') end
    end
    local pulse = fs.pulse
    if type(pulse) == 'table' and pulse.rate then
        gen('pulse', L('g_last_pulse', pulse.rate, L('site_' .. tostring(pulse.site or 'radial')), L('strength_' .. tostring(pulse.strength or 'normal')), ago(snap, pulse.at)), 'teal')
    end
    local br = fs.breathing
    if type(br) == 'table' and br.rate then
        gen('lungs', L('g_last_breathing', br.rate, L('call_' .. tostring(br.call or 'skip')), ago(snap, br.at)), 'teal')
    end
    for key, f in pairs(fs) do
        if type(f) == 'table' and not f.group and key ~= 'pulse' and key ~= 'breathing' and f.text then
            gen('alert', f.text, 'amber')
        end
    end
    local devices = {}
    local d = snap.devices or {}
    if d.iv then devices[#devices + 1] = L('dev_iv') end
    if d.collar then devices[#devices + 1] = L('dev_collar') end
    if d.binder then devices[#devices + 1] = L('dev_binder') end
    if d.oxygen then devices[#devices + 1] = L('dev_oxygen') end
    if d.intubated then devices[#devices + 1] = L('dev_intubated') end
    if d.foil then devices[#devices + 1] = L('dev_foil') end

    local bleedWord = totalBleedWord(snap.bleedTotal)
    return {
        name = snap.name, sex = snap.sex, age = snap.age, state = snap.state, stateLabel = L('state_' .. tostring(snap.state)),
        triage = snap.triage, avpu = avpu,
        bleed = bleedWord, bleedLabel = L('tb_' .. bleedWord),
        stabilized = snap.stabilized == true,
        clock = (snap.state == 'wounded' and not snap.stabilized) and math.floor(tonumber(snap.clock) or 0) or nil,
        toTreat = toTreat,
        groups = out,
        general = general,
        devices = devices,
        canStop = A.FindRoute('stopbleed') ~= nil and (tonumber(snap.bleedTotal) or 0) >= 1,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION
-- ════════════════════════════════════════════════════════════════════════

function A.FindRoute(id)
    for _, r in ipairs(NZA.ExamRoutes) do
        if type(r) == 'table' and r.id == id then return r end
    end
    return nil
end

local function say(level, force)
    local s = exam
    if not s or not s.snap then return end
    local sc = A.Cfg('Speech')
    if sc.enabled == false then return end
    local snap = s.snap
    if snap.kind == 'player' and not sc.players then return end
    if snap.state == 'arrest' or snap.state == 'dead' then return end
    local avpu = (snap.vitals and snap.vitals.avpu) or 'A'
    if avpu == 'U' then return end
    local now = GetGameTimer()
    if not force and now - (s.spoke or 0) < (sc.cooldown or 4) * 1000 then return end
    local lines = (sc.lines or {})[snap.sex == 'f' and 'f' or 'm'] or (sc.lines or {}).m
    if type(lines) ~= 'table' then return end
    local lv = sc.levels or {}
    local group
    if avpu == 'P' then
        group = 'groan'
    elseif level >= (lv.severe or 70) then
        group = 'severe'
    elseif level >= (lv.moderate or 45) then
        group = 'moderate'
    elseif level >= (lv.mild or 20) then
        group = 'mild'
    else
        group = 'none'
    end
    if avpu == 'V' and math.random() < 0.5 then group = 'groan' end
    local list = lines[group]
    if type(list) ~= 'table' or #list == 0 then return end
    s.spoke = now
    NZA.UI.Speech(snap.name, list[math.random(#list)], sc.duration or 3800)
end

local function cleanup(reason, fromJs)
    local s = exam
    if not s then return end
    exam = nil
    if s.stop then pcall(s.stop) end
    A.Untrack(APP)
    A.CamStop()
    if not s.keepPose then A.StopAnim(PlayerPedId()) end
    if not fromJs then NZA.UI.Close(APP) end
    if A.Busy() == 'exam' then A.SetBusy(nil) end
    if reason and reason ~= 'closed' and reason ~= 'treat' and reason ~= 'action' then
        A.Toast('assess.exam_closed_' .. reason, 'warning')
    end
end

local function anchors(ped)
    local defs = {}
    for g, bone in pairs(GROUP_BONE) do defs[g] = { entity = ped, bone = bone } end
    defs.center = { entity = ped, bone = 24817 }
    return defs
end

local function openUi(s, snap)
    local groups = {}
    for _, g in ipairs(NZA.Const.Groups) do
        groups[#groups + 1] = { name = g.name, label = L('group_' .. g.name) }
    end
    NZA.UI.Open(APP, {
        locale = A.Locale(),
        groups = groups,
        view = buildView(snap),
        patient = { name = snap.name, sex = snap.sex, npc = snap.kind == 'npc' },
        perms = { pulse = NZA.Perm(A.Cfg('Interact').perm or 'assess'), breathing = NZA.Perm(A.Cfg('Interact').perm or 'assess') },
    }, { focus = true, cursor = true })
end

local function begin(entity, target, quiet)
    local me = PlayerPedId()
    local ok, res, info = pcall(lib.callback.await, 'nza:assess:exam', false, target)
    if not ok or not res then
        A.SetBusy(nil)
        NZA.UI.Toast({ title = L('title'), message = (type(info) == 'string' and info) or L('err_generic'), type = 'error' })
        return
    end
    local snap = NZA.Patient.Get(target)
    if type(snap) ~= 'table' then
        A.SetBusy(nil)
        A.Toast('assess.err_patient', 'error')
        return
    end
    local s = { entity = entity, target = target, snap = snap, started = GetGameTimer() }
    exam = s

    TaskTurnPedToFaceEntity(me, entity, 800)
    Wait(500)
    if exam ~= s then return end
    local ec = A.Cfg('Exam')
    A.Anim(me, ec.anim, 1)
    A.Cam(ec.camera or 'topdown', entity, { height = ec.height or 2.6 })
    A.Track(APP, anchors(entity))
    openUi(s, snap)
    if A.Cfg('Speech').onOpen ~= false and not quiet then
        SetTimeout(700, function() if exam == s then say(tonumber(snap.pain) or 0, true) end end)
    end

    s.stop = NZA.Patient.Watch(target, function(fresh, reason)
        if exam ~= s then return end
        if not fresh then
            cleanup((reason == 'far' or reason == 'denied') and reason or 'gone')
            return
        end
        s.snap = fresh
        NZA.UI.Send(APP, 'view', buildView(fresh))
    end, { initial = false, maxDist = (ec.maxDistance or 4.0) + 1.0 })

    -- distance / own state guard
    CreateThread(function()
        local maxD = ec.maxDistance or 4.0
        while exam == s do
            Wait(250)
            if exam ~= s then break end
            if not DoesEntityExist(entity) then cleanup('gone') break end
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then cleanup('down') break end
            if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) > maxD then cleanup('far') break end
            -- keep kneeling (other scripts may clear tasks); come back down after a touch idle
            local me = PlayerPedId()
            if s.idleUntil then
                if GetGameTimer() > s.idleUntil then
                    s.idleUntil = nil
                    A.Anim(me, ec.anim, 1, true)
                end
            elseif ec.anim and not A.IsKneeling(me) and not IsEntityPlayingAnim(me, ec.anim.dict, ec.anim.clip, 3) then
                A.Anim(me, ec.anim, 1)
            end
        end
    end)
end

function A.Start.exam(entity, target, quiet)
    if exam then cleanup('closed') end
    A.SetBusy('exam')
    begin(entity, target, quiet)
end

-- after a treatment, come back to the exam once the minigame is over; when we do not come
-- back (moved away, option off, patient gone) the medic stands up again
local function standUp()
    local me = PlayerPedId()
    if exam or A.Busy() or NZA.UI.Top() ~= nil then return end
    if A.IsKneeling(me) or IsEntityPlayingAnim(me, 'amb@medic@standing@tendtodead@base', 'base', 3) then A.StopAnim(me) end
end

local function reopenLater(entity, target)
    local ec = A.Cfg('Exam')
    CreateThread(function()
        Wait(1200)
        local deadline = GetGameTimer() + (ec.reopenWait or 600) * 1000
        while GetGameTimer() < deadline do
            local busyNow = NZA.UI.Top() ~= nil or (lib.progressActive and lib.progressActive()) or A.Busy() ~= nil
                or (NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() ~= nil)
            if not busyNow then break end
            Wait(400)
        end
        Wait(300)
        if exam or A.Busy() or NZA.UI.Top() ~= nil then return end
        local ok = ec.reopenAfterTreat ~= false and DoesEntityExist(entity)
            and not (NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown())
            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) <= 3.0
        if ok then
            A.Start.exam(entity, target, true)
        else
            standUp()
        end
    end)
end

local function findInjury(s, id)
    for _, inj in ipairs(s.snap.injuries or {}) do
        if inj.id == id then return inj end
    end
    for _, ci in ipairs(conditionInjuries(s.snap, findingsFor(s.snap))) do
        if ci.id == id then return ci end
    end
    return nil
end

local function runRoute(route, inj)
    local s = exam
    if not s then return end
    local entity, target, snap = s.entity, s.target, s.snap
    s.keepPose = true
    cleanup('treat')
    CreateThread(function()
        local ok, err = pcall(route.run, target, inj, snap)
        if not ok then NZA.Warn(('exam route "%s" failed: %s'):format(tostring(route.id), tostring(err))) end
        reopenLater(entity, target)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'touch', function(data, cb)
    cb({ ok = true })
    local s = exam
    if not s or type(data) ~= 'table' then return end
    local g = data.group
    if not GROUP_BONE[g] then return end
    local view = buildView(s.snap)
    local pain = view.groups[g] and view.groups[g].pain or 0
    local idle = A.Cfg('Exam').idle
    if idle and idle.dict then
        A.Anim(PlayerPedId(), idle, 1)
        s.idleUntil = GetGameTimer() + 2500
    end
    if A.Cfg('Speech').onTouch ~= false and pain >= ((A.Cfg('Speech').levels or {}).mild or 20) then say(pain) end
end)

NZA.UI.On(APP, 'treat', function(data, cb)
    local s = exam
    if not s or type(data) ~= 'table' then return cb({ ok = false }) end
    local route = A.FindRoute(data.route)
    local inj = findInjury(s, data.id)
    if not route or not inj then return cb({ ok = false }) end
    if route.perm and not NZA.Perm(route.perm) then
        A.Toast('assess.err_perm', 'error')
        return cb({ ok = false })
    end
    if type(route.available) == 'function' then
        local ok, avail, reason = pcall(route.available, inj, s.snap)
        if not ok or not avail then
            NZA.UI.Toast({ title = L('title'), message = (ok and reason) or L('route_unavailable'), type = 'error' })
            return cb({ ok = false })
        end
    end
    if type(route.items) == 'table' then
        for name, need in pairs(route.items) do
            if A.ItemCount(name) < (tonumber(need) or 1) then
                NZA.UI.Toast({ title = L('title'), message = L('err_item', A.ItemLabel(name)), type = 'error' })
                return cb({ ok = false })
            end
        end
    end
    cb({ ok = true })
    runRoute(route, inj)
end)

NZA.UI.On(APP, 'action', function(data, cb)
    cb({ ok = true })
    local s = exam
    if not s or type(data) ~= 'table' then return end
    local entity, target = s.entity, s.target
    if data.action == 'pulse' or data.action == 'breathing' then
        s.keepPose = true
        cleanup('action')
        CreateThread(function()
            local fn = A.Start[data.action]
            if fn then fn(entity, target, A.Cfg('Exam').reopenAfterTreat ~= false) end
            reopenLater(entity, target)
        end)
    elseif data.action == 'stopbleed' then
        local route = A.FindRoute('stopbleed')
        if not route then return end
        -- worst bleeding injury, in the selected group first
        local best, bestBleed = nil, 0
        for pass = 1, 2 do
            for _, inj in ipairs(s.snap.injuries or {}) do
                local R = NZA.Const.Region[inj.region]
                local inGroup = pass == 2 or (R and R.group == data.group)
                if inGroup and inj.type ~= 'internal' and (tonumber(inj.bleed) or 0) > bestBleed then
                    best, bestBleed = inj, tonumber(inj.bleed) or 0
                end
            end
            if best then break end
        end
        if not best or bestBleed < 0.5 then
            A.Toast('assess.no_bleeding', 'info')
            return
        end
        runRoute(route, best)
    end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    cleanup('closed', true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if exam then
        A.Untrack(APP)
        A.CamStop()
        ClearPedTasks(PlayerPedId())
        exam = nil
    end
end)
