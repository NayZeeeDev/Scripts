--[[
    NAYZEEE AMBULANCE - Transport (server): carry, help up, stretchers, beds & tables

    The server owns every transport record. Clients only ask; the server checks permission
    (NZA.Staff.Can), distance (server-side coords), rate limits and the current state, then
    writes the patient meta + replicated state bags that every client follows:

      patient (player state bag / NPC entity state bag) 'nzaTr' =
          { m = 'carry'|'str'|'bed'|'bay'|'seat'|'free', n = seq,
            c = carrier sid, s = stretcher net, b = point id, bt = point type, at = {x,y,z,w},
            v = vehicle net, seat = index, slot = bay slot, stand = bool, from = 'bay' }
      stretcher entity 'nzaStr' = { pid, pk = target, pusher = sid, veh = net (loaded in), low, home = veh net }
      ambulance entity 'nzaAmb' = { str = stretcher net, inside = bool, bay = medics in the bay }
    Patient meta (core): carried = carrier src, stretcher = net, bed = { point, type }, inBed,
    vehicle = net, bay = vehicle net (transport_bay.lua). All transient (dropped on load).

    API (server, other modules)
      NZA.Transport.Info(pidOrPatient)       → { carried, stretcher, bed, bay, vehicle } | nil
      NZA.Transport.Free(pidOrPatient, at?)  → bool   release the patient from everything (carry,
                                                      stretcher, bed, seat, bay) and lay them at `at` (vector4)
      NZA.Transport.Release(pidOrPatient)    → bool   release without moving (respawn teleports)
      NZA.Transport.PatientBag(p, tbl)       write the 'nzaTr' bag (internal, used by transport_bay.lua)
      NZA.Transport.VehicleRear(veh, extra)  → vector3, heading   behind the back doors (server coords)

    Callbacks (lib.callback, all 'nza:transport:*')
      carry (target)                 drop ({ veh?, seat? })          helpUp (target)
      outVehicle (target)            str:take ({ veh? | point? })   str:register (token, net)
      str:push (net, on)             str:height (net, low)          str:swap (net, newNet)
      str:place (net, target)        str:off (net)                  str:load (net, veh)
      str:unload (veh)               str:store (net, veh?, point?)  bed:place (point, net?)
      bed:leave (target)             bed:self ()
      Every reply: true, data | false, { err, msg }
    S→C events: nza:transport:carryEnd (carrier), nza:transport:pushEnd (pusher)
    C→S events: nza:transport:selfRelease (a DEAD player about to respawn lets go of everything)
    Bus (server) emitted: transport:loaded (src, p, vehNet, strNet)   ← dispatch uses it for TRN
                          transport:unloaded (src, p|nil, vehNet)  transport:bed (src, p, point)
                          transport:carry (src, p, on)
    Bus listened: patient:removed, player:unloaded, state:changed, wounded:respawned
    Exports: GetTransportState(src) → Info table
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local T = NZA.Transport
local U = NZA.Util

T.carries    = T.carries or {}      -- [carrier src] = pid
T.stretchers = T.stretchers or {}   -- [net] = record
T.vehicles   = T.vehicles or {}     -- [vehicle net] = { str = net, inside = bool }
T.beds       = T.beds or {}         -- [point id] = pid
T.trips      = T.trips or {}        -- [pid] = { veh, at }  ambulance trip (billing)

local pending = {}                  -- [src] = { token, veh, point, at }
local seq = 0
local vehModels = nil
local strModels = nil

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section)
    local c = Config.Transport or {}
    if not section then return c end
    return c[section] or {}
end
T.Cfg = cfg

local function L(key, ...)
    return NZA.L('transport.' .. key, ...)
end

local function fail(err, extra)
    local r = { err = err, msg = L('err_' .. err) }
    if type(extra) == 'table' then for k, v in pairs(extra) do r[k] = v end end
    return false, r
end
T.Fail = fail

local function norm(h)
    h = tonumber(h) or 0
    if h > 0x7FFFFFFF then h = h - 0x100000000 end
    return math.floor(h)
end

local function rate(src, bucket, n, ms)
    return NZA.Core.Rate('nza:transport:' .. bucket, src, n or 6, ms or 2000)
end
T.Rate = rate

local function can(src, perm)
    if perm == false or perm == nil then return true end
    return NZA.Staff.Can(src, perm)
end
T.Can = can

local function P() return NZA.Patients end

local function medicAlive(src)
    local me = P().GetBySource(src)
    return not me or me.state == 'alive'
end
T.MedicAlive = medicAlive

local function entFromNet(net)
    net = tonumber(net)
    if not net then return 0 end
    local e = NetworkGetEntityFromNetworkId(net)
    if e and e ~= 0 and DoesEntityExist(e) then return e end
    return 0
end
T.Ent = entFromNet

local function srcCoords(src)
    return NZA.Core.SrcCoords(src)
end

local function dist(a, b)
    if not a or not b then return math.huge end
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

local function toV4(c)
    if not c then return nil end
    local t = type(c)
    if t == 'vector4' then return c end
    if t == 'vector3' then return vector4(c.x, c.y, c.z, 0.0) end
    if t == 'table' then
        local x = tonumber(c.x or c[1])
        local y = tonumber(c.y or c[2])
        local z = tonumber(c.z or c[3])
        if not x or not y or not z then return nil end
        return vector4(x, y, z, tonumber(c.w or c.h or c.heading or c[4]) or 0.0)
    end
    return nil
end
T.V4 = toV4

local function pack(v)
    if not v then return nil end
    return { x = U.round(v.x, 3), y = U.round(v.y, 3), z = U.round(v.z, 3), w = U.round(v.w or 0.0, 1) }
end
T.Pack = pack

local function key(p)
    if p.kind == 'player' then return { kind = 'player', sid = p.src } end
    return { kind = 'npc', net = p.net }
end
T.Key = key

local function patientName(p)
    return (p and p.name) or L('patient')
end

local function resolve(target)
    local p = P().Resolve(target)
    if not p then return nil end
    return p
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE BAGS
-- ════════════════════════════════════════════════════════════════════════

function T.PatientBag(p, tbl)
    if not p then return end
    seq = seq + 1
    if tbl then tbl.n = seq end
    if p.kind == 'player' then
        if p.src then Player(p.src).state:set('nzaTr', tbl, true) end
        return
    end
    local ped = NZA.Core.PatientPed(p)
    if ped ~= 0 then Entity(ped).state:set('nzaTr', tbl, true) end
end
local patientBag = T.PatientBag

local function strBag(rec)
    local ent = entFromNet(rec.net)
    if ent == 0 then return end
    local p = rec.pid and P().Get(rec.pid) or nil
    Entity(ent).state:set('nzaStr', {
        pid = rec.pid, pk = p and key(p) or nil, pusher = rec.pusher, veh = rec.veh,
        low = rec.low == true, home = rec.home,
    }, true)
end
T.StrBag = strBag

function T.VehBag(vehNet)
    local ent = entFromNet(vehNet)
    if ent == 0 then return end
    local v = T.vehicles[vehNet]
    local bay = T.bays and T.bays[vehNet]
    local crew = 0
    if bay then for _ in pairs(bay.medics) do crew = crew + 1 end end
    Entity(ent).state:set('nzaAmb', {
        str = v and v.str or nil, inside = v and v.inside == true or false, bay = crew,
    }, true)
end
local vehBag = T.VehBag

-- ════════════════════════════════════════════════════════════════════════
-- MODELS & VEHICLES
-- ════════════════════════════════════════════════════════════════════════

local function vehicleConfig(veh)
    if not vehModels then
        vehModels = {}
        for name, c in pairs(cfg('Stretcher').vehicles or {}) do
            vehModels[norm(joaat(name))] = c
        end
    end
    if veh == 0 then return nil end
    return vehModels[norm(GetEntityModel(veh))]
end
T.VehicleConfig = vehicleConfig

local function stretcherModelOk(ent)
    if not strModels then
        strModels = {}
        local s = cfg('Stretcher')
        local function add(k)
            if not k then return end
            local name = (Config.Props and Config.Props[k]) or nil
            if name then strModels[norm(joaat(name))] = true end
            local fb = Config.PropFallbacks and Config.PropFallbacks[k]
            if fb then strModels[norm(joaat(fb))] = true end
        end
        add(s.model or 'stretcher')
        add(s.lowModel)
    end
    return strModels[norm(GetEntityModel(ent))] == true
end

function T.VehicleRear(veh, extra)
    local c = vehicleConfig(veh) or {}
    local pos = GetEntityCoords(veh)
    local h = GetEntityHeading(veh)
    local r = math.rad(h)
    local d = (tonumber(c.rear) or 3.6) + (extra or 0.0)
    return vector3(pos.x + math.sin(r) * d, pos.y - math.cos(r) * d, pos.z), h
end

local function nearVehicleRear(src, veh, slack)
    local me = srcCoords(src)
    if not me then return false end
    local rear = T.VehicleRear(veh, 0.0)
    if #(me - rear) <= (cfg('Stretcher').rearReach or 2.3) + (slack or 2.5) then return true end
    return #(me - GetEntityCoords(veh)) <= 4.5 + (slack or 0.0)
end
T.NearRear = nearVehicleRear

local function vehRec(vehNet)
    local v = T.vehicles[vehNet]
    if not v then
        v = { str = nil, inside = false }
        T.vehicles[vehNet] = v
    end
    return v
end

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITAL POINTS
-- ════════════════════════════════════════════════════════════════════════

local function bedTypeConfig(pt)
    if not pt then return nil end
    local types = cfg('Beds').types or {}
    if types[pt.type] then return types[pt.type] end
    if type(pt.data) == 'table' and pt.data.bed == true then return {} end
    return nil
end
T.BedType = bedTypeConfig

local function findPoint(id)
    local H = NZA.Hospitals
    if id == nil or type(H) ~= 'table' then return nil end
    for _, fname in ipairs({ 'Point', 'GetPoint' }) do
        if type(H[fname]) == 'function' then
            local ok, pt = pcall(H[fname], id)
            if ok and type(pt) == 'table' then return pt end
        end
    end
    if type(H.Points) ~= 'function' then return nil end
    local sid = tostring(id)
    local function scan(list)
        if type(list) ~= 'table' then return nil end
        for _, pt in pairs(list) do
            if type(pt) == 'table' and tostring(pt.id) == sid then return pt end
        end
        return nil
    end
    local ok, all = pcall(H.Points, nil)
    local found = ok and scan(all) or nil
    if found then return found end
    local kinds = { 'stretcher' }
    for t in pairs(cfg('Beds').types or {}) do kinds[#kinds + 1] = t end
    for _, t in ipairs(kinds) do
        local ok2, list = pcall(H.Points, t)
        found = ok2 and scan(list) or nil
        if found then return found end
    end
    return nil
end
T.FindPoint = findPoint

local function pointLabel(pt)
    if not pt then return '' end
    if pt.label and pt.label ~= '' then return pt.label end
    local k = 'transport.pt_' .. tostring(pt.type)
    local s = NZA.L(k)
    if s ~= k then return s end
    return tostring(pt.type)
end
T.PointLabel = pointLabel

-- ════════════════════════════════════════════════════════════════════════
-- RELEASE HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function hospitalOccupant(pointId)
    local H = NZA.Hospitals
    if type(H) ~= 'table' or type(H.BedOccupant) ~= 'function' then return nil end
    local ok, pid = pcall(H.BedOccupant, pointId)
    return ok and pid or nil
end

local function releaseBed(p)
    local b = p.meta and p.meta.bed
    if type(b) == 'table' and b.point ~= nil then
        if T.beds[b.point] == p.pid then T.beds[b.point] = nil end
        local H = NZA.Hospitals
        if type(H) == 'table' and type(H.ReleaseBed) == 'function' and hospitalOccupant(b.point) == p.pid then
            pcall(H.ReleaseBed, b.point)
        end
    end
    if p.meta and (p.meta.bed ~= nil or p.meta.inBed ~= nil) then
        P().SetMeta(p, 'bed', nil)
        P().SetMeta(p, 'inBed', nil)
    end
end

local function releaseStretcher(p)
    local net = p.meta and p.meta.stretcher
    if net ~= nil then
        local rec = T.stretchers[net]
        if rec and rec.pid == p.pid then
            rec.pid = nil
            rec.touched = os.time()
            strBag(rec)
        end
        P().SetMeta(p, 'stretcher', nil)
    end
end

local function releaseCarry(p, silent)
    local c = p.meta and p.meta.carried
    if c ~= nil then
        if T.carries[c] == p.pid then
            T.carries[c] = nil
            if not silent then TriggerClientEvent('nza:transport:carryEnd', c) end
            NZA.Bus.Emit('transport:carry', c, p, false)
        end
        P().SetMeta(p, 'carried', nil)
    end
end

local function releaseSeat(p)
    if p.meta and p.meta.vehicle ~= nil then P().SetMeta(p, 'vehicle', nil) end
end

-- everything but the bay (transport_bay.lua owns that)
local function releaseAll(p, silentCarry)
    releaseCarry(p, silentCarry)
    releaseStretcher(p)
    releaseBed(p)
    releaseSeat(p)
end
T.ReleaseAll = releaseAll

local function groundBelow(v)
    return vector4(v.x, v.y, v.z, v.w or 0.0)
end

-- lay the patient down at `at` (vector4); stand = get up (alive patients)
local function setFree(p, at, stand)
    local cmd = { m = 'free', at = pack(at), stand = stand and true or nil }
    patientBag(p, cmd)
    return cmd
end

function T.Free(pidOrP, at)
    local p = type(pidOrP) == 'table' and pidOrP or P().Get(pidOrP)
    if not p then return false end
    local pos = at and toV4(at) or nil
    local fromBay = false
    if p.meta and p.meta.bay ~= nil then
        fromBay = true
        if not pos and T.BayExitAt then pos = T.BayExitAt(p.meta.bay) end
        if T.LeaveBay then T.LeaveBay(p) end
    end
    releaseAll(p)
    if not pos then
        local c = NZA.Core.PatientCoords(p)
        pos = c and vector4(c.x, c.y, c.z, 0.0) or nil
    end
    if pos then
        patientBag(p, { m = 'free', at = pack(pos), stand = p.state == 'alive' or nil, from = fromBay and 'bay' or nil })
    end
    return true
end

-- release without moving anybody (respawn teleport, character switch)
function T.Release(pidOrP)
    local p = type(pidOrP) == 'table' and pidOrP or P().Get(pidOrP)
    if not p then return false end
    if p.meta and p.meta.bay ~= nil and T.LeaveBay then T.LeaveBay(p) end
    releaseAll(p)
    patientBag(p, nil)
    return true
end

function T.Info(pidOrP)
    local p = type(pidOrP) == 'table' and pidOrP or P().Get(pidOrP)
    if not p or not p.meta then return nil end
    return {
        carried = p.meta.carried, stretcher = p.meta.stretcher, bed = p.meta.bed,
        bay = p.meta.bay, vehicle = p.meta.vehicle,
    }
end

local function isPusher(src)
    for _, rec in pairs(T.stretchers) do
        if rec.pusher == src then return rec end
    end
    return nil
end
T.Pushing = isPusher

local function busy(src)
    if T.carries[src] then return true end
    if isPusher(src) then return true end
    if T.InBay and T.InBay(src) then return true end
    return false
end
T.Busy = busy

-- ════════════════════════════════════════════════════════════════════════
-- CARRY
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:transport:carry', function(src, target)
    local c = cfg('Carry')
    if c.enabled == false then return fail('disabled') end
    if not rate(src, 'carry', 4, 2000) then return fail('rate') end
    if not can(src, c.perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    if busy(src) then return fail('busy') end
    local p = resolve(target)
    if not p then return fail('no_patient') end
    if p.kind == 'player' and p.src == src then return fail('state') end
    local states = c.states or {}
    if not states[p.state] then return fail('state') end
    if p.meta.carried or p.meta.stretcher or p.meta.bay or p.meta.bodybag then return fail('patient_busy') end
    if p.meta.vehicle then return fail('state') end
    if NZA.Core.DistanceTo(src, p) > (c.distance or 2.0) + 1.5 then return fail('too_far') end

    releaseBed(p)
    T.carries[src] = p.pid
    P().SetMeta(p, 'carried', src)
    local cmd = { m = 'carry', c = src }
    patientBag(p, cmd)
    NZA.Bus.Emit('transport:carry', src, p, true)
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', name = patientName(p) }
end)

lib.callback.register('nza:transport:drop', function(src, opts)
    if not rate(src, 'drop', 6, 2000) then return fail('rate') end
    local pid = T.carries[src]
    local p = pid and P().Get(pid)
    if not p then
        T.carries[src] = nil
        return fail('no_patient')
    end
    opts = type(opts) == 'table' and opts or {}
    local c = cfg('Carry')
    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)

    -- into a vehicle seat
    if opts.veh then
        local veh = entFromNet(opts.veh)
        if veh == 0 or GetEntityType(veh) ~= 2 then return fail('no_vehicle') end
        if #(pos - GetEntityCoords(veh)) > (c.seatRange or 3.2) + 3.0 then return fail('too_far') end
        local seat = tonumber(opts.seat)
        local allowed = false
        for _, s in ipairs(c.seats or { 1, 2, 0 }) do if s == seat then allowed = true end end
        if not allowed then return fail('no_seat') end
        local occupant = GetPedInVehicleSeat(veh, seat)
        if occupant and occupant ~= 0 then return fail('no_seat') end
        releaseCarry(p, true)
        P().SetMeta(p, 'vehicle', opts.veh)
        local cmd = { m = 'seat', v = opts.veh, seat = seat }
        patientBag(p, cmd)
        return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', msg = L('ok_seated', patientName(p)) }
    end

    releaseCarry(p, true)
    local r = math.rad(h)
    local ahead = c.dropAhead or 0.9
    local at = vector4(pos.x - math.sin(r) * ahead, pos.y + math.cos(r) * ahead, pos.z - 0.9, (h + 90.0) % 360.0)
    local cmd = setFree(p, groundBelow(at), p.state == 'alive')
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc' }
end)

-- ════════════════════════════════════════════════════════════════════════
-- HELP UP / OUT OF A VEHICLE
-- ════════════════════════════════════════════════════════════════════════

local standErr = { bleeding = 'bleeding', avpu = 'avpu', blood = 'blood', condition = 'condition' }

local function standUp(p, reason)
    if p.state == 'wounded' then
        P().SetState(p, 'alive', reason or 'helped_up')
        if p.kind == 'player' and p.src then
            TriggerClientEvent('nza:revived', p.src, { reason = reason or 'helped_up' })
            P().Sync(p)
        end
    end
end

lib.callback.register('nza:transport:helpUp', function(src, target)
    local c = cfg('HelpUp')
    if c.enabled == false then return fail('disabled') end
    if not rate(src, 'helpup', 3, 2000) then return fail('rate') end
    if not can(src, c.perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local p = resolve(target)
    if not p then return fail('no_patient') end
    if p.kind == 'player' and p.src == src then return fail('state') end
    if p.meta.carried or p.meta.stretcher or p.meta.bay or p.meta.vehicle or p.meta.bodybag then return fail('patient_busy') end
    if p.state ~= 'wounded' then return fail('state') end
    if NZA.Core.DistanceTo(src, p) > (c.distance or 2.0) + 1.5 then return fail('too_far') end
    local okStand, why = P().CanStand(p)
    if not okStand then return fail(standErr[why] or 'cant_stand') end
    releaseBed(p)
    standUp(p, 'helped_up')
    local pos = NZA.Core.PatientCoords(p)
    local cmd = { m = 'free', at = pos and pack(vector4(pos.x, pos.y, pos.z, 0.0)) or nil, stand = true }
    patientBag(p, cmd)
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', msg = L('ok_helped_up', patientName(p)) }
end)

lib.callback.register('nza:transport:outVehicle', function(src, target)
    if not rate(src, 'outveh', 4, 2000) then return fail('rate') end
    if not can(src, cfg('Carry').perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local p = resolve(target)
    if not p then return fail('no_patient') end
    local vehNet = p.meta.vehicle
    if not vehNet then return fail('state') end
    if NZA.Core.DistanceTo(src, p) > 5.0 then return fail('too_far') end
    releaseSeat(p)
    local me = srcCoords(src)
    local at = me and vector4(me.x, me.y, me.z - 0.9, 0.0) or nil
    local cmd = setFree(p, at or vector4(0.0, 0.0, 0.0, 0.0), p.state == 'alive')
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc' }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STRETCHER: TAKE / REGISTER / STORE
-- ════════════════════════════════════════════════════════════════════════

local function stretcherCount(vehNet)
    local n = 0
    for _, rec in pairs(T.stretchers) do
        if rec.home == vehNet then n = n + 1 end
    end
    return n
end

lib.callback.register('nza:transport:str:take', function(src, from)
    local s = cfg('Stretcher')
    if s.enabled == false then return fail('disabled') end
    if not rate(src, 'take', 3, 3000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    if busy(src) then return fail('busy') end
    from = type(from) == 'table' and from or {}
    local me = srcCoords(src)
    if not me then return fail('failed') end

    if from.veh then
        local veh = entFromNet(from.veh)
        if veh == 0 then return fail('no_vehicle') end
        if not vehicleConfig(veh) then return fail('no_vehicle') end
        if not nearVehicleRear(src, veh) then return fail('too_far') end
        local v = vehRec(from.veh)
        if v.str and T.stretchers[v.str] then
            if v.inside then return fail('loaded') end
            return fail('stretcher_out')
        end
        if stretcherCount(from.veh) >= (s.maxPerVehicle or 1) then return fail('stretcher_out') end
    elseif from.point ~= nil then
        local pt = findPoint(from.point)
        if not pt or pt.type ~= 'stretcher' then return fail('no_point') end
        local pc = toV4(pt.coords)
        if not pc or dist(me, pc) > 4.0 then return fail('too_far') end
    else
        return fail('failed')
    end

    local token = U.uid('st')
    pending[src] = { token = token, veh = from.veh, point = from.point, at = os.time() }
    return true, { token = token }
end)

lib.callback.register('nza:transport:str:register', function(src, token, net)
    local pend = pending[src]
    pending[src] = nil
    if not pend or pend.token ~= token or os.time() - pend.at > 20 then return fail('failed') end
    net = tonumber(net)
    if not net or net <= 0 or T.stretchers[net] then return fail('failed') end
    local ent = 0
    for _ = 1, 20 do
        ent = entFromNet(net)
        if ent ~= 0 then break end
        Wait(100)
    end
    if ent == 0 or GetEntityType(ent) ~= 3 then return fail('failed') end
    if not stretcherModelOk(ent) then
        DeleteEntity(ent)
        return fail('model')
    end
    local me = srcCoords(src)
    if not me or #(me - GetEntityCoords(ent)) > 8.0 then
        DeleteEntity(ent)
        return fail('too_far')
    end
    local rec = {
        net = net, owner = src, home = pend.veh, point = pend.point, pusher = nil, pid = nil,
        veh = nil, low = false, created = os.time(), touched = os.time(),
    }
    T.stretchers[net] = rec
    if pend.veh then
        local v = vehRec(pend.veh)
        v.str, v.inside = net, false
        vehBag(pend.veh)
    end
    strBag(rec)
    return true, { net = net }
end)

local function deleteStretcher(rec)
    local ent = entFromNet(rec.net)
    if rec.pid then
        local p = P().Get(rec.pid)
        if p then
            releaseStretcher(p)
            local c = ent ~= 0 and GetEntityCoords(ent) or NZA.Core.PatientCoords(p)
            if c then setFree(p, vector4(c.x, c.y, c.z, 0.0), p.state == 'alive') end
        end
    end
    if rec.pusher then TriggerClientEvent('nza:transport:pushEnd', rec.pusher, rec.net) end
    T.stretchers[rec.net] = nil
    for vehNet, v in pairs(T.vehicles) do
        if v.str == rec.net then
            v.str, v.inside = nil, false
            vehBag(vehNet)
        end
    end
    if ent ~= 0 then DeleteEntity(ent) end
end
T.DeleteStretcher = deleteStretcher

lib.callback.register('nza:transport:str:store', function(src, net, vehNet, pointId)
    if not rate(src, 'store', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if rec.pid then return fail('not_empty') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    local ent = entFromNet(rec.net)
    local me = srcCoords(src)
    if not me then return fail('failed') end
    if ent ~= 0 and #(me - GetEntityCoords(ent)) > 5.0 then return fail('too_far') end
    if vehNet then
        local veh = entFromNet(vehNet)
        if veh == 0 or not vehicleConfig(veh) then return fail('no_vehicle') end
        if not nearVehicleRear(src, veh, 3.0) then return fail('too_far') end
        local v = vehRec(vehNet)
        if v.str and v.str ~= rec.net and T.stretchers[v.str] then return fail('vehicle_full') end
    elseif pointId ~= nil then
        local pt = findPoint(pointId)
        local pc = pt and toV4(pt.coords)
        if not pt or pt.type ~= 'stretcher' or not pc then return fail('no_point') end
        if dist(me, pc) > 5.0 then return fail('too_far') end
    elseif not rec.veh then
        return fail('no_vehicle')
    end
    deleteStretcher(rec)
    return true, { msg = L('ok_returned') }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STRETCHER: PUSH / HEIGHT / SWAP
-- ════════════════════════════════════════════════════════════════════════

local function nearStretcher(src, rec, range)
    local ent = entFromNet(rec.net)
    local me = srcCoords(src)
    if ent == 0 or not me then return false end
    return #(me - GetEntityCoords(ent)) <= (range or 3.5)
end
T.NearStretcher = nearStretcher

lib.callback.register('nza:transport:str:push', function(src, net, on)
    if not rate(src, 'push', 8, 2000) then return fail('rate') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if not on then
        if rec.pusher == src then
            rec.pusher = nil
            rec.touched = os.time()
            strBag(rec)
        end
        return true, {}
    end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    if rec.veh then return fail('loaded') end
    if T.carries[src] or (T.InBay and T.InBay(src)) then return fail('busy') end
    local other = isPusher(src)
    if other and other ~= rec then return fail('busy') end
    if rec.pusher and rec.pusher ~= src and GetPlayerPed(rec.pusher) ~= 0 then return fail('pushed') end
    if not nearStretcher(src, rec, 3.5) then return fail('too_far') end
    rec.pusher = src
    rec.touched = os.time()
    strBag(rec)
    local p = rec.pid and P().Get(rec.pid) or nil
    return true, { low = rec.low, patient = p and key(p) or nil }
end)

lib.callback.register('nza:transport:str:height', function(src, net, low)
    if not rate(src, 'height', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if rec.veh then return fail('loaded') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    if not nearStretcher(src, rec, 3.5) then return fail('too_far') end
    rec.low = low and true or false
    rec.touched = os.time()
    strBag(rec)
    return true, { low = rec.low, msg = L(rec.low and 'ok_lowered' or 'ok_raised') }
end)

-- the client replaced the cot entity with the lowered / raised model
lib.callback.register('nza:transport:str:swap', function(src, net, newNet)
    if not rate(src, 'swap', 4, 2000) then return fail('rate') end
    local rec = T.stretchers[tonumber(net) or -1]
    newNet = tonumber(newNet)
    if not rec or not newNet or T.stretchers[newNet] then return fail('failed') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    if not nearStretcher(src, rec, 4.0) then return fail('too_far') end
    local ent = 0
    for _ = 1, 20 do
        ent = entFromNet(newNet)
        if ent ~= 0 then break end
        Wait(100)
    end
    if ent == 0 or GetEntityType(ent) ~= 3 or not stretcherModelOk(ent) then
        if ent ~= 0 then DeleteEntity(ent) end
        return fail('model')
    end
    local old = entFromNet(rec.net)
    T.stretchers[rec.net] = nil
    rec.net = newNet
    T.stretchers[newNet] = rec
    for vehNet, v in pairs(T.vehicles) do
        if v.str == net then
            v.str = newNet
            vehBag(vehNet)
        end
    end
    if rec.pid then
        local p = P().Get(rec.pid)
        if p then
            P().SetMeta(p, 'stretcher', newNet)
            patientBag(p, { m = 'str', s = newNet })
        end
    end
    strBag(rec)
    if old ~= 0 then DeleteEntity(old) end
    return true, { net = newNet }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STRETCHER: PATIENT ON / OFF
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:transport:str:place', function(src, net, target)
    if not rate(src, 'place', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if rec.pid then return fail('not_empty') end
    if rec.veh then return fail('loaded') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    local p = resolve(target)
    if not p then return fail('no_patient') end
    if p.kind == 'player' and p.src == src then return fail('state') end
    local carrying = T.carries[src] == p.pid
    if p.meta.carried and not carrying then return fail('patient_busy') end
    if p.meta.stretcher or p.meta.bay or p.meta.vehicle or p.meta.bodybag then return fail('patient_busy') end
    if (T.carries[src] and not carrying) then return fail('busy') end
    if not nearStretcher(src, rec, cfg('Stretcher').findRange or 6.0) then return fail('too_far') end
    local ent = entFromNet(rec.net)
    local pc = NZA.Core.PatientCoords(p)
    if not carrying and (not pc or ent == 0 or #(pc - GetEntityCoords(ent)) > (cfg('Stretcher').findRange or 6.0) + 1.0) then
        return fail('too_far')
    end
    releaseAll(p, true)
    rec.pid = p.pid
    rec.touched = os.time()
    P().SetMeta(p, 'stretcher', rec.net)
    local cmd = { m = 'str', s = rec.net }
    patientBag(p, cmd)
    strBag(rec)
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', carried = carrying }
end)

lib.callback.register('nza:transport:str:off', function(src, net)
    if not rate(src, 'off', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if not rec.pid then return fail('no_patient') end
    if rec.veh then return fail('loaded') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    if not nearStretcher(src, rec, 3.5) then return fail('too_far') end
    local p = P().Get(rec.pid)
    if not p then
        rec.pid = nil
        strBag(rec)
        return fail('no_patient')
    end
    if p.meta.bay then return fail('in_bay') end
    releaseStretcher(p)
    local ent = entFromNet(rec.net)
    local sc = GetEntityCoords(ent)
    local h = GetEntityHeading(ent)
    local r = math.rad(h)
    local side = 1.05
    local at = vector4(sc.x + math.cos(r) * side, sc.y + math.sin(r) * side, sc.z, (h + 90.0) % 360.0)
    local cmd = setFree(p, at, p.state == 'alive')
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc' }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STRETCHER: LOAD / UNLOAD
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:transport:str:load', function(src, net, vehNet)
    if not rate(src, 'load', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local rec = T.stretchers[tonumber(net) or -1]
    if not rec then return fail('no_stretcher') end
    if rec.veh then return fail('loaded') end
    if rec.pusher and rec.pusher ~= src then return fail('pushed') end
    vehNet = tonumber(vehNet)
    local veh = entFromNet(vehNet)
    if veh == 0 or not vehicleConfig(veh) then return fail('no_vehicle') end
    if not nearVehicleRear(src, veh) then return fail('too_far') end
    if not nearStretcher(src, rec, 4.0) then return fail('too_far') end
    local v = vehRec(vehNet)
    if v.str and v.str ~= rec.net and T.stretchers[v.str] then return fail('vehicle_full') end

    -- a cot from another ambulance now belongs to this one
    if rec.home and rec.home ~= vehNet then
        local old = T.vehicles[rec.home]
        if old and old.str == rec.net then
            old.str, old.inside = nil, false
            vehBag(rec.home)
        end
    end
    rec.home = vehNet
    rec.veh = vehNet
    rec.pusher = nil
    rec.touched = os.time()
    if cfg('Stretcher').load and cfg('Stretcher').load.autoLower ~= false then rec.low = true end
    v.str, v.inside = rec.net, true
    strBag(rec)
    vehBag(vehNet)

    local p = rec.pid and P().Get(rec.pid) or nil
    local msg = L('ok_loaded_empty')
    if p then
        P().SetMeta(p, 'vehicle', vehNet)
        T.trips[p.pid] = { veh = vehNet, at = os.time() }
        msg = L('ok_loaded', patientName(p))
        NZA.Bus.Emit('transport:loaded', src, p, vehNet, rec.net)
    end
    return true, { msg = msg, low = rec.low, patient = p and key(p) or nil }
end)

lib.callback.register('nza:transport:str:unload', function(src, vehNet)
    if not rate(src, 'unload', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    if busy(src) then return fail('busy') end
    vehNet = tonumber(vehNet)
    local veh = entFromNet(vehNet)
    if veh == 0 or not vehicleConfig(veh) then return fail('no_vehicle') end
    if not nearVehicleRear(src, veh) then return fail('too_far') end
    local v = T.vehicles[vehNet]
    local rec = v and v.inside and v.str and T.stretchers[v.str] or nil
    if not rec then return fail('not_loaded') end
    local bay = T.bays and T.bays[vehNet]
    if bay and bay.pid then return fail('in_bay') end
    rec.veh = nil
    rec.pusher = src
    rec.touched = os.time()
    if cfg('Stretcher').load and cfg('Stretcher').load.autoLower ~= false then rec.low = false end
    v.inside = false
    strBag(rec)
    vehBag(vehNet)
    local p = rec.pid and P().Get(rec.pid) or nil
    if p then releaseSeat(p) end
    NZA.Bus.Emit('transport:unloaded', src, p, vehNet)
    return true, { net = rec.net, low = rec.low, patient = p and key(p) or nil, npc = p and p.kind == 'npc' or false, msg = L('ok_unloaded') }
end)

-- ════════════════════════════════════════════════════════════════════════
-- BEDS & TABLES
-- ════════════════════════════════════════════════════════════════════════

local function billTrip(src, p)
    local b = cfg('Billing')
    local trip = T.trips[p.pid]
    T.trips[p.pid] = nil
    if not b.enabled or not trip or p.kind ~= 'player' or not p.src then return end
    local amount = tonumber(b.transport) or 0
    if amount <= 0 or not NZA.Billing or type(NZA.Billing.Charge) ~= 'function' then return end
    local ok = pcall(NZA.Billing.Charge, p.src, amount, b.reason or 'Ambulance transport', { kind = 'transport', pid = p.pid, medic = src })
    if ok then NZA.Core.Notify(p.src, L('billed', amount), 'info', L('title')) end
end

lib.callback.register('nza:transport:bed:place', function(src, pointId, net)
    local bc = cfg('Beds')
    if bc.enabled == false then return fail('disabled') end
    if not rate(src, 'bed', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local pt = findPoint(pointId)
    local tc = bedTypeConfig(pt)
    if not pt or not tc then return fail('no_point') end
    local pc = toV4(pt.coords)
    local me = srcCoords(src)
    if not pc or not me then return fail('no_point') end
    local range = (bc.range or 3.0) + 1.5
    if dist(me, pc) > range + 1.0 then return fail('too_far') end

    local p, rec = nil, nil
    if net then
        rec = T.stretchers[tonumber(net) or -1]
        if not rec or not rec.pid then return fail('no_patient') end
        if rec.veh then return fail('loaded') end
        if rec.pusher and rec.pusher ~= src then return fail('pushed') end
        if not nearStretcher(src, rec, 4.0) then return fail('too_far') end
        local ent = entFromNet(rec.net)
        if ent == 0 or dist(GetEntityCoords(ent), pc) > range + 1.5 then return fail('too_far') end
        p = P().Get(rec.pid)
    else
        local pid = T.carries[src]
        p = pid and P().Get(pid) or nil
    end
    if not p then return fail('no_patient') end
    local occ = T.beds[pt.id]
    if occ and occ ~= p.pid and P().Get(occ) then return fail('occupied') end
    local hocc = hospitalOccupant(pt.id)
    if hocc and hocc ~= p.pid then return fail('occupied') end
    -- someone (a player who lay down by themselves) is already lying there
    for _, other in pairs(P().All()) do
        local ob = other.meta and other.meta.bed
        if other.pid ~= p.pid and type(ob) == 'table' and tostring(ob.point) == tostring(pt.id) then return fail('occupied') end
    end

    releaseAll(p, true)
    T.beds[pt.id] = p.pid
    P().SetMeta(p, 'bed', { point = pt.id, type = pt.type, hospital = pt.hospital })
    if NZA.Hospitals and type(NZA.Hospitals.OccupyBed) == 'function' then
        pcall(NZA.Hospitals.OccupyBed, pt.id, p.pid)
    end
    if tc.heal then P().SetMeta(p, 'inBed', true) end
    local cmd = { m = 'bed', b = pt.id, bt = pt.type, at = pack(pc) }
    patientBag(p, cmd)
    billTrip(src, p)
    NZA.Bus.Emit('transport:bed', src, p, pt)
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', msg = L('ok_on_bed', patientName(p), pointLabel(pt)) }
end)

local function besideBed(p)
    local b = p.meta.bed
    local pt = b and findPoint(b.point)
    local pc = pt and toV4(pt.coords)
    if not pc then
        local c = NZA.Core.PatientCoords(p)
        return c and vector4(c.x, c.y, c.z, 0.0) or vector4(0.0, 0.0, 0.0, 0.0), pt
    end
    local r = math.rad(pc.w)
    local side = cfg('Beds').leaveSide or 1.0
    return vector4(pc.x + math.cos(r) * side, pc.y + math.sin(r) * side, pc.z, (pc.w - 90.0) % 360.0), pt
end

lib.callback.register('nza:transport:bed:leave', function(src, target)
    if not rate(src, 'bedleave', 4, 2000) then return fail('rate') end
    if not can(src, cfg().perm) then return fail('no_perm') end
    if not medicAlive(src) then return fail('down') end
    local p = resolve(target)
    if not p then return fail('no_patient') end
    if not p.meta.bed then return fail('not_lying') end
    if NZA.Core.DistanceTo(src, p) > 4.5 then return fail('too_far') end
    local okStand, why = P().CanStand(p)
    if not okStand then return fail(standErr[why] or 'cant_stand') end
    local at, pt = besideBed(p)
    releaseBed(p)
    standUp(p, 'helped_off_table')
    local cmd = setFree(p, at, true)
    return true, { cmd = cmd, target = key(p), npc = p.kind == 'npc', msg = L('ok_off_bed', patientName(p), pointLabel(pt)) }
end)

lib.callback.register('nza:transport:bed:self', function(src)
    local sl = cfg('Beds').selfLeave or {}
    if sl.enabled == false then return fail('disabled') end
    if not rate(src, 'bedself', 3, 3000) then return fail('rate') end
    local p = P().GetBySource(src)
    if not p or not p.meta.bed then return fail('not_lying') end
    if p.state ~= 'alive' then return fail('cant_stand') end
    local at = besideBed(p)
    releaseBed(p)
    setFree(p, at, true)
    return true, {}
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

local function endCarry(src, reason)
    local pid = T.carries[src]
    T.carries[src] = nil
    if src then TriggerClientEvent('nza:transport:carryEnd', src) end
    local p = pid and P().Get(pid)
    if not p then return end
    if p.meta.carried ~= nil then P().SetMeta(p, 'carried', nil) end
    local c = NZA.Core.PatientCoords(p)
    if c then setFree(p, vector4(c.x, c.y, c.z - 0.9, 0.0), p.state == 'alive' and reason == 'revived') end
    NZA.Bus.Emit('transport:carry', src, p, false)
end
T.EndCarry = endCarry

local function forgetSource(src)
    pending[src] = nil
    if T.carries[src] then endCarry(src, 'left') end
    for _, rec in pairs(T.stretchers) do
        if rec.pusher == src then
            rec.pusher = nil
            rec.touched = os.time()
            strBag(rec)
        end
    end
end

local function forgetPatient(pid)
    for src, cp in pairs(T.carries) do
        if cp == pid then
            T.carries[src] = nil
            TriggerClientEvent('nza:transport:carryEnd', src)
        end
    end
    for _, rec in pairs(T.stretchers) do
        if rec.pid == pid then
            rec.pid = nil
            strBag(rec)
        end
    end
    for point, bp in pairs(T.beds) do
        if bp == pid then
            T.beds[point] = nil
            if hospitalOccupant(point) == pid and type(NZA.Hospitals.ReleaseBed) == 'function' then
                pcall(NZA.Hospitals.ReleaseBed, point)
            end
        end
    end
    T.trips[pid] = nil
end
T.ForgetPatient = forgetPatient

AddEventHandler('playerDropped', function()
    local src = source
    forgetSource(src)
end)

-- the client is about to respawn at a hospital (only a dead patient may release themselves)
RegisterNetEvent('nza:transport:selfRelease', function()
    local src = source
    if NZA.Core.IsLocalSource(src) or not rate(src, 'selfrelease', 2, 5000) then return end
    local p = P().GetBySource(src)
    if not p or p.state ~= 'dead' then return end
    T.Release(p)
end)

NZA.Bus.On('wounded:respawned', function(_, p)
    if p and p.meta and (p.meta.carried or p.meta.stretcher or p.meta.bed or p.meta.bay or p.meta.vehicle) then
        T.Release(p)
    end
end)

NZA.Bus.On('player:unloaded', function(src)
    forgetSource(src)
    for pid, p in pairs(P().All()) do
        if p.kind == 'player' and p.src == src then forgetPatient(pid) end
    end
end)

NZA.Bus.On('patient:removed', function(pid)
    forgetPatient(pid)
end)

NZA.Bus.On('state:changed', function(p, old, new)
    if not p then return end
    -- a carrier that goes down drops the patient
    if p.kind == 'player' and p.src and new ~= 'alive' then
        if T.carries[p.src] then endCarry(p.src, 'down') end
        local rec = isPusher(p.src)
        if rec then
            rec.pusher = nil
            strBag(rec)
            TriggerClientEvent('nza:transport:pushEnd', p.src, rec.net)
        end
    end
    -- a carried patient who wakes up gets put down on their feet
    if new == 'alive' and p.meta and p.meta.carried then
        endCarry(p.meta.carried, 'revived')
    end
end)

-- watchdog: carriers, pushers, lost / abandoned stretchers
CreateThread(function()
    while true do
        Wait(1500)
        local now = os.time()
        for src, pid in pairs(T.carries) do
            local p = P().Get(pid)
            local ped = GetPlayerPed(src)
            if not p or not ped or ped == 0 then
                endCarry(src, 'gone')
            elseif NZA.Core.DistanceTo(src, p) > 8.0 then
                endCarry(src, 'far')
            end
        end
        local abandon = tonumber(cfg('Stretcher').abandon) or 0
        for net, rec in pairs(T.stretchers) do
            local ent = entFromNet(net)
            if ent == 0 then
                deleteStretcher(rec)
            else
                if rec.pusher then
                    local ped = GetPlayerPed(rec.pusher)
                    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(ent)) > 9.0 then
                        rec.pusher = nil
                        strBag(rec)
                    else
                        rec.touched = now
                    end
                end
                if rec.veh and entFromNet(rec.veh) == 0 then
                    rec.veh = nil
                    deleteStretcher(rec)
                elseif rec.pid and not P().Get(rec.pid) then
                    rec.pid = nil
                    strBag(rec)
                elseif abandon > 0 and not rec.pid and not rec.pusher and not rec.veh and now - (rec.touched or now) > abandon then
                    deleteStretcher(rec)
                end
            end
        end
        for vehNet, v in pairs(T.vehicles) do
            if entFromNet(vehNet) == 0 then
                T.vehicles[vehNet] = nil
            elseif v.str and not T.stretchers[v.str] then
                v.str, v.inside = nil, false
                vehBag(vehNet)
            end
        end
        for point, pid in pairs(T.beds) do
            if not P().Get(pid) then T.beds[point] = nil end
        end
        for pid, trip in pairs(T.trips) do
            if now - trip.at > 3600 then T.trips[pid] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, rec in pairs(T.stretchers) do
        local ent = entFromNet(rec.net)
        if ent ~= 0 then DeleteEntity(ent) end
    end
end)

exports('GetTransportState', function(src)
    local p = P().GetBySource(tonumber(src) or -1)
    return p and T.Info(p) or nil
end)
