--[[
    NAYZEEE AMBULANCE - Ultrasound (server): eFAST scan, chest drain, needle decompression,
    pericardiocentesis

    The server owns the truth. A scan session gets IMAGE parameters for the six eFAST windows
    (how much fluid each window shows, whether the lung slides, how thick the effusion is) so the
    NUI can draw a live B-mode picture; the medic marks every window positive / negative and the
    server grades those marks against its own truth when the session finishes. Only then does the
    client receive the truth table, the graded windows and the authoritative treatment plan.

    Procedures (ARCHITECTURE §5.2, NZA.Proc.Register):
      'ultrasound'  perm Config.Ultrasound.Scan.perm        eFAST scan (location: cart / bay / field / easy)
      'chestdrain'  perm Config.Ultrasound.ChestDrain.perm  haemothorax / pneumothorax on payload.side
      'decompress'  perm Config.Ultrasound.Decompress.perm  tension pneumothorax, works anywhere
      'pericardio'  perm Config.Ultrasound.Pericardio.perm  cardiac tamponade (ultrasound guided)
    Rooms: patient.meta.bed.type must be in the section's `rooms`, or the patient lies within
      Scan.cartRange of an 'ultrasound' point, or patient.meta.bay is set (`bay`), or `field`;
      easy mode (NZA.Staff.Easy) skips every location requirement and only needs the supplies.

    Findings (assess module, guarded): haemothorax_suspected_<side>, pneumothorax_suspected_<side>,
      tamponade_suspected, us_internal_<injuryId> (reveals the internal bleed in the examination).
    Patient meta written: efast = { at, by, pos = { [window] = true }, score }.

    Net events: S→C 'nza:us:use' (kind) - a usable item was used; the client starts it on the
      nearest patient.
    Bus events emitted: ultrasound:scan (src, p, outcome), ultrasound:drain (src, p, outcome),
      ultrasound:decompress (src, p, outcome), ultrasound:pericardio (src, p, outcome).
    Lua API: NZA.Ultrasound.Truth(p) → truth, render · NZA.Ultrasound.Location(src, p, section, easy)
      → ok, where | false, err · NZA.Ultrasound.BasePlan(p) → steps
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Ultrasound = NZA.Ultrasound or {}
local US = NZA.Ultrasound
local U = NZA.Util

local WINDOWS = { 'ruq', 'luq', 'pelvis', 'cardiac', 'lung_r', 'lung_l' }
US.Windows = WINDOWS

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section)
    local c = Config.Ultrasound or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...)
    return NZA.L('ultrasound.' .. key, ...)
end

