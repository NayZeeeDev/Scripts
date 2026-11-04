--[[
    NAYZEEE AMBULANCE - Care plan (NZA.Care)

    What a patient still needs, most urgent first. It drives the guided third eye, the
    'Care steps' card in the head-to-toe check and the steps card on the HUD, so a medic
    always knows what to do next. Only OUTSTANDING steps are listed: a step disappears
    once the treatment is done.

      NZA.Care.Plan(p)      → { { c = code, r = region?, i = injury id?, w = 'field'|'hospital',
                                  u = true when life threatening }, ... }
      NZA.Care.Compact(p)   → the first Config.Care.maxSteps steps (state bag summary.plan)

    Codes, in priority order (locales/en/care.lua has the texts):
      extricate  NPC trapped in a wreck (cut free first)         field
      cpr        cardiac arrest                                  field
      bleed      a bleed a medic can stop right here: pressure / packing / dressing
                 (Config.Firstaid.StopBleed) or a tourniquet on the arm or leg
                 (per wound). Never internal bleeding, a closed fracture or a burn  field
      airway     airway swelling / closed, tube in the gullet    field
      breathing  low oxygen, water or smoke in the lungs         field
      recovery   unconscious and snoring: on their side          field
      chest      tension pneumothorax (found)                    field
      overdose   opioid overdose                                 field
      binder     pelvic fracture or pelvic bleeding, no binder   field
      fluids     big blood loss                                  field
      warm       body temperature low                            field
      collar     neck / spine injury without a collar            field
      splint     fracture not held still (per wound)             field
      burn       burn needing cooling or a dressing (per wound)  field
      wound      open wound needing a dressing / stitches        field
      cool       bruise (ice pack)                               field
      pain       a lot of pain (no painkiller working)           field
      infection  infected wound (antibiotics)                    field
      standup    stable now: help them up                        field (wounded only)
      scan       hidden bleeding suspected (ultrasound)          hospital
      internal   internal bleeding found (angiography)           hospital
      drain      blood in the chest (chest drain)                hospital
      tamponade  blood around the heart                          hospital
      bullet     bullet / fragment still inside                  hospital
      xray       broken arm / leg that must be imaged before it
                 is set / cast (players only, once)              hospital
      xray_read  the X-ray is taken: read the film on a lightbox hospital
      reduce     read, displaced: set the bone                   hospital
      cast       read and aligned: put on a cast                 hospital
                 (NPC patients skip the X-ray: set → cast; Config.Care.xrayNpc)
      graft      deep burn (skin graft)                          hospital
      hospital   take them to hospital (when any hospital step)  -
      release    NPC from a call with nothing left: release      field
      bodybag    the patient died                                field

    Findings decide what a medic can know: internal bleeding and chest conditions only
    become their own step once something found them (p.meta.findings, same rules as the
    head-to-toe check); before that the plan says 'scan'. Bleeding nobody can press on
    (inside the belly / pelvis / chest, a closed fracture) never becomes 'bleed': it shows
    as binder (pelvis), splint (the fracture), fluids (blood loss) and the hospital steps.

    X-rays (Config.Care.xrayOnlyLimbs / xrayNpc): a player gets 'xray' only for a broken arm
    or leg that still has to be set or cast, and only until a film showed it. NPC patients
    never get one: their fractures go splint → set the bone → cast (xray_ortho skips the film).

      NZA.Care.BleedHere(p, inj)   → bool   the 'bleed' rule for one wound
      NZA.Care.OptionBleed(p)      → press, limb (mL/min) what 'Control bleeding' / 'Tourniquet' can
                                     take (summary sb / tb gate those two options)
      NZA.Care.XrayFree(p)         → bool   this patient's bones are set / cast without a film
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Care = NZA.Care or {}
local Care = NZA.Care

local function cfg(key, default)
    local c = Config.Care
    if type(c) ~= 'table' or c[key] == nil then return default end
    return c[key]
end

local function wcfg(key, default)
    local c = Config.Wounded
    if type(c) ~= 'table' or c[key] == nil then return default end
    return c[key]
end

local function status(p, inj)
    local Phys = NZA.Physiology
    if Phys and Phys.Status then
        local ok, s = pcall(Phys.Status, p, inj)
        if ok and s then return s end
    end
    return inj.status or 'open'
end

local function findings(p)
    return type(p.meta) == 'table' and type(p.meta.findings) == 'table' and p.meta.findings or {}
end

-- internal injuries count once something found them (head-to-toe check rules)
local function internalKnown(inj, fs)
    if inj.treat and (inj.treat.coiled or inj.treat.xrayMarked) then return true end
    local R = NZA.Const.Region[inj.region]
    for key, f in pairs(fs) do
        if type(f) == 'table' then
            if f.injury == inj.id then return true end
            if key == ('internal_suspected_' .. inj.region) then return true end
            if R and key == ('internal_suspected_' .. R.group) then return true end
        end
    end
    return false
end

local function condKnown(fs, cond)
    for _, f in pairs(fs) do
        if type(f) == 'table' and f.cond == cond then return true end
    end
    return false
end

local function spineBone(inj)
    local b = inj.fracture and inj.fracture.bone
    return b == 'c_spine' or b == 't_spine' or b == 'l_spine'
end

local function loss(p)
    local P = NZA.Patients
    if P and P.Loss then
        local ok, v = pcall(P.Loss, p)
        if ok and type(v) == 'number' then return v end
    end
    return 0
end

-- ════════════════════════════════════════════════════════════════════════
-- BLEEDING A MEDIC CAN STOP
-- ════════════════════════════════════════════════════════════════════════

-- wound types the tourniquet route takes (client/modules/firstaid.lua 'tourniquet' exam route)
local TQ_TYPES = { gunshot = true, shrapnel = true, stab = true, laceration = true, fracture = true }

local function listHas(list, v)
    if type(list) ~= 'table' then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- 'bleed' only when the bleeding comes out of a wound AND one of the bleed-control procedures
-- would take it now, with the procedures' own limits:
--   · pressure / packing / a dressing (NZA.Proc 'stopbleed'): Config.Firstaid.StopBleed.types,
--     minBleed (abrasions abrasionMin), and FA.Plan still has a step left (not packed + dressed)
--   · a tourniquet: an arm or leg, the tourniquet route's wound types (an open fracture too),
--     at least Config.Firstaid.Tourniquet.minBleed, no tourniquet on it yet
-- Internal bleeding and a closed fracture bleed inside (binder / splint / fluids / hospital);
-- a burn weeps (burn care); a wound under a tourniquet, packed or bandaged is 'controlled'.
-- An abrasion oozing under abrasionMin or a dressed wound still seeping gets 'wound' instead.
local function bleedHere(p, inj)
    local kind = inj.type
    if kind == 'internal' or kind == 'burn' or kind == 'contusion' then return false end
    if kind == 'fracture' and not (type(inj.fracture) == 'table' and inj.fracture.kind == 'open') then return false end
    local b = tonumber(inj.bleed) or 0
    if b < 0.5 or status(p, inj) ~= 'open' then return false end
    local FA = NZA.Firstaid
    if not (FA and type(FA.Cfg) == 'function') then return true end      -- no first aid module: any open bleed
    local sb = FA.Cfg('StopBleed')
    local types = type(sb.types) == 'table' and sb.types or { 'gunshot', 'shrapnel', 'stab', 'laceration', 'abrasion' }
    local treats = type(FA.BleedTreats) == 'function' and FA.BleedTreats(inj, sb) or listHas(types, kind)
    if treats and b >= (tonumber(sb.minBleed) or 0.5)
        and (kind ~= 'abrasion' or b >= (tonumber(sb.abrasionMin) or 2.0)) then
        local plan = true
        if type(FA.Plan) == 'function' then
            local ok, res = pcall(FA.Plan, p, inj)
            plan = ok and res ~= nil
        end
        if plan then return true end
    end
    local R = NZA.Const.Region[inj.region]
    if R and R.tourniquet and TQ_TYPES[kind] then
        local tc = FA.Cfg('Tourniquet')
        local covered = type(FA.TqCovers) == 'function' and FA.TqCovers(p, inj.region)
        if not covered and b >= (tonumber(tc.minBleed) or 15) then return true end
    end
    return false
end
Care.BleedHere = bleedHere

-- mL/min each bleed-control OPTION on the patient (third eye, the check's 'More tools') can work on,
-- so 'Control bleeding' / 'Tourniquet' only show when their procedure has a wound to take (else
-- they answer "Nothing is bleeding." / "No bleeding arm or leg for a tourniquet."). Summary sb / tb.
--   press  the 'stopbleed' procedure's own pick (server/modules/firstaid_procs.lua bleedFilter)
--   limb   bleeding you can see on an arm or leg that has no tourniquet on it yet (the tourniquet pick)
-- → press, limb  (nil, nil without the first aid module)
function Care.OptionBleed(p)
    local FA = NZA.Firstaid
    if type(p) ~= 'table' or not (FA and type(FA.Cfg) == 'function') then return nil, nil end
    local sb = FA.Cfg('StopBleed')
    local press, limb = 0, 0
    for _, inj in pairs(p.injuries or {}) do
        local kind = inj.type
        local shown = type(FA.ShownBleed) == 'function' and FA.ShownBleed(p, inj) or (tonumber(inj.bleed) or 0)
        local treats = type(FA.BleedTreats) == 'function' and FA.BleedTreats(inj, sb) or listHas(sb.types, kind)
        if treats and shown >= (tonumber(sb.minBleed) or 0.5)
            and (kind ~= 'abrasion' or shown >= (tonumber(sb.abrasionMin) or 2.0))
            and (type(FA.Plan) ~= 'function' or FA.Plan(p, inj) ~= nil) then
            press = press + shown
        end
        local b = tonumber(inj.bleed) or 0
        local inside = kind == 'internal' or kind == 'burn' or kind == 'contusion'
            or (kind == 'fracture' and not (type(inj.fracture) == 'table' and inj.fracture.kind == 'open'))
        local R = NZA.Const.Region[inj.region]
        if not inside and b >= 0.5 and R and R.tourniquet
            and not (type(FA.TqCovers) == 'function' and FA.TqCovers(p, inj.region)) then
            limb = limb + b
        end
    end
    return press, limb
end

-- broken bones of this patient are set / cast without an X-ray film first
local function xrayFree(p)
    return p.kind == 'npc' and cfg('xrayNpc', false) ~= true
end
Care.XrayFree = xrayFree

-- ════════════════════════════════════════════════════════════════════════
-- PLAN
-- ════════════════════════════════════════════════════════════════════════

-- the patient is at a hospital: in a bed / on a hospital point, or within Config.Care.hospitalRadius
-- of one. Hospital work is then done right here, without a 'take them to hospital' line first.
local function atHospital(p)
    local m = p.meta or {}
    if m.bed ~= nil or m.inBed then return true end
    local H = NZA.Hospitals
    if not (H and type(H.Nearest) == 'function' and NZA.Core and NZA.Core.PatientCoords) then return false end
    local ok, c = pcall(NZA.Core.PatientCoords, p)
    if not ok or not c then return false end
    local ok2, dept, dist = pcall(H.Nearest, c)
    return ok2 and dept ~= nil and dist ~= nil and dist <= (tonumber(cfg('hospitalRadius', 60.0)) or 60.0)
end
Care.AtHospital = atHospital

function Care.Plan(p)
    local out = {}
    if type(p) ~= 'table' then return out end
    local function add(c, extra)
        local s = { c = c, w = 'field' }
        if extra then for k, v in pairs(extra) do s[k] = v end end
        out[#out + 1] = s
    end

    if p.state == 'dead' then
        if not (p.meta and p.meta.bodybag) then add('bodybag') end
        return out
    end

    local c, d, fs = p.conditions or {}, p.devices or {}, findings(p)
    local npcCall = p.kind == 'npc' and type(p.meta) == 'table' and (p.meta.callId or p.meta.scene) ~= nil

    -- 0. trapped in a wreck: cut them free before anything else
    if p.kind == 'npc' and type(p.meta) == 'table' and p.meta.trapped then add('extricate', { u = true }) end
    local injuries = {}
    for _, inj in pairs(p.injuries or {}) do injuries[#injuries + 1] = inj end
    table.sort(injuries, function(a, b)
        if (a.bleed or 0) ~= (b.bleed or 0) then return (a.bleed or 0) > (b.bleed or 0) end
        if (a.severity or 0) ~= (b.severity or 0) then return (a.severity or 0) > (b.severity or 0) end
        return tostring(a.id) < tostring(b.id)
    end)

    -- 1. no pulse
    if p.state == 'arrest' then add('cpr', { u = true }) end

    -- 2. bleeding a medic can stop here (bleedHere: internal bleeding and a closed fracture
    --    bleed inside - binder / splint / fluids / hospital; burns get burn care)
    local bleeding = {}
    for _, inj in ipairs(injuries) do
        if bleedHere(p, inj) then
            bleeding[inj.id] = true
            add('bleed', { r = inj.region, i = inj.id, u = (inj.bleed or 0) >= 5 })
        end
    end
    local arrest = p.state == 'arrest'

    -- 3. airway & breathing
    local v = p.vitals or {}
    local meta = p.meta or {}
    local aw = c.airway
    local tube = meta.tube
    if not arrest and (aw and not d.intubated and (aw.kind == 'obstructed' or (aw.level or 0) >= 40))
        or (d.intubated and type(tube) == 'table' and tube.placed == 'oesophagus' and tube.detected) then
        add('airway', { u = true })
    end
    -- not breathing while down: CPR (the CPR module does the breaths too)
    if p.state == 'wounded' and v.avpu == 'U' and (v.breathing == 'absent' or v.breathing == 'agonal') then
        add('cpr', { u = true })
    end
    local hx = c.hypoxia
    local lowO2 = (tonumber(v.spo2) or 99) < cfg('spo2', 90)
    if not arrest and (lowO2 or (hx and ((hx.water or 0) > 0 or (hx.smoke or 0) > 0))) and not d.oxygen and not d.intubated then
        add('breathing', { u = (tonumber(v.spo2) or 99) < 85 })
    end
    -- unconscious and snoring / gurgling: on their side
    if p.state == 'wounded' and (v.avpu == 'P' or v.avpu == 'U') and not d.intubated and not meta.recovery
        and (v.airway == 'snoring' or v.airway == 'gurgling')
        and not (meta.carried or meta.stretcher or meta.bed or meta.inBed or meta.bay or meta.vehicle) then
        add('recovery')
    end
    if c.pneumothorax and c.pneumothorax.tension and condKnown(fs, 'pneumothorax') then add('chest', { u = true }) end
    local od = c.overdose
    if od and od.drug == 'opioid' and (od.amount or 0) >= 20 then add('overdose', { u = true }) end

    -- 4. circulation
    local pelvic = false
    for _, inj in ipairs(injuries) do
        if inj.region == 'pelvis' and (inj.type == 'fracture' or (inj.type == 'internal' and internalKnown(inj, fs))) and status(p, inj) ~= 'treated' then
            pelvic = true
        end
    end
    if pelvic and not d.binder then add('binder', { r = 'pelvis', u = true }) end
    if loss(p) >= cfg('loss', 0.20) then add('fluids', { u = loss(p) >= wcfg('lossDown', 0.30) * 0.8 }) end
    if ((p.temp or 37) < cfg('cold', 35.0) or c.hypothermia) and not d.foil then add('warm') end

    -- 5. injuries (field care)
    local hasSpine = c.spinal ~= nil
    for _, inj in ipairs(injuries) do
        if inj.type == 'fracture' and spineBone(inj) then hasSpine = true end
    end
    if hasSpine and not d.collar then add('collar', { r = 'neck' }) end

    local hospital = {}
    local function hosp(code, extra)
        local s = { c = code, w = 'hospital' }
        if extra then for k, v in pairs(extra) do s[k] = v end end
        hospital[#hospital + 1] = s
    end
    local internalHidden, hiddenHeavy = false, false
    local noFilm = xrayFree(p)
    local onlyLimbs = cfg('xrayOnlyLimbs', true) ~= false
    for _, inj in ipairs(injuries) do
        local t, kind, st = inj.treat or {}, inj.type, status(p, inj)
        local R = NZA.Const.Region[inj.region]
        if kind == 'fracture' and spineBone(inj) then
            -- broken neck / back: the collar step above (not a wound to close)
        elseif kind == 'fracture' then
            local f = inj.fracture or {}
            local limbSplint = R and R.splint and R.splint ~= 'collar' and R.splint ~= 'binder'
            if not (t.splinted or t.cast) and limbSplint then
                add('splint', { r = inj.region, i = inj.id, u = (inj.bleed or 0) >= 5 })
            end
            -- an open fracture still bleeding where no splint / binder / tourniquet holds it (head,
            -- face, chest ...): cover it (a dressing from the kit), never 'Stop the bleeding'
            if f.kind == 'open' and not bleeding[inj.id] and st == 'open' and not limbSplint
                and not (R and R.splint == 'binder') then
                add('wound', { r = inj.region, i = inj.id })
            end
            -- limbs: X-ray, set the bone, cast. Ribs, pelvis, skull ...: nothing to set or cast, so
            -- no X-ray step either (Config.Care.xrayOnlyLimbs = false brings it back for players)
            local castable = R and R.limb and true or false
            local cc = Config.Xray and Config.Xray.Cast and Config.Xray.Cast.regions
            if type(cc) == 'table' then castable = cc[inj.region] and true or false end
            -- one step at a time: take the X-ray → read the film → set the bone (displaced) → cast.
            -- Imaged once (treat.xray / xrayMarked) is enough; NPC patients need no film at all.
            local X = NZA.Xray
            local function filmStep()
                local pending = X and X.PendingFilm and X.PendingFilm(p.pid, inj.id)
                hosp(pending and 'xray_read' or 'xray', { r = inj.region, i = inj.id })
            end
            if castable then
                if not t.cast and ((inj.severity or 1) >= 2 or f.displaced) then
                    if not (t.xray or t.xrayMarked or noFilm) then filmStep()
                    elseif f.displaced and not t.reduced then hosp('reduce', { r = inj.region, i = inj.id })
                    else hosp('cast', { r = inj.region, i = inj.id }) end
                end
            elseif not onlyLimbs and not noFilm and R and R.xray and not t.xrayMarked and (inj.severity or 1) >= 2 then
                filmStep()
            end
        elseif kind == 'burn' then
            local deg = inj.burn and inj.burn.degree or 1
            if deg >= 3 and not t.grafted then
                if not (t.cooled or t.dressed) then add('burn', { r = inj.region, i = inj.id }) end
                hosp('graft', { r = inj.region, i = inj.id })
            elseif st ~= 'treated' and st ~= 'healing' then
                add('burn', { r = inj.region, i = inj.id })
            end
        elseif kind == 'internal' then
            -- only bleeds angiography can coil (Config.Angio.organs); the others stop on their own
            local organs = Config.Angio and Config.Angio.organs
            local organ = inj.internal and inj.internal.organ
            local coilable = type(organs) ~= 'table' or (organ ~= nil and organs[organ] == true)
            if coilable and not (t.coiled or t.sutured) and (inj.severity or 1) >= 2 and ((inj.bleed or 0) > 0 or (inj.bleedBase or 0) > 0) then
                local heavy = (inj.bleed or 0) >= 5
                if internalKnown(inj, fs) then hosp('internal', { r = inj.region, i = inj.id, u = heavy or nil })
                else
                    internalHidden = true
                    hiddenHeavy = hiddenHeavy or heavy
                end
            end
        elseif kind == 'contusion' then
            if not t.cooled and (inj.severity or 1) >= 2 then add('cool', { r = inj.region, i = inj.id }) end
        elseif kind == 'abrasion' and (inj.severity or 1) <= 1 then
            -- grazes heal by themselves
        elseif st ~= 'treated' and st ~= 'healing' and not bleeding[inj.id] then
            -- gunshot, shrapnel, stab, laceration, abrasion: covered but not closed yet (or seeping
            -- a little where pressure / a dressing has nothing left to do: dress or stitch it)
            add('wound', { r = inj.region, i = inj.id })
        end
        if (inj.retained or 0) > 0 and not t.extracted then hosp('bullet', { r = inj.region, i = inj.id }) end
    end

    local now = os.time()
    local function medOn(name) return type(p.meds) == 'table' and (tonumber(p.meds[name]) or 0) > now end
    local pain = tonumber(p.pain) or 0
    if pain >= cfg('pain', 60) and p.state ~= 'arrest' and not medOn('painkillers') and not medOn('morphine') then add('pain') end
    if c.infection and not medOn('antibiotics') then add('infection') end

    -- 6. chest & hidden bleeding (hospital)
    local drains = d.chestDrain or {}
    local function drained(side)
        if side == 'left' or side == 'right' then return drains[side] and true or false end
        return (drains.left or drains.right) and true or false
    end
    local hm = c.haemothorax
    local pn = c.pneumothorax
    local needDrain = false
    if hm and (hm.ml or 0) >= 300 and not drained(hm.side) then
        if condKnown(fs, 'haemothorax') then needDrain = true else internalHidden = true end
    end
    -- a collapsed lung that is not under pressure (or was needled) still needs a drain
    if pn and not pn.tension and not drained(pn.side) and condKnown(fs, 'pneumothorax') then needDrain = true end
    if needDrain then hosp('drain') end
    local tp = c.tamponade
    if tp and (tp.ml or 0) >= 50 then
        if condKnown(fs, 'tamponade') then hosp('tamponade', { u = true }) else internalHidden = true end
    end
    if c.pneumothorax and c.pneumothorax.tension and not condKnown(fs, 'pneumothorax') then internalHidden = true end
    -- a scan in the last 15 minutes counts, even when it could not see a small bleed yet
    local efast = type(p.meta) == 'table' and p.meta.efast
    local scanned = type(efast) == 'table' and (os.time() - (tonumber(efast.at) or 0)) < cfg('rescan', 900)
    if internalHidden and not scanned then table.insert(hospital, 1, { c = 'scan', w = 'hospital', u = hiddenHeavy or nil }) end

    -- 7. stable: back on their feet
    if p.state == 'wounded' then
        local P = NZA.Patients
        local ok, can = pcall(P.CanStand, p)
        if ok and can then add('standup') end
    end

    -- hospital work last, behind one 'take them to hospital' line - or, at the hospital, as
    -- ordinary steps to do here
    local here = #hospital > 0 and atHospital(p)
    if #hospital > 0 and not here then
        -- urgent when something there cannot wait (heavy internal bleed, blood around the heart)
        local urgent = nil
        for _, s in ipairs(hospital) do if s.u then urgent = true break end end
        add('hospital', { w = 'hospital', n = #hospital, u = urgent })
        for _, s in ipairs(hospital) do out[#out + 1] = s end
    elseif here then
        for _, s in ipairs(hospital) do s.w = 'field'; out[#out + 1] = s end
    end
    if #hospital == 0 and npcCall and p.state == 'alive' then
        -- walking wounded from a call with nothing left: let them go home
        local Calls = NZA.Calls
        local ok, can = true, true
        if Calls and Calls.Releasable then ok, can = pcall(Calls.Releasable, p) end
        if ok and can and #out == 0 then add('release') end
    end
    return out
end

function Care.Compact(p)
    local plan = Care.Plan(p)
    local max = math.max(1, math.floor(tonumber(cfg('maxSteps', 8)) or 8))
    while #plan > max do table.remove(plan) end
    return plan
end
