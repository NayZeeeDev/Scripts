--[[
    NAYZEEE AMBULANCE - Check-in (server): tickets, queue, staff calls, waiting room board

    A patient takes a ticket at a check-in desk point ('checkin', placed in game). Tickets are
    numbered per department, per desk letter and per day (A-001, A-002 ...), triaged with
    NZA.Patients.Triage (P1 Critical / P2 Urgent / P3 Standard) and wait in the department's
    queue (P1 first, then by time). Staff with Config.Checkin.desk.perm call the next patient
    to a free bed; with nobody on duty the AI doctor (checkin_ai.lua) takes them.

    Ticket life:  waiting → called (bed assigned, shown on the board) → treatment → closed
                  closed = done | noshow | left | cancelled

    SERVER API (everyone)
      NZA.Checkin.Queue(hospital?) → { { id, ticket, number, code, name, priority, tri, created,
                                         wait, status, bed, hospital, hospitalLabel }, … }
      NZA.Checkin.Get(id) → ticket | nil (live table, read only)
      NZA.Checkin.ForPid(pid) / ForSource(src) → open ticket | nil
      NZA.Checkin.CallNext(hospital, bySrc?) → ok, ticketOrErr       (bySrc nil/0 = system)
      NZA.Checkin.Call(id, bedPointId?, bySrc?, ai?) → ok, err
      NZA.Checkin.Close(id, status, bySrc?) → bool                 status done|noshow|left|cancelled
      NZA.Checkin.SetTreatment(id, bySrc?) → bool
      NZA.Checkin.Board(hospital) → waiting room board payload
      NZA.Checkin.Beds(hospital) → { { id, label, coords, state = 'free'|'occupied'|'reserved', ticket?, name? } }
      NZA.Checkin.BedLabel(point) → 'Bed 3'
      NZA.Checkin.StaffCount(hospital) → on-duty staff that count for the AI doctor
    Server export: GetCheckinQueue(hospital?)

    CALLBACKS (lib.callback)
      nza:checkin:checkin (pointId)          → { ok, ticket, say } | { ok = false, err, say }
      nza:checkin:mine    ()                 → { ok, ticket | nil }
      nza:checkin:leave   ()                 → { ok }
      nza:checkin:desk    ({ point?, hospital?, watch = bool }) → { ok, desk } (staff)
      nza:checkin:action  (action, data)     → { ok, msg? }  callNext call ai recall treatment treated noshow requeue cancel
      nza:checkin:tv      (hospital, on)     → { ok, board }
    NET EVENTS
      C→S nza:checkin:callNext (hospital?)   call the next patient (dispatch board, radial)
      S→C nza:checkin:mine (ticket | false, event)   own ticket changed (issued called treatment closed update)
      S→C nza:checkin:receipt (ticket)       show the paper receipt (ticket item used)
      S→C nza:checkin:staff (note)           staff notification (new patient, triage change, AI took a patient)
      S→C nza:checkin:desk (desk)            live reception window data (watchers only)
      S→C nza:checkin:board (hospital, board) live board data (TV watchers only)
      S→C nza:checkin:bed ({ point, on })    you were put in / taken out of a hospital bed (rest HUD)
    BUS  listens: hospital:bed transport:bed treat:done proc:done player:loaded player:unloaded patient:removed
                  patient:death (a waiting / called ticket is closed 'left')
         emits:   checkin:issued (t) checkin:called (t) checkin:treatment (t) checkin:closed (t, status)

    DATA  nza_tickets (created on start; also in sql/install.sql)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Checkin = NZA.Checkin or {}
local C = NZA.Checkin
local U = NZA.Util

local OPEN = { waiting = true, called = true, treatment = true }
local CLOSED = { done = true, noshow = true, left = true, cancelled = true }

local tickets = {}        -- [id] = ticket (open only)
local history = {}        -- [hospital] = { public closed ticket, … } newest first
local counters = {}       -- ['hosp|prefix|day'] = last number
local lastCheckin = {}    -- [identifier] = os.time()
local deskWatch = {}      -- [src] = hospital (reception window open)
local tvWatch = {}        -- [src] = hospital (near a board)
local reserved = {}       -- [bed point id] = ticket id
local dirty = {}          -- [hospital] = true (desk / board push pending)
local flushQueued = false
local dbOk = false

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section, key, default)
    local s = Config.Checkin and Config.Checkin[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end
C.Cfg = cfg

local function L(key, ...) return NZA.L('checkin.' .. key, ...) end
C.L = L

local function now() return os.time() end
local function today() return os.date('%Y-%m-%d') end

local function rate(src, bucket, n, ms)
    local r = Config.Checkin and Config.Checkin.rates or {}
    return NZA.Core.Rate('checkin:' .. (bucket or 'a'), src, n or tonumber(r.actions) or 12, ms or tonumber(r.window) or 10000)
end

local function fail(err, extra)
    local out = { ok = false, err = err, msg = L('err_' .. err) }
    if extra then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function hosp(id) return NZA.Hospitals and NZA.Hospitals.Get and NZA.Hospitals.Get(id) or nil end

local function hospitalLabel(id)
    local h = hosp(id)
    return (h and h.label) or L('hospital')
end
C.HospitalLabel = hospitalLabel

local function point(id)
    if not (NZA.Hospitals and NZA.Hospitals.Point) then return nil end
    return NZA.Hospitals.Point(id)
end

local function pointPos(pt)
    local c = pt and pt.coords
    if not c then return nil end
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
end
C.PointPos = pointPos

local function triageOf(p)
    local ok, lvl, label = pcall(NZA.Patients.Triage, p)
    if not ok then return 3, L('tri_3') end
    return U.clamp(math.floor(tonumber(lvl) or 3), 1, 3), label or L('tri_' .. tostring(lvl))
end

local function staffRec(src)
    local ok, rec = pcall(NZA.Staff.Get, src)
    return ok and type(rec) == 'table' and rec or {}
end

local function isStaffFor(src, hospital)
    local perm = cfg('desk', 'perm', 'checkin')
    if not NZA.Staff.Can(src, perm) then return false end
    if NZA.Core.IsAdmin(src) then return true end
    local rec = staffRec(src)
    return rec.hospital == nil or hospital == nil or rec.hospital == hospital
end
C.IsStaffFor = isStaffFor

local function playerSrc(t)
    if t.src and NZA.Core.Online(t.src) and NZA.Core.Identifier(t.src) == t.identifier then return t.src end
    if t.identifier and Bridge and Bridge.GetSourceFromIdentifier then
        local ok, s = pcall(Bridge.GetSourceFromIdentifier, t.identifier)
        s = ok and tonumber(s) or nil
        if s and NZA.Core.Online(s) then t.src = s return s end
    end
    return nil
end
C.PlayerSrc = playerSrc

local function patientOf(t)
    return NZA.Patients.Get(t.pid)
end

-- ════════════════════════════════════════════════════════════════════════
-- DATABASE
-- ════════════════════════════════════════════════════════════════════════

local function db(kind, sql, params, cb)
    if not dbOk or not MySQL or not MySQL[kind] then
        if cb then cb(nil) end
        return
    end
    local ok, err = pcall(MySQL[kind], sql, params or {}, function(res) if cb then cb(res) end end)
    if not ok then
        NZA.Warn('checkin: database error: ' .. tostring(err))
        if cb then cb(nil) end
    end
end

local function dbSave(t)
    local data = json.encode({ desk = t.desk, deskLabel = t.deskLabel, ai = t.ai or nil, by = t.byName })
    db('update', [[UPDATE nza_tickets SET status = ?, triage = ?, bed = ?, handled_by = ?, called = ?, closed = ?, data = ? WHERE id = ?]],
        { t.status, t.triage, t.bed, t.byName, t.called, t.closed, data, t.id })
end

local function dbInsert(t)
    db('insert', [[INSERT INTO nza_tickets (id, hospital, day, prefix, number, identifier, name, triage, status, issued, data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { t.id, t.hospital, t.day, t.prefix, t.number, t.identifier, t.name, t.triage, t.status, t.issued,
          json.encode({ desk = t.desk, deskLabel = t.deskLabel }) })
end

-- ════════════════════════════════════════════════════════════════════════
-- BEDS
-- ════════════════════════════════════════════════════════════════════════

local function bedPoints(hospital)
    if not (NZA.Hospitals and NZA.Hospitals.Points) then return {} end
    local ok, list = pcall(NZA.Hospitals.Points, 'bed', hospital)
    return ok and type(list) == 'table' and list or {}
end

function C.BedLabel(pt)
    if type(pt) ~= 'table' then return L('bed') end
    if type(pt.label) == 'string' and pt.label ~= '' then return pt.label end
    local list = bedPoints(pt.hospital)
    for i, b in ipairs(list) do
        if b.id == pt.id then return L('bed_n', i) end
    end
    return L('bed_n', tostring(pt.id))
end

local function occupant(id)
    if not (NZA.Hospitals and NZA.Hospitals.BedOccupant) then return nil end
    local ok, pid = pcall(NZA.Hospitals.BedOccupant, id)
    return ok and pid or nil
end

function C.Beds(hospital)
    local out = {}
    for _, b in ipairs(bedPoints(hospital)) do
        local pid = occupant(b.id)
        local rt = reserved[b.id] and tickets[reserved[b.id]]
        local e = { id = b.id, label = C.BedLabel(b), state = 'free' }
        if pid then
            local p = NZA.Patients.Get(pid)
            e.state, e.name = 'occupied', p and p.name or nil
            local t = C.ForPid(pid)
            if t then e.ticket = t.code end
        elseif rt then
            e.state, e.ticket, e.name = 'reserved', rt.code, rt.name
        end
        out[#out + 1] = e
    end
    return out
end

local function freeBed(hospital, prefer)
    local list = bedPoints(hospital)
    if prefer then
        for _, b in ipairs(list) do
            if b.id == prefer and not occupant(b.id) and (not reserved[b.id]) then return b end
        end
    end
    for _, b in ipairs(list) do
        if not occupant(b.id) and not reserved[b.id] then return b end
    end
    return nil
end
C.FreeBed = freeBed

local function release(t)
    if t.bed and reserved[t.bed] == t.id then reserved[t.bed] = nil end
end

-- ════════════════════════════════════════════════════════════════════════
-- QUEUE ORDER / PUBLIC SHAPES
-- ════════════════════════════════════════════════════════════════════════

local function before(a, b)
    if a.triage ~= b.triage then return a.triage < b.triage end
    if a.issued ~= b.issued then return a.issued < b.issued end
    return a.number < b.number
end

local function waitingList(hospital)
    local list = {}
    for _, t in pairs(tickets) do
        if t.status == 'waiting' and (not hospital or t.hospital == hospital) then list[#list + 1] = t end
    end
    table.sort(list, before)
    return list
end
C.Waiting = waitingList

local function openList(hospital)
    local list = {}
    for _, t in pairs(tickets) do
        if not hospital or t.hospital == hospital then list[#list + 1] = t end
    end
    local rank = { called = 1, treatment = 2, waiting = 3 }
    table.sort(list, function(a, b)
        if rank[a.status] ~= rank[b.status] then return rank[a.status] < rank[b.status] end
        return before(a, b)
    end)
    return list
end

local function aheadOf(t)
    if t.status ~= 'waiting' then return 0 end
    local n = 0
    for _, o in pairs(tickets) do
        if o ~= t and o.hospital == t.hospital and o.status == 'waiting' and before(o, t) then n = n + 1 end
    end
    return n
end

local function staffCount(hospital)
    local perm = cfg('ai', 'staffPerm', 'checkin')
    local n = 0
    local ok, list = pcall(NZA.Staff.OnDuty)
    if not ok or type(list) ~= 'table' then return 0 end
    for _, s in ipairs(list) do
        local rec = staffRec(s)
        if rec.onDuty ~= false and (rec.hospital == nil or rec.hospital == hospital) and (not perm or NZA.Staff.Can(s, perm)) then
            n = n + 1
        end
    end
    return n
end
C.StaffCount = staffCount

local function estimateFor(t)
    if t.status ~= 'waiting' then return 0 end
    local per = cfg('queue', 'estimate', { 4, 8, 12 })
    local secs = 0
    for _, o in pairs(tickets) do
        if o ~= t and o.hospital == t.hospital and (o.status == 'waiting' and before(o, t) or o.status == 'called') then
            secs = secs + (tonumber(per[o.triage]) or 8) * 60
        end
    end
    local staff = math.max(1, staffCount(t.hospital))
    return math.floor(secs / staff)
end

local function injurySummary(p)
    local out = {}
    if not p then return out end
    local list = {}
    for _, inj in pairs(p.injuries or {}) do list[#list + 1] = inj end
    table.sort(list, function(a, b) return (a.severity or 0) > (b.severity or 0) end)
    for i = 1, math.min(6, #list) do
        local inj = list[i]
        local ty = NZA.Const.InjuryTypes[inj.type] or {}
        local rg = NZA.Const.Region[inj.region] or {}
        out[#out + 1] = { type = inj.type, short = ty.short or inj.type, label = ty.label or inj.type,
            region = rg.label or inj.region, severity = inj.severity, status = inj.status }
    end
    return out, #list
end

function C.Public(t, full)
    if not t then return nil end
    local out = {
        id = t.id, code = t.code, number = t.number, prefix = t.prefix, hospital = t.hospital,
        hospitalLabel = hospitalLabel(t.hospital), desk = t.deskLabel, status = t.status,
        triage = t.triage, triageLabel = t.triageLabel, issued = t.issued, called = t.called,
        treatmentAt = t.treatmentAt, closed = t.closed, bed = t.bedLabel, bedId = t.bed, ai = t.ai == true,
        ahead = aheadOf(t), estimate = estimateFor(t), now = now(), name = t.name,
        by = t.byName,
    }
    if t.bed then
        local pt = point(t.bed)
        local c = pt and pt.coords
        if c then out.bedCoords = { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 } end
    end
    if full then
        local p = patientOf(t)
        out.injuries, out.injuryCount = injurySummary(p)
        out.state = p and p.state or nil
        out.blood = p and p.bloodMax and math.floor(((p.blood or 0) / p.bloodMax) * 100 + 0.5) or nil
        out.online = playerSrc(t) ~= nil
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- PUSHES (desk windows, boards, the patient)
-- ════════════════════════════════════════════════════════════════════════

local function pushMine(t, event)
    local src = playerSrc(t)
    if not src then return end
    if t.status and OPEN[t.status] and tickets[t.id] == t then
        TriggerClientEvent('nza:checkin:mine', src, C.Public(t), event or 'update')
    else
        TriggerClientEvent('nza:checkin:mine', src, false, event or 'closed', C.Public(t))
    end
end
C.PushMine = pushMine

-- ── ambulances on the way (waiting room board) ──────────────────────────

local function vehEnt(net)
    net = tonumber(net)
    if not net then return 0 end
    local e = NetworkGetEntityFromNetworkId(net)
    if not e or e == 0 or not DoesEntityExist(e) then return 0 end
    return e
end

local function pedVehNet(ped)
    if not ped or ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return nil end
    return NetworkGetNetworkIdFromEntity(veh)
end

-- department nearest to coords → id, distance (dispatch's rule, else the hospital module's)
local function nearestDept(coords)
    local D = NZA.Dispatch
    if D and D.NearestHospital then
        local ok, h, d = pcall(D.NearestHospital, coords)
        if ok and h and d and d < math.huge then return h.id, d end
        return nil
    end
    local H = NZA.Hospitals
    if H and H.Nearest then
        local ok, h, d = pcall(H.Nearest, coords)
        if ok and type(h) == 'table' and d then return h.id, d end
    end
    return nil
end

local function plateOf(veh)
    local ok, plate = pcall(GetVehicleNumberPlateText, veh)
    plate = ok and type(plate) == 'string' and plate:gsub('^%s+', ''):gsub('%s+$', '') or ''
    return plate ~= '' and plate or nil
end

-- Units in TRN (dispatch calls), ambulances that loaded a patient without a 911 call
-- (NZA.Transport.trips) and the AI ambulance in its transport stage (NZA.AIMedic.Jobs),
-- when their nearest department is this one. One card per vehicle.
local function incoming(hospital)
    local out = {}
    local D = NZA.Dispatch
    local dcfg = Config.Dispatch and Config.Dispatch.status or {}
    local speed = tonumber(dcfg.etaSpeed) or tonumber(cfg('tv', 'etaSpeed', 19.0)) or 19.0
    local arriving = tonumber(cfg('tv', 'arriving', 150.0)) or 150.0
    local seenVeh, seenSrc, seenCall = {}, {}, {}
    local function add(unit, priority, d, title)
        out[#out + 1] = {
            unit = unit or '?',
            priority = tonumber(priority) or 3,
            eta = math.max(0, math.floor(d / math.max(1.0, speed))),
            arriving = d <= arriving,
            title = title,
        }
    end
    local unitBySrc = {}
    if D and D.Units and D.NearestHospital then
        local ok, units = pcall(D.Units, true)
        if ok and type(units) == 'table' then
            for _, u in ipairs(units) do
                if u.src then unitBySrc[u.src] = u end
                if u.status == 'TRN' and u.x and u.y then
                    local hok, h, d = pcall(D.NearestHospital, vector3(u.x + 0.0, u.y + 0.0, (u.z or 0.0) + 0.0))
                    if hok and h and h.id == hospital and d and d < math.huge then
                        local call = u.call and D.Get and D.Get(u.call) or nil
                        add(u.callsign or u.short or u.name, call and call.priority or 3, d, call and call.title or nil)
                        if u.src then
                            seenSrc[u.src] = true
                            local vn = pedVehNet(GetPlayerPed(u.src))
                            if vn then seenVeh[vn] = true end
                        end
                        if u.call then seenCall[u.call] = true end
                    end
                end
            end
        end
    end
    -- ambulance trips (stretcher loaded) — also the ones without a dispatch call
    local Tr = NZA.Transport
    local P = NZA.Patients
    if Tr and type(Tr.trips) == 'table' and P and P.Get then
        for pid, trip in pairs(Tr.trips) do
            local vn = tonumber(trip.veh)
            local veh = vn and not seenVeh[vn] and vehEnt(vn) or 0
            local p = veh ~= 0 and P.Get(pid) or nil
            local m = p and p.meta or {}
            -- still in that ambulance (unloaded patients keep the trip until they reach a bed)
            if p and (tonumber(m.vehicle) == vn or tonumber(m.bay) == vn) then
                local call = D and D.CallForPatient and D.CallForPatient(p) or nil
                local driverSrc
                local drv = GetPedInVehicleSeat(veh, -1)
                if drv and drv ~= 0 then
                    for src, _ in pairs(unitBySrc) do
                        if GetPlayerPed(src) == drv then driverSrc = src break end
                    end
                end
                if not (call and seenCall[call.id]) and not (driverSrc and seenSrc[driverSrc]) then
                    local id, d = nearestDept(GetEntityCoords(veh))
                    if id == hospital and d then
                        local u = driverSrc and unitBySrc[driverSrc] or nil
                        local tri = (call and tonumber(call.priority)) or (P.Triage and P.Triage(pid)) or 3
                        add((u and (u.callsign or u.short)) or plateOf(veh), tri, d, call and call.title or nil)
                        seenVeh[vn] = true
                        if driverSrc then seenSrc[driverSrc] = true end
                        if call then seenCall[call.id] = true end
                    end
                end
            end
        end
    end
    -- AI ambulance driving a patient in
    local A = NZA.AIMedic
    if A and A.Jobs and P and P.Get then
        local ok, jobs = pcall(A.Jobs)
        if ok and type(jobs) == 'table' then
            for _, job in pairs(jobs) do
                local vn = tonumber(job.veh)
                local veh = job.state == 'transport' and vn and not seenVeh[vn] and vehEnt(vn) or 0
                if veh ~= 0 and not (job.callId and seenCall[job.callId]) then
                    local c = GetEntityCoords(veh)
                    local dest = job.hospital
                    local id, d
                    if type(dest) == 'table' and dest.hospital and dest.coords then
                        id = dest.hospital
                        d = #(c - vector3(dest.coords.x + 0.0, dest.coords.y + 0.0, dest.coords.z + 0.0))
                    else
                        id, d = nearestDept(c)
                    end
                    if id == hospital and d then
                        local tri = P.Triage and P.Get(job.pid) and P.Triage(job.pid) or 3
                        add(NZA.L('calls.ai_unit'), tri, d, nil)
                        seenVeh[vn] = true
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.eta < b.eta end)
    local max = tonumber(cfg('tv', 'maxIncoming', 3)) or 3
    while #out > max do table.remove(out) end
    return out
end

function C.Board(hospital)
    local serving, waiting = {}, {}
    local inTreatment = 0
    local keep = tonumber(cfg('queue', 'keepServing', 120)) or 120
    local t0 = now()
    local list = openList(hospital)
    for _, t in ipairs(list) do
        if t.status == 'called' then
            serving[#serving + 1] = { code = t.code, triage = t.triage, bed = t.bedLabel, status = t.status, at = t.called }
        elseif t.status == 'treatment' then
            inTreatment = inTreatment + 1
            if t.treatmentAt and t0 - t.treatmentAt <= keep then
                serving[#serving + 1] = { code = t.code, triage = t.triage, bed = t.bedLabel, status = t.status, at = t.called or t.treatmentAt }
            end
        end
    end
    table.sort(serving, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local maxServing = tonumber(cfg('queue', 'maxServing', 3)) or 3
    while #serving > maxServing do table.remove(serving) end
    local wl = waitingList(hospital)
    local maxWaiting = tonumber(cfg('tv', 'maxWaiting', 7)) or 7
    for i, t in ipairs(wl) do
        if i > maxWaiting then break end
        waiting[#waiting + 1] = { code = t.code, triage = t.triage, issued = t.issued }
    end
    local beds = C.Beds(hospital)
    local free = 0
    for _, b in ipairs(beds) do if b.state == 'free' then free = free + 1 end end
    local h = hosp(hospital)
    local staff = staffCount(hospital)
    return {
        hospital = hospital, label = hospitalLabel(hospital), now = t0,
        serving = serving, waiting = waiting, waitingMore = math.max(0, #wl - #waiting),
        incoming = incoming(hospital),
        counts = { waiting = #wl, treatment = inTreatment, bedsFree = free, bedsTotal = #beds, staff = staff },
        ai = cfg('ai', 'enabled', true) == true and cfg('ai', 'noStaff', true) == true and staff == 0,
        hq = h and h.hq and true or false,
    }
end

local function historyOf(hospital)
    return history[hospital] or {}
end

local function deskPayload(hospital)
    local list = {}
    for _, t in ipairs(openList(hospital)) do list[#list + 1] = C.Public(t, true) end
    local hist = historyOf(hospital)
    local served, noshow, waitSum, waitN = 0, 0, 0, 0
    for _, h in ipairs(hist) do
        if h.status == 'done' then served = served + 1 end
        if h.status == 'noshow' then noshow = noshow + 1 end
        if h.waited then waitSum, waitN = waitSum + h.waited, waitN + 1 end
    end
    local staff = staffCount(hospital)
    local aiTreating = 0
    for _, t in pairs(tickets) do if t.hospital == hospital and t.ai and t.status == 'treatment' then aiTreating = aiTreating + 1 end end
    return {
        hospital = hospital, label = hospitalLabel(hospital), now = now(),
        tickets = list, beds = C.Beds(hospital), history = hist, staff = staff,
        ai = { enabled = cfg('ai', 'enabled', true) == true, standby = cfg('ai', 'noStaff', true) and staff == 0,
               treating = aiTreating, timeout = tonumber(cfg('ai', 'waitTimeout', 0)) or 0 },
        stats = { served = served, noshow = noshow, avgWait = waitN > 0 and math.floor(waitSum / waitN) or nil },
    }
end

local function flush()
    flushQueued = false
    local list = dirty
    dirty = {}
    for hospital in pairs(list) do
        local board, desk
        for src, h in pairs(tvWatch) do
            if h == hospital then
                if NZA.Core.Online(src) then
                    board = board or C.Board(hospital)
                    TriggerClientEvent('nza:checkin:board', src, hospital, board)
                else
                    tvWatch[src] = nil
                end
            end
        end
        for src, h in pairs(deskWatch) do
            if h == hospital then
                if NZA.Core.Online(src) and isStaffFor(src, hospital) then
                    desk = desk or deskPayload(hospital)
                    TriggerClientEvent('nza:checkin:desk', src, desk)
                else
                    deskWatch[src] = nil
                end
            end
        end
    end
end

local function changed(hospital)
    if not hospital then return end
    dirty[hospital] = true
    if flushQueued then return end
    flushQueued = true
    SetTimeout(200, flush)
end
C.Changed = changed

-- every open ticket of a hospital: ahead / estimate change for everyone behind
local function pushAll(hospital)
    for _, t in pairs(tickets) do
        if t.hospital == hospital and t.status == 'waiting' then pushMine(t, 'update') end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STAFF NOTIFICATIONS
-- ════════════════════════════════════════════════════════════════════════

local function notifyStaff(t, kind, extra)
    local n = cfg('queue', 'notify', {})
    local perm = cfg('desk', 'perm', 'checkin')
    local ok, list = pcall(NZA.Staff.OnDuty)
    if not ok or type(list) ~= 'table' then return end
    local note = {
        kind = kind, code = t.code, triage = t.triage, triageLabel = t.triageLabel, name = t.name,
        hospital = t.hospital, hospitalLabel = hospitalLabel(t.hospital), bed = t.bedLabel,
        toast = n.toast ~= false, sound = n.sound ~= false,
    }
    if extra then for k, v in pairs(extra) do note[k] = v end end
    for _, s in ipairs(list) do
        local rec = staffRec(s)
        local scopeOk = n.scope == 'all' or rec.hospital == nil or rec.hospital == t.hospital or NZA.Core.IsAdmin(s)
        if scopeOk and NZA.Staff.Can(s, perm) and s ~= t.src then
            TriggerClientEvent('nza:checkin:staff', s, note)
            -- pager line (when the dispatch module offers one)
            if kind == 'new' and n.pager ~= false and NZA.Dispatch and type(NZA.Dispatch.Page) == 'function' then
                pcall(NZA.Dispatch.Page, s, { kind = 'checkin', priority = t.triage, title = L('pager_title', t.code),
                    text = L('staff_new', t.code, ('P%d %s'):format(t.triage, t.triageLabel or '')), hospital = hospitalLabel(t.hospital) })
            end
            local phone = n.phone
            if kind == 'new' and phone and Bridge and Bridge.Phone and Bridge.Phone.Notify then
                local paired = phone == true or (phone == 'paired' and NZA.Dispatch and NZA.Dispatch.Paired and NZA.Dispatch.Paired(s))
                if paired then
                    pcall(Bridge.Phone.Notify, s, { title = L('phone_title', hospitalLabel(t.hospital)),
                        message = L('staff_new', t.code, ('P%d %s'):format(t.triage, t.triageLabel or '')), icon = 'ticket' })
                end
            end
        end
    end
end
C.NotifyStaff = notifyStaff

-- ════════════════════════════════════════════════════════════════════════
-- ITEM
-- ════════════════════════════════════════════════════════════════════════

local function itemName() return Config.Items and Config.Items.triage_ticket or nil end

local function giveItem(src, t)
    if not cfg('desk', 'giveItem', true) then return end
    local name = itemName()
    if not name or not (Bridge and Bridge.Inv and Bridge.Inv.AddItem) then return end
    local meta = {
        ticket = t.code, ticketId = t.id, hospital = hospitalLabel(t.hospital),
        triage = ('P%d %s'):format(t.triage, t.triageLabel or ''), issued = os.date('%H:%M', t.issued),
        description = L('item_desc', t.code, hospitalLabel(t.hospital)), label = L('item_label', t.code),
    }
    local ok, given = pcall(Bridge.Inv.AddItem, src, name, 1, meta)
    t.item = ok and given and true or false
end

local function takeItem(t)
    if not t.item or not cfg('desk', 'takeBack', true) then return end
    local src = playerSrc(t)
    local name = itemName()
    if not src or not name or not (Bridge and Bridge.Inv and Bridge.Inv.Search and Bridge.Inv.RemoveItem) then return end
    local ok, found = pcall(Bridge.Inv.Search, src, name)
    if not ok or type(found) ~= 'table' then return end
    for _, it in ipairs(found) do
        local m = type(it.metadata) == 'table' and it.metadata or {}
        if m.ticketId == t.id then
            pcall(Bridge.Inv.RemoveItem, src, name, 1, m, it.slot)
            t.item = false
            return
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

function C.Get(id) return tickets[id] end

function C.ForPid(pid)
    if not pid then return nil end
    for _, t in pairs(tickets) do if t.pid == pid then return t end end
    return nil
end

function C.ForSource(src)
    local ident = NZA.Core.Identifier(src)
    if not ident then return nil end
    for _, t in pairs(tickets) do if t.identifier == ident then return t end end
    return nil
end

local function nextNumber(hospital, prefix)
    local key = ('%s|%s|%s'):format(hospital, prefix, today())
    counters[key] = (counters[key] or 0) + 1
    return counters[key]
end

local function formatCode(prefix, number)
    local digits = U.clamp(math.floor(tonumber(cfg('desk', 'digits', 3)) or 3), 1, 6)
    return ('%s-%0' .. digits .. 'd'):format(prefix, number)
end

local function sanitizePrefix(v)
    local s = tostring(v or ''):upper():gsub('[^A-Z0-9]', '')
    if s == '' then s = tostring(cfg('desk', 'prefix', 'A')):upper():gsub('[^A-Z0-9]', '') end
    if s == '' then s = 'A' end
    return s:sub(1, 2)
end

local function addHistory(t)
    local h = history[t.hospital] or {}
    local pub = C.Public(t)
    pub.waited = t.called and (t.called - t.issued) or nil
    table.insert(h, 1, pub)
    local max = tonumber(cfg('queue', 'history', 40)) or 40
    while #h > max do table.remove(h) end
    history[t.hospital] = h
end

function C.Close(id, status, bySrc)
    local t = type(id) == 'table' and id or tickets[id]
    if not t or not tickets[t.id] then return false end
    if not CLOSED[status] then status = 'cancelled' end
    if C.AI and C.AI.Stop then C.AI.Stop(t, 'closed') end
    release(t)
    tickets[t.id] = nil
    t.status = status
    t.closed = now()
    if bySrc and bySrc ~= 0 and not t.byName then t.byName = NZA.Core.Name(bySrc) end
    addHistory(t)
    dbSave(t)
    takeItem(t)
    pushMine(t, 'closed')
    NZA.Bus.Emit('checkin:closed', t, status)
    changed(t.hospital)
    pushAll(t.hospital)
    return true
end

function C.SetTreatment(id, bySrc)
    local t = type(id) == 'table' and id or tickets[id]
    if not t or not tickets[t.id] or t.status == 'treatment' then return false end
    t.status = 'treatment'
    t.treatmentAt = now()
    t.called = t.called or t.treatmentAt
    if bySrc and bySrc ~= 0 then t.by, t.byName = bySrc, NZA.Core.Name(bySrc) end
    dbSave(t)
    pushMine(t, 'treatment')
    NZA.Bus.Emit('checkin:treatment', t)
    changed(t.hospital)
    pushAll(t.hospital)
    return true
end

function C.Call(id, bedId, bySrc, ai)
    local t = type(id) == 'table' and id or tickets[id]
    if not t or not tickets[t.id] then return false, 'no_ticket' end
    if t.status == 'treatment' then return false, 'in_treatment' end
    local bed
    if bedId then
        local pt = point(bedId)
        if not pt or pt.type ~= 'bed' or pt.hospital ~= t.hospital then return false, 'bad_bed' end
        if occupant(pt.id) or (reserved[pt.id] and reserved[pt.id] ~= t.id) then return false, 'bed_busy' end
        bed = pt
    else
        if t.bed and reserved[t.bed] == t.id then bed = point(t.bed) end
        bed = bed or freeBed(t.hospital)
    end
    if not bed then return false, 'no_bed' end
    release(t)
    reserved[bed.id] = t.id
    t.bed, t.bedLabel = bed.id, C.BedLabel(bed)
    t.status = 'called'
    t.called = now()
    t.ai = ai == true
    if ai then
        t.by, t.byName = nil, L('ai_name')
    elseif bySrc and bySrc ~= 0 then
        t.by, t.byName = bySrc, NZA.Core.Name(bySrc)
    end
    dbSave(t)
    pushMine(t, 'called')
    NZA.Bus.Emit('checkin:called', t)
    changed(t.hospital)
    pushAll(t.hospital)
    if ai then notifyStaff(t, 'ai') end
    return true, t
end

function C.CallNext(hospital, bySrc)
    local list = waitingList(hospital)
    if #list == 0 then return false, 'empty' end
    for _, t in ipairs(list) do
        local ok, err = C.Call(t, nil, bySrc, false)
        if ok then return true, t end
        if err == 'no_bed' then return false, err end
    end
    return false, 'empty'
end

local function requeue(t)
    if not tickets[t.id] then return false end
    if C.AI and C.AI.Stop then C.AI.Stop(t, 'requeue') end
    release(t)
    t.status, t.bed, t.bedLabel, t.called, t.treatmentAt, t.ai = 'waiting', nil, nil, nil, nil, false
    t.by, t.byName = nil, nil
    dbSave(t)
    pushMine(t, 'update')
    changed(t.hospital)
    pushAll(t.hospital)
    return true
end
C.Requeue = requeue

function C.Queue(hospital)
    local out = {}
    local t0 = now()
    for _, t in ipairs(openList(hospital)) do
        out[#out + 1] = {
            id = t.id, ticket = t.code, number = t.number, code = t.code, name = t.name,
            priority = t.triage, tri = t.triage, created = t.issued, wait = t0 - t.issued,
            status = t.status, bed = t.bedLabel, hospital = t.hospital, hospitalLabel = hospitalLabel(t.hospital),
        }
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- CHECK IN
-- ════════════════════════════════════════════════════════════════════════

local function hasSomethingToTreat(p)
    if next(p.injuries or {}) then return true end
    for _ in pairs(p.conditions or {}) do return true end
    if (p.bloodMax or 0) > 0 and (p.blood or 0) / p.bloodMax < 0.9 then return true end
    return p.state ~= 'alive'
end

local function issue(src, pt)
    local p = NZA.Patients.GetBySource(src)
    if not p then return fail('failed') end
    local ident = NZA.Core.Identifier(src)
    if not ident then return fail('failed') end
    local existing = C.ForSource(src)
    if existing then
        existing.src = src
        return { ok = true, ticket = C.Public(existing), again = true, say = 'say_again' }
    end
    if p.state == 'arrest' or p.state == 'dead' then return fail('state') end
    if p.state == 'wounded' and not cfg('desk', 'allowDowned', true) then return fail('state') end
    if p.meta and (p.meta.carried or p.meta.stretcher or p.meta.bed) then return fail('busy') end
    if cfg('desk', 'requireInjury', true) and not hasSomethingToTreat(p) then
        return fail('nothing', { say = 'say_nothing' })
    end
    local cd = tonumber(cfg('desk', 'cooldown', 15)) or 15
    if lastCheckin[ident] and now() - lastCheckin[ident] < cd then return fail('cooldown') end
    lastCheckin[ident] = now()

    local hospital = pt.hospital
    local prefix = sanitizePrefix(pt.data and pt.data.prefix)
    local number = nextNumber(hospital, prefix)
    local tri, triLabel = triageOf(p)
    local t = {
        id = U.uid('T'), hospital = hospital, prefix = prefix, number = number, code = formatCode(prefix, number),
        day = today(), pid = p.pid, identifier = ident, src = src, name = p.name or NZA.Core.Name(src),
        triage = tri, triageLabel = triLabel, status = 'waiting', issued = now(),
        desk = pt.id, deskLabel = (type(pt.label) == 'string' and pt.label ~= '' and pt.label) or L('desk'),
    }
    tickets[t.id] = t
    dbInsert(t)
    giveItem(src, t)
    notifyStaff(t, 'new')
    NZA.Bus.Emit('checkin:issued', t)
    changed(hospital)
    local pub = C.Public(t)
    local say = tri == 1 and 'say_p1' or (pub.ahead == 0 and 'say_next' or 'say_wait')
    return { ok = true, ticket = pub, say = say }
end

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITAL RESOLUTION FOR STAFF
-- ════════════════════════════════════════════════════════════════════════

local function hospitalFor(src, wanted, pointId)
    if pointId then
        local pt = point(pointId)
        if pt and pt.type == 'checkin' then
            local me = NZA.Core.SrcCoords(src)
            local pos = pointPos(pt)
            if me and pos and #(me - pos) <= (tonumber(cfg('desk', 'promptDistance', 2.6)) or 2.6) + 4.0 then
                return pt.hospital
            end
        end
    end
    local rec = staffRec(src)
    if wanted and hosp(wanted) then
        if NZA.Core.IsAdmin(src) or rec.hospital == nil or rec.hospital == wanted then return wanted end
    end
    if rec.hospital and hosp(rec.hospital) then return rec.hospital end
    -- no department: the nearest one that has a check-in desk
    local me = NZA.Core.SrcCoords(src)
    if not me or not (NZA.Hospitals and NZA.Hospitals.Points) then return nil end
    local ok, desks = pcall(NZA.Hospitals.Points, 'checkin')
    if not ok or type(desks) ~= 'table' then return nil end
    local best, bestD = nil, math.huge
    for _, d in ipairs(desks) do
        local pos = pointPos(d)
        local dist = pos and #(me - pos) or math.huge
        if dist < bestD then best, bestD = d, dist end
    end
    return best and best.hospital or nil
end
C.HospitalFor = hospitalFor

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:checkin:checkin', function(src, pointId)
    if not rate(src, 'checkin', 4, 5000) then return fail('rate') end
    local pt = point(tonumber(pointId) or pointId)
    if not pt or pt.type ~= 'checkin' then return fail('no_desk') end
    local me = NZA.Core.SrcCoords(src)
    local pos = pointPos(pt)
    if not me or not pos or #(me - pos) > (tonumber(cfg('desk', 'promptDistance', 2.6)) or 2.6) + 1.5 then
        return fail('too_far')
    end
    return issue(src, pt)
end)

lib.callback.register('nza:checkin:mine', function(src)
    if not rate(src, 'mine', 8, 5000) then return fail('rate') end
    local t = C.ForSource(src)
    if t then t.src = src end
    return { ok = true, ticket = t and C.Public(t) or nil }
end)

lib.callback.register('nza:checkin:leave', function(src)
    if not rate(src, 'leave', 3, 5000) then return fail('rate') end
    local t = C.ForSource(src)
    if not t then return fail('no_ticket') end
    if t.status == 'treatment' then return fail('in_treatment') end
    C.Close(t, 'left', nil)
    return { ok = true, msg = L('left_queue', t.code) }
end)

lib.callback.register('nza:checkin:desk', function(src, payload)
    if not rate(src, 'desk', 10, 5000) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    if payload.watch == false then
        deskWatch[src] = nil
        return { ok = true }
    end
    local hospital = hospitalFor(src, payload.hospital, payload.point)
    if not hospital then return fail('no_hospital') end
    if not isStaffFor(src, hospital) then return fail('no_perm') end
    deskWatch[src] = hospital
    local desk = deskPayload(hospital)
    if NZA.Core.IsAdmin(src) and NZA.Hospitals and NZA.Hospitals.All then
        local list = {}
        for _, h in ipairs(NZA.Hospitals.All()) do list[#list + 1] = { id = h.id, label = h.label } end
        desk.hospitals = list
    end
    return { ok = true, desk = desk }
end)

local ACTIONS = {}

ACTIONS.callNext = function(src, data)
    local hospital = hospitalFor(src, data.hospital, data.point)
    if not hospital then return fail('no_hospital') end
    if not isStaffFor(src, hospital) then return fail('no_perm') end
    local ok, res = C.CallNext(hospital, src)
    if not ok then return fail(res) end
    return { ok = true, msg = L('called_ok', res.code, res.bedLabel or '') }
end

local function ticketFor(src, data)
    local t = tickets[tostring(data.id or '')]
    if not t then return nil, fail('no_ticket') end
    if not isStaffFor(src, t.hospital) then return nil, fail('no_perm') end
    return t
end

ACTIONS.call = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    local ok, e = C.Call(t, tonumber(data.bed), src, false)
    if not ok then return fail(e) end
    return { ok = true, msg = L('called_ok', t.code, t.bedLabel or '') }
end

ACTIONS.ai = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    if not cfg('ai', 'enabled', true) then return fail('ai_off') end
    if t.status == 'treatment' then return fail('in_treatment') end
    local ok, e = C.Call(t, tonumber(data.bed) or (t.status == 'called' and t.bed or nil), src, true)
    if not ok then return fail(e) end
    return { ok = true, msg = L('ai_took', t.code) }
end

ACTIONS.recall = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    if t.status ~= 'called' then return fail('not_called') end
    t.called = now()
    pushMine(t, 'called')
    changed(t.hospital)
    return { ok = true, msg = L('recalled', t.code) }
end

ACTIONS.treatment = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    C.SetTreatment(t, src)
    return { ok = true }
end

ACTIONS.treated = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    t.by, t.byName = src, NZA.Core.Name(src)
    C.Close(t, 'done', src)
    return { ok = true, msg = L('marked_done', t.code) }
end

ACTIONS.noshow = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    C.Close(t, 'noshow', src)
    return { ok = true, msg = L('marked_noshow', t.code) }
end

ACTIONS.cancel = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    C.Close(t, 'cancelled', src)
    return { ok = true, msg = L('marked_cancel', t.code) }
end

ACTIONS.requeue = function(src, data)
    local t, err = ticketFor(src, data)
    if not t then return err end
    requeue(t)
    return { ok = true, msg = L('requeued', t.code) }
end

lib.callback.register('nza:checkin:action', function(src, action, data)
    if not rate(src, 'action') then return fail('rate') end
    local fn = type(action) == 'string' and ACTIONS[action]
    if not fn then return fail('failed') end
    local ok, res = pcall(fn, src, type(data) == 'table' and data or {})
    if not ok then
        NZA.Warn('checkin action ' .. action .. ' failed: ' .. tostring(res))
        return fail('failed')
    end
    return res
end)

RegisterNetEvent('nza:checkin:callNext', function(hospital)
    local src = source
    if NZA.Core.IsLocalSource(src) then return end
    if not rate(src, 'action') then return end
    local res = ACTIONS.callNext(src, { hospital = type(hospital) == 'string' and hospital or nil })
    NZA.Core.Notify(src, { title = L('title'), message = res.msg or L('err_failed'), type = res.ok and 'success' or 'error' })
end)

lib.callback.register('nza:checkin:tv', function(src, hospital, on)
    if not rate(src, 'tv', 10, 5000) then return fail('rate') end
    if on == false or not hospital then
        tvWatch[src] = nil
        return { ok = true }
    end
    if not hosp(hospital) then return fail('no_hospital') end
    -- only near one of that hospital's boards
    local me = NZA.Core.SrcCoords(src)
    local near = false
    if me and NZA.Hospitals and NZA.Hospitals.Points then
        local ok, list = pcall(NZA.Hospitals.Points, 'tv', hospital)
        if ok and type(list) == 'table' then
            local max = (tonumber(cfg('tv', 'drawDistance', 28.0)) or 28.0) + 15.0
            for _, b in ipairs(list) do
                local pos = pointPos(b)
                if pos and #(me - pos) <= max then near = true break end
            end
        end
    end
    if not near then return fail('too_far') end
    tvWatch[src] = hospital
    return { ok = true, board = C.Board(hospital) }
end)

-- ════════════════════════════════════════════════════════════════════════
-- ITEM USE (show the receipt again)
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local name = itemName()
    if not name or not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src, item)
        if not rate(src, 'item', 4, 3000) then return end
        local meta = type(item) == 'table' and type(item.metadata) == 'table' and item.metadata or {}
        local t = meta.ticketId and tickets[meta.ticketId] or nil
        local ident = NZA.Core.Identifier(src)
        if t and t.identifier == ident then
            t.src = src
            TriggerClientEvent('nza:checkin:receipt', src, C.Public(t))
            return
        end
        -- an old ticket: show it stamped as no longer valid
        TriggerClientEvent('nza:checkin:receipt', src, {
            code = meta.ticket or '?', hospitalLabel = meta.hospital or L('hospital'), status = 'expired',
            triage = tonumber(tostring(meta.triage or ''):match('P(%d)')) or 3, now = now(),
        })
    end)
    if not ok then NZA.Warn('checkin: could not register the ticket item: ' .. tostring(err)) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BUS
-- ════════════════════════════════════════════════════════════════════════

local function onBed(pointId, pid, occupied)
    local pt = point(pointId)
    local p = NZA.Patients.Get(pid)
    if p and p.kind == 'player' and p.src and pt and pt.type == 'bed' then
        TriggerClientEvent('nza:checkin:bed', p.src, { point = pt.id, on = occupied == true })
    end
    if pt then changed(pt.hospital) end
    local t = C.ForPid(pid)
    if not t then return end
    if occupied and (t.status == 'called' or t.status == 'waiting') and pt and pt.hospital == t.hospital then
        if t.bed ~= pt.id then
            release(t)
            t.bed, t.bedLabel = pt.id, C.BedLabel(pt)
        end
        reserved[pt.id] = nil
        if t.ai and C.AI and C.AI.Start then
            C.SetTreatment(t)
            -- let the patient's client finish lying down before the HUD starts
            SetTimeout(800, function()
                if tickets[t.id] == t and t.status == 'treatment' and t.ai then C.AI.Start(t) end
            end)
        elseif cfg('queue', 'autoTreatment', true) then
            C.SetTreatment(t)
        end
    end
end

NZA.Bus.On('hospital:bed', onBed)

NZA.Bus.On('transport:bed', function(src, p, pt)
    if type(p) ~= 'table' or type(pt) ~= 'table' then return end
    if p.kind == 'player' and p.src and pt.type == 'bed' then
        TriggerClientEvent('nza:checkin:bed', p.src, { point = pt.id, on = true })
    end
    local t = C.ForPid(p.pid)
    if t and pt.hospital == t.hospital and t.status ~= 'treatment' then
        if C.AI and C.AI.Stop then C.AI.Stop(t, 'staff') end
        t.ai = false
        if t.bed ~= pt.id then release(t) t.bed, t.bedLabel = pt.id, C.BedLabel(pt) end
        C.SetTreatment(t, src)
    end
end)

-- a medic treating a waiting patient directly moves the ticket to treatment
local function treatedBy(src, p)
    if type(p) ~= 'table' or not src or src == 0 then return end
    local t = C.ForPid(p.pid)
    if not t or t.status == 'treatment' or t.src == src or t.ai then return end
    C.SetTreatment(t, src)
end
NZA.Bus.On('treat:done', function(src, p) treatedBy(src, p) end)
NZA.Bus.On('proc:done', function(src, p) treatedBy(src, p) end)

-- a patient who dies while waiting / called gives the ticket (and the reserved bed) up, so
-- nobody - the AI doctor included - calls a body to a bed; in treatment the bedside staff
-- or the AI session (checkin_ai.lua) deal with it
NZA.Bus.On('patient:death', function(p)
    if type(p) ~= 'table' then return end
    local t = C.ForPid(p.pid)
    if t and t.status ~= 'treatment' then C.Close(t, 'left') end
end)

NZA.Bus.On('player:loaded', function(src)
    local ident = NZA.Core.Identifier(src)
    if not ident then return end
    for _, t in pairs(tickets) do
        if t.identifier == ident then
            t.src, t.offlineSince = src, nil
            SetTimeout(3000, function() if tickets[t.id] then pushMine(t, 'update') end end)
        end
    end
end)

NZA.Bus.On('player:unloaded', function(src)
    deskWatch[src], tvWatch[src] = nil, nil
    for _, t in pairs(tickets) do
        if t.src == src then t.offlineSince = now() end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    deskWatch[src], tvWatch[src] = nil, nil
end)

-- ════════════════════════════════════════════════════════════════════════
-- TICK (re-triage, AI hand-over, no-shows, offline, expiry)
-- ════════════════════════════════════════════════════════════════════════

local function tick()
    local t0 = now()
    local expire = tonumber(cfg('queue', 'expire', 7200)) or 7200
    local grace = tonumber(cfg('queue', 'offlineGrace', 300)) or 300
    local noShow = tonumber(cfg('queue', 'noShow', 240)) or 240
    local touched = {}
    for _, t in pairs(tickets) do
        local p = patientOf(t)
        local online = playerSrc(t) ~= nil
        if online then t.offlineSince = nil elseif not t.offlineSince then t.offlineSince = t0 end
        if t.offlineSince and t0 - t.offlineSince > grace and t.status ~= 'treatment' then
            C.Close(t, 'left')
        elseif t.status == 'waiting' and t0 - t.issued > expire then
            C.Close(t, 'left')
        elseif t.status == 'called' and t.called and t0 - t.called > noShow then
            C.Close(t, 'noshow')
        elseif p and online then
            -- nothing left to treat while waiting → the visit is over
            if t.status == 'waiting' and p.state == 'alive' and not next(p.injuries or {}) and t0 - t.issued > 20 then
                C.Close(t, 'left')
            elseif t.status == 'treatment' and not t.ai and p.state == 'alive' and not next(p.injuries or {})
                and not (p.meta and p.meta.bed) and cfg('queue', 'doneOnLeave', true) then
                C.Close(t, 'done')
            elseif t.status == 'waiting' then
                local tri, label = triageOf(p)
                if tri ~= t.triage then
                    local worse = tri < t.triage
                    t.triage, t.triageLabel = tri, label
                    dbSave(t)
                    touched[t.hospital] = true
                    pushMine(t, 'update')
                    if worse then notifyStaff(t, 'triage') end
                end
            end
        end
    end
    for h in pairs(touched) do changed(h) pushAll(h) end
    if C.AI and C.AI.Tick then
        local ok, err = pcall(C.AI.Tick, t0)
        if not ok then NZA.Warn('checkin AI tick failed: ' .. tostring(err)) end
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        local ok, err = pcall(tick)
        if not ok then NZA.Warn('checkin tick failed: ' .. tostring(err)) end
    end
end)

-- periodic board refresh (waiting times, incoming ambulance ETAs, staff count)
CreateThread(function()
    while true do
        Wait(math.max(3, tonumber(cfg('tv', 'refresh', 8)) or 8) * 1000)
        local hs = {}
        for _, h in pairs(tvWatch) do hs[h] = true end
        for _, h in pairs(deskWatch) do hs[h] = true end
        for h in pairs(hs) do changed(h) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- START (table, counters, restore)
-- ════════════════════════════════════════════════════════════════════════

local function restore()
    db('query', [[SELECT hospital, prefix, MAX(number) AS n FROM nza_tickets WHERE day = ? GROUP BY hospital, prefix]], { today() }, function(rows)
        for _, r in ipairs(rows or {}) do
            local key = ('%s|%s|%s'):format(r.hospital, r.prefix, today())
            counters[key] = math.max(counters[key] or 0, tonumber(r.n) or 0)
        end
    end)
    if not cfg('queue', 'restore', true) then
        db('update', [[UPDATE nza_tickets SET status = 'cancelled', closed = ? WHERE status IN ('waiting', 'called', 'treatment')]], { now() })
        return
    end
    local since = now() - (tonumber(cfg('queue', 'expire', 7200)) or 7200)
    db('query', [[SELECT * FROM nza_tickets WHERE status IN ('waiting', 'called', 'treatment') AND issued > ?]], { since }, function(rows)
        local n = 0
        for _, r in ipairs(rows or {}) do
            if r.identifier and r.id and hosp(r.hospital) ~= nil then
                local data = type(r.data) == 'string' and json.decode(r.data) or {}
                local t = {
                    id = r.id, hospital = r.hospital, prefix = r.prefix, number = tonumber(r.number) or 0, day = r.day,
                    pid = 'p:' .. tostring(r.identifier), identifier = r.identifier, name = r.name,
                    triage = U.clamp(tonumber(r.triage) or 3, 1, 3), status = 'waiting', issued = tonumber(r.issued) or now(),
                    desk = data and data.desk, deskLabel = data and data.deskLabel or L('desk'), offlineSince = now(),
                }
                t.code = formatCode(t.prefix, t.number)
                t.triageLabel = L('tri_' .. t.triage)
                tickets[t.id] = t
                n = n + 1
            end
        end
        local keep = {}
        for id in pairs(tickets) do keep[#keep + 1] = id end
        db('update', [[UPDATE nza_tickets SET status = 'left', closed = ? WHERE status IN ('waiting', 'called', 'treatment')]], { now() }, function()
            for _, id in ipairs(keep) do
                db('update', [[UPDATE nza_tickets SET status = 'waiting', bed = NULL, closed = NULL WHERE id = ?]], { id })
            end
        end)
        if n > 0 then NZA.Debug('checkin: restored ' .. n .. ' tickets') end
        for _, t in pairs(tickets) do changed(t.hospital) end
    end)
end

CreateThread(function()
    if not MySQL then
        NZA.Warn('checkin: oxmysql not found - tickets are kept in memory only')
        return
    end
    local ok, err = pcall(function()
        -- same statement as sql/install.sql
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nza_tickets` (
            `id` VARCHAR(24) NOT NULL,
            `hospital` VARCHAR(64) NOT NULL,
            `day` CHAR(10) NOT NULL,
            `prefix` VARCHAR(4) NOT NULL,
            `number` INT NOT NULL,
            `identifier` VARCHAR(80) NULL,
            `name` VARCHAR(80) NULL,
            `triage` TINYINT NOT NULL DEFAULT 3,
            `status` VARCHAR(16) NOT NULL DEFAULT 'waiting',
            `bed` INT NULL,
            `handled_by` VARCHAR(80) NULL,
            `issued` INT NOT NULL,
            `called` INT NULL,
            `closed` INT NULL,
            `data` LONGTEXT NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_nza_tickets_day` (`hospital`, `day`, `prefix`),
            INDEX `idx_nza_tickets_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
    if not ok then
        NZA.Warn('checkin: could not create nza_tickets: ' .. tostring(err))
        return
    end
    dbOk = true
    -- give the hospital module a moment to load departments and points
    local t = GetGameTimer()
    while NZA.Hospitals and NZA.Hospitals.Ready and not NZA.Hospitals.Ready() and GetGameTimer() - t < 15000 do Wait(250) end
    restore()
end)

exports('GetCheckinQueue', function(hospital) return C.Queue(hospital) end)
