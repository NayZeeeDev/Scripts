--[[
    NAYZEEE AMBULANCE - Check-in (server): AI doctor, queue beds, bed rest

    AI DOCTOR
      Takes waiting tickets when no staff of the department is on duty (after
      Config.Checkin.ai.noStaffDelay) or when nobody called them within ai.waitTimeout.
      The patient is called to a free bed (walk with a waypoint, or a fade teleport),
      lies down, and the treatment runs on the server: one step per injury (plus
      assessment, resuscitation, transfusion and discharge), each step applies its
      treatment to that injury when it ends, so the vitals the patient watches really
      improve. At the end: heal (ai.heal), revive, bill (insurance), ticket closed as done.
      Getting up early stops it; finished steps are still billed.

    SERVER API
      NZA.Checkin.AI.Plan(p) → steps, total            NZA.Checkin.AI.Bill(p, ticket, steps) → bill
      NZA.Checkin.AI.Start(ticket) → bool              NZA.Checkin.AI.Stop(ticket, reason)
      NZA.Checkin.AI.Session(ticketId) → session       NZA.Checkin.AI.Tick(now)  (called by checkin.lua)

    CALLBACKS
      nza:checkin:lie  ({ point, on, teleport }) → { ok, coords, label, mode } | { ok = false, err }
                       lie on the bed your ticket was called to (on = false: get up)
      nza:checkin:rest () → { ok, inBed, label, hospital, mult, recovery, eta, injuries[], blood, pain, state }
    NET EVENTS
      S→C nza:checkin:ai (action, data)   start (session) · step ({ index, elapsed }) · vitals (vitals)
                                          · done ({ bill, paid, msg }) · abort ({ reason, bill?, paid? })
    BUS   emits checkin:ai (ticket, outcome)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Checkin = NZA.Checkin or {}
NZA.Checkin.AI = NZA.Checkin.AI or {}
local C = NZA.Checkin
local AI = NZA.Checkin.AI
local U = NZA.Util

local sessions = {}       -- [ticket id] = session

local function cfg(section, key, default)
    local s = Config.Checkin and Config.Checkin[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function L(key, ...) return NZA.L('checkin.' .. key, ...) end

local function fail(err, extra)
    local out = { ok = false, err = err, msg = L('err_' .. err) }
    if extra then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function point(id)
    if not (NZA.Hospitals and NZA.Hospitals.Point) then return nil end
    return NZA.Hospitals.Point(tonumber(id) or id)
end

local function pos(pt)
    local c = pt and pt.coords
    return c and vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) or nil
end

local TYPE_ICON = {
    gunshot = 'crosshair', shrapnel = 'burst', stab = 'knife', laceration = 'cut', abrasion = 'scrape',
    contusion = 'bruise', fracture = 'bone', burn = 'flame', internal = 'scalpel',
}

-- what the AI doctor does for each injury type (treat flags merged into the injury)
local TREAT = {
    gunshot    = { extracted = true, irrigated = true, packed = true, sutured = true, dressed = true },
    shrapnel   = { extracted = true, irrigated = true, sutured = true, dressed = true },
    stab       = { irrigated = true, packed = true, sutured = true, dressed = true },
    laceration = { irrigated = true, anesthetized = true, sutured = true, dressed = true },
    abrasion   = { irrigated = true, dressed = true },
    contusion  = { dressed = true },
    fracture   = { xray = true, reduced = true, splinted = true, cast = true },
    burn       = { cooled = true, debrided = true, dressed = true },
    internal   = { coiled = true, packed = true },
}

-- ════════════════════════════════════════════════════════════════════════
-- PLAN & BILL
-- ════════════════════════════════════════════════════════════════════════

local function sortedInjuries(p)
    local list = {}
    for _, inj in pairs(p.injuries or {}) do list[#list + 1] = inj end
    table.sort(list, function(a, b)
        if (a.severity or 0) ~= (b.severity or 0) then return (a.severity or 0) > (b.severity or 0) end
        return (a.bleed or 0) > (b.bleed or 0)
    end)
    return list
end

function AI.Plan(p)
    local times = cfg('ai', 'times', {})
    local per = tonumber(times.perSeverity) or 4
    local steps = {}
    local function add(s) steps[#steps + 1] = s end
    add({ key = 'assess', icon = 'stetho', label = L('step_assess'), text = L('step_assess_t'), time = tonumber(times.assess) or 8 })
    if p.state ~= 'alive' and cfg('ai', 'revive', true) then
        add({ key = 'resus', icon = 'heart', label = L('step_resus'), text = L('step_resus_t'), time = tonumber(times.resus) or 16, bill = 'resus' })
    end
    local frac = (p.bloodMax or 0) > 0 and (p.blood or 0) / p.bloodMax or 1
    if frac < (tonumber(cfg('ai', 'transfuseBelow', 0.8)) or 0.8) then
        add({ key = 'transfusion', icon = 'bloodbag', label = L('step_transfusion', p.bloodType or 'O-'),
              text = L('step_transfusion_t'), time = tonumber(times.transfusion) or 14, bill = 'transfusion' })
    end
    for _, inj in ipairs(sortedInjuries(p)) do
        local rg = NZA.Const.Region[inj.region] or {}
        local ty = NZA.Const.InjuryTypes[inj.type] or {}
        local base = tonumber(times[inj.type]) or 14
        add({
            key = inj.type, injury = inj.id, icon = TYPE_ICON[inj.type] or 'medkit', severity = inj.severity or 1,
            label = L('step_' .. inj.type, rg.label or inj.region), text = L('step_' .. inj.type .. '_t'),
            injuryLabel = ty.label or inj.type, region = rg.label or inj.region,
            time = base + per * math.max(0, (inj.severity or 1) - 1), bill = inj.type,
        })
    end
    add({ key = 'discharge', icon = 'check', label = L('step_discharge'), text = L('step_discharge_t'), time = tonumber(times.discharge) or 8 })

    local scale = math.max(0.05, tonumber(cfg('ai', 'scale', 1.0)) or 1.0)
    local total = 0
    for _, s in ipairs(steps) do s.time = s.time * scale total = total + s.time end
    local minT = tonumber(cfg('ai', 'minTime', 20)) or 20
    local maxT = tonumber(cfg('ai', 'maxTime', 240)) or 240
    local target = U.clamp(total, minT, math.max(minT, maxT))
    if total > 0 and target ~= total then
        local f = target / total
        for _, s in ipairs(steps) do s.time = s.time * f end
    end
    total = 0
    for _, s in ipairs(steps) do
        s.time = math.max(2, math.floor(s.time + 0.5))
        total = total + s.time
    end
    return steps, total
end

local function insurance(identifier)
    if not (NZA.Insurance and NZA.Insurance.Get) or not identifier then return nil end
    local ok, ins = pcall(NZA.Insurance.Get, identifier)
    if not ok or type(ins) ~= 'table' then return nil end
    if ins.expires and tonumber(ins.expires) and tonumber(ins.expires) < os.time() then return nil end
    return ins
end

function AI.Bill(p, t, steps, onlyDone)
    local prices = cfg('ai', 'prices', {})
    local perSev = tonumber(prices.perSeverity) or 0.25
    local lines = {}
    local subtotal = 0
    local function add(label, amount)
        amount = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
        if amount <= 0 then return end
        lines[#lines + 1] = { label = label, amount = amount }
        subtotal = subtotal + amount
    end
    add(L('bill_base'), prices.base or 0)
    for _, s in ipairs(steps or {}) do
        if s.bill and (not onlyDone or s.applied) then
            local price = tonumber(prices[s.bill]) or 0
            if s.injury then
                price = price * (1 + perSev * math.max(0, (s.severity or 1) - 1))
                add(L('bill_line', s.injuryLabel or s.bill, s.region or ''), price)
            else
                add(s.label, price)
            end
        end
    end
    local ins = insurance(t and t.identifier)
    local cover = ins and U.clamp(tonumber(ins.cover) or 0, 0, 1) or 0
    local coverAmount = math.floor(subtotal * cover + 0.5)
    return {
        lines = lines, subtotal = subtotal, cover = cover, coverAmount = coverAmount,
        plan = ins and (ins.label or ins.plan) or nil, total = subtotal - coverAmount,
        enabled = cfg('ai', 'billing', true) == true,
    }
end

local function canPay(src, amount)
    if amount <= 0 or not (Bridge and Bridge.GetMoney) then return true end
    local acct = cfg('ai', 'account', 'bank')
    local ok, have = pcall(Bridge.GetMoney, src, acct)
    have = ok and tonumber(have) or 0
    if have >= amount then return true end
    if cfg('ai', 'fallbackCash', true) and acct ~= 'cash' then
        local ok2, cash = pcall(Bridge.GetMoney, src, 'cash')
        if ok2 and (tonumber(cash) or 0) >= amount then return true end
    end
    return false
end

-- → paid (bool), amount the patient paid / owes, extra { unpaid, covered }
local function charge(src, t, bill)
    if not bill.enabled or bill.subtotal <= 0 then return true, 0, {} end
    local reason = L('bill_reason', C.HospitalLabel(t.hospital))
    if NZA.Billing and NZA.Billing.Charge then
        local society = NZA.Hospitals and NZA.Hospitals.Society and NZA.Hospitals.Society(t.hospital) or nil
        local ok, res, info = pcall(NZA.Billing.Charge, src, bill.subtotal, reason,
            { kind = 'ai_doctor', pid = t.pid, society = society, account = cfg('ai', 'account', 'bank'), silent = true })
        if ok and res == true then
            info = type(info) == 'table' and info or {}
            bill.coverAmount = tonumber(info.covered) or bill.coverAmount
            bill.total = tonumber(info.pay) or bill.total
            bill.plan = info.planLabel or bill.plan
            return info.unpaid ~= true, bill.total, { unpaid = info.unpaid == true, invoiced = info.invoiced == true }
        end
        if ok then return false, bill.total, { unpaid = true } end
    end
    local net = bill.total
    if net <= 0 then return true, 0, {} end
    if not (Bridge and Bridge.RemoveMoney) then return false, net, { unpaid = true } end
    local acct = cfg('ai', 'account', 'bank')
    local ok, r = pcall(Bridge.RemoveMoney, src, acct, net, reason)
    local paid = ok and r == true
    if not paid and cfg('ai', 'fallbackCash', true) and acct ~= 'cash' then
        local ok2, r2 = pcall(Bridge.RemoveMoney, src, 'cash', net, reason)
        paid = ok2 and r2 == true
    end
    if paid and Bridge.Society and Bridge.Society.Add then
        local soc = (NZA.Hospitals and NZA.Hospitals.Society and NZA.Hospitals.Society(t.hospital))
            or (Config.Billing and Config.Billing.society) or 'ambulance'
        pcall(Bridge.Society.Add, soc, net)
    end
    return paid, net, { unpaid = not paid }
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION
-- ════════════════════════════════════════════════════════════════════════

local function vitalsOf(p)
    local v = p.vitals or {}
    return {
        hr = v.ecgRate or v.hr, spo2 = v.spo2, sys = v.sys, dia = v.dia, map = v.map, rr = v.rr,
        temp = v.temp or p.temp, rhythm = v.rhythm, etco2 = v.etco2, state = p.state,
        blood = (p.bloodMax or 0) > 0 and math.floor((p.blood or 0) / p.bloodMax * 100 + 0.5) or nil,
    }
end

local function publicSession(s)
    local pt = point(s.point)
    local c = pt and pt.coords
    local steps = {}
    for i, st in ipairs(s.steps) do
        steps[i] = { key = st.key, label = st.label, text = st.text, icon = st.icon, time = st.time,
                     region = st.region, severity = st.severity }
    end
    return {
        ticket = s.t.code, bed = s.t.bedLabel, hospital = C.HospitalLabel(s.t.hospital), point = s.point,
        steps = steps, total = s.total, elapsed = (GetGameTimer() - s.startedMs) / 1000, index = s.idx,
        doctor = L('ai_name'), bill = s.bill, vitals = vitalsOf(s.p), name = s.p.name,
        coords = c and { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 } or nil,
    }
end

local function applyStep(s, st)
    local p = NZA.Patients.Get(s.pid)
    if not p then return end
    st.applied = true
    if st.key == 'resus' then
        if p.state == 'arrest' then NZA.Patients.Revive(p, { rosc = true, reason = 'ai_doctor' }) end
        if p.state ~= 'alive' and p.state ~= 'dead' then NZA.Patients.Revive(p, { reason = 'ai_doctor' }) end
    elseif st.key == 'transfusion' then
        local want = (p.bloodMax or 5000) * 0.95 - (p.blood or 0)
        if want > 0 then NZA.Patients.AddBlood(p, want) end
    elseif st.injury and p.injuries and p.injuries[st.injury] then
        local flags = TREAT[st.key] or { dressed = true }
        local quality = {}
        for k in pairs(flags) do quality[k] = 85 end
        NZA.Patients.UpdateInjury(p, st.injury, { treat = flags, quality = quality })
    end
end

local function finish(s)
    s.done = true
    sessions[s.t.id] = nil
    local p = NZA.Patients.Get(s.pid)
    local src = C.PlayerSrc(s.t)
    if p then
        local heal = tonumber(cfg('ai', 'heal', 100)) or 100
        if heal >= 100 then
            NZA.Patients.Revive(p, { full = true, reason = 'ai_doctor' })
        else
            if heal > 0 then NZA.Patients.Heal(p, heal) end
            if p.state ~= 'alive' and cfg('ai', 'revive', true) then NZA.Patients.Revive(p, { reason = 'ai_doctor' }) end
        end
    end
    local bill = s.bill
    local paid, amount, extra = true, 0, {}
    if src then paid, amount, extra = charge(src, s.t, bill) end
    if p and NZA.Records and NZA.Records.Add then
        local names = {}
        for _, st in ipairs(s.steps) do names[#names + 1] = st.label end
        pcall(NZA.Records.Add, p, { medic = 'ai', medicName = L('ai_name'), action = 'ai_doctor',
            summary = { ticket = s.t.code, hospital = C.HospitalLabel(s.t.hospital), steps = names, bill = bill.total, paid = paid } })
    end
    s.t.byName = L('ai_name')
    C.Close(s.t, 'done')
    if src then
        TriggerClientEvent('nza:checkin:ai', src, 'done', {
            bill = bill, paid = paid, amount = amount, unpaid = extra.unpaid == true,
            msg = paid and L('ai_done', s.t.code) or L('ai_done_unpaid', amount),
        })
    end
    NZA.Bus.Emit('checkin:ai', s.t, 'done')
end

local function abort(s, reason)
    if s.done then return end
    s.done = true
    sessions[s.t.id] = nil
    local src = C.PlayerSrc(s.t)
    local bill = AI.Bill(NZA.Patients.Get(s.pid) or s.p, s.t, s.steps, true)
    local billable = false
    for _, st in ipairs(s.steps) do if st.applied and st.bill then billable = true break end end
    local paid, amount = true, 0
    if billable and src then
        local ok, a = charge(src, s.t, bill)
        paid, amount = ok, a
    end
    if src then
        TriggerClientEvent('nza:checkin:ai', src, 'abort', { reason = reason, bill = billable and bill or nil, paid = paid, amount = amount })
    end
    NZA.Bus.Emit('checkin:ai', s.t, reason)
end

local function inBed(p, pointId)
    local bed = p and p.meta and p.meta.bed
    return type(bed) == 'table' and tonumber(bed.point) == tonumber(pointId)
end

local function run(s)
    local lastVitals = 0
    local away = 0
    local pt = point(s.point)
    local bedPos = pos(pt)
    while sessions[s.t.id] == s and not s.done do
        Wait(500)
        if sessions[s.t.id] ~= s or s.done then return end
        local p = NZA.Patients.Get(s.pid)
        local src = C.PlayerSrc(s.t)
        local ok = p ~= nil and src ~= nil and p.state ~= 'dead'
        if ok then
            local me = NZA.Core.SrcCoords(src)
            local placed = inBed(p, s.point) and me ~= nil and bedPos ~= nil and #(me - bedPos) <= 4.5
            away = placed and 0 or away + 0.5
            if away >= 3 then ok = false end
        end
        if not ok then
            local why = (p == nil or src == nil) and 'gone' or (p.state == 'dead' and 'died' or 'left_bed')
            abort(s, why)
            C.Close(s.t, 'left')
            return
        end
        s.p = p
        local elapsed = (GetGameTimer() - s.startedMs) / 1000
        local acc = 0
        local idx = #s.steps
        for i, st in ipairs(s.steps) do
            acc = acc + st.time
            if elapsed < acc then idx = i break end
        end
        while s.idx < idx - 1 do
            s.idx = s.idx + 1
            applyStep(s, s.steps[s.idx])
        end
        if s.cur ~= idx then
            s.cur = idx
            TriggerClientEvent('nza:checkin:ai', src, 'step', { index = idx, elapsed = elapsed })
        end
        if GetGameTimer() - lastVitals >= 2000 then
            lastVitals = GetGameTimer()
            TriggerClientEvent('nza:checkin:ai', src, 'vitals', vitalsOf(p))
        end
        if elapsed >= s.total then
            while s.idx < #s.steps do
                s.idx = s.idx + 1
                applyStep(s, s.steps[s.idx])
            end
            finish(s)
            return
        end
    end
end

function AI.Session(id) return sessions[id] end

function AI.Start(t)
    if not t or sessions[t.id] then return false end
    local p = NZA.Patients.Get(t.pid)
    local src = C.PlayerSrc(t)
    if not p or not src or not t.bed then return false end
    local steps, total = AI.Plan(p)
    local s = {
        t = t, pid = p.pid, p = p, point = t.bed, steps = steps, total = total,
        startedMs = GetGameTimer(), idx = 0, cur = 0,
    }
    s.bill = AI.Bill(p, t, steps, false)
    sessions[t.id] = s
    TriggerClientEvent('nza:checkin:ai', src, 'start', publicSession(s))
    CreateThread(function()
        local ok, err = pcall(run, s)
        if not ok then
            NZA.Warn('checkin AI session failed: ' .. tostring(err))
            if sessions[t.id] == s then abort(s, 'error') C.Close(t, 'left') end
        end
    end)
    return true
end

function AI.Stop(t, reason)
    local s = t and sessions[t.id]
    if not s or s.done then return end
    abort(s, reason or 'stopped')
end

-- hand waiting tickets to the AI doctor
function AI.Tick(t0)
    if not cfg('ai', 'enabled', true) then return end
    local noStaff = cfg('ai', 'noStaff', true)
    local delay = tonumber(cfg('ai', 'noStaffDelay', 12)) or 12
    local timeout = tonumber(cfg('ai', 'waitTimeout', 600)) or 0
    local critical = tonumber(cfg('ai', 'criticalTimeout', 0)) or 0
    local staffCache, fullBeds = {}, {}
    for _, t in ipairs(C.Waiting(nil)) do
        if not fullBeds[t.hospital] and not t.aiDenied then
            local staff = staffCache[t.hospital]
            if staff == nil then
                staff = C.StaffCount(t.hospital)
                staffCache[t.hospital] = staff
            end
            local age = t0 - t.issued
            local take = (noStaff and staff == 0 and age >= delay) or (timeout > 0 and age >= timeout)
                or (critical > 0 and t.triage == 1 and age >= critical)
            -- the AI doctor cannot take a patient in cardiac arrest or dead (the bed lie refuses
            -- them): leave the ticket to the staff / the death listener in checkin.lua
            local p = take and NZA.Patients.Get(t.pid) or nil
            if p and (p.state == 'arrest' or p.state == 'dead') then take = false end
            if take then
                local src = C.PlayerSrc(t)
                if src then
                    if cfg('ai', 'requirePayment', false) and p then
                        local steps = AI.Plan(p)
                        local bill = AI.Bill(p, t, steps, false)
                        if bill.enabled and not canPay(src, bill.total) then
                            t.aiDenied = true
                            NZA.Core.Notify(src, { title = L('title'), message = L('ai_cant_pay', bill.total), type = 'error', duration = 8000 })
                        end
                    end
                    if not t.aiDenied then
                        local ok, err = C.Call(t, nil, nil, true)
                        if not ok and err == 'no_bed' then fullBeds[t.hospital] = true end
                    end
                end
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function rate(src, bucket, n, ms)
    return NZA.Core.Rate('checkin:' .. bucket, src, n, ms)
end

lib.callback.register('nza:checkin:lie', function(src, payload)
    if not rate(src, 'lie', 6, 5000) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local p = NZA.Patients.GetBySource(src)
    if not p then return fail('failed') end
    local t = C.ForSource(src)

    if not payload.on then
        if t and sessions[t.id] then AI.Stop(t, 'cancelled') C.Close(t, 'left') end
        local bed = p.meta and p.meta.bed
        local id = type(bed) == 'table' and tonumber(bed.point) or tonumber(payload.point)
        if id and NZA.Hospitals and NZA.Hospitals.BedOccupant and NZA.Hospitals.BedOccupant(id) == p.pid then
            NZA.Hospitals.ReleaseBed(id)
        end
        return { ok = true }
    end

    local pt = point(payload.point)
    if not pt or pt.type ~= 'bed' then return fail('bad_bed') end
    if not t or t.bed ~= pt.id or (t.status ~= 'called' and t.status ~= 'treatment') then return fail('not_your_bed') end
    if p.state == 'arrest' or p.state == 'dead' then return fail('state') end
    if p.meta and (p.meta.carried or p.meta.stretcher) then return fail('busy') end
    local travel = cfg('ai', 'travel', 'walk')
    local mayTeleport = payload.teleport == true and t.ai and t.status == 'called'
        and (travel == 'teleport' or (p.state == 'wounded' and cfg('ai', 'downedTeleport', true)))
    if p.state == 'wounded' and not mayTeleport then return fail('state') end
    if not mayTeleport then
        local me = NZA.Core.SrcCoords(src)
        local bp = pos(pt)
        if not me or not bp or #(me - bp) > 3.5 then return fail('too_far') end
    end
    if not (NZA.Hospitals and NZA.Hospitals.OccupyBed) then return fail('failed') end
    if not NZA.Hospitals.OccupyBed(pt.id, p.pid) then
        -- someone took it: find another one
        local ok = C.Call(t, nil, t.by, t.ai)
        return fail('bed_taken', { moved = ok == true })
    end
    local c = pt.coords
    return { ok = true, coords = { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 }, label = C.BedLabel(pt), mode = t.ai and 'ai' or 'rest' }
end)

lib.callback.register('nza:checkin:rest', function(src)
    if not rate(src, 'rest', 4, 3000) then return fail('rate') end
    local p = NZA.Patients.GetBySource(src)
    if not p then return fail('failed') end
    local bed = p.meta and p.meta.bed
    local isBed = type(bed) == 'table' and (bed.type == nil or bed.type == 'bed')
    local pt = isBed and point(bed.point) or nil
    local mult = (p.meta and p.meta.inBed) and 4 or 1
    local rateMin = (tonumber(Config.Physiology and Config.Physiology.healRate) or 0.4) * mult
    local list, sum, n, eta = {}, 0, 0, 0
    for _, inj in ipairs(sortedInjuries(p)) do
        local hm = 0
        if NZA.Physiology and NZA.Physiology.HealMultiplier then
            local ok, m = pcall(NZA.Physiology.HealMultiplier, p, inj)
            hm = ok and tonumber(m) or 0
        end
        local heal = math.floor(tonumber(inj.heal) or 0)
        local ty = NZA.Const.InjuryTypes[inj.type] or {}
        local rg = NZA.Const.Region[inj.region] or {}
        local secs = nil
        if hm > 0 and rateMin > 0 then
            secs = math.floor((100 - heal) / (rateMin * hm) * 60)
            eta = math.max(eta, secs)
        end
        list[#list + 1] = { label = ty.label or inj.type, short = ty.short, icon = TYPE_ICON[inj.type], region = rg.label or inj.region,
            heal = heal, severity = inj.severity, healing = hm > 0, eta = secs }
        sum, n = sum + heal, n + 1
    end
    local s = nil
    local t = C.ForSource(src)
    if t then s = sessions[t.id] end
    return {
        ok = true, inBed = isBed and pt ~= nil, point = pt and pt.id or nil, label = pt and C.BedLabel(pt) or nil,
        hospital = pt and C.HospitalLabel(pt.hospital) or nil, mult = mult, injuries = list,
        recovery = n > 0 and math.floor(sum / n) or 100, eta = n > 0 and eta or 0,
        blood = (p.bloodMax or 0) > 0 and math.floor((p.blood or 0) / p.bloodMax * 100 + 0.5) or 100,
        pain = math.floor(tonumber(p.pain) or 0), state = p.state, ai = s ~= nil,
    }
end)
