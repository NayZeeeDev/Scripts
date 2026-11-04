--[[
    NAYZEEE AMBULANCE - Examine Patient (client)                       NUI app 'exam'

    The medic kneels, the camera goes above the patient (Config.Assess.Exam.camera) and the
    8 body groups (NZA.Const.Groups) ALL get a label on the body, whatever the pose (a group with
    nothing wrong reads Healthy). A live medic snapshot (NZA.Patient.Watch) is turned into what a
    medic can actually see:
      * per group: status Healthy / Minor / Serious / Critical / Treated
      * per injury: type, severity and plain findings (bleeding word, retained projectile
        suspected, contamination, deformity / open fracture, burn depth & area, X-ray results,
        treatments already done)
      * hidden problems (internal bleeding, haemothorax, pneumothorax, tamponade, airway) only
        appear once a check found them (patient.meta.findings, server NZA.Findings)
      * WHAT TO DO, where the medic looks for it - this is how treatments start (the third eye only
        has the check, Config.Care.thirdEye):
          - on an injury: the care step(s) the server plan lists for it (NZA.Care, snap.care) and the
            treatments from NZA.ExamRoutes with the items you carry (have / need) and a Start button
          - on a group: steps for that body part that belong to no single wound (collar, pelvic binder)
          - on the patient card: whole-body needs (CPR, airway, oxygen, fluids, warmth, pain relief,
            help up, take to hospital, scans and drains at the hospital ...)
          - 'More tools': every other option for this patient (remove a device, monitor, crutches ...)
      * a General card: consciousness, skin, lips, visible bleeding, last pulse / breathing, devices

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
        The route with id 'stopbleed' is used by the "Bleed control" button.

    NUI callbacks: exam:touch { group }, exam:treat { id, route }, exam:step { index } (a care step
                   from the plan), exam:tool { name } (an interaction option), exam:action
                   { action, group }, exam:close
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
    -- no bleeding word where nothing runs out: a closed fracture bleeds into the tissue (swelling),
    -- a burn weeps (server rule: NZA.Patients.VisibleBleed)
    local inside = t == 'burn' or (t == 'fracture' and not (type(inj.fracture) == 'table' and inj.fracture.kind == 'open'))
    if t ~= 'contusion' and t ~= 'internal' and not inside and not settled then add(word, tone) end

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

-- bleeding you can see: internal bleeding and a closed fracture bleed inside (the plan's rule)
local function externalBleed(inj)
    -- same rule as the server's NZA.Patients.VisibleBleed: a burn weeps, a bruise bleeds under the skin
    if inj.type == 'internal' or inj.type == 'burn' or inj.type == 'contusion' then return false end
    if inj.type == 'fracture' and not (type(inj.fracture) == 'table' and inj.fracture.kind == 'open') then return false end
    return true
end

local function visibleBleed(snap)
    local total = 0
    for _, inj in ipairs(snap.injuries or {}) do
        if externalBleed(inj) then total = total + math.max(0, tonumber(inj.bleed) or 0) end
    end
    return total
end

-- the wound "Bleed control" would treat: the worst one the 'stopbleed' route can actually do
-- (in the selected group first). nil = nothing to control, so the button stays dark.
local function stopTarget(snap, group)
    local route = A.FindRoute('stopbleed')
    if not route then return nil end
    local best, bestBleed = nil, 0
    for pass = group and 1 or 2, 2 do
        for _, inj in ipairs(snap.injuries or {}) do
            local R = NZA.Const.Region[inj.region]
            local b = tonumber(inj.bleed) or 0
            if externalBleed(inj) and b > bestBleed and (pass == 2 or (R and R.group == group)) then
                local ok, avail = true, true
                if type(route.available) == 'function' then ok, avail = pcall(route.available, inj, snap) end
                if ok and avail then best, bestBleed = inj, b end
            end
        end
        if best then break end
    end
    return best, route
end

-- The server plan (snap.care, NZA.Care) placed where the medic looks for it: a step with a wound
-- goes on that wound's card, a step with a body part on that group's card, the rest on the
-- patient card. Each row says what would run (route / option, supplies) or why not here.
local function placePlan(s, snap, groups, ivById, counts)
    local general = {}
    local Care = NZA.Care
    if not (Care and Care.Describe and Care.Action) or type(snap.care) ~= 'table' or not s then return general end
    for idx, step in ipairs(snap.care) do
        if type(step) == 'table' and step.c then
            local d = Care.Describe(step)
            local a = Care.Action(s.entity, s.target, step, snap, counts) or {}
            local row = {
                idx = idx, code = d.code, inj = step.i, title = d.title, why = d.why, where = d.where, urgent = d.urgent,
                icon = d.icon or a.icon, can = a.can == true, kind = a.kind, id = a.id, label = a.label,
                items = a.items or {}, reason = (not a.can) and a.reason or nil,
            }
            -- the Hospital tag already says it
            if row.where == 'hospital' and row.reason == NZA.L('care.at_hospital') then row.reason = nil end
            local iv = step.i and ivById[step.i]
            local R = step.r and NZA.Const.Region[step.r]
            local g = R and groups[R.group]
            if iv then
                iv.steps[#iv.steps + 1] = row
                iv.planned = true
                -- the treatment the step picked goes first on the card
                if row.kind == 'route' and row.id then
                    for k, r in ipairs(iv.routes) do
                        if r.id == row.id then
                            if k > 1 then table.remove(iv.routes, k) table.insert(iv.routes, 1, r) end
                            row.onCard = true
                            break
                        end
                    end
                end
            elseif g then
                g.todo[#g.todo + 1] = row
            else
                general[#general + 1] = row
            end
        end
    end
    return general
end

-- Every other option for this patient ('More tools'): what used to be on the third eye and is
-- not a care step right now - removing a device, the monitor, blood typing, crutches ... Moving
-- the patient stays on the third eye; pulse and breathing are on the check's dock.
local TOOL_SKIP = { nza_examine = true, nza_pulse = true, nza_breathing = true }
local function toolsFor(s)
    local out = {}
    if not s or not s.entity or s.entity == 0 or not DoesEntityExist(s.entity) then return out end
    if not (NZA.Interact and NZA.Interact.Options) then return out end
    local Care = NZA.Care
    for _, opt in ipairs(NZA.Interact.Options(s.entity, true)) do
        local n = opt.name
        if not TOOL_SKIP[n] and not opt.guided and not (Care and Care.Handling and Care.Handling(n)) then
            out[#out + 1] = { name = n, label = opt.label, icon = opt.icon }
        end
    end
    return out
end

local function buildView(s, snap)
    local fs = findingsFor(snap)
    local counts = {}
    local groups = {}
    local ivById = {}
    for _, g in ipairs(NZA.Const.Groups) do
        groups[g.name] = { status = 'healthy', worst = 0, injuries = {}, notes = {}, pain = 0, treated = 0, todo = {} }
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
                steps = {},
                heal = inj.heal and math.floor(inj.heal) or 0,
            }
            ivById[inj.id] = iv
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
            steps = {},
        }
        ivById[ci.id] = iv
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

    local todo = placePlan(s, snap, groups, ivById, counts)

    local out = {}
    for name, g in pairs(groups) do
        local status = sevStatus(g.worst)
        if g.worst == 0 and g.treated > 0 then status = 'treated' end
        -- something still to do here but nothing serious: at least 'minor', never 'healthy'
        if status == 'healthy' and #g.todo > 0 then status = 'minor' end
        local function busy(iv) return #iv.steps > 0 or #iv.routes > 0 end
        table.sort(g.injuries, function(a, b)
            if busy(a) ~= busy(b) then return busy(a) end
            if a.severity ~= b.severity then return a.severity > b.severity end
            return tostring(a.id) < tostring(b.id)
        end)
        out[name] = { status = status, statusLabel = L('gs_' .. status), injuries = g.injuries, notes = g.notes, pain = g.pain, todo = g.todo }
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

    local bleedWord = totalBleedWord(visibleBleed(snap))
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
        todo = todo,
        tools = toolsFor(s),
        canStop = stopTarget(snap) ~= nil,
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

local function viewFor(s, snap)
    return buildView(s, snap)
end

local function openUi(s, snap)
    local groups = {}
    for _, g in ipairs(NZA.Const.Groups) do
        groups[#groups + 1] = { name = g.name, label = L('group_' .. g.name) }
    end
    NZA.UI.Open(APP, {
        locale = A.Locale(),
        groups = groups,
        view = viewFor(s, snap),
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
    if NZA.Care and NZA.Care.MarkChecked then NZA.Care.MarkChecked(target, snap.pid) end

    TaskTurnPedToFaceEntity(me, entity, 800)
    Wait(500)
    if exam ~= s then return end
    local ec = A.Cfg('Exam')
    A.Anim(me, ec.anim, 1)
    A.Cam(ec.camera or 'topdown', entity, { height = ec.height or 2.6 })
    A.Track(APP, anchors(entity))
    openUi(s, snap)

    s.stop = NZA.Patient.Watch(target, function(fresh, reason)
        if exam ~= s then return end
        if not fresh then
            cleanup((reason == 'far' or reason == 'denied') and reason or 'gone')
            return
        end
        s.snap = fresh
        NZA.UI.Send(APP, 'view', viewFor(s, fresh))
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
        -- carrying someone or pushing a stretcher meanwhile: no kneeling check on top of that
        local moving = NZA.Transport and NZA.Transport.Busy and NZA.Transport.Busy()
        if moving == 'carry' or moving == 'push' then return end
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

-- Start buttons that move or hand over the patient (the 'hospital', 'standup', 'release' and
-- 'bodybag' steps): the medic stands up and the check does not come back on top of the carry,
-- the stretcher or the walk
local MOVES = {
    nza_tr_carry = true, nza_tr_onstretcher = true, nza_tr_tobed = true, nza_askwalk = true,
    nza_tr_helpup = true, nza_calls_release = true, nza_bodybag = true,
}

-- a module's own interaction option (the check closes, the option runs like a third-eye click)
local function runOption(opt)
    local s = exam
    if not s then return end
    local entity, target = s.entity, s.target
    local moves = MOVES[opt.name] == true
    s.keepPose = not moves
    cleanup('treat')
    CreateThread(function()
        NZA.Interact.Run(opt, entity)
        if not moves then reopenLater(entity, target) end
    end)
end

-- the plan step behind a Start button: by index, checked against code / wound (the plan may have
-- moved on since the view was sent)
local function stepFrom(s, data)
    local plan = type(s.snap.care) == 'table' and s.snap.care or {}
    local idx, code, inj = tonumber(data.index), data.code, data.inj
    local function same(st) return type(st) == 'table' and (code == nil or st.c == code) and (inj == nil or st.i == inj) end
    if idx and same(plan[idx]) then return plan[idx] end
    if code == nil then return nil end
    for _, st in ipairs(plan) do
        if same(st) then return st end
    end
    return nil
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
    local idle = A.Cfg('Exam').idle
    if idle and idle.dict then
        A.Anim(PlayerPedId(), idle, 1)
        s.idleUntil = GetGameTimer() + 2500
    end
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
        -- the worst wound the bleed-control route can really treat, in the selected group first
        local best, route = stopTarget(s.snap, GROUP_BONE[data.group] and data.group or nil)
        if not best then
            A.Toast('assess.no_bleeding', 'info')
            return
        end
        runRoute(route, best)
    end
end)

-- a 'what to do' Start button: the care step's exam route for that wound, else the module's option
NZA.UI.On(APP, 'step', function(data, cb)
    cb({ ok = true })
    local s = exam
    if not s or type(data) ~= 'table' or not NZA.Care then return end
    local step = stepFrom(s, data)
    if not step then
        A.Toast('care.done_already', 'info')
        return
    end
    local act, why = NZA.Care.Resolve(s.entity, s.target, step, s.snap)
    if not act then
        NZA.UI.Toast({ title = L('title'), message = why or NZA.L('care.no_action'), type = 'error' })
        return
    end
    if act.kind == 'route' then return runRoute(act.route, act.inj) end
    runOption(act.opt)
end)

-- 'More tools': any interaction option this patient has (also the ones the short third eye hides)
NZA.UI.On(APP, 'tool', function(data, cb)
    cb({ ok = true })
    local s = exam
    if not s or type(data) ~= 'table' or type(data.name) ~= 'string' then return end
    local opt = NZA.Interact.Get(data.name)
    if not opt or TOOL_SKIP[data.name] or not NZA.Interact.Allowed(opt, s.entity, true) then
        NZA.UI.Toast({ title = L('title'), message = L('route_unavailable'), type = 'error' })
        return
    end
    runOption(opt)
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
