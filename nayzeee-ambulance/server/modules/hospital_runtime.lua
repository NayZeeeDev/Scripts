--[[
    NAYZEEE AMBULANCE - Hospital positions at runtime (server)

    What happens when someone uses a placed position. Every handler checks the player's
    department (NZA.Hospitals.Internal.Membership), duty, grade, the position's type and
    department and the distance from the server-side ped (ARCHITECTURE §13).

    Callbacks (lib.callback)
      nza:hospital:duty           ({ point?, on? })           → { ok, onDuty }   duty point or radial
      nza:hospital:locker         (pointId)                   → { ok, outfits, dept }
      nza:hospital:stash          (pointId)                   → { ok, mode = 'ox'|'qb'|'qbold'|'own', id, label, slots, weight, items?, inv? }
      nza:hospital:stash:move     ({ point, dir = 'in'|'out', slot?, index?, count })  built-in storage only
      nza:hospital:storage        (pointId)                   → { ok, items = [{ key, name, label, image, limit, taken }] }
      nza:hospital:storage:take   ({ point, key, count })     → { ok, items }
      nza:hospital:garage         (pointId)                   → { ok, vehicles, out, max }
      nza:hospital:garage:spawn   ({ point, id })             → { ok, net, plate, livery, extras, colour, warp, fuel }
      nza:hospital:garage:store   ({ point, net })            → { ok }
      nza:hospital:bed            ({ point, on })             → { ok }          lie down / get up (self)
    Bus (server): hospital:duty (src, onDuty)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Hospitals = NZA.Hospitals or {}
NZA.Hospitals.Internal = NZA.Hospitals.Internal or {}
local H = NZA.Hospitals
local I = H.Internal
local Core = NZA.Core

local function cfg(key, default)
    local c = Config.Hospital
    if c and c[key] ~= nil then return c[key] end
    return default
end

local function fail(err, ...)
    return { ok = false, err = err, msg = NZA.L('hospital.err_' .. err, ...) }
end

local function rate(src)
    local n = (cfg('rates', {}).runtime) or 6
    return Core.Rate('nza:hospital:rt', src, n, 4000)
end

-- the player's department + grade (raw membership, duty not applied)
local function member(src)
    local d, level = I.Membership(src, nil)
    if not d then return nil end
    return d, I.GradeFor(d, level)
end

-- point of `kind` (string or set) that belongs to src's department and is within reach
local function usePoint(src, pointId, kind, reach)
    local pt = H.Point(pointId)
    if not pt then return nil, 'no_point' end
    if type(kind) == 'table' then
        if not kind[pt.type] then return nil, 'no_point' end
    elseif pt.type ~= kind then
        return nil, 'no_point'
    end
    local me = Core.SrcCoords(src)
    if not me or #(me - I.PointPos(pt)) > (reach or 4.0) then return nil, 'too_far' end
    return pt
end

local function onDuty(src)
    local rec = NZA.Staff.Get(src)
    return rec and rec.onDuty == true
end

local function hasGradePerm(g, perm)
    if not perm then return true end
    for _, p in ipairs(g and g.perms or {}) do if p == perm then return true end end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- DUTY
-- ════════════════════════════════════════════════════════════════════════

local shift = {}   -- [identifier] = { start = os.time(), taken = { [key] = n } }

local function resetShift(src)
    local ident = Core.Identifier(src)
    if ident then shift[ident] = nil end
end

lib.callback.register('nza:hospital:duty', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local d = member(src)
    if not d then return fail('not_member') end

    local dc = cfg('duty', {})
    if payload.point ~= nil then
        local pt, err = usePoint(src, payload.point, 'duty', 4.0)
        if not pt then return fail(err) end
        if pt.hospital ~= d.id then return fail('other_point') end
    else
        -- no point: the radial menu (ours or the dispatch one) - optionally only near a duty point
        if dc.requirePoint then
            local me = Core.SrcCoords(src)
            local near = false
            for _, pt in ipairs(H.Points('duty', d.id)) do
                if me and #(me - I.PointPos(pt)) <= (dc.range or 30.0) then near = true; break end
            end
            if not near then return fail('need_duty_point') end
        end
    end

    local rec = NZA.Staff.Get(src) or {}
    local on = payload.on
    if type(on) ~= 'boolean' then on = not rec.onDuty end

    if rec.frameworkMedic then
        if Core.B('SetDuty', src, on) == true then
            I.SetOwnDuty(src, nil)
        else
            I.SetOwnDuty(src, on)
        end
    else
        I.SetOwnDuty(src, on)
    end
    local now = NZA.Staff.Refresh(src, true) or {}
    -- the framework may report the change a moment later; trust our intent meanwhile
    if (now.onDuty == true) ~= on then
        I.SetOwnDuty(src, on)
        now = NZA.Staff.Refresh(src, true) or {}
    end
    if not on and (cfg('storage', {}).shiftReset) ~= false then resetShift(src) end
    NZA.Bus.Emit('hospital:duty', src, on)
    Core.Notify(src, NZA.L(on and 'hospital.duty_on' or 'hospital.duty_off', d.label), on and 'success' or 'info', d.label)
    return { ok = true, onDuty = now.onDuty == true }
end)

-- ════════════════════════════════════════════════════════════════════════
-- LOCKER
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:locker', function(src, pointId)
    if not rate(src) then return fail('rate') end
    local d, g = member(src)
    if not d then return fail('not_member') end
    local pt, err = usePoint(src, pointId, 'locker', 4.0)
    if not pt then return fail(err) end
    if pt.hospital ~= d.id then return fail('other_point') end
    local level = g and g.level or 0
    local list = {}
    for _, o in ipairs(d.outfits or {}) do
        local allowed = #(o.grades or {}) == 0
        for _, gl in ipairs(o.grades or {}) do if gl == level then allowed = true end end
        if allowed then
            list[#list + 1] = { id = o.id, name = o.name, grades = o.grades, male = o.male, female = o.female }
        end
    end
    local grades = {}
    for _, gr in ipairs(d.grades) do grades[#grades + 1] = gr.label end
    return { ok = true, outfits = list, dept = d.label, grade = g and g.label, grades = grades }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STASH
-- ════════════════════════════════════════════════════════════════════════

local stashes = {}        -- [id] = { stacks = { { name, count, metadata } }, loaded = true }
local oxRegistered = {}

local function stashCfg(pt)
    local sc = cfg('stash', {})
    local data = pt.data or {}
    return {
        slots = I.int(data.slots, 1, 500, sc.slots or 80),
        weight = I.int(data.weight, 1000, 10000000, sc.weight or 250000),
        personal = data.personal == true,
        minGrade = I.int(data.minGrade, 0, 50, 0),
        label = pt.label or NZA.L('hospital.type_stash'),
    }
end

local function stashId(pt, ident, personal)
    if personal then return ('nza_stash_%d_%s'):format(pt.id, ((ident or ''):gsub('[^%w]', ''))) end
    return ('nza_stash_%d'):format(pt.id)
end

local function loadStash(id)
    local s = stashes[id]
    if s then return s end
    local row = MySQL.single.await('SELECT `items` FROM `nza_hospital_stash` WHERE `id` = ?', { id })
    s = { stacks = (row and I.decode(row.items)) or {} }
    if type(s.stacks) ~= 'table' then s.stacks = {} end
    stashes[id] = s
    return s
end

local function saveStash(id)
    local s = stashes[id]
    if not s then return end
    MySQL.query('INSERT INTO `nza_hospital_stash` (`id`, `items`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `items` = VALUES(`items`)',
        { id, json.encode(s.stacks) })
end

local function itemView(name, count, metadata, extra)
    local out = {
        name = name, count = count,
        label = Core.B('Inv.Label', name) or name,
        image = Core.B('Inv.Image', name),
        meta = (type(metadata) == 'table' and next(metadata)) and metadata or nil,
    }
    if extra then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function stashState(src, id)
    local s = loadStash(id)
    local items = {}
    for i, st in ipairs(s.stacks) do items[#items + 1] = itemView(st.name, st.count, st.metadata, { index = i }) end
    local inv = {}
    for _, it in ipairs(Core.B('Inv.GetItems', src) or {}) do
        inv[#inv + 1] = itemView(it.name, it.count, it.metadata, { slot = it.slot })
    end
    return items, inv
end

local function inventoryKind()
    local name = Core.B('Inv.Resource')
    if name == 'ox_inventory' and GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if name == 'qb-inventory' and GetResourceState('qb-inventory') == 'started' then
        local v = GetResourceMetadata('qb-inventory', 'version', 0) or '0'
        if (tonumber(v:match('^(%d+)')) or 0) >= 2 then return 'qb' end
        return 'qbold'
    end
    -- the classic 'inventory:server:OpenInventory' stash event (qb-inventory 1.x, lj, qs);
    -- ps-inventory renamed it, its stashes open through Bridge.Inv.OpenStash only
    if (name == 'lj-inventory' or name == 'qs-inventory') and GetResourceState(name) == 'started' then
        return 'qbold'
    end
    return 'own'
end

local function stashAccess(src, pointId)
    local d, g = member(src)
    if not d then return nil, 'not_member' end
    if not onDuty(src) then return nil, 'off_duty' end
    local pt, err = usePoint(src, pointId, 'stash', 4.0)
    if not pt then return nil, err end
    if pt.hospital ~= d.id then return nil, 'other_point' end
    local sc = stashCfg(pt)
    if (g and g.level or 0) < sc.minGrade then return nil, 'grade' end
    return pt, sc, d
end

lib.callback.register('nza:hospital:stash', function(src, pointId)
    if not rate(src) then return fail('rate') end
    local pt, sc, d = stashAccess(src, pointId)
    if not pt then return fail(sc) end
    local ident = Core.Identifier(src)
    local id = stashId(pt, ident, sc.personal)
    local label = ('%s · %s'):format(d.label, sc.label)

    -- the bridge's stash opener (ox, qb 1.x/2.x, ps, lj, qs) wins; the paths below are fallbacks
    if Core.Has('Inv.OpenStash') then
        local okOpen = Core.B('Inv.OpenStash', src, id, { label = label, slots = sc.slots, weight = sc.weight, owner = sc.personal and ident or nil })
        if okOpen then return { ok = true, mode = 'bridge', id = id } end
    end

    local kind = inventoryKind()
    if kind == 'ox' then
        if not oxRegistered[id] then
            local okReg = pcall(function()
                exports.ox_inventory:RegisterStash(id, label, sc.slots, sc.weight, sc.personal and true or nil)
            end)
            if okReg then oxRegistered[id] = true end
        end
        if oxRegistered[id] then return { ok = true, mode = 'ox', id = id } end
    elseif kind == 'qb' then
        local okOpen = pcall(function()
            exports['qb-inventory']:OpenInventory(src, id, { maxweight = sc.weight, slots = sc.slots, label = label })
        end)
        if okOpen then return { ok = true, mode = 'qb', id = id } end
    elseif kind == 'qbold' then
        return { ok = true, mode = 'qbold', id = id, slots = sc.slots, weight = sc.weight, label = label }
    end

    if cfg('stash', {}).ownStorage == false then return fail('no_stash') end
    local items, inv = stashState(src, id)
    return { ok = true, mode = 'own', id = id, label = label, items = items, inv = inv, max = (cfg('stash', {}).maxStacks) or 150 }
end)

lib.callback.register('nza:hospital:stash:move', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local pt, sc = stashAccess(src, payload.point)
    if not pt then return fail(sc) end
    if cfg('stash', {}).ownStorage == false or inventoryKind() ~= 'own' then return fail('no_stash') end
    local id = stashId(pt, Core.Identifier(src), sc.personal)
    local s = loadStash(id)
    local count = I.int(payload.count, 1, 100000, 1)

    if payload.dir == 'in' then
        local slot = I.int(payload.slot, 0, 100000)
        local it = slot and Core.B('Inv.GetSlot', src, slot)
        if not it or not it.name or (tonumber(it.count) or 0) < 1 then return fail('no_item') end
        count = math.min(count, tonumber(it.count) or 0)
        local meta = (type(it.metadata) == 'table' and next(it.metadata)) and it.metadata or nil
        local target
        if not meta then
            for _, st in ipairs(s.stacks) do
                if st.name == it.name and not st.metadata then target = st; break end
            end
        end
        if not target and #s.stacks >= ((cfg('stash', {}).maxStacks) or 150) then return fail('stash_full') end
        if not Core.B('Inv.RemoveItem', src, it.name, count, meta, it.slot) then return fail('no_item') end
        if meta then
            -- metadata items (blood bags, films) stay single units
            for _ = 1, count do s.stacks[#s.stacks + 1] = { name = it.name, count = 1, metadata = meta } end
        elseif target then
            target.count = target.count + count
        else
            s.stacks[#s.stacks + 1] = { name = it.name, count = count }
        end
    elseif payload.dir == 'out' then
        local index = I.int(payload.index, 1, 100000)
        local st = index and s.stacks[index]
        if not st or (payload.name and payload.name ~= st.name) then return fail('no_item') end
        count = math.min(count, st.count)
        if Core.B('Inv.CanCarry', src, st.name, count) == false then return fail('cant_carry') end
        if not Core.B('Inv.AddItem', src, st.name, count, st.metadata) then return fail('cant_carry') end
        st.count = st.count - count
        if st.count <= 0 then table.remove(s.stacks, index) end
    else
        return fail('failed')
    end
    saveStash(id)
    local items, inv = stashState(src, id)
    return { ok = true, items = items, inv = inv }
end)

-- ════════════════════════════════════════════════════════════════════════
-- SUPPLY CABINET (per-shift limits)
-- ════════════════════════════════════════════════════════════════════════

local function shiftOf(src)
    local ident = Core.Identifier(src)
    if not ident then return nil end
    local s = shift[ident]
    local hours = tonumber((cfg('storage', {}).shiftHours)) or 4
    if not s or (hours > 0 and os.time() - s.start > hours * 3600) then
        s = { start = os.time(), taken = {} }
        shift[ident] = s
    end
    return s
end

local function storageList(src, g)
    local s = shiftOf(src) or { taken = {} }
    local out = {}
    for _, e in ipairs((cfg('storage', {}).items) or {}) do
        local name = Config.Items and Config.Items[e.key]
        if name and hasGradePerm(g, e.perm) then
            out[#out + 1] = itemView(name, nil, nil, { key = e.key, limit = e.limit or 1, taken = s.taken[e.key] or 0 })
        end
    end
    return out
end

local function storageAccess(src, pointId)
    local d, g = member(src)
    if not d then return nil, 'not_member' end
    if not onDuty(src) then return nil, 'off_duty' end
    local pt, err = usePoint(src, pointId, 'storage', 4.0)
    if not pt then return nil, err end
    if pt.hospital ~= d.id then return nil, 'other_point' end
    return pt, g
end

lib.callback.register('nza:hospital:storage', function(src, pointId)
    if not rate(src) then return fail('rate') end
    local pt, g = storageAccess(src, pointId)
    if not pt then return fail(g) end
    return { ok = true, items = storageList(src, g) }
end)

lib.callback.register('nza:hospital:storage:take', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local pt, g = storageAccess(src, payload.point)
    if not pt then return fail(g) end
    local entry
    for _, e in ipairs((cfg('storage', {}).items) or {}) do
        if e.key == payload.key then entry = e; break end
    end
    local name = entry and Config.Items and Config.Items[entry.key]
    if not name or not hasGradePerm(g, entry.perm) then return fail('no_item') end
    local s = shiftOf(src)
    local left = (entry.limit or 1) - (s.taken[entry.key] or 0)
    local count = I.int(payload.count, 1, 100, 1)
    if left <= 0 then return fail('limit_reached') end
    count = math.min(count, left)
    if Core.B('Inv.CanCarry', src, name, count) == false then return fail('cant_carry') end
    if not Core.B('Inv.AddItem', src, name, count) then return fail('cant_carry') end
    s.taken[entry.key] = (s.taken[entry.key] or 0) + count
    return { ok = true, items = storageList(src, g), msg = NZA.L('hospital.took', count, Core.B('Inv.Label', name) or name) }
end)

-- ════════════════════════════════════════════════════════════════════════
-- GARAGE & HELIPAD
-- ════════════════════════════════════════════════════════════════════════

local spawned = {}   -- [netId] = { src, dept, entity, plate, model }
local GARAGE = { garage = true, heli = true }

local function vehiclesOut(src)
    local n = 0
    for net, v in pairs(spawned) do
        if not DoesEntityExist(v.entity) then
            spawned[net] = nil
        elseif v.src == src then
            n = n + 1
        end
    end
    return n
end

local function garageAccess(src, pointId)
    local d, g = member(src)
    if not d then return nil, 'not_member' end
    if not onDuty(src) then return nil, 'off_duty' end
    local pt, err = usePoint(src, pointId, GARAGE, (cfg('garage', {}).storeRadius or 12.0) + 4.0)
    if not pt then return nil, err end
    if pt.hospital ~= d.id then return nil, 'other_point' end
    return pt, d, g
end

local function allowedVehicles(d, g, pt)
    local want = pt.type == 'heli' and 'heli' or 'car'
    local level = g and g.level or 0
    local out = {}
    for _, v in ipairs(d.vehicles or {}) do
        if v.type == want then
            out[#out + 1] = { id = v.id, model = v.model, label = v.label, type = v.type, minGrade = v.minGrade,
                locked = level < (v.minGrade or 0), gradeLabel = d.grades[(v.minGrade or 0) + 1] and d.grades[(v.minGrade or 0) + 1].label or nil }
        end
    end
    return out
end

lib.callback.register('nza:hospital:garage', function(src, pointId)
    if not rate(src) then return fail('rate') end
    local pt, d, g = garageAccess(src, pointId)
    if not pt then return fail(d) end
    return { ok = true, vehicles = allowedVehicles(d, g, pt), out = vehiclesOut(src), max = (cfg('garage', {}).maxPerPlayer) or 0, kind = pt.type }
end)

local function makePlate()
    local prefix = tostring((cfg('garage', {}).platePrefix) or 'EMS'):upper():gsub('[^%w ]', ''):sub(1, 5)
    local plate = prefix
    while #plate < 8 do plate = plate .. tostring(math.random(0, 9)) end
    return plate
end

local function spawnClear(pt, radius)
    local pos = I.PointPos(pt)
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - pos) < radius then return false end
    end
    return true
end

lib.callback.register('nza:hospital:garage:spawn', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local pt, d, g = garageAccess(src, payload.point)
    if not pt then return fail(d) end
    local gc = cfg('garage', {})
    local want = pt.type == 'heli' and 'heli' or 'car'
    local v
    for _, e in ipairs(d.vehicles or {}) do
        if e.id == payload.id and e.type == want then v = e; break end
    end
    if not v then return fail('no_vehicle') end
    if (g and g.level or 0) < (v.minGrade or 0) then return fail('grade') end
    local max = tonumber(gc.maxPerPlayer) or 0
    if max > 0 and vehiclesOut(src) >= max then return fail('too_many', max) end
    if not spawnClear(pt, gc.clearRadius or 3.5) then return fail('blocked') end

    local c = pt.coords
    local ok, veh = pcall(CreateVehicleServerSetter, GetHashKey(v.model), want == 'heli' and 'heli' or 'automobile', c.x, c.y, c.z + 0.25, c.w)
    if not ok or not veh or veh == 0 then return fail('spawn_failed') end
    local t = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - t < 3000 do Wait(25) end
    if not DoesEntityExist(veh) then return fail('spawn_failed') end
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, veh, 2) end   -- keep it when the owner's client leaves

    local plate = makePlate()
    SetVehicleNumberPlateText(veh, plate)
    local net = NetworkGetNetworkIdFromEntity(veh)
    spawned[net] = { src = src, dept = d.id, entity = veh, plate = plate, model = v.model }
    Core.B('Vehicle.GiveKeys', src, veh, plate)
    NZA.Debug(('hospital garage: %s spawned %s (%s) for %s'):format(d.id, v.model, plate, Core.Name(src)))
    return {
        ok = true, net = net, plate = plate, livery = v.livery, extras = v.extras, colour = v.colour,
        warp = gc.warp ~= false, fuel = gc.fuel or 100.0, label = v.label,
    }
end)

lib.callback.register('nza:hospital:garage:store', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local pt, d = garageAccess(src, payload.point)
    if not pt then return fail(d) end
    local net = tonumber(payload.net)
    local entry = net and spawned[net]
    if not entry or entry.dept ~= d.id or not DoesEntityExist(entry.entity) then return fail('not_dept_vehicle') end
    local vpos = GetEntityCoords(entry.entity)
    if #(vpos - I.PointPos(pt)) > ((cfg('garage', {}).storeRadius) or 12.0) then return fail('too_far') end
    local me = Core.SrcCoords(src)
    if not me or #(me - vpos) > 10.0 then return fail('too_far') end
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(entry.entity, seat)
        if ped and ped ~= 0 and ped ~= GetPlayerPed(tostring(src)) then return fail('occupied') end
    end
    DeleteEntity(entry.entity)
    spawned[net] = nil
    return { ok = true, msg = NZA.L('hospital.stored') }
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    if (cfg('garage', {}).deleteOnDrop) ~= false then
        for net, v in pairs(spawned) do
            if v.src == src then
                if DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
                spawned[net] = nil
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    for _, v in pairs(spawned) do
        if DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BEDS (lie down yourself; medics place patients through the transport module)
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:hospital:bed', function(src, payload)
    if not rate(src) then return fail('rate') end
    payload = type(payload) == 'table' and payload or {}
    local p = NZA.Patients.GetBySource(src)
    if not p then return fail('failed') end
    if payload.on then
        local pt, err = usePoint(src, payload.point, 'bed', 3.5)
        if not pt then return fail(err) end
        if p.state ~= 'alive' then return fail('state') end
        if p.meta and (p.meta.carried or p.meta.stretcher) then return fail('state') end
        if not H.OccupyBed(pt.id, p.pid) then return fail('bed_taken') end
        return { ok = true }
    end
    local bed = p.meta and p.meta.bed
    local id = type(bed) == 'table' and tonumber(bed.point) or tonumber(payload.point)
    if id and H.BedOccupant(id) == p.pid then H.ReleaseBed(id) end
    return { ok = true }
end)
