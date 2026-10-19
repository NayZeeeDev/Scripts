--[[
    NAYZEEE AMBULANCE - Dispatch (server): calls, units, status chain        ARCHITECTURE §9

    Every EMS call lives here. Other modules create calls (wounded players, the NPC calls
    module, phones through the bridge, /911) and this module routes them to on-duty
    medics (call card, pager, phone), tracks which units respond and advances the status
    chain by itself from server-side positions and treatment events:

        DSP ─respond→ ENR ─within sceneRadius→ SCN ─first treatment→ CARE
            ─patient loaded (bus 'transport:loaded' or vehicle/bay fallback)→ TRN
            ─within hospitalRadius of a hospital / patient on a hospital point→ HSP → close

    SERVER API (everyone)
      NZA.Dispatch.Create(call) → callId | nil, err
          call = { code, priority 1..3, title, type, coords, street?, zone?, caller?, callerSrc?,
                   phone?, message?, voice? ('audio/…' under html/), patients = { pid | Patient | target },
                   npc = bool, source = 'player'|'npc'|'system', blip = { sprite, colour }, meta = {} }
      NZA.Dispatch.Update(callId, patch) → bool       code priority title type coords street zone caller
                                                      message voice blip npc meta(merge) patients(add)
      NZA.Dispatch.Close(callId, reason) → bool
      NZA.Dispatch.Get(callId) → call | nil           live table, read only
      NZA.Dispatch.SetStatus(callId, src, status, opts) → ok, err
          status 'DSP' (removes the unit) | 'ENR' | 'SCN' | 'CARE' | 'TRN' | 'HSP'
          opts = { forward = true } only moves forward; { force = true } ignores maxUnits
      NZA.Dispatch.Respond(src, callId) → ok, err    NZA.Dispatch.Clear(src, callId?, reason) → ok, err
      NZA.Dispatch.Assign(callId, targetSrc, bySrc) → ok, err
      NZA.Dispatch.Page(src, { kind?, priority 1..3, title, text?, hospital? }) → bool
                                                      one line on that medic's pager (page log, LCD, beep)
      NZA.Dispatch.Decline(src, callId)
      NZA.Dispatch.Active() → { call, … } (newest first)      NZA.Dispatch.CallOf(src) → call | nil
      NZA.Dispatch.CallForPatient(p) → call | nil
      NZA.Dispatch.Unit(src) → unit | nil   NZA.Dispatch.Units() → { unit, … }   NZA.Dispatch.UnitStatus(src) → '10-8'|'10-7'|stage
      NZA.Dispatch.SetOutOfService(src, bool)   NZA.Dispatch.SetCallsign(src, text) → ok
      NZA.Dispatch.Tick()   run the automatic status pass now (it also runs every Config.Dispatch.status.tick ms)
      NZA.Dispatch.Hospitals() → { { id, label, coords } }   NZA.Dispatch.NearestHospital(coords) → h, dist
      NZA.Dispatch.Public(call) → serializable table   NZA.Dispatch.Me(src) → own unit record for the client
      NZA.Dispatch.Board(src) → board payload           NZA.Dispatch.Paired(src) / SetPaired(src, bool)
      NZA.Dispatch.NpcCalls(src) / SetNpcCalls(src, bool)   (Player(src).state.nzaNpcCalls, read by the calls module)

    NET EVENTS SENT (S→C, on-duty medics)
      nza:dispatch:call   (call, { alert, realert })      new call (alert = show the card / beep)
      nza:dispatch:update (call)                          call changed (status, units, patients…)
      nza:dispatch:close  (callId, reason)
      nza:dispatch:me     (me)                            own unit record changed
      nza:dispatch:stage  (callId, stage, extra)          this unit's stage changed (toasts, GPS)
      nza:dispatch:assigned (call, byName)                dispatch assigned this unit
      nza:dispatch:page   { id, kind, priority, title, text, hospital }   pager line (NZA.Dispatch.Page)
      nza:dispatch:units  (units[])                       roster changed
      nza:dispatch:police (summary)                       on-duty police, violent calls only
      nza:wounded:help    { eta, unit, status }           patient players (through NZA.Wounded.Help)

    BUS (server)  listens: treat:done proc:done transport:loaded transport:bed patient:created
                           patient:removed state:changed patient:arrest staff:changed player:unloaded
                  emits:   dispatch:created (call) dispatch:status (call, src, stage)
                           dispatch:closed (call, reason) dispatch:respond (call, src)

    Net events received, callbacks and commands are in dispatch_net.lua; the call log
    (nza_calls) in dispatch_log.lua.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Dispatch = NZA.Dispatch or {}
local D = NZA.Dispatch
local U = NZA.Util

local STAGES = { 'DSP', 'ENR', 'SCN', 'CARE', 'TRN', 'HSP' }
local STAGE = {}
for i, s in ipairs(STAGES) do STAGE[s] = i end
D.Stages = STAGES
D.StageIndex = STAGE

local calls = {}       -- id → call (active)
local units = {}       -- src → unit (on-duty medics)
local recent = {}      -- closed calls, newest first (public tables)
local paired = {}      -- src → true (pager paired with the phone)
local dirty = {}       -- id → true (pending broadcast)
local flushQueued = false
local unitsQueued = false
local RECENT_MAX = 60

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section, key, default)
    local root = Config.Dispatch
    local c = type(root) == 'table' and root[section] or nil
    if type(c) ~= 'table' then return default end
    local v = c[key]
    if v == nil then return default end
    return v
end
D.Cfg = cfg

-- phone alerts: 'paired' = only medics who linked their phone (pager SETUP or radial Calls ▸ Link phone),
-- 'always' = every medic who gets the call card, false = never. Old configs: pager.phonePairing.
function D.PhoneMode()
    local m = cfg('phone', 'alerts', nil)
    if m == nil then return cfg('pager', 'phonePairing', true) ~= false and 'paired' or false end
    if m == 'always' or m == 'paired' then return m end
    return false
end

local function str(v, max)
    if type(v) == 'number' then v = tostring(v) end
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    if max and #v > max then v = v:sub(1, max) end
    return v
end
D.Str = str

local function now() return os.time() end

local function online(src)
    return NZA.Core.Online(src)
end

local function coordsOf(src)
    return NZA.Core.SrcCoords(src)
end

local function isOnDutyMedic(src)
    src = tonumber(src)
    if not src or not online(src) then return false end
    local rec = NZA.Staff.Get(src)
    return rec ~= nil and rec.medic == true and rec.onDuty == true
end
D.IsOnDutyMedic = isOnDutyMedic

local function bridge(path, ...)
    if NZA.Core.Has and NZA.Core.Has(path) then return NZA.Core.B(path, ...) end
    return nil
end

local function shortName(name)
    if type(name) ~= 'string' then return '?' end
    local first, last = name:match('^(%S+)%s+(.+)$')
    if first and last then return first:sub(1, 1) .. '. ' .. last end
    return name
end

local function round(n) return math.floor((n or 0) + 0.5) end

-- ════════════════════════════════════════════════════════════════════════
-- UNITS
-- ════════════════════════════════════════════════════════════════════════

local function kvpKey(kind, ident) return ('nza_%s:%s'):format(kind, ident) end

local function callsignFor(src, ident)
    if ident then
        local saved = GetResourceKvpString(kvpKey('callsign', ident))
        if saved and saved ~= '' then return saved end
    end
    local rec = NZA.Staff.Get(src)
    if rec and type(rec.callsign) == 'string' and rec.callsign ~= '' then return rec.callsign end
    local fmt = cfg('units', 'callsignFormat', 'Unit %02d')
    local ok, out = pcall(string.format, fmt, src)
    return ok and out or ('Unit ' .. src)
end

function D.NpcCalls(src)
    local u = units[tonumber(src)]
    if u then return u.npc == true end
    local st = Player(src) and Player(src).state
    return st and st.nzaNpcCalls == true or false
end

local function applyNpcState(src, on)
    local p = Player(src)
    if p and p.state then p.state:set('nzaNpcCalls', on == true, true) end
end

function D.SetNpcCalls(src, on)
    src = tonumber(src)
    local u = units[src]
    if not u then return false end
    u.npc = on == true
    if u.ident then SetResourceKvp(kvpKey('npccalls', u.ident), u.npc and '1' or '0') end
    applyNpcState(src, u.npc)
    return true
end

function D.Paired(src) return paired[tonumber(src)] == true end

function D.SetPaired(src, on)
    src = tonumber(src)
    if not src then return false end
    paired[src] = on == true or nil
    local ident = NZA.Core.Identifier(src)
    if ident then SetResourceKvpInt(kvpKey('pager_pair', ident), on and 1 or 0) end
    return true
end

local function ensureUnit(src)
    src = tonumber(src)
    if not src then return nil end
    local u = units[src]
    if u then return u end
    if not isOnDutyMedic(src) then return nil end
    local ident = NZA.Core.Identifier(src)
    local rec = NZA.Staff.Get(src) or {}
    u = {
        src = src, ident = ident, name = NZA.Core.Name(src), callsign = callsignFor(src, ident),
        grade = rec.gradeLabel, dept = rec.deptLabel or rec.dept, hospital = rec.hospital,
        oos = false, call = nil, since = now(),
    }
    -- NPC call preference (read by the calls module from the player state bag)
    local npc = cfg('npcCalls', 'defaultOn', true) == true
    if ident then
        local saved = GetResourceKvpString(kvpKey('npccalls', ident))
        if saved == '1' then npc = true elseif saved == '0' then npc = false end
        paired[src] = GetResourceKvpInt(kvpKey('pager_pair', ident)) == 1 or nil
    end
    u.npc = npc
    applyNpcState(src, npc)
    units[src] = u
    return u
end
D.EnsureUnit = ensureUnit

function D.Unit(src) return units[tonumber(src)] end

function D.UnitStatus(src)
    local u = units[tonumber(src)]
    if not u then return '10-7' end
    local c = u.call and calls[u.call]
    local cu = c and c.units[u.src]
    if cu then return cu.stage end
    return u.oos and '10-7' or '10-8'
end

local function unitPublic(u, withCoords)
    local out = {
        src = u.src, name = u.name, short = shortName(u.name), callsign = u.callsign, grade = u.grade,
        dept = u.dept, status = D.UnitStatus(u.src), call = u.call, oos = u.oos == true, since = u.since,
    }
    if withCoords then
        local ped = GetPlayerPed(u.src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            out.x, out.y = round(c.x), round(c.y)
            out.h = round(GetEntityHeading(ped))
            out.veh = GetVehiclePedIsIn(ped, false) ~= 0
        end
    end
    return out
end

function D.Units(withCoords)
    local list = {}
    for _, u in pairs(units) do list[#list + 1] = unitPublic(u, withCoords) end
    table.sort(list, function(a, b) return tostring(a.callsign) < tostring(b.callsign) end)
    return list
end

local function unitLabel(u)
    if not u then return nil end
    return ('%s · %s'):format(u.callsign or '?', shortName(u.name))
end
D.UnitLabel = function(src) return unitLabel(units[tonumber(src)]) end

local function medics()
    local out = {}
    for _, src in ipairs(NZA.Staff.OnDuty()) do
        if online(src) then out[#out + 1] = src end
    end
    return out
end
D.Medics = medics

function D.Me(src)
    src = tonumber(src)
    local rec = src and NZA.Staff.Get(src) or nil
    local u = units[src]
    local me = {
        src = src, medic = rec and rec.medic == true or false, onDuty = rec and rec.onDuty == true or false,
        name = NZA.Core.Name(src), status = D.UnitStatus(src), call = u and u.call or nil,
        oos = u and u.oos == true or false, paired = paired[src] == true, npc = u and u.npc == true or D.NpcCalls(src),
        callsign = u and u.callsign or callsignFor(src, NZA.Core.Identifier(src)), grade = rec and rec.gradeLabel or nil,
        canAssign = src and NZA.Staff.Can(src, cfg('board', 'assignPerm', 'manage')) or false,
    }
    return me
end

local function sendMe(src)
    if src and online(src) then TriggerClientEvent('nza:dispatch:me', src, D.Me(src)) end
end
D.SendMe = sendMe

local function queueUnits()
    if unitsQueued then return end
    unitsQueued = true
    SetTimeout(400, function()
        unitsQueued = false
        local list = D.Units(false)
        for _, src in ipairs(medics()) do TriggerClientEvent('nza:dispatch:units', src, list) end
    end)
end
D.QueueUnits = queueUnits

function D.SetOutOfService(src, on)
    local u = units[tonumber(src)]
    if not u then return false end
    u.oos = on == true
    sendMe(u.src)
    queueUnits()
    return true
end

function D.SetCallsign(src, text)
    src = tonumber(src)
    text = str(text, tonumber(cfg('units', 'callsignMax', 12)) or 12)
    if not text then return false end
    text = text:gsub('[^%w%-%s%._]', '')
    if text == '' then return false end
    local ident = NZA.Core.Identifier(src)
    if ident then SetResourceKvp(kvpKey('callsign', ident), text) end
    local u = units[src]
    if u then u.callsign = text end
    sendMe(src)
    queueUnits()
    return true, text
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function nextId()
    local n = (GetResourceKvpInt('nza_dispatch_seq') or 0) + 1
    if n > 99999 then n = 1 end
    SetResourceKvpInt('nza_dispatch_seq', n)
    return ('%s%04d'):format(cfg('calls', 'idPrefix', 'C-'), n)
end

local function voicePath(v)
    if type(v) ~= 'string' or v == '' or #v > 160 then return nil end
    if v:find('%.%.') or not v:match('^[%w_%-/%.]+$') then return nil end
    local ext = v:match('%.(%w+)$')
    if ext ~= 'ogg' and ext ~= 'mp3' and ext ~= 'wav' then return nil end
    if v:sub(1, 6) ~= 'audio/' then v = 'audio/' .. v:gsub('^/+', '') end
    return v
end

local function patientPid(v)
    if type(v) == 'string' and v ~= '' then return v end
    if type(v) == 'table' then
        if type(v.pid) == 'string' then return v.pid end
        local ok, p = pcall(NZA.Patients.Resolve, v)
        if ok and p then return p.pid end
    end
    if type(v) == 'number' then
        local p = NZA.Patients.GetBySource(v)
        return p and p.pid or nil
    end
    return nil
end

local function addPatient(c, v)
    local pid = patientPid(v)
    if not pid then return false end
    for _, x in ipairs(c.patients) do if x == pid then return false end end
    c.patients[#c.patients + 1] = pid
    c.hadPatients = true
    if NZA.Patients.Get(pid) and NZA.Patients.SetMeta then pcall(NZA.Patients.SetMeta, pid, 'callId', c.id) end
    return true
end

local function callPatients(c)
    local out = {}
    for _, pid in ipairs(c.patients) do
        local p = NZA.Patients.Get(pid)
        if p then out[#out + 1] = p end
    end
    return out
end
D.CallPatients = callPatients

function D.CallForPatient(p)
    if type(p) ~= 'table' then p = NZA.Patients.Resolve(p) end
    if type(p) ~= 'table' then return nil end
    local id = p.meta and p.meta.callId
    if id and calls[id] then return calls[id] end
    for _, c in pairs(calls) do
        for _, pid in ipairs(c.patients) do
            if pid == p.pid then return c end
        end
    end
    return nil
end

local function patientPublic(p)
    local tri = 3
    local ok, lvl = pcall(NZA.Patients.Triage, p.pid)
    if ok and tonumber(lvl) then tri = tonumber(lvl) end
    local tags, seen = {}, {}
    for _, inj in pairs(p.injuries or {}) do
        if inj.type and not seen[inj.type] then
            seen[inj.type] = true
            tags[#tags + 1] = inj.type
            if #tags >= 4 then break end
        end
    end
    return { pid = p.pid, name = p.name, st = p.state, tri = tri, npc = p.kind == 'npc', tags = tags }
end

local function stageOf(c)
    local best = 1
    for _, cu in pairs(c.units) do
        local i = STAGE[cu.stage] or 1
        if i > best then best = i end
    end
    return STAGES[best]
end

function D.Public(c, full)
    if not c then return nil end
    local list = {}
    for src, cu in pairs(c.units) do
        local u = units[src]
        list[#list + 1] = {
            src = src, stage = cu.stage, at = cu.at, joined = cu.joined,
            callsign = u and u.callsign or ('#' .. src), name = u and u.name or '?', short = u and shortName(u.name) or '?',
        }
    end
    table.sort(list, function(a, b) return (a.joined or 0) < (b.joined or 0) end)
    local pts, tags, seen = {}, {}, {}
    for _, p in ipairs(callPatients(c)) do
        local pp = patientPublic(p)
        pts[#pts + 1] = pp
        for _, t in ipairs(pp.tags) do
            if not seen[t] then seen[t] = true; tags[#tags + 1] = t end
        end
    end
    local declined = 0
    for _ in pairs(c.declined) do declined = declined + 1 end
    local out = {
        id = c.id, code = c.code, priority = c.priority, title = c.title, type = c.type,
        x = c.coords.x, y = c.coords.y, z = c.coords.z, street = c.street, zone = c.zone,
        caller = c.caller, phone = c.phone, message = c.message, voice = c.voice, npc = c.npc, source = c.source,
        blip = c.blip, created = c.created, age = now() - c.created, status = c.status, units = list,
        patients = pts, tags = tags, declined = declined, closed = c.closed, reason = c.reason,
        respondedAt = c.respondedAt, arrivedAt = c.arrivedAt,
    }
    if full then out.history = c.history end
    return out
end

local function broadcast(event, ...)
    for _, src in ipairs(medics()) do TriggerClientEvent(event, src, ...) end
end

local function flush()
    flushQueued = false
    for id in pairs(dirty) do
        dirty[id] = nil
        local c = calls[id]
        if c then broadcast('nza:dispatch:update', D.Public(c)) end
    end
end

local function markDirty(id)
    dirty[id] = true
    if flushQueued then return end
    flushQueued = true
    SetTimeout(200, flush)
end
D.MarkDirty = markDirty

local function pushHistory(c, status, src)
    c.history[#c.history + 1] = { s = status, t = now(), u = src and units[src] and units[src].callsign or nil }
    if #c.history > 30 then table.remove(c.history, 2) end
end

-- Show "medic on the way · ETA" on a downed player's HUD (wounded module).
local function help(p, data)
    if not p or p.kind ~= 'player' or not p.src then return end
    if NZA.Wounded and NZA.Wounded.Help then
        pcall(NZA.Wounded.Help, p.src, data)
    else
        TriggerClientEvent('nza:wounded:help', p.src, data)
    end
end

local function helpAll(c, data)
    for _, p in ipairs(callPatients(c)) do help(p, data) end
end

local function etaFor(src, c)
    local a = coordsOf(src)
    if not a then return nil end
    local speed = tonumber(cfg('status', 'etaSpeed', 19.0)) or 19.0
    return math.max(5, math.floor(#(a - c.coords) / math.max(1.0, speed)))
end

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITALS (built in game, else the fallback list)
-- ════════════════════════════════════════════════════════════════════════

local function hospitalCoords(h)
    if type(h) ~= 'table' then return nil end
    local c = U.vec(h.hq or h.coords or h.center or h.pos or h.position or h.entrance)
    if c then return c end
    -- no HQ placed: use one of the hospital's points (check-in desk first)
    if h.id and NZA.Hospitals and NZA.Hospitals.Points then
        for _, kind in ipairs({ 'checkin', 'bed', 'respawn', 'duty' }) do
            local ok, list = pcall(NZA.Hospitals.Points, kind, h.id)
            if ok and type(list) == 'table' then
                for _, pt in pairs(list) do
                    local pc = U.vec(pt.coords)
                    if pc then return pc end
                end
            end
        end
    end
    return nil
end

local function hospitalsBuilt()
    if not (NZA.Hospitals and NZA.Hospitals.All) then return nil end
    local ok, all = pcall(NZA.Hospitals.All)
    if not ok or type(all) ~= 'table' or next(all) == nil then return nil end
    return all
end

function D.Hospitals()
    local out = {}
    local all = hospitalsBuilt()
    if all then
        for id, h in pairs(all) do
            local c = hospitalCoords(h)
            if c then out[#out + 1] = { id = h.id or id, label = h.label or h.name or tostring(id), coords = c } end
        end
    end
    if #out == 0 then
        for i, v in ipairs(cfg('status', 'fallbackHospitals', {}) or {}) do
            local c = U.vec(v)
            if c then out[#out + 1] = { id = 'fallback' .. i, label = NZA.L('dispatch.hospital'), coords = c } end
        end
    end
    return out
end

function D.NearestHospital(coords)
    coords = U.vec(coords)
    if not coords then return nil, math.huge end
    if hospitalsBuilt() and NZA.Hospitals.Nearest then
        local ok, h, d = pcall(NZA.Hospitals.Nearest, coords)
        if ok and type(h) == 'table' then
            local hc = hospitalCoords(h)
            d = tonumber(d) or (hc and #(hc - coords)) or nil
            if d then return { id = h.id, label = h.label or h.name, coords = hc or coords }, d end
        end
    end
    local best, bestD = nil, math.huge
    for _, h in ipairs(D.Hospitals()) do
        local d = #(h.coords - coords)
        if d < bestD then best, bestD = h, d end
    end
    return best, bestD
end

-- ════════════════════════════════════════════════════════════════════════
-- ALERTS (card, pager, phone, police, external)
-- ════════════════════════════════════════════════════════════════════════

local function phoneNotify(src, c)
    if D.PhoneMode() == false then return end
    local title = NZA.L('dispatch.phone_title', c.priority, c.code or '', c.title or '')
    local where = c.street or c.zone or NZA.L('dispatch.unknown_location')
    local msg = c.caller and NZA.L('dispatch.phone_msg_caller', where, c.caller) or where
    if Bridge and Bridge.Phone and Bridge.Phone.Notify then
        pcall(Bridge.Phone.Notify, src, { title = title, message = msg, icon = 'ambulance' })
    end
    if cfg('phone', 'mail', cfg('pager', 'phoneMail', false)) and Bridge and Bridge.Phone and Bridge.Phone.Mail then
        pcall(Bridge.Phone.Mail, src, {
            sender = NZA.L('dispatch.mail_sender'), subject = ('%s · %s'):format(c.id, title),
            message = NZA.L('dispatch.mail_body', c.id, c.title or '', where, c.caller or '-', c.message or '-'),
        })
    end
end

local function minPriority()
    return tonumber(cfg('card', 'minPriority', 3)) or 3
end

local function alert(c, opts)
    local pub = D.Public(c)
    local oosAlerts = cfg('units', 'outOfServiceAlerts', false) == true
    local phone = D.PhoneMode()
    for _, src in ipairs(medics()) do
        local u = ensureUnit(src)
        local wants = u ~= nil and (not u.oos or oosAlerts) and c.priority <= minPriority()
        if opts and opts.realert then wants = wants and (u.call == nil) end
        TriggerClientEvent('nza:dispatch:call', src, pub, { alert = wants, realert = opts and opts.realert or nil })
        if wants and (phone == 'always' or (phone == 'paired' and paired[src])) then phoneNotify(src, c) end
    end
end

local function policeMirror(c)
    local pc = Config.Dispatch and Config.Dispatch.police
    if type(pc) ~= 'table' or pc.enabled == false then return end
    if not (pc.all or (type(pc.types) == 'table' and pc.types[c.type])) then return end
    local data = {
        id = c.id, code = c.code, priority = c.priority, title = c.title, type = c.type,
        x = c.coords.x, y = c.coords.y, z = c.coords.z, street = c.street, zone = c.zone,
        created = c.created, blipTime = tonumber(pc.blipTime) or 240,
    }
    local players = bridge('GetPlayers') or {}
    for _, src in ipairs(players) do
        if bridge('IsPolice', src) and bridge('IsOnDuty', src) then
            TriggerClientEvent('nza:dispatch:police', src, data)
        end
    end
end

local function externalMirror(c)
    if Config.Dispatch.external == false then return end
    if not (Bridge and Bridge.Dispatch and Bridge.Dispatch.External) then return end
    local ok, err = pcall(Bridge.Dispatch.External, {
        id = c.id, code = c.code, priority = c.priority, title = c.title, type = c.type, message = c.message,
        coords = c.coords, street = c.street, zone = c.zone, caller = c.caller, callerSrc = c.callerSrc,
        blip = c.blip,
    })
    if not ok then NZA.Debug('dispatch: external mirror failed', err) end
end

-- ════════════════════════════════════════════════════════════════════════
-- API: CREATE / UPDATE / CLOSE / GET
-- ════════════════════════════════════════════════════════════════════════

local function logCall(kind, c)
    local L = NZA.DispatchLog
    if not L or cfg('log', 'enabled', true) == false then return end
    local fn = L[kind]
    if fn then
        local ok, err = pcall(fn, c)
        if not ok then NZA.Warn('dispatch: log ' .. kind .. ' failed: ' .. tostring(err)) end
    end
end

local function trimActive()
    local max = tonumber(cfg('calls', 'maxActive', 60)) or 60
    local count, oldest = 0, nil
    for _, c in pairs(calls) do
        count = count + 1
        if next(c.units) == nil and (not oldest or c.created < oldest.created) then oldest = c end
    end
    if count > max and oldest then D.Close(oldest.id, 'overflow') end
end

function D.Create(call)
    if type(call) ~= 'table' then return nil, 'bad_call' end
    if Config.Dispatch.enabled == false then return nil, 'disabled' end
    local coords = U.vec(call.coords)
    if not coords then return nil, 'no_coords' end
    -- the same patient already has an open call: merge instead of paging twice
    if cfg('calls', 'mergeDuplicates', true) and type(call.patients) == 'table' then
        for _, v in ipairs(call.patients) do
            local pid = patientPid(v)
            local p = pid and NZA.Patients.Get(pid)
            local open = p and D.CallForPatient(p)
            if open then
                local prio = U.clamp(math.floor(tonumber(call.priority) or open.priority), 1, 3)
                D.Update(open.id, {
                    priority = math.min(open.priority, prio), message = call.message or open.message,
                    patients = call.patients, caller = open.caller or call.caller,
                })
                pushHistory(open, 'DUP')
                if next(open.units) == nil then alert(open, { realert = true }) end
                NZA.Debug('dispatch: merged duplicate call into', open.id)
                return open.id
            end
        end
    end
    local id = nextId()
    while calls[id] do id = nextId() end
    local src = tostring(call.source or '')
    if src ~= 'player' and src ~= 'npc' and src ~= 'system' then src = call.npc and 'npc' or 'system' end
    local c = {
        id = id,
        code = str(call.code, 16) or cfg('calls', 'defaultCode', '10-52'),
        priority = U.clamp(math.floor(tonumber(call.priority) or 2), 1, 3),
        title = str(call.title, 64) or NZA.L('dispatch.call_default'),
        type = (str(call.type, 24) or cfg('calls', 'defaultType', 'unknown')):lower(),
        coords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0),
        street = str(call.street, 80), zone = str(call.zone, 64),
        caller = str(call.caller, 64), callerSrc = tonumber(call.callerSrc), phone = str(call.phone, 24),
        message = str(call.message, 250), voice = voicePath(call.voice),
        patients = {}, npc = call.npc == true, source = src, via = str(call.via, 32),
        blip = type(call.blip) == 'table' and { sprite = tonumber(call.blip.sprite), colour = tonumber(call.blip.colour) } or nil,
        meta = type(call.meta) == 'table' and call.meta or {},
        created = now(), updated = now(), status = 'DSP', units = {}, declined = {},
        history = { { s = 'DSP', t = now() } },
    }
    if type(call.patients) == 'table' then
        for _, v in ipairs(call.patients) do addPatient(c, v) end
    end
    calls[id] = c
    trimActive()
    logCall('Insert', c)
    alert(c)
    policeMirror(c)
    externalMirror(c)
    NZA.Bus.Emit('dispatch:created', c)
    NZA.Debug('dispatch: new call', id, c.code, c.title, 'P' .. c.priority, #c.patients .. ' patients')
    return id
end

function D.Update(id, patch)
    local c = calls[id]
    if not c or type(patch) ~= 'table' then return false end
    if patch.code ~= nil then c.code = str(patch.code, 16) or c.code end
    if patch.priority ~= nil then c.priority = U.clamp(math.floor(tonumber(patch.priority) or c.priority), 1, 3) end
    if patch.title ~= nil then c.title = str(patch.title, 64) or c.title end
    if patch.type ~= nil then c.type = (str(patch.type, 24) or c.type):lower() end
    if patch.coords ~= nil then
        local v = U.vec(patch.coords)
        if v then c.coords = vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0) end
    end
    if patch.street ~= nil then c.street = str(patch.street, 80) end
    if patch.zone ~= nil then c.zone = str(patch.zone, 64) end
    if patch.caller ~= nil then c.caller = str(patch.caller, 64) end
    if patch.message ~= nil then c.message = str(patch.message, 250) end
    if patch.voice ~= nil then c.voice = voicePath(patch.voice) end
    if patch.npc ~= nil then c.npc = patch.npc == true end
    if type(patch.blip) == 'table' then c.blip = { sprite = tonumber(patch.blip.sprite), colour = tonumber(patch.blip.colour) } end
    if type(patch.meta) == 'table' then for k, v in pairs(patch.meta) do c.meta[k] = v end end
    if type(patch.patients) == 'table' then
        for _, v in ipairs(patch.patients) do addPatient(c, v) end
    end
    c.updated = now()
    markDirty(id)
    return true
end

function D.Get(id) return calls[id] end

function D.Active()
    local list = {}
    for _, c in pairs(calls) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.created > b.created
    end)
    return list
end

function D.CallOf(src)
    local u = units[tonumber(src)]
    return u and u.call and calls[u.call] or nil
end

function D.Recent() return recent end

function D.Close(id, reason)
    local c = calls[id]
    if not c then return false end
    calls[id] = nil
    dirty[id] = nil
    reason = str(reason, 32) or 'closed'
    c.closed = now()
    c.reason = reason
    local hadUnits = next(c.units) ~= nil
    local reachedHsp = c.status == 'HSP'
    for src in pairs(c.units) do
        local u = units[src]
        if u and u.call == id then u.call = nil end
        if online(src) then sendMe(src) end
    end
    if hadUnits and not reachedHsp then
        helpAll(c, { status = 'cleared' })
    end
    local pub = D.Public(c)
    c.units = {}
    pub.status = c.status
    table.insert(recent, 1, pub)
    while #recent > RECENT_MAX do table.remove(recent) end
    logCall('Close', c)
    broadcast('nza:dispatch:close', id, reason)
    if hadUnits then queueUnits() end
    NZA.Bus.Emit('dispatch:closed', c, reason)
    NZA.Debug('dispatch: closed', id, reason)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- API: STATUS / RESPOND / CLEAR / ASSIGN
-- ════════════════════════════════════════════════════════════════════════

local function stageSideEffects(c, src, stage, u)
    if stage == 'ENR' then
        c.respondedAt = c.respondedAt or now()
        local eta = etaFor(src, c)
        helpAll(c, { eta = eta, unit = unitLabel(u), status = 'enroute' })
        c.lastEta = now()
        if c.callerSrc and online(c.callerSrc) and not c.callerToldAt then
            local isPatient = false
            for _, p in ipairs(callPatients(c)) do if p.src == c.callerSrc then isPatient = true end end
            if not isPatient then
                c.callerToldAt = now()
                NZA.Core.Notify(c.callerSrc, NZA.L('dispatch.caller_responding', eta and U.formatTime(eta) or '--:--'), 'info', NZA.L('dispatch.caller_title'))
            end
        end
    elseif stage == 'SCN' then
        c.arrivedAt = c.arrivedAt or now()
        helpAll(c, { unit = unitLabel(u), status = 'onscene' })
    elseif stage == 'HSP' then
        c.closeAt = now() + (tonumber(cfg('calls', 'closeAfterHospital', 15)) or 15)
    end
end

function D.SetStatus(id, src, status, opts)
    opts = opts or {}
    local c = calls[id]
    if not c then return false, 'no_call' end
    status = type(status) == 'string' and status:upper() or nil
    if not status or not STAGE[status] then return false, 'bad_status' end
    src = tonumber(src)
    if not src then
        -- whole call: every unit on it
        local any = false
        for s in pairs(c.units) do
            if D.SetStatus(id, s, status, opts) then any = true end
        end
        return any, any and nil or 'no_units'
    end
    if status == 'DSP' then return D.Clear(src, id, 'status') end
    local u = units[src] or ensureUnit(src)
    if not u then return false, 'not_unit' end
    if u.call and u.call ~= id and calls[u.call] then D.Clear(src, u.call, 'switched') end
    local cu = c.units[src]
    if not cu then
        local max = tonumber(cfg('calls', 'maxUnits', 4)) or 4
        if max > 0 and not opts.force then
            local n = 0
            for _ in pairs(c.units) do n = n + 1 end
            if n >= max then return false, 'full' end
        end
        cu = { stage = status, at = now(), joined = now() }
        c.units[src] = cu
        c.declined[src] = nil
        u.call = id
        pushHistory(c, 'JOIN', src)
    else
        if opts.forward and STAGE[status] <= STAGE[cu.stage] then return false, 'not_forward' end
        if cu.stage == status then return true end
        cu.stage = status
        cu.at = now()
    end
    u.oos = false
    local old = c.status
    c.status = stageOf(c)
    if c.status ~= old or status == c.status then pushHistory(c, status, src) end
    c.updated = now()
    c.touched = now()
    stageSideEffects(c, src, status, u)
    local extra
    if status == 'TRN' then
        local h = D.NearestHospital(coordsOf(src) or c.coords)
        if h then extra = { hospital = h.label, x = h.coords.x, y = h.coords.y, z = h.coords.z } end
    end
    TriggerClientEvent('nza:dispatch:stage', src, id, status, extra)
    markDirty(id)
    sendMe(src)
    queueUnits()
    NZA.Bus.Emit('dispatch:status', c, src, status)
    return true
end

-- Only move forward (automatic advances)
local function advance(c, src, stage)
    local cu = c.units[src]
    if cu and STAGE[stage] <= STAGE[cu.stage] then return false end
    return D.SetStatus(c.id, src, stage, { forward = true, force = true })
end
D.Advance = function(id, src, stage) local c = calls[id]; return c and advance(c, tonumber(src), stage) or false end

function D.Respond(src, id)
    src = tonumber(src)
    local c = calls[id]
    if not c then return false, 'no_call' end
    local u = ensureUnit(src)
    if not u then return false, 'not_unit' end
    local cu = c.units[src]
    if cu and STAGE[cu.stage] >= STAGE.ENR then return false, 'already' end
    local ok, err = D.SetStatus(id, src, 'ENR')
    if not ok then return false, err end
    NZA.Bus.Emit('dispatch:respond', c, src)
    -- already standing at the scene
    local a = coordsOf(src)
    local radius = tonumber(cfg('status', 'sceneRadius', 35.0)) or 35.0
    if a and #(a - c.coords) <= radius and cfg('status', 'auto', true) then advance(c, src, 'SCN') end
    return true
end

function D.Clear(src, id, reason)
    src = tonumber(src)
    local u = units[src]
    id = id or (u and u.call)
    local c = id and calls[id]
    if not c or not c.units[src] then
        if u and u.call == id then u.call = nil; sendMe(src) end
        return false, 'not_on_call'
    end
    c.units[src] = nil
    if u and u.call == id then u.call = nil end
    pushHistory(c, 'CLR', src)
    c.status = stageOf(c)
    c.updated = now()
    sendMe(src)
    queueUnits()
    if next(c.units) == nil then
        if c.arrivedAt then
            D.Close(id, reason == 'status' and 'cleared' or (reason or 'cleared'))
            return true
        end
        c.status = 'DSP'
        c.respondedAt = nil
        helpAll(c, { status = 'cancelled' })
        markDirty(id)
        if cfg('calls', 'realertOnDrop', true) then alert(c, { realert = true }) end
        return true
    end
    markDirty(id)
    return true
end

function D.Decline(src, id)
    local c = calls[id]
    if not c then return false end
    c.declined[tonumber(src)] = true
    markDirty(id)
    return true
end

function D.Assign(id, target, by)
    target = tonumber(target)
    local c = calls[id]
    if not c then return false, 'no_call' end
    if not isOnDutyMedic(target) then return false, 'not_unit' end
    local ok, err = D.SetStatus(id, target, 'ENR', { force = true })
    if not ok then return false, err end
    local byName = by and by ~= 0 and units[tonumber(by)] and units[tonumber(by)].callsign or NZA.L('dispatch.dispatcher')
    TriggerClientEvent('nza:dispatch:assigned', target, D.Public(c), byName)
    return true
end

-- one line on a medic's pager (page log + LCD + beep), e.g. a new hospital check-in
local pageSeq = 0
function D.Page(src, msg)
    src = tonumber(src)
    if not src or type(msg) ~= 'table' or not online(src) then return false end
    local title, text = str(msg.title, 48), str(msg.text, 120)
    if not title and not text then return false end
    pageSeq = pageSeq + 1
    TriggerClientEvent('nza:dispatch:page', src, {
        id = ('PG-%d-%d'):format(now(), pageSeq),
        kind = str(msg.kind, 16) or 'page',
        priority = U.clamp(math.floor(tonumber(msg.priority) or 3), 1, 3),
        title = title, text = text, hospital = str(msg.hospital, 48),
    })
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- BOARD
-- ════════════════════════════════════════════════════════════════════════

local function checkinQueue()
    if not (NZA.Checkin and type(NZA.Checkin.Queue) == 'function') then return nil end
    local ok, list = pcall(NZA.Checkin.Queue)
    if not ok or type(list) ~= 'table' then return nil end
    local out, t = {}, now()
    for _, e in pairs(list) do
        if type(e) == 'table' then
            local created = tonumber(e.created or e.at or e.time or e.issued)
            out[#out + 1] = {
                ticket = tostring(e.ticket or e.number or e.code or e.id or '?'),
                name = str(e.name or e.patient, 48) or '?',
                priority = U.clamp(math.floor(tonumber(e.priority or e.tri or e.triage) or 3), 1, 3),
                wait = tonumber(e.wait) or (created and math.max(0, t - created)) or 0,
                status = str(e.status, 24) or 'waiting',
                hospital = str(e.hospitalLabel or e.hospital, 48),
            }
            if #out >= 40 then break end
        end
    end
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.wait > b.wait
    end)
    return out
end

local function responseStats()
    local total, n = 0, 0
    local dayAgo = now() - 86400
    local function add(c)
        if c.arrivedAt and c.created and c.created >= dayAgo then
            total = total + (c.arrivedAt - c.created)
            n = n + 1
        end
    end
    for _, c in pairs(calls) do add(c) end
    for _, c in ipairs(recent) do add(c) end
    return n > 0 and math.floor(total / n) or nil, n
end

function D.Board(src)
    local list = {}
    for _, c in ipairs(D.Active()) do list[#list + 1] = D.Public(c, true) end
    local hosp = {}
    for _, h in ipairs(D.Hospitals()) do hosp[#hosp + 1] = { id = h.id, label = h.label, x = h.coords.x, y = h.coords.y } end
    local unitsList = D.Units(true)
    if cfg('units', 'showOffDutyInRoster', false) then
        for _, id in ipairs(GetPlayers()) do
            local s = tonumber(id)
            local rec = s and not units[s] and NZA.Staff.Get(s) or nil
            if rec and rec.medic and not rec.onDuty then
                local name = NZA.Core.Name(s)
                unitsList[#unitsList + 1] = { src = s, name = name, short = shortName(name), callsign = callsignFor(s, NZA.Core.Identifier(s)),
                    grade = rec.gradeLabel, status = '10-7', offDuty = true }
            end
        end
    end
    -- incoming ambulances: units transporting, ETA to their nearest hospital
    local incoming = {}
    local speed = tonumber(cfg('status', 'etaSpeed', 19.0)) or 19.0
    for _, u in ipairs(unitsList) do
        if u.status == 'TRN' and u.x then
            local h, d = D.NearestHospital(vector3(u.x, u.y, 0.0))
            local c = u.call and calls[u.call]
            incoming[#incoming + 1] = {
                callsign = u.callsign, name = u.short, call = u.call, priority = c and c.priority or 3,
                title = c and c.title or '', hospital = h and h.label or '-', eta = d < math.huge and math.floor(d / speed) or nil,
            }
        end
    end
    local available, onCall, offDuty = 0, 0, 0
    for _, u in ipairs(unitsList) do
        if u.status == '10-8' then available = available + 1 elseif u.call then onCall = onCall + 1 end
        if u.offDuty then offDuty = offDuty + 1 end
    end
    local p1 = 0
    for _, c in ipairs(list) do if c.priority == 1 then p1 = p1 + 1 end end
    local avg, served = responseStats()
    local queue = checkinQueue()
    -- "Call next" on the ER intake page (nza:checkin:callNext checks the same permission)
    local deskPerm = (Config.Checkin and Config.Checkin.desk and Config.Checkin.desk.perm) or 'checkin'
    return {
        now = now(), calls = list, units = unitsList, hospitals = hosp, queue = queue, queueAvailable = queue ~= nil,
        canCallNext = queue ~= nil and NZA.Staff.Can(src, deskPerm) == true,
        incoming = incoming, recent = recent,
        stats = { active = #list, p1 = p1, available = available, onDuty = #unitsList - offDuty, onCall = onCall,
                  avgResponse = avg, served = served, waiting = queue and #queue or nil },
        me = D.Me(src),
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- AUTOMATIC STATUS CHAIN
-- ════════════════════════════════════════════════════════════════════════

local function patientLoaded(p)
    local ped = NZA.Core.PatientPed(p)
    local veh = (ped and ped ~= 0) and GetVehiclePedIsIn(ped, false) or 0
    local meta = p.meta or {}
    return veh ~= 0 or meta.bay ~= nil or meta.vehicle ~= nil or meta.stretcher ~= nil, veh, ped
end

local function nearUnits(c, coords, radius)
    local out = {}
    for src in pairs(c.units) do
        local a = coordsOf(src)
        if a and coords and #(a - coords) <= radius then out[#out + 1] = src end
    end
    return out
end

local function tickCall(c, t)
    local auto = cfg('status', 'auto', true)
    local sceneR = tonumber(cfg('status', 'sceneRadius', 35.0)) or 35.0
    local hospR = tonumber(cfg('status', 'hospitalRadius', 70.0)) or 70.0
    local trnD = tonumber(cfg('status', 'transportDistance', 60.0)) or 60.0

    -- timeouts
    if next(c.units) == nil then
        local limit = tonumber(cfg('calls', 'unassignedTimeout', 900)) or 900
        if limit > 0 and t - c.created > limit then D.Close(c.id, 'expired') end
        return
    end
    local stale = tonumber(cfg('calls', 'staleTimeout', 2700)) or 2700
    if stale > 0 and t - (c.touched or c.updated or c.created) > stale then D.Close(c.id, 'stale') return end
    if c.closeAt and t >= c.closeAt then D.Close(c.id, 'hospital') return end
    if not auto then return end

    local patients = callPatients(c)
    -- patient placed on a hospital point (bed, surgery…) → HSP
    for _, p in ipairs(patients) do
        if p.meta and p.meta.bed ~= nil then
            for src, cu in pairs(c.units) do
                if STAGE[cu.stage] < STAGE.HSP then advance(c, src, 'HSP') end
            end
            return
        end
    end

    for src, cu in pairs(c.units) do
        if not calls[c.id] then return end
        local a = coordsOf(src)
        if a then
            local stage = cu.stage
            if stage == 'ENR' then
                if #(a - c.coords) <= sceneR then
                    advance(c, src, 'SCN')
                end
            elseif stage == 'TRN' then
                local _, d = D.NearestHospital(a)
                if d <= hospR then advance(c, src, 'HSP') end
            end
        end
    end

    -- fallback transport detection (the transport module normally emits 'transport:loaded')
    if calls[c.id] and STAGE[c.status] >= STAGE.SCN and STAGE[c.status] < STAGE.TRN then
        for _, p in ipairs(patients) do
            local loaded, veh, ped = patientLoaded(p)
            if loaded and ped and ped ~= 0 then
                local pc = GetEntityCoords(ped)
                local moved = #(pc - c.coords) > trnD
                for src, cu in pairs(c.units) do
                    if STAGE[cu.stage] < STAGE.TRN then
                        local uped = GetPlayerPed(src)
                        local sameVeh = veh ~= 0 and uped and uped ~= 0 and GetVehiclePedIsIn(uped, false) == veh
                        local a = coordsOf(src)
                        if sameVeh or (moved and a and #(a - pc) <= 40.0) then advance(c, src, 'TRN') end
                    end
                end
            end
        end
    end

    -- ETA to the patient's HUD while units are en route
    local every = tonumber(cfg('status', 'etaUpdate', 10)) or 10
    if calls[c.id] and c.status == 'ENR' and (not c.lastEta or t - c.lastEta >= every) then
        c.lastEta = t
        local best, bestSrc = nil, nil
        for src, cu in pairs(c.units) do
            if cu.stage == 'ENR' then
                local eta = etaFor(src, c)
                if eta and (not best or eta < best) then best, bestSrc = eta, src end
            end
        end
        if best then helpAll(c, { eta = best, unit = unitLabel(units[bestSrc]), status = 'enroute' }) end
    end
end

-- one pass over every open call (timeouts, arrival, transport, hospital, ETAs)
function D.Tick()
    if next(calls) == nil then return end
    local t = now()
    local list = {}
    for _, c in pairs(calls) do list[#list + 1] = c end
    for _, c in ipairs(list) do
        if calls[c.id] then
            local ok, err = pcall(tickCall, c, t)
            if not ok then NZA.Warn('dispatch: tick failed for ' .. tostring(c.id) .. ': ' .. tostring(err)) end
        end
    end
end

CreateThread(function()
    while true do
        local tick = tonumber(cfg('status', 'tick', 1500)) or 1500
        Wait(math.max(500, tick))
        D.Tick()
    end
end)

-- Roster safety net: units follow NZA.Staff.OnDuty()
CreateThread(function()
    while true do
        Wait(10000)
        local seen = {}
        for _, src in ipairs(medics()) do
            seen[src] = true
            if not units[src] then
                ensureUnit(src)
                queueUnits()
            end
        end
        for src in pairs(units) do
            if not seen[src] then D.RemoveUnit(src, 'offduty') end
        end
    end
end)

function D.RemoveUnit(src, reason)
    src = tonumber(src)
    local u = units[src]
    if not u then return false end
    if u.call and calls[u.call] then D.Clear(src, u.call, reason or 'offduty') end
    units[src] = nil
    if online(src) then
        applyNpcState(src, false)
        TriggerClientEvent('nza:dispatch:sync', src, { calls = {}, units = {}, me = D.Me(src) })
    end
    queueUnits()
    return true
end

function D.SyncPayload(src)
    local me = D.Me(src)
    if not (me.medic and me.onDuty) then return { calls = {}, units = {}, me = me } end
    ensureUnit(src)
    local list = {}
    for _, c in ipairs(D.Active()) do list[#list + 1] = D.Public(c) end
    return { calls = list, units = D.Units(false), me = D.Me(src), recent = recent }
end

-- ════════════════════════════════════════════════════════════════════════
-- BUS
-- ════════════════════════════════════════════════════════════════════════

local function onTreatment(src, p)
    src = tonumber(src)
    if not src or type(p) ~= 'table' then return end
    local c = D.CallForPatient(p)
    if not c then return end
    local cu = c.units[src]
    if cu then
        if STAGE[cu.stage] < STAGE.CARE then advance(c, src, 'CARE') end
    elseif cfg('calls', 'autoAttach', true) and isOnDutyMedic(src) then
        D.SetStatus(c.id, src, 'CARE', { force = true })
        if not c.arrivedAt then c.arrivedAt = now() end
    end
end

NZA.Bus.On('treat:done', function(src, p) onTreatment(src, p) end)
NZA.Bus.On('proc:done', function(src, p) onTreatment(src, p) end)

-- transport module: Emit('transport:loaded', src, patient, kind, netId) — read defensively
NZA.Bus.On('transport:loaded', function(...)
    local args = { ... }
    local src, p
    for i = 1, select('#', ...) do
        local v = args[i]
        if type(v) == 'number' and not src and online(v) then src = v
        elseif type(v) == 'table' and not p and v.pid then p = v
        elseif type(v) == 'string' and not p and v:match('^[pn]:') then p = NZA.Patients.Get(v) end
    end
    if not p then return end
    local c = D.CallForPatient(p)
    if not c then return end
    local pc = NZA.Core.PatientCoords(p) or c.coords
    local list = src and c.units[src] and { src } or nearUnits(c, pc, 40.0)
    if #list == 0 then for s in pairs(c.units) do list[#list + 1] = s end end
    for _, s in ipairs(list) do advance(c, s, 'TRN') end
    if src and not c.units[src] and isOnDutyMedic(src) and cfg('calls', 'autoAttach', true) then
        D.SetStatus(c.id, src, 'TRN', { force = true })
    end
end)

-- transport module: patient placed on a hospital point (bed, x-ray, surgery…) → delivered
NZA.Bus.On('transport:bed', function(src, p)
    if type(p) ~= 'table' then return end
    local c = D.CallForPatient(p)
    if not c then return end
    for s, cu in pairs(c.units) do
        if STAGE[cu.stage] < STAGE.HSP then advance(c, s, 'HSP') end
    end
end)

NZA.Bus.On('patient:created', function(p)
    if type(p) ~= 'table' or not p.meta or not p.meta.callId then return end
    local c = calls[p.meta.callId]
    if c and addPatient(c, p.pid) then markDirty(c.id) end
end)

NZA.Bus.On('patient:removed', function(pid)
    if type(pid) == 'table' then pid = pid.pid end
    if type(pid) ~= 'string' then return end
    for _, c in pairs(calls) do
        for i = #c.patients, 1, -1 do
            if c.patients[i] == pid then
                table.remove(c.patients, i)
                if #c.patients == 0 and c.hadPatients and STAGE[c.status] < STAGE.TRN then
                    SetTimeout(0, function() if calls[c.id] and #c.patients == 0 then D.Close(c.id, 'patient_gone') end end)
                else
                    markDirty(c.id)
                end
            end
        end
    end
end)

NZA.Bus.On('state:changed', function(p, _, new)
    if type(p) ~= 'table' then return end
    local c = D.CallForPatient(p)
    if not c then return end
    if new == 'arrest' and cfg('calls', 'upgradeOnArrest', true) and c.priority > 1 then
        c.priority = 1
        pushHistory(c, 'P1')
    end
    if new == 'alive' and cfg('calls', 'closeWhenRecovered', true) and next(c.units) == nil then
        local all = true
        for _, x in ipairs(callPatients(c)) do if x.state ~= 'alive' then all = false end end
        if all then
            SetTimeout(0, function() if calls[c.id] and next(calls[c.id].units) == nil then D.Close(c.id, 'recovered') end end)
            return
        end
    end
    markDirty(c.id)
end)

NZA.Bus.On('staff:changed', function(src, rec)
    src = tonumber(src)
    if not src then return end
    local on = type(rec) == 'table' and rec.medic == true and rec.onDuty == true
    if on and not units[src] then
        ensureUnit(src)
        TriggerClientEvent('nza:dispatch:sync', src, D.SyncPayload(src))
        queueUnits()
    elseif not on and units[src] then
        D.RemoveUnit(src, 'offduty')
    elseif units[src] then
        local u = units[src]
        u.grade = rec.gradeLabel
        u.dept = rec.deptLabel or rec.dept
        sendMe(src)
    end
end)

local function dropped(src)
    src = tonumber(src)
    if not src then return end
    if units[src] then
        local u = units[src]
        if u.call and calls[u.call] then D.Clear(src, u.call, 'dropped') end
        units[src] = nil
        queueUnits()
    end
    paired[src] = nil
end

NZA.Bus.On('player:unloaded', function(src) dropped(src) end)
AddEventHandler('playerDropped', function() dropped(source) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, c in pairs(calls) do
        c.closed = now()
        c.reason = 'restart'
        logCall('Close', c)
        calls[id] = nil
    end
end)