local function num(v, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    return v
end

-- { Config.Items key = n } → { [item name] = n }
local function itemsOf(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = Config.Items and Config.Items[key]
        n = math.floor(num(n, 0))
        if name and n > 0 then out[name] = n end
    end
    return out
end

local function hashSeed(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ str:byte(i)) * 16777619 % 4294967296
    end
    return math.floor(h % 2147483646) + 1
end

local function fail(err, ...)
    local key = 'ultrasound.err_' .. err
    local msg = NZA.L(key, ...)
    if msg == key then msg = L('err_generic') end
    return false, { err = err, msg = msg }
end

local function patientCoords(p)
    if NZA.Core and NZA.Core.PatientCoords then
        local ok, c = pcall(NZA.Core.PatientCoords, p)
        if ok and c then return c end
    end
    return nil
end

local function bill(src, p, amount, reasonKey, kind)
    amount = num(amount, 0)
    if amount <= 0 or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L(reasonKey), { medic = src, kind = kind })
    if not ok then NZA.Warn('ultrasound: billing failed: ' .. tostring(err)) end
end

local function findings()
    if cfg('Scan').findings == false then return nil end
    if NZA.Findings and type(NZA.Findings.Add) == 'function' then return NZA.Findings end
    return nil
end

local function addFinding(pid, key, data)
    local F = findings()
    if not F then return end
    local ok, err = pcall(F.Add, pid, key, data)
    if not ok then NZA.Warn('ultrasound: finding failed: ' .. tostring(err)) end
end

local function vitalsOf(p)
    local v = p.vitals or {}
    return {
        hr = v.ecgRate or v.hr, sys = v.sys, dia = v.dia, map = v.map, spo2 = v.spo2, rr = v.rr,
        rhythm = v.rhythm, etco2 = v.etco2, avpu = v.avpu,
    }
end

local function sideOf(s)
    if s == 'left' or s == 'right' then return s end
    return 'right'
end

-- ════════════════════════════════════════════════════════════════════════
-- WHERE (cart point / bed / ambulance bay / field / easy)
-- ════════════════════════════════════════════════════════════════════════

local function nearCart(p)
    local H = NZA.Hospitals
    if not (H and type(H.Points) == 'function') then return false end
    local c = patientCoords(p)
    if not c then return false end
    local range = num(cfg('Scan').cartRange, 2.6)
    local ok, list = pcall(H.Points, 'ultrasound')
    if not ok or type(list) ~= 'table' then return false end
    for _, pt in ipairs(list) do
        local pc = pt.coords
        if pc and pc.x then
            local dx, dy, dz = c.x - pc.x, c.y - pc.y, c.z - pc.z
            if math.sqrt(dx * dx + dy * dy) <= range and math.abs(dz) <= 2.5 then return true end
        end
    end
    return false
end

-- section: 'Scan' | 'ChestDrain' | 'Pericardio' → ok, where | false, err
function US.Location(src, p, section, easy)
    if easy then return true, 'easy' end
    local c = cfg(section)
    local meta = p.meta or {}
    if meta.bay ~= nil and c.bay ~= false then return true, 'bay' end
    local bed = meta.bed
    if section == 'Scan' then
        if type(bed) == 'table' and bed.type == 'ultrasound' then return true, 'cart' end
        if nearCart(p) then return true, 'cart' end
    else
        local rooms = c.rooms or {}
        if type(bed) == 'table' and rooms[bed.type] then return true, 'room' end
        if rooms.ultrasound and nearCart(p) then return true, 'room' end
    end
    if c.field == true then return true, 'field' end
    if section == 'Scan' then return false, 'need_cart' end
    return false, 'need_room'
end

-- ════════════════════════════════════════════════════════════════════════
-- TRUTH: what each eFAST window really shows
-- ════════════════════════════════════════════════════════════════════════

-- share of an organ's bleed that pools in each window (supine patient)
local SPREAD = {
    liver      = { ruq = 0.75, pelvis = 0.25 },
    spleen     = { luq = 0.7, pelvis = 0.2, ruq = 0.1 },
    bowel      = { ruq = 0.4, pelvis = 0.45, luq = 0.15 },
    mesenteric = { ruq = 0.4, pelvis = 0.45, luq = 0.15 },
    pelvic     = { pelvis = 0.85, ruq = 0.15 },
}

local function abdominalFluid(p)
    local vol = { ruq = 0, luq = 0, pelvis = 0 }
    local src = { ruq = {}, luq = {}, pelvis = {} }
    local now = os.time()
    for id, inj in pairs(p.injuries or {}) do
        local treat = inj.treat or {}
        if inj.type == 'internal' and not treat.coiled and inj.status ~= 'healing'
            and (inj.region == 'abdomen' or inj.region == 'pelvis' or inj.region == 'back') then
            local organ = inj.internal and inj.internal.organ or 'mesenteric'
            local spread = SPREAD[organ]
            if organ == 'kidney' then
                local right = (inj.spot and num(inj.spot.x, 0.5) or 0.5) < 0.5
                spread = right and { ruq = 0.55, pelvis = 0.1 } or { luq = 0.55, pelvis = 0.1 }
            end
            if spread then
                local sev = U.clamp(math.floor(num(inj.severity, 2)), 1, 4)
                local mins = math.max(0, (now - num(inj.created, now)) / 60)
                local base = num(inj.bleedBase, num(inj.bleed, 0))
                local ml = U.clamp(90 * sev + base * mins * 0.5, 0, 520 * sev)
                for w, share in pairs(spread) do
                    vol[w] = vol[w] + ml * share
                    src[w][#src[w] + 1] = id
                end
            end
        end
    end
    return vol, src
end

-- → truth { [window] = { pos, kinds = { 'free_fluid' | 'haemothorax' | 'pneumothorax' | 'tamponade' }, mm, ml, side, injuries } },
--   render { [window] = image parameters for the NUI }
function US.Truth(p)
    local vis = cfg('Scan').visible or {}
    local c = p.conditions or {}
    local truth, render = {}, {}
    for _, w in ipairs(WINDOWS) do
        truth[w] = { pos = false, kinds = {} }
        render[w] = {}
    end

    -- free fluid (haemoperitoneum)
    local vol, srcs = abdominalFluid(p)
    local minFree = num(vis.freeFluid, 120)
    for _, w in ipairs({ 'ruq', 'luq', 'pelvis' }) do
        local ml = vol[w]
        if ml >= minFree then
            local mm = U.round(U.clamp(ml / (w == 'pelvis' and 28 or 24), 3, 32), 0)
            truth[w].pos = true
            truth[w].kinds[#truth[w].kinds + 1] = 'free_fluid'
            truth[w].free = { ml = math.floor(ml), mm = mm, injuries = srcs[w] }
            render[w].free = mm
        end
    end

    -- haemothorax: fluid above the diaphragm, seen from the upper quadrants
    local h = c.haemothorax
    if h and num(h.ml, 0) >= num(vis.haemothorax, 80) then
        local mm = U.round(U.clamp(num(h.ml, 0) / 22, 5, 85), 0)
        local sides = h.side == 'both' and { 'right', 'left' } or { sideOf(h.side) }
        for _, s in ipairs(sides) do
            local w = s == 'left' and 'luq' or 'ruq'
            truth[w].pos = true
            truth[w].kinds[#truth[w].kinds + 1] = 'haemothorax'
            truth[w].pleural = { ml = math.floor(num(h.ml, 0)), mm = mm, side = s }
            render[w].pleural = mm
        end
    end

    -- pneumothorax: the lung stops sliding under the anterior probe
    local pn = c.pneumothorax
    if pn and (num(pn.size, 20) >= num(vis.pneumothorax, 5) or pn.tension) then
        local s = sideOf(pn.side)
        local w = s == 'left' and 'lung_l' or 'lung_r'
        truth[w].pos = true
        truth[w].kinds[#truth[w].kinds + 1] = 'pneumothorax'
        truth[w].ptx = { size = U.round(num(pn.size, 20), 0), side = s, tension = pn.tension == true }
        render[w].ptx = true
        render[w].size = U.round(num(pn.size, 20), 0)
    end
    for _, w in ipairs({ 'lung_r', 'lung_l' }) do
        if not render[w].ptx then render[w].slide = true end
    end

    -- tamponade: blood around the heart
    local tp = c.tamponade
    if tp and num(tp.ml, 0) >= num(vis.tamponade, 25) then
        local mm = U.round(U.clamp(num(tp.ml, 0) / 14, 3, 30), 0)
        truth.cardiac.pos = true
        truth.cardiac.kinds[1] = 'tamponade'
        truth.cardiac.effusion = { ml = math.floor(num(tp.ml, 0)), mm = mm }
        render.cardiac.effusion = mm
        render.cardiac.collapse = num(tp.ml, 0) >= 140
    end
    render.cardiac.arrest = p.state == 'arrest' or p.state == 'dead'
    return truth, render
end

-- ════════════════════════════════════════════════════════════════════════
-- TREATMENT PLAN
--   Steps the scan does not need to know about (visible in any exam): external bleeding and
--   retained fragments. The NUI adds scan steps from the medic's own marks; the outcome of a
--   finished scan carries the full plan built from the truth.
--   step = { id, kind, side?, regions?, items = { [Config.Items key] = n }, action? }
-- ════════════════════════════════════════════════════════════════════════

local function angioItems()
    local a = Config.Angio
    if type(a) == 'table' and type(a.items) == 'table' then return a.items end
    return nil
end

function US.BasePlan(p)
    local steps = {}
    local tq, wraps, regions = 0, 0, {}
    local frags, fragRegions = 0, {}
    for _, inj in pairs(p.injuries or {}) do
        local treat = inj.treat or {}
        local R = NZA.Const.Region[inj.region or '']
        if inj.type ~= 'internal' and num(inj.bleed, 0) >= 1.0 and inj.status == 'open'
            and not treat.tourniquet and not treat.packed and not treat.bandaged and not treat.sutured then
            if R and R.tourniquet then tq = tq + 1 else wraps = wraps + 1 end
            regions[#regions + 1] = inj.region
        end
        if (inj.type == 'gunshot' or inj.type == 'shrapnel') and num(inj.retained, 0) > 0 and not treat.extracted then
            frags = frags + 1
            fragRegions[#fragRegions + 1] = inj.region
        end
    end
    if tq + wraps > 0 then
        local items = {}
        if tq > 0 then items.tourniquet = tq end
        if wraps > 0 then items.bandage = wraps; items.gauze = wraps end
        steps[#steps + 1] = { id = 'bleeding', kind = 'bleeding', regions = regions, items = items, order = 10 }
    end
    if frags > 0 then
        steps[#steps + 1] = { id = 'fragments', kind = 'fragments', regions = fragRegions, items = { surgical_kit = 1 }, order = 90 }
    end
    return steps
end

local function fullPlan(p, truth)
    local steps = US.BasePlan(p)
    local c = p.conditions or {}
    local pn = c.pneumothorax
    if pn and pn.tension then
        steps[#steps + 1] = { id = 'decompress', kind = 'decompress', side = sideOf(pn.side), items = cfg('Decompress').items, action = 'decompress', order = 20 }
    end
    local drains = {}
    for _, w in ipairs({ 'ruq', 'luq' }) do
        if truth[w].pleural then drains[truth[w].pleural.side] = 'haemothorax' end
    end
    for _, w in ipairs({ 'lung_r', 'lung_l' }) do
        if truth[w].ptx and not drains[truth[w].ptx.side] then drains[truth[w].ptx.side] = 'pneumothorax' end
    end
    for _, s in ipairs({ 'right', 'left' }) do
        if drains[s] and not ((p.devices or {}).chestDrain or {})[s] then
            steps[#steps + 1] = { id = 'drain_' .. s, kind = 'chestdrain', side = s, cause = drains[s], items = cfg('ChestDrain').items, action = 'chestdrain', order = 30 }
        end
    end
    if truth.cardiac.pos then
        steps[#steps + 1] = { id = 'pericardio', kind = 'pericardio', items = cfg('Pericardio').items, action = 'pericardio', order = 40 }
    end
    if truth.ruq.free or truth.luq.free or truth.pelvis.free then
        steps[#steps + 1] = { id = 'angio', kind = 'angio', items = angioItems() or {}, order = 50 }
    end
    table.sort(steps, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return steps
end

-- ════════════════════════════════════════════════════════════════════════
-- SCAN (eFAST)
-- ════════════════════════════════════════════════════════════════════════

local scans = {}      -- [token-less key src] = { pid, truth, render, at }

local function scanStart(src, p, payload, info)
    local sc = cfg('Scan')
    local easy = info and info.easy
    local ok, where = US.Location(src, p, 'Scan', easy)
    if not ok then return fail(where) end
    local truth, render = US.Truth(p)
    scans[src] = { pid = p.pid, truth = truth, at = os.time() }
    local seed = hashSeed(p.pid .. ':us')
    return true, {
        where = where,
        seed = seed,
        study = ('US-%05d'):format(seed % 100000),
        patient = { name = p.name, sex = p.sex, age = p.age, bloodType = p.bloodType },
        vitals = vitalsOf(p),
        views = render,
        plan = US.BasePlan(p),
        drains = { left = ((p.devices or {}).chestDrain or {}).left == true, right = ((p.devices or {}).chestDrain or {}).right == true },
        labels = sc.labels ~= false,
        minSeen = num(sc.minSeen, 1.2),
        easy = easy,
    }
end

local function sanitizeMarks(raw)
    local marks, seen, measure = {}, {}, {}
    raw = type(raw) == 'table' and raw or {}
    local rm = type(raw.marks) == 'table' and raw.marks or {}
    local rs = type(raw.seen) == 'table' and raw.seen or {}
    local rme = type(raw.measure) == 'table' and raw.measure or {}
    for _, w in ipairs(WINDOWS) do
        if rm[w] == 'pos' or rm[w] == 'neg' then marks[w] = rm[w] end
        seen[w] = U.clamp(num(rs[w], 0), 0, 900)
        local m = num(rme[w], nil)
        if m then measure[w] = U.clamp(m, 0, 250) end
    end
    return marks, seen, measure
end

local function scanFinish(src, p, session, result)
    local sc = cfg('Scan')
    local s = scans[src]
    scans[src] = nil
    -- re-read the truth now: things may have changed while scanning (drained, coiled)
    local truth = US.Truth(p)
    if s and s.pid == p.pid then
        -- a window that was positive when the scan started still counts as positive
        for _, w in ipairs(WINDOWS) do
            if s.truth[w] and s.truth[w].pos and not truth[w].pos then truth[w] = s.truth[w] end
        end
    end
    local marks, seen, measure = sanitizeMarks(result)
    local easy = result.easy == true
    local minSeen = num(sc.minSeen, 1.2)

    local graded, pts, marked, missed = {}, 0, 0, {}
    for _, w in ipairs(WINDOWS) do
        local t = truth[w]
        local m = marks[w]
        local g = { pos = t.pos, kinds = t.kinds, mark = m, seen = U.round(seen[w], 1) }
        if t.pleural then g.mm = t.pleural.mm elseif t.free then g.mm = t.free.mm elseif t.effusion then g.mm = t.effusion.mm end
        if easy then
            g.result = 'auto'
        elseif not m then
            g.result = t.pos and 'missed' or 'skipped'
            if t.pos then missed[#missed + 1] = w end
        elseif (m == 'pos') == t.pos then
            marked = marked + 1
            local full = seen[w] >= minSeen
            pts = pts + (full and 1 or 0.5)
            g.result = full and 'correct' or 'guess'
        else
            marked = marked + 1
            g.result = (m == 'neg') and 'missed' or 'false'
            if m == 'neg' then missed[#missed + 1] = w end
        end
        if measure[w] and g.mm then
            g.measured = U.round(measure[w], 0)
            if math.abs(measure[w] - g.mm) <= math.max(4, g.mm * 0.25) then
                g.measureOk = true
                pts = pts + 0.12
            end
        end
        graded[w] = g
    end

    local score = easy and result.score or U.clamp(math.floor(pts / #WINDOWS * 100 + 0.5), 0, 100)

    -- findings: every true positive the medic called (all of them in easy mode)
    local posMap = {}
    for _, w in ipairs(WINDOWS) do
        local t, g = truth[w], graded[w]
        if t.pos and (easy or g.mark == 'pos') then
            posMap[w] = true
            if t.pleural then
                addFinding(p.pid, 'haemothorax_suspected_' .. t.pleural.side, {
                    cond = 'haemothorax', side = t.pleural.side, group = 'chest', source = 'ultrasound', by = src,
                    text = L('finding_haemo', t.pleural.mm),
                })
            end
            if t.ptx then
                addFinding(p.pid, 'pneumothorax_suspected_' .. t.ptx.side, {
                    cond = 'pneumothorax', side = t.ptx.side, group = 'chest', source = 'ultrasound', by = src,
                    text = L('finding_ptx'),
                })
            end
            if t.effusion then
                addFinding(p.pid, 'tamponade_suspected', {
                    cond = 'tamponade', group = 'chest', source = 'ultrasound', by = src,
                    text = L('finding_tamponade', t.effusion.mm),
                })
            end
            if t.free then
                for _, id in ipairs(t.free.injuries or {}) do
                    local inj = p.injuries[id]
                    if inj then
                        addFinding(p.pid, 'us_internal_' .. id, {
                            injury = id, region = inj.region, group = 'abdomen', source = 'ultrasound', by = src,
                            text = L('finding_free_' .. w),
                        })
                    end
                end
            end
        end
    end
    NZA.Patients.SetMeta(p.pid, 'efast', { at = os.time(), by = src, pos = posMap, score = score })
    bill(src, p, sc.fee, 'bill_scan', 'ultrasound')

    local nPos = 0
    for _ in pairs(posMap) do nPos = nPos + 1 end
    local msg
    if #missed > 0 and not easy then
        msg = L('scan_missed', #missed)
    elseif nPos > 0 then
        msg = L('scan_pos', nPos)
    else
        msg = L('scan_clear')
    end

    local outcome = {
        msg = msg, windows = graded, plan = fullPlan(p, truth), missed = missed,
        drains = { left = ((p.devices or {}).chestDrain or {}).left == true, right = ((p.devices or {}).chestDrain or {}).right == true },
        record = L('record_scan', nPos, marked, score),
    }
    if not easy then outcome.score = score end
    NZA.Bus.Emit('ultrasound:scan', src, p, outcome)
    return outcome
end

-- ════════════════════════════════════════════════════════════════════════
-- CHEST DRAIN
-- ════════════════════════════════════════════════════════════════════════

local function chestState(p, side)
    local c = p.conditions or {}
    local h, pn = c.haemothorax, c.pneumothorax
    local haemo = h and (h.side == side or h.side == 'both' or (h.side ~= 'left' and h.side ~= 'right' and side == 'right')) and h or nil
    local ptx = pn and (sideOf(pn.side) == side) and pn or nil
    return haemo, ptx
end

local function drainStart(src, p, payload, info)
    local side = payload.side
    if side ~= 'left' and side ~= 'right' then return fail('bad_side') end
    local ok, where = US.Location(src, p, 'ChestDrain', info and info.easy)
    if not ok then return fail(where) end
    if ((p.devices or {}).chestDrain or {})[side] then return fail('drain_in') end
    local haemo, ptx = chestState(p, side)
    if not haemo and not ptx then return fail('nothing_to_drain') end
    local cd = cfg('ChestDrain')
    local lido = 0
    if cd.numbing ~= false and Config.Items.lidocaine and NZA.Core and NZA.Core.B then
        lido = num(NZA.Core.B('Inv.Count', src, Config.Items.lidocaine), 0)
    end
    return true, {
        where = where, side = side,
        haemo = haemo and math.floor(num(haemo.ml, 0)) or 0,
        haemoRate = haemo and U.round(num(haemo.rate, 0), 1) or 0,
        ptx = ptx and U.round(num(ptx.size, 20), 0) or 0,
        tension = ptx and ptx.tension == true or false,
        patient = { name = p.name, sex = p.sex, age = p.age },
        vitals = vitalsOf(p),
        seed = hashSeed(p.pid .. ':drain:' .. side),
        numbing = lido > 0,
        quality = cd.quality or 'high',
    }
end

local function drainFinish(src, p, session, result)
    local cd = cfg('ChestDrain')
    local side = session.payload and session.payload.side
    if side ~= 'left' and side ~= 'right' then side = 'right' end
    local score = result.score or 0
    if score < num(cd.minScore, 30) and not result.easy then
        bill(src, p, math.floor(num(cd.price, 0) * 0.5), 'bill_drain', 'chestdrain')
        return { failed = true, side = side, msg = L('drain_failed'), record = L('record_drain_failed', L('side_' .. side)) }
    end
    if result.numbed == true and Config.Items.lidocaine and NZA.Core and NZA.Core.TakeItems then
        pcall(NZA.Core.TakeItems, src, { [Config.Items.lidocaine] = 1 })
    end
    NZA.Patients.SetDevice(p.pid, 'chestDrain', side, true)
    local haemo, ptx = chestState(p, side)
    local drained = 0
    if haemo then
        local ml = num(haemo.ml, 0)
        drained = math.floor(ml * U.clamp(num(cd.drainNow, 0.85), 0, 1) * (0.6 + 0.4 * score / 100))
        haemo.ml = U.round(math.max(0, ml - drained), 1)
        haemo.output = U.round(num(haemo.output, 0) + drained, 1)
        if haemo.ml <= 1 and num(haemo.rate, 0) <= 0.2 then
            NZA.Patients.SetCondition(p.pid, 'haemothorax', nil)
        else
            NZA.Patients.SetCondition(p.pid, 'haemothorax', haemo)
        end
    end
    if ptx then
        NZA.Patients.SetCondition(p.pid, 'pneumothorax', nil)
    end
    if NZA.Findings and type(NZA.Findings.Remove) == 'function' then
        if not chestState(p, side) then
            pcall(NZA.Findings.Remove, p.pid, 'haemothorax_suspected_' .. side)
        end
        pcall(NZA.Findings.Remove, p.pid, 'pneumothorax_suspected_' .. side)
    end
    bill(src, p, cd.price, 'bill_drain', 'chestdrain')
    local outcome = {
        side = side, drained = drained, air = ptx ~= nil,
        msg = haemo and L('drain_done_blood', drained) or L('drain_done_air'),
        record = L('record_drain', L('side_' .. side), drained),
    }
    NZA.Bus.Emit('ultrasound:drain', src, p, outcome)
    return outcome
end

-- ════════════════════════════════════════════════════════════════════════
-- NEEDLE DECOMPRESSION
-- ════════════════════════════════════════════════════════════════════════

local function decompStart(src, p, payload)
    local pn = (p.conditions or {}).pneumothorax
    local side = payload.side
    if side ~= 'left' and side ~= 'right' then side = pn and sideOf(pn.side) or 'right' end
    payload.side = side
    return true, {
        side = side,
        patient = { name = p.name, sex = p.sex, age = p.age },
        vitals = vitalsOf(p),
        seed = hashSeed(p.pid .. ':decomp:' .. side),
    }
end

local function decompFinish(src, p, session, result)
    local dc = cfg('Decompress')
    local side = session.payload and session.payload.side or 'right'
    local pn = (p.conditions or {}).pneumothorax
    local score = result.score or 0
    bill(src, p, dc.price, 'bill_decomp', 'decompress')
    if score < num(dc.minScore, 25) and not result.easy then
        return { failed = true, side = side, msg = L('decomp_missed'), record = L('record_decomp_failed', L('side_' .. side)) }
    end
    if not pn or sideOf(pn.side) ~= side then
        return { failed = true, side = side, quiet = true, msg = L('decomp_no_air'), record = L('record_decomp_none', L('side_' .. side)) }
    end
    local wasTension = pn.tension == true
    pn.tension, pn.pressure, pn.decompressed = false, 0, true
    pn.size = math.max(5, num(pn.size, 20) - 8)
    NZA.Patients.SetCondition(p.pid, 'pneumothorax', pn)
    local outcome = {
        side = side, hiss = true, tension = wasTension,
        msg = wasTension and L('decomp_done') or L('decomp_done_simple'),
        record = L('record_decomp', L('side_' .. side)),
    }
    NZA.Bus.Emit('ultrasound:decompress', src, p, outcome)
    return outcome
end

-- ════════════════════════════════════════════════════════════════════════
-- PERICARDIOCENTESIS
-- ════════════════════════════════════════════════════════════════════════

local function pericardioStart(src, p, payload, info)
    local tp = (p.conditions or {}).tamponade
    if not tp or num(tp.ml, 0) < 10 then return fail('no_effusion') end
    local ok, where = US.Location(src, p, 'Pericardio', info and info.easy)
    if not ok then return fail(where) end
    local pc = cfg('Pericardio')
    local truth, render = US.Truth(p)
    return true, {
        where = where,
        ml = math.floor(num(tp.ml, 0)),
        rate = U.round(num(tp.rate, 0), 1),
        syringe = num(pc.syringe, 60),
        drawRate = num(pc.drawRate, 7),
        leftOver = num(pc.leftOver, 20),
        patient = { name = p.name, sex = p.sex, age = p.age },
        vitals = vitalsOf(p),
        seed = hashSeed(p.pid .. ':us'),
        views = { cardiac = render.cardiac },
        labels = cfg('Scan').labels ~= false,
        mm = truth.cardiac.effusion and truth.cardiac.effusion.mm or 4,
    }
end

local function pericardioFinish(src, p, session, result)
    local pc = cfg('Pericardio')
    local tp = (p.conditions or {}).tamponade
    local elapsed = num(session.elapsed, 0)
    local claimed = U.clamp(num(result.drawn, 0), 0, 2000)
    if result.easy then claimed = tp and num(tp.ml, 0) or 0 end
    local cap = math.max(0, elapsed * num(pc.maxDrawRate, 12))
    local drawn = math.floor(math.min(claimed, cap, tp and num(tp.ml, 0) or 0))
    local touches = math.floor(U.clamp(num(result.touches, 0), 0, 50))
    if result.easy then touches = 0 end
    bill(src, p, pc.price, 'bill_pericardio', 'pericardio')

    local left = 0
    if tp then
        tp.ml = U.round(math.max(0, num(tp.ml, 0) - drawn), 1)
        left = tp.ml
        if left <= num(pc.leftOver, 20) then tp.rate = U.round(num(tp.rate, 0) * U.clamp(num(pc.slowBleed, 0.45), 0, 1), 2) end
        if tp.ml <= 2 and num(tp.rate, 0) < 0.6 then
            NZA.Patients.SetCondition(p.pid, 'tamponade', nil)
        else
            NZA.Patients.SetCondition(p.pid, 'tamponade', tp)
        end
    end

    local vf = false
    if touches > 0 and p.state ~= 'arrest' and p.state ~= 'dead' then
        local chance = math.min(num(pc.maxVf, 0.6), num(pc.touchVf, 0.18) * touches)
        if math.random() < chance then
            vf = true
            NZA.Patients.SetCondition(p.pid, 'arrest', { rhythm = 'vf', cause = 'pericardio' })
        end
    end
    if drawn > 0 and NZA.Findings and type(NZA.Findings.Remove) == 'function' and left <= num(pc.leftOver, 20) then
        pcall(NZA.Findings.Remove, p.pid, 'tamponade_suspected')
    end

    local outcome = {
        drawn = drawn, left = math.floor(left), touches = touches, vf = vf,
        failed = drawn <= 0,
        msg = vf and L('peri_vf') or (drawn > 0 and L('peri_done', drawn) or L('peri_none')),
        record = L('record_peri', drawn, touches),
    }
    NZA.Bus.Emit('ultrasound:pericardio', src, p, outcome)
    return outcome
end

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRATION
-- ════════════════════════════════════════════════════════════════════════

local function register()
    local sc, cd, dc, pc = cfg('Scan'), cfg('ChestDrain'), cfg('Decompress'), cfg('Pericardio')
    NZA.Proc.Register('ultrasound', {
        perm = sc.perm or 'ultrasound', label = L('title'),
        items = function() return itemsOf(sc.items) end,
        maxDist = num(sc.maxDist, 3.0), minTime = num(sc.minTime, 10), maxTime = num(sc.maxTime, 900),
        easyTime = num(sc.easyTime, 8), consume = 'finish',
        states = { alive = true, wounded = true, arrest = true },
        onStart = scanStart, onFinish = scanFinish,
        onAbort = function(src) scans[src] = nil end,
    })
    NZA.Proc.Register('chestdrain', {
        perm = cd.perm or 'chestdrain', label = L('drain_title'),
        items = function() return itemsOf(cd.items) end,
        maxDist = num(cd.maxDist, 3.0), minTime = num(cd.minTime, 30), maxTime = num(cd.maxTime, 900),
        easyTime = num(cd.easyTime, 10), consume = cd.consume or 'finish',
        states = { alive = true, wounded = true, arrest = true },
        onStart = drainStart, onFinish = drainFinish,
    })
    NZA.Proc.Register('decompress', {
        perm = dc.perm or 'chestdrain', label = L('decomp_title'),
        items = function() return itemsOf(dc.items) end,
        maxDist = num(dc.maxDist, 3.0), minTime = num(dc.minTime, 4), maxTime = num(dc.maxTime, 300),
        easyTime = num(dc.easyTime, 5), consume = dc.consume or 'finish',
        states = { alive = true, wounded = true, arrest = true },
        onStart = decompStart, onFinish = decompFinish,
    })
    NZA.Proc.Register('pericardio', {
        perm = pc.perm or 'pericardio', label = L('peri_title'),
        items = function() return itemsOf(pc.items) end,
        maxDist = num(pc.maxDist, 3.0), minTime = num(pc.minTime, 18), maxTime = num(pc.maxTime, 900),
        easyTime = num(pc.easyTime, 10), consume = pc.consume or 'finish',
        states = { alive = true, wounded = true, arrest = true },
        onStart = pericardioStart, onFinish = pericardioFinish,
    })
end

if NZA.Proc and type(NZA.Proc.Register) == 'function' then
    register()
else
    CreateThread(function()
        local waited = 0
        while not (NZA.Proc and type(NZA.Proc.Register) == 'function') and waited < 30000 do
            Wait(250)
            waited = waited + 250
        end
        if NZA.Proc and type(NZA.Proc.Register) == 'function' then
            register()
        else
            NZA.Warn('ultrasound: NZA.Proc.Register is missing - the ultrasound procedures are disabled')
        end
    end)
end

AddEventHandler('playerDropped', function()
    scans[source] = nil
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS (chest drain kit, decompression needle)
-- ════════════════════════════════════════════════════════════════════════

local function registerUsable(key, kind, perm)
    local name = Config.Items and Config.Items[key]
    if not name or not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
        src = tonumber(src)
        if not src then return end
        if NZA.Core and NZA.Core.Rate and not NZA.Core.Rate('nza:us:use', src, 1, 1500) then return end
        if not NZA.Staff.Can(src, perm) then
            if NZA.Core and NZA.Core.Notify then NZA.Core.Notify(src, L('err_no_perm'), 'error', L('title')) end
            return
        end
        TriggerClientEvent('nza:us:use', src, kind)
    end)
    if not ok then NZA.Warn('ultrasound: usable ' .. tostring(name) .. ' failed: ' .. tostring(err)) end
end

CreateThread(function()
    Wait(1500)
    if cfg().usable == false then return end
    registerUsable('chest_drain_kit', 'chestdrain', cfg('ChestDrain').perm or 'chestdrain')
    registerUsable('decomp_needle', 'decompress', cfg('Decompress').perm or 'chestdrain')
end)
