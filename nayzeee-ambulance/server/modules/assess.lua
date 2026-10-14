--[[
    NAYZEEE AMBULANCE - Assessment (server): findings, examination, ask to walk

    Discovered findings (what medics have found out about a patient)
      Hidden problems (haemothorax, pneumothorax, tamponade, internal bleeding, airway...)
      only show up in the Examination screen once a check found them. Every check
      (pulse, breathing, ultrasound, X-ray, ...) adds what it found here; the list lives in
      patient.meta.findings (saved with player patients) and is part of the medic snapshot.

        NZA.Findings.Add(pid, key, data)   → finding     key = 'haemothorax_suspected_right' ...
            data (all optional): { cond = 'haemothorax', side = 'left'|'right', group = 'chest',
                                   injury = 'i7', region = 'abdomen', source = 'breathing'|'ultrasound'|'xray'|...,
                                   label = 'free text', text = 'detail line', by = src, ...plain values }
            cond   → the finding is dropped automatically when that condition is cleared
            injury → the finding is dropped automatically when that injury is removed
            group  → which exam body group shows it (head neck chest abdomen l_arm r_arm l_leg r_leg);
                     no group = 'General' card
        NZA.Findings.Remove(pid, key)      → bool
        NZA.Findings.Has(pid, key)         → bool
        NZA.Findings.Get(pid)              → { [key] = finding } (copy)
        NZA.Findings.Clear(pid, filter?)   filter(finding, key) → true to drop; nil = drop all
      Bus (server): findings:changed (p, key, finding|nil)

    Shared helpers for the assessment procedures (assess_pulse.lua, assess_breathing.lua)
        NZA.Assess.Can(src, perm)          NZA.Assess.Encode(seed, values) → string
        NZA.Assess.Outcome(src, nonce, outcome)     store a result for the client to fetch
        NZA.Assess.Record(src, p, kind, data)       bus 'assess:done' (src, p, kind, data); the core
                                                    writes nza_records from outcome.record
        NZA.Assess.Bill(src, p, kind)               optional fee (Config.Assess.Billing)

    Callbacks (lib.callback)
        nza:assess:exam (target)           → ok, info|reason   start of an examination (perm, distance)
        nza:assess:walk (target, on)       → ok, info|reason   ask a patient to walk / stop following
        nza:assess:outcome (nonce)         → outcome | nil      result of the last pulse/breathing check
    Bus listeners: condition:changed, injury:removed, patient:revived, player:unloaded
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Findings = NZA.Findings or {}
NZA.Assess = NZA.Assess or {}
local F = NZA.Findings
local A = NZA.Assess

local outcomes = {}     -- [src] = { nonce, outcome, at }
local walkCooldown = {} -- [pid] = os.time()
local billed = {}       -- [src .. pid .. kind] = os.time()

local LEG_REGIONS = { l_upper_leg = true, l_lower_leg = true, r_upper_leg = true, r_lower_leg = true, pelvis = true }
local PLACED_META = { carried = true, stretcher = true, bed = true, inBed = true, bodybag = true, vehicle = true, bay = true }

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section)
    local c = Config.Assess or {}
    return c[section] or {}
end

local function resolve(pid)
    if type(pid) == 'table' and pid.pid and pid.injuries then return pid end
    return NZA.Patients.Resolve(pid)
end

function A.Can(src, perm)
    if perm == nil then return true end
    if NZA.Staff and NZA.Staff.Can then
        local ok, res = pcall(NZA.Staff.Can, src, perm)
        return ok and res == true
    end
    return NZA.Core.IsAdmin(src)
end

-- Light obfuscation for data the NUI must render but should not be able to read at a
-- glance (beat / breath schedules). Park-Miller stream added to each 12-bit value.
function A.Encode(seed, values)
    local x = math.floor(seed) % 2147483647
    if x <= 0 then x = 1 end
    local out = {}
    for i = 1, #values do
        x = (x * 48271) % 2147483647
        local v = math.floor((tonumber(values[i]) or 0) + 0.5)
        if v < 0 then v = 0 elseif v > 4095 then v = 4095 end
        out[i] = ('%03x'):format((v + x % 4096) % 4096)
    end
    return table.concat(out)
end

function A.Seed()
    return math.random(1000, 2147483000)
end

function A.Outcome(src, nonce, outcome)
    outcomes[src] = { nonce = nonce, outcome = outcome, at = os.time() }
end

-- The core writes the treatment record itself (outcome.record); this only tells the rest
-- of the resource that an assessment finished.
function A.Record(src, p, kind, data)
    NZA.Bus.Emit('assess:done', src, p, kind, data)
end

function A.Bill(src, p, kind)
    local amount = tonumber(cfg('Billing')[kind]) or 0
    if amount <= 0 or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local key = ('%s:%s:%s'):format(src, p.pid, kind)
    local now = os.time()
    if billed[key] and now - billed[key] < 600 then return end
    billed[key] = now
    local target = p.src or p.identifier
    local ok, err = pcall(NZA.Billing.Charge, target, amount, NZA.L('assess.bill_' .. kind), { medic = src, kind = 'assess' })
    if not ok then NZA.Debug('assess billing failed', err) end
end

local function sanitizeValue(v, depth)
    local t = type(v)
    if t == 'string' then return v:sub(1, 200) end
    if t == 'number' or t == 'boolean' then return v end
    if t == 'table' and depth < 2 then
        local out = {}
        local n = 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 24 then break end
            if type(k) == 'string' or type(k) == 'number' then out[k] = sanitizeValue(x, depth + 1) end
        end
        return out
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- FINDINGS API
-- ════════════════════════════════════════════════════════════════════════

local function list(p)
    local l = p.meta.findings
    if type(l) ~= 'table' then
        l = {}
    end
    return l
end

local function store(p, l)
    if next(l) == nil then
        NZA.Patients.SetMeta(p.pid, 'findings', nil)
    else
        NZA.Patients.SetMeta(p.pid, 'findings', l)
    end
end

function F.Add(pid, key, data)
    local p = resolve(pid)
    if not p or type(key) ~= 'string' or key == '' or #key > 64 or not key:match('^[%w_%-%.:]+$') then return nil end
    local l = list(p)
    local f = {}
    if type(data) == 'table' then
        for k, v in pairs(data) do
            if type(k) == 'string' then f[k] = sanitizeValue(v, 0) end
        end
    end
    f.key = key
    f.at = os.time()
    if f.by and type(f.by) == 'number' and not f.byName then f.byName = NZA.Core.Name(f.by) end
    l[key] = f
    store(p, l)
    NZA.Bus.Emit('findings:changed', p, key, f)
    return f
end

function F.Remove(pid, key)
    local p = resolve(pid)
    if not p then return false end
    local l = list(p)
    if l[key] == nil then return false end
    l[key] = nil
    store(p, l)
    NZA.Bus.Emit('findings:changed', p, key, nil)
    return true
end

function F.Has(pid, key)
    local p = resolve(pid)
    return p ~= nil and type(p.meta.findings) == 'table' and p.meta.findings[key] ~= nil
end

function F.Get(pid)
    local p = resolve(pid)
    if not p then return {} end
    return NZA.Util.deepcopy(list(p))
end

function F.Clear(pid, filter)
    local p = resolve(pid)
    if not p then return 0 end
    local l = list(p)
    local removed = {}
    for key, f in pairs(l) do
        if filter == nil or filter(f, key) then removed[#removed + 1] = key end
    end
    if #removed == 0 then return 0 end
    for _, key in ipairs(removed) do l[key] = nil end
    store(p, l)
    for _, key in ipairs(removed) do NZA.Bus.Emit('findings:changed', p, key, nil) end
    return #removed
end

-- ════════════════════════════════════════════════════════════════════════
-- DISTANCE / PATIENT CHECKS
-- ════════════════════════════════════════════════════════════════════════

local function examRange()
    return ((Config.Physiology and Config.Physiology.examDistance) or 4.0) + 1.0
end

-- Patient in the same bed point / ambulance bay as the medic counts as near even when the
-- peds are a little apart (bay interiors).
local function near(src, p, range)
    local d = NZA.Core.DistanceTo(src, p)
    if d <= range then return true end
    local me = NZA.Patients.GetBySource(src)
    if me and p.meta.bay and me.meta and me.meta.bay == p.meta.bay then return true end
    return false
end
A.Near = near

local function avpu(p)
    return (p.vitals and p.vitals.avpu) or 'A'
end

local function legFracture(p)
    local fractured, splinted = false, true
    for _, inj in pairs(p.injuries) do
        if inj.type == 'fracture' and LEG_REGIONS[inj.region] then
            fractured = true
            if not (inj.treat.splinted or inj.treat.cast) then splinted = false end
        end
    end
    return fractured, fractured and splinted
end

local function legPain(p)
    for _, inj in pairs(p.injuries) do
        if LEG_REGIONS[inj.region] and (inj.severity or 1) >= 2 and inj.type ~= 'abrasion' then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:assess:exam', function(src, target)
    if not NZA.Core.Rate('assess_exam', src, 8, 10000) then return false, NZA.L('assess.err_rate') end
    local perm = cfg('Interact').perm or 'assess'
    if not A.Can(src, perm) then return false, NZA.L('assess.err_perm') end
    local p = NZA.Patients.Resolve(target)
    if not p then return false, NZA.L('assess.err_patient') end
    if p.kind == 'player' and p.src == src then return false, NZA.L('assess.err_self') end
    if not near(src, p, examRange()) then return false, NZA.L('assess.err_far') end

    if cfg('Exam').notifyPatient ~= false and p.kind == 'player' and p.src then
        NZA.Core.Notify(p.src, {
            title = NZA.L('assess.notify_exam_title'),
            message = NZA.L('assess.notify_exam', NZA.Core.Name(src)),
            type = 'info', duration = 4000,
        })
    end
    A.Bill(src, p, 'exam')
    NZA.Bus.Emit('assess:exam', src, p)
    return true, { pid = p.pid }
end)

lib.callback.register('nza:assess:walk', function(src, target, on)
    local wc = cfg('Walk')
    if wc.enabled == false then return false, NZA.L('assess.err_disabled') end
    if not NZA.Core.Rate('assess_walk', src, 6, 6000) then return false, NZA.L('assess.err_rate') end
    if wc.perm and not A.Can(src, wc.perm) then return false, NZA.L('assess.err_perm') end
    local p = NZA.Patients.Resolve(target)
    if not p then return false, NZA.L('assess.err_patient') end
    if p.kind == 'player' and p.src == src then return false, NZA.L('assess.err_self') end

    -- stop following: always allowed for the medic who leads the patient
    if on == false then
        if p.meta.escort == src then NZA.Patients.SetMeta(p.pid, 'escort', nil) end
        return true, {}
    end

    if NZA.Core.DistanceTo(src, p) > 4.0 then return false, NZA.L('assess.err_far') end
    local now = os.time()
    if walkCooldown[p.pid] and now - walkCooldown[p.pid] < (wc.cooldown or 5) then
        return false, NZA.L('assess.err_wait')
    end
    walkCooldown[p.pid] = now

    if p.state ~= 'alive' then return false, NZA.L('assess.walk_down') end
    if avpu(p) == 'P' or avpu(p) == 'U' then return false, NZA.L('assess.walk_unconscious') end
    for k in pairs(PLACED_META) do
        if p.meta[k] then return false, NZA.L('assess.walk_placed') end
    end
    local fractured, splinted = legFracture(p)
    if fractured and not (splinted and wc.allowSplinted) then
        return false, NZA.L('assess.walk_fracture')
    end

    if p.kind == 'player' then
        if p.src then
            TriggerClientEvent('nza:assess:walkPrompt', p.src, {
                medic = NZA.Core.Name(src),
                ms = tonumber(wc.playerPrompt) or 6000,
            })
        end
        return true, { player = true }
    end

    if p.meta.escort and p.meta.escort ~= src and NZA.Core.Online(p.meta.escort) then
        return false, NZA.L('assess.walk_taken')
    end
    NZA.Patients.SetMeta(p.pid, 'escort', src)
    return true, { limp = legPain(p) or fractured, pid = p.pid }
end)

lib.callback.register('nza:assess:outcome', function(src, nonce)
    local o = outcomes[src]
    if not o then return nil end
    if nonce ~= nil and o.nonce ~= nonce then return nil end
    outcomes[src] = nil
    return o.outcome
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOUSEKEEPING (findings follow the conditions/injuries they describe)
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('condition:changed', function(p, name, value)
    if value ~= nil or type(p) ~= 'table' or type(p.meta) ~= 'table' or type(p.meta.findings) ~= 'table' then return end
    F.Clear(p, function(f) return f.cond == name end)
end)

NZA.Bus.On('injury:removed', function(p, id)
    if type(p) ~= 'table' or type(p.meta) ~= 'table' or type(p.meta.findings) ~= 'table' then return end
    F.Clear(p, function(f) return f.injury ~= nil and f.injury == id end)
end)

NZA.Bus.On('patient:revived', function(p, opts)
    if type(p) ~= 'table' or type(p.meta) ~= 'table' then return end
    if type(opts) == 'table' and opts.full then
        if type(p.meta.findings) == 'table' then F.Clear(p) end
    else
        -- ROSC: the "no pulse" finding is no longer true
        if type(p.meta.findings) == 'table' then
            F.Clear(p, function(f, key) return key == 'pulseless' or key == 'apnoea' end)
        end
    end
end)

NZA.Bus.On('state:changed', function(p, old, new)
    if type(p) ~= 'table' or type(p.meta) ~= 'table' then return end
    -- a patient who goes down stops following
    if new ~= 'alive' and p.meta.escort then NZA.Patients.SetMeta(p.pid, 'escort', nil) end
end)

NZA.Bus.On('player:unloaded', function(src)
    outcomes[src] = nil
    for key in pairs(billed) do
        if key:sub(1, #tostring(src) + 1) == tostring(src) .. ':' then billed[key] = nil end
    end
    -- NPCs led by this medic stop following
    for _, p in pairs(NZA.Patients.All()) do
        if p.meta and p.meta.escort == src then NZA.Patients.SetMeta(p.pid, 'escort', nil) end
    end
end)

-- stale outcomes / cooldowns
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, o in pairs(outcomes) do
            if now - o.at > 120 then outcomes[src] = nil end
        end
        for pid, at in pairs(walkCooldown) do
            if now - at > 60 then walkCooldown[pid] = nil end
        end
        for key, at in pairs(billed) do
            if now - at > 900 then billed[key] = nil end
        end
    end
end)

exports('AddFinding', function(pid, key, data) return F.Add(pid, key, data) end)
exports('GetFindings', function(pid) return F.Get(pid) end)
