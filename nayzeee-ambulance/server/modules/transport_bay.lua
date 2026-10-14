--[[
    NAYZEEE AMBULANCE - Transport (server): ambulance treatment bay + supplies shelves

    Every ambulance with an open bay gets a slot on a hidden grid (Config.Transport.Bay.base +
    slot offset). Clients spawn the interior model locally at that spot; the server only keeps
    who is inside and moves people in and out.

      T.bays[vehNet] = { veh = net, slot, medics = { [src] = { idx, from = vector4 } },
                         pid = patient pid | nil, str = stretcher net, last = vector4, speed }
      Medics and the patient get patient.meta.bay = vehicle net (core view rules + procedures).
      The patient on the loaded stretcher goes in with the first medic and comes back out
      onto that stretcher when the last medic leaves.

    API: NZA.Transport.BayOrigin(slot) → vector3   NZA.Transport.InBay(src) → vehNet, bay
         NZA.Transport.LeaveBay(p)   (take a patient out of any bay, e.g. T.Free)
         NZA.Transport.BayExitAt(vehNet) → vector4 behind that ambulance's back doors
         NZA.Transport.BayOf(vehNet) → bay record

    Callbacks (lib.callback)
      nza:transport:bay:enter (vehNet)      → true, { slot, idx, veh, plate, model, str, npc?, patient?, crew }
                                              (at the back doors of a standing ambulance, or from one of its
                                              passenger seats at any speed - not the driver)
      nza:transport:bay:exit ()             → true, { at = {x,y,z,w}, veh, returnNpc = { net, s }? }
      nza:transport:bay:supplies ()         → true, { items, categories, resetIn }
      nza:transport:bay:take (key, count)   → true, { list, msg }
    S→C: nza:transport:bay:crew ({ crew[], patient }), nza:transport:bay:tick ({ speed, plate }),
         nza:transport:bay:kick ({ at })    (vehicle deleted / medic went down)
    Bus (server) emitted: transport:bay (src, vehNet, inside)
    Bus listened: staff:changed (a new shift resets the supplies limits)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local T = NZA.Transport
local U = NZA.Util

T.bays  = T.bays or {}     -- [vehicle net] = bay
T.slots = T.slots or {}    -- [slot] = vehicle net

local shifts = {}          -- [identifier] = { started, taken = { [itemKey] = n } }
local returning = {}       -- [pid] = { at = vector4, until = os.time() } NPCs on their way back out

local function cfg()
    return (Config.Transport or {}).Bay or {}
end

local function L(key, ...)
    return NZA.L('transport.' .. key, ...)
end

local function fail(err)
    return false, { err = err, msg = L('err_' .. err) }
end

local function P() return NZA.Patients end

local function ent(net)
    net = tonumber(net)
    if not net then return 0 end
    local e = NetworkGetEntityFromNetworkId(net)
    if e and e ~= 0 and DoesEntityExist(e) then return e end
    return 0
end

local function pack(v)
    if not v then return nil end
    return { x = U.round(v.x, 3), y = U.round(v.y, 3), z = U.round(v.z, 3), w = U.round(v.w or 0.0, 1) }
end

-- ════════════════════════════════════════════════════════════════════════
-- SLOTS
-- ════════════════════════════════════════════════════════════════════════

function T.BayOrigin(slot)
    local c = cfg()
    local base = c.base or vector3(480.0, 5580.0, 360.0)
    local cols = math.max(1, math.floor(tonumber(c.columns) or 6))
    local sp = tonumber(c.spacing) or 32.0
    local i = (tonumber(slot) or 1) - 1
    local col, row = i % cols, math.floor(i / cols)
    return vector3(base.x + col * sp, base.y + row * sp, base.z)
end

local function freeSlot()
    local max = math.max(1, math.floor(tonumber(cfg().maxSlots) or 36))
    for i = 1, max do
        if not T.slots[i] then return i end
    end
    return nil
end

function T.InBay(src)
    for vehNet, bay in pairs(T.bays) do
        if bay.medics[src] then return vehNet, bay end
    end
    return nil, nil
end

function T.BayOf(vehNet)
    return T.bays[vehNet]
end

local function medicCount(bay)
    local n = 0
    for _ in pairs(bay.medics) do n = n + 1 end
    return n
end

local function crewList(bay)
    local out = {}
    for src, m in pairs(bay.medics) do
        local rec = NZA.Staff.Get(src) or {}
        out[#out + 1] = { sid = src, idx = m.idx, name = NZA.Core.Name(src), grade = rec.gradeLabel or rec.jobLabel }
    end
    table.sort(out, function(a, b) return a.idx < b.idx end)
    return out
end

local function broadcastCrew(bay)
    local crew = crewList(bay)
    local p = bay.pid and P().Get(bay.pid) or nil
    local payload = { crew = crew, patient = p and T.Key(p) or nil }
    for src in pairs(bay.medics) do
        TriggerClientEvent('nza:transport:bay:crew', src, payload)
    end
end

local function plateOf(veh)
    if veh == 0 then return nil end
    local ok, plate = pcall(GetVehicleNumberPlateText, veh)
    if ok and type(plate) == 'string' then return (plate:gsub('^%s+', ''):gsub('%s+$', '')) end
    return nil
end

local function vehicleSpeed(veh)
    local v = GetEntityVelocity(veh)
    return #(vector3(v.x, v.y, v.z))
end

local function exitAt(bay, src)
    local c = cfg()
    local veh = ent(bay.veh)
    if veh ~= 0 then
        local rear, h = T.VehicleRear(veh, c.exitBehind or 1.2)
        return vector4(rear.x, rear.y, rear.z, (h + 180.0) % 360.0)
    end
    if bay.last then
        local r = math.rad(bay.last.w)
        local d = 4.8
        return vector4(bay.last.x + math.sin(r) * d, bay.last.y - math.cos(r) * d, bay.last.z, (bay.last.w + 180.0) % 360.0)
    end
    local m = src and bay.medics[src]
    return m and m.from or vector4(0.0, 0.0, 72.0, 0.0)
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT IN / OUT
-- ════════════════════════════════════════════════════════════════════════

local function stretcherInside(vehNet)
    local v = T.vehicles and T.vehicles[vehNet]
    local rec = v and v.inside and v.str and T.stretchers[v.str] or nil
    if rec and rec.veh == vehNet then return rec end
    return nil
end

local function patientIn(bay)
    if bay.pid then return P().Get(bay.pid), stretcherInside(bay.veh) end
    local rec = stretcherInside(bay.veh)
    local p = rec and rec.pid and P().Get(rec.pid) or nil
    if not p or p.meta.bay then return nil, rec end
    bay.pid = p.pid
    bay.str = rec.net
    P().SetMeta(p, 'bay', bay.veh)
    T.PatientBag(p, { m = 'bay', v = bay.veh, slot = bay.slot, s = rec.net })
    return p, rec, true
end

-- patient back out onto the stretcher in the ambulance (or on the ground if that is gone)
local function returnPatient(bay, at)
    local p = bay.pid and P().Get(bay.pid) or nil
    bay.pid = nil
    if not p then return nil end
    P().SetMeta(p, 'bay', nil)
    local rec = stretcherInside(bay.veh)
    if rec and rec.pid == p.pid and ent(bay.veh) ~= 0 then
        T.PatientBag(p, { m = 'str', s = rec.net, from = 'bay', at = pack(at) })
        if p.kind == 'npc' then
            returning[p.pid] = { at = at, untilAt = os.time() + 15 }
            return { net = p.net, s = rec.net, at = pack(at) }
        end
        return nil
    end
    -- the ambulance or the cot is gone: lay the patient down where the ambulance was
    if rec and rec.pid == p.pid then
        rec.pid = nil
        T.StrBag(rec)
    end
    P().SetMeta(p, 'stretcher', nil)
    P().SetMeta(p, 'vehicle', nil)
    T.PatientBag(p, { m = 'free', at = pack(at), from = 'bay' })
    if p.kind == 'npc' then
        local ped = NZA.Core.PatientPed(p)
        if ped ~= 0 then SetEntityCoords(ped, at.x, at.y, at.z, false, false, false, false) end
        return { net = p.net, at = pack(at), free = true }
    end
    return nil
end

function T.BayExitAt(vehNet)
    local bay = T.bays[vehNet]
    if not bay then
        local veh = ent(vehNet)
        if veh == 0 then return nil end
        local rear, h = T.VehicleRear(veh, cfg().exitBehind or 1.2)
        return vector4(rear.x, rear.y, rear.z, (h + 180.0) % 360.0)
    end
    return exitAt(bay)
end

function T.LeaveBay(p)
    if not p or not p.meta or p.meta.bay == nil then return end
    local bay = T.bays[p.meta.bay]
    if bay and bay.pid == p.pid then bay.pid = nil end
    P().SetMeta(p, 'bay', nil)
end

local function closeBay(bay)
    if T.slots[bay.slot] == bay.veh then T.slots[bay.slot] = nil end
    T.bays[bay.veh] = nil
    if T.VehBag then T.VehBag(bay.veh) end
end

local function removeMedic(bay, src)
    local m = bay.medics[src]
    if not m then return nil end
    bay.medics[src] = nil
    local me = P().GetBySource(src)
    if me and me.meta.bay ~= nil then P().SetMeta(me, 'bay', nil) end
    NZA.Bus.Emit('transport:bay', src, bay.veh, false)
    return m
end

-- ════════════════════════════════════════════════════════════════════════
-- ENTER / EXIT
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:transport:bay:enter', function(src, vehNet)
    local c = cfg()
    if c.enabled == false then return fail('disabled') end
    if not T.Rate(src, 'bay', 3, 3000) then return fail('rate') end
    if not T.Can(src, c.perm or (Config.Transport and Config.Transport.perm)) then return fail('no_perm') end
    if not T.MedicAlive(src) then return fail('down') end
    if T.InBay(src) then return fail('busy') end
    if T.carries[src] or T.Pushing(src) then return fail('busy') end
    vehNet = tonumber(vehNet)
    local veh = ent(vehNet)
    if veh == 0 or GetEntityType(veh) ~= 2 then return fail('no_vehicle') end
    local vc = T.VehicleConfig(veh)
    if not vc then return fail('no_vehicle') end
    if vc.bay == false then return fail('no_bay') end
    -- from a passenger seat of that ambulance you can climb into the back while it drives
    local myPed = GetPlayerPed(src)
    local seated = myPed ~= 0 and GetVehiclePedIsIn(myPed, false) == veh
    if seated then
        if GetPedInVehicleSeat(veh, -1) == myPed then return fail('driver') end
    else
        if not T.NearRear(src, veh, 2.5) then return fail('too_far') end
        if vehicleSpeed(veh) > (tonumber(c.maxEnterSpeed) or 1.5) then return fail('moving') end
    end

    local me = P().GetBySource(src) or P().LoadPlayer(src)
    if not me then return fail('failed') end

    local bay = T.bays[vehNet]
    if not bay then
        local slot = freeSlot()
        if not slot then return fail('bay_full') end
        bay = { veh = vehNet, slot = slot, medics = {}, pid = nil, str = nil, created = os.time() }
        T.bays[vehNet] = bay
        T.slots[slot] = vehNet
    end
    local used = {}
    for _, m in pairs(bay.medics) do used[m.idx] = true end
    local idx = 1
    while used[idx] do idx = idx + 1 end

    local ped = GetPlayerPed(src)
    local pc = GetEntityCoords(ped)
    bay.medics[src] = { idx = idx, from = vector4(pc.x, pc.y, pc.z, GetEntityHeading(ped)), at = os.time() }
    P().SetMeta(me, 'bay', vehNet)
    local vp = GetEntityCoords(veh)
    bay.last = vector4(vp.x, vp.y, vp.z, GetEntityHeading(veh))

    local p, rec, moved = patientIn(bay)
    T.VehBag(vehNet)
    broadcastCrew(bay)
    NZA.Bus.Emit('transport:bay', src, vehNet, true)
    return true, {
        slot = bay.slot, idx = idx, veh = vehNet, plate = plateOf(veh), model = GetEntityModel(veh),
        str = rec and rec.net or nil,
        patient = p and T.Key(p) or nil,
        npc = (p and p.kind == 'npc' and moved) and p.net or nil,
        crew = crewList(bay),
    }
end)

local function leave(src, bay, kicked)
    local m = removeMedic(bay, src)
    local at = exitAt(bay, src)
    local back = nil
    if medicCount(bay) == 0 then
        back = returnPatient(bay, at)
        closeBay(bay)
    else
        broadcastCrew(bay)
        T.VehBag(bay.veh)
    end
    return at, back, m
end

lib.callback.register('nza:transport:bay:exit', function(src)
    local vehNet, bay = T.InBay(src)
    if not bay then
        -- not in a bay any more (vehicle deleted while the client was busy): send them out anyway
        local me = P().GetBySource(src)
        if me and me.meta.bay ~= nil then P().SetMeta(me, 'bay', nil) end
        return fail('not_in_bay')
    end
    local at, back = leave(src, bay, false)
    return true, { at = pack(at), veh = vehNet, returnNpc = back }
end)

-- ════════════════════════════════════════════════════════════════════════
-- SUPPLIES (per medic, per shift)
-- ════════════════════════════════════════════════════════════════════════

local function shiftOf(src)
    local id = NZA.Core.Identifier(src) or ('src:' .. tostring(src))
    local sc = cfg().supplies or {}
    local len = tonumber(sc.shiftLength) or 14400
    local s = shifts[id]
    if not s or (len > 0 and os.time() - s.started > len) then
        s = { started = os.time(), taken = {} }
        shifts[id] = s
    end
    return s, len
end

local function itemLabel(key, name)
    local def = Config.ItemDefs and Config.ItemDefs[key]
    if def and def.label then return def.label end
    local lbl = NZA.Core.B('Inv.Label', name)
    return (type(lbl) == 'string' and lbl ~= '') and lbl or name
end

local function supplyList(src)
    local sc = cfg().supplies or {}
    local s, len = shiftOf(src)
    local items = {}
    for _, e in ipairs(sc.items or {}) do
        local name = Config.Items and Config.Items[e.item]
        if name then
            local max = math.max(0, math.floor(tonumber(e.max) or 0))
            local taken = s.taken[e.item] or 0
            items[#items + 1] = {
                key = e.item, name = name, label = itemLabel(e.item, name), category = e.category,
                max = max, taken = taken, left = math.max(0, max - taken),
                have = NZA.Core.B('Inv.Count', src, name) or 0,
            }
        end
    end
    local cats = {}
    for _, cat in ipairs(sc.categories or {}) do
        cats[#cats + 1] = { id = cat.id, icon = cat.icon, label = L('cat_' .. cat.id) }
    end
    return {
        items = items, categories = cats,
        resetIn = len > 0 and math.max(0, s.started + len - os.time()) or nil,
        maxPerTake = math.max(1, math.floor(tonumber(sc.maxPerTake) or 10)),
    }
end

lib.callback.register('nza:transport:bay:supplies', function(src)
    local sc = cfg().supplies or {}
    if sc.enabled == false then return fail('disabled') end
    if not T.Rate(src, 'supplies', 4, 2000) then return fail('rate') end
    if not T.InBay(src) then return fail('not_in_bay') end
    return true, supplyList(src)
end)

lib.callback.register('nza:transport:bay:take', function(src, itemKey, count)
    local sc = cfg().supplies or {}
    if sc.enabled == false then return fail('disabled') end
    if not T.Rate(src, 'take_supply', 6, 2000) then return fail('rate') end
    if not T.InBay(src) then return fail('not_in_bay') end
    if not T.MedicAlive(src) then return fail('down') end
    local entry
    for _, e in ipairs(sc.items or {}) do
        if e.item == itemKey then entry = e break end
    end
    local name = entry and Config.Items and Config.Items[entry.item]
    if not name then return fail('failed') end
    local s = shiftOf(src)
    local max = math.max(0, math.floor(tonumber(entry.max) or 0))
    local left = max - (s.taken[entry.item] or 0)
    if left <= 0 then return fail('limit') end
    local n = math.floor(tonumber(count) or 1)
    n = U.clamp(n, 1, math.min(left, math.max(1, math.floor(tonumber(sc.maxPerTake) or 10))))
    if NZA.Core.Has('Inv.CanCarry') and NZA.Core.B('Inv.CanCarry', src, name, n) == false then
        return fail('no_space')
    end
    if not NZA.Core.B('Inv.AddItem', src, name, n) then return fail('no_space') end
    s.taken[entry.item] = (s.taken[entry.item] or 0) + n
    return true, { list = supplyList(src), msg = L('ok_taken', n, itemLabel(entry.item, name)) }
end)

NZA.Bus.On('staff:changed', function(src, rec, old)
    if type(rec) ~= 'table' then return end
    if rec.onDuty and not (type(old) == 'table' and old.onDuty) then
        local id = NZA.Core.Identifier(src)
        if id then shifts[id] = nil end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- WATCHDOG
-- ════════════════════════════════════════════════════════════════════════

local function kick(bay, src)
    local at = leave(src, bay, true)
    TriggerClientEvent('nza:transport:bay:kick', src, { at = pack(at) })
end

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for vehNet, bay in pairs(T.bays) do
            local veh = ent(vehNet)
            if veh == 0 then
                -- the ambulance was deleted: everyone out where it last was
                for src in pairs(bay.medics) do
                    if T.bays[vehNet] then kick(bay, src) end
                end
                if T.bays[vehNet] then
                    returnPatient(bay, exitAt(bay))
                    closeBay(bay)
                end
            else
                local vp = GetEntityCoords(veh)
                bay.last = vector4(vp.x, vp.y, vp.z, GetEntityHeading(veh))
                local kmh = math.floor(vehicleSpeed(veh) * 3.6 + 0.5)
                local changed = bay.speed == nil or math.abs(kmh - bay.speed) >= 2
                bay.speed = kmh
                for src in pairs(bay.medics) do
                    local ped = GetPlayerPed(src)
                    if not ped or ped == 0 then
                        if T.bays[vehNet] then leave(src, bay, true) end
                    elseif not T.MedicAlive(src) then
                        if T.bays[vehNet] then kick(bay, src) end
                    elseif changed then
                        TriggerClientEvent('nza:transport:bay:tick', src, { speed = kmh, plate = plateOf(veh) })
                    end
                end
                if T.bays[vehNet] and bay.pid and not P().Get(bay.pid) then bay.pid = nil end
                if T.bays[vehNet] and medicCount(bay) == 0 then
                    returnPatient(bay, exitAt(bay))
                    closeBay(bay)
                end
            end
        end
        -- NPCs coming out of a bay: make sure they reach the ambulance even if no client moved them
        for pid, r in pairs(returning) do
            local p = P().Get(pid)
            if not p or now > r.untilAt then
                returning[pid] = nil
            elseif now > r.untilAt - 12 then
                local ped = NZA.Core.PatientPed(p)
                if ped ~= 0 and #(GetEntityCoords(ped) - vector3(r.at.x, r.at.y, r.at.z)) > 25.0 then
                    SetEntityCoords(ped, r.at.x, r.at.y, r.at.z, false, false, false, false)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local _, bay = T.InBay(src)
    if bay then leave(src, bay, true) end
end)

NZA.Bus.On('patient:removed', function(pid)
    for _, bay in pairs(T.bays) do
        if bay.pid == pid then bay.pid = nil end
    end
    returning[pid] = nil
end)
