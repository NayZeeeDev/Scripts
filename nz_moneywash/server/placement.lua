--[[ Player-placed equipment — buy a kit, set up shop anywhere (within the rules), get raided. ]]

Placement = {}

local P = Config.Placement

local function ownedCount(cid)
    local n = 0
    for _, st in pairs(Stations.list) do
        if st.placed and st.owner == cid then n = n + 1 end
    end
    return n
end

function Placement.def(row)
    local fid = tonumber(row.facility)
    return {
        id = 'p' .. row.id, type = row.type, x = row.x, y = row.y, z = row.z, h = row.h,
        placed = true, owner = row.owner, ownerName = row.owner_name, share = row.share,
        opLabel = fid and ('Unit #' .. fid) or ((row.owner_name ~= '' and row.owner_name or 'Private') .. "'s setup"),
        facility = fid, bucket = fid and Facility.bucket(fid) or 0,
    }
end

local pendingByUnit = {} -- placements awaiting their DB insert, so racing crews can't overfill a unit

local function sameBucket(src, st)
    return GetPlayerRoutingBucket(src) == (st.bucket or 0)
end

local function startPlacement(src, stType)
    if not P.enabled then return end
    TriggerClientEvent('nzmw:placement:start', src, stType)
end

for stType, item in pairs(P.kits) do
    Bridge.registerUsable(item, function(src) startPlacement(src, stType) end)
    -- ox_inventory item definitions can point at these: server = { export = 'nz_moneywash.nzmw_washer_kit' }
    exports(item, function(event, _, inventory)
        if event == 'usingItem' then startPlacement(inventory.id, stType) end
    end)
end

lib.callback.register('nzmw:place', function(src, stType, pos, heading, inInterior)
    if not P.enabled or not P.kits[stType] then return { ok = false, err = 'Disabled.' } end
    if Inv.count(src, P.kits[stType]) < 1 then return { ok = false, err = 'You do not have that kit.' } end
    if type(pos) ~= 'table' and type(pos) ~= 'vector3' then return { ok = false, err = 'Bad position.' } end
    local coords = vec3(tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0)
    heading = (tonumber(heading) or 0) % 360

    local cid = Bridge.getIdentifier(src)
    local bucket = GetPlayerRoutingBucket(src)
    local unit = Config.Facility.enabled and Facility.byBucket(bucket) or nil

    if unit then
        -- inside a wash unit: the unit's slots are the limit, the whole crew can build
        if not Facility.isMember(src, unit.id) then return { ok = false, err = 'This isn\'t your unit.' } end
        if #Facility.machines(unit.id) + (pendingByUnit[unit.id] or 0) >= Facility.slots(unit) then
            return { ok = false, err = 'The unit is full. Expand it at the terminal.' }
        end
        if #(coords - Config.Facility.interior.coords) > 60.0 then return { ok = false, err = 'Not here.' } end
    else
        if P.mode == 'unit' then return { ok = false, err = 'Set this up inside your wash unit.' } end
        if bucket ~= 0 then return { ok = false, err = 'Not here.' } end
        if ownedCount(cid) >= P.maxPerPlayer then return { ok = false, err = ('You already run %d machines.'):format(P.maxPerPlayer) } end
        if P.interiorOnly and not inInterior then return { ok = false, err = 'This needs to be set up indoors.' } end
        for _, z in ipairs(P.blacklist) do
            if #(coords - z.coords) < z.radius then return { ok = false, err = 'Not here. Way too much attention.' } end
        end
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > P.maxDistance + 2.0 then return { ok = false, err = 'Too far away.' } end
    for _, st in pairs(Stations.list) do
        if (st.bucket or 0) == bucket and #(coords - vec3(st.x, st.y, st.z)) < P.minSpacing then
            return { ok = false, err = 'Too close to another machine.' }
        end
    end

    local share
    if unit then
        share = 'facility:' .. unit.id
    elseif P.share == 'gang' then
        local g = Bridge.getGang(src)
        share = g and ('gang:' .. g.name) or nil
    elseif P.share == 'job' then
        local job = Bridge.getJob(src).name
        if job and job ~= 'unemployed' and job ~= 'none' then share = 'job:' .. job end
    end

    if not Inv.remove(src, P.kits[stType], 1) then return { ok = false, err = 'Could not use the kit.' } end
    if unit then pendingByUnit[unit.id] = (pendingByUnit[unit.id] or 0) + 1 end
    local name = Bridge.getName(src)
    local id = MySQL.insert.await('INSERT INTO nzmw_equipment (type, owner, owner_name, share, x, y, z, h, facility) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { stType, cid, name, share, coords.x, coords.y, coords.z, heading, unit and unit.id or nil })
    if unit then pendingByUnit[unit.id] = math.max(0, (pendingByUnit[unit.id] or 1) - 1) end
    if not id then
        Inv.add(src, P.kits[stType], 1)
        return { ok = false, err = 'Database error.' }
    end
    Stations.add(Placement.def({ id = id, type = stType, owner = cid, owner_name = name, share = share,
        x = coords.x, y = coords.y, z = coords.z, h = heading, facility = unit and unit.id or nil }))
    Bridge.log('Equipment placed', { { 'Player', name .. ' (' .. src .. ')' }, { 'Type', stType },
        { 'Coords', ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z) } })
    return { ok = true }
end)

local function equipmentId(st)
    return st and st.placed and tonumber(st.id:sub(2))
end

lib.callback.register('nzmw:pack', function(src, id)
    local st = Stations.list[id]
    if not st or not st.placed then return { ok = false, err = 'Nothing to pack.' } end
    local cid = Bridge.getIdentifier(src)
    local leaseholder = st.facility and Facility.role(cid, st.facility) == 'owner'
    if cid ~= st.owner and not leaseholder then return { ok = false, err = 'Not yours.' } end
    if st.state ~= 'idle' then return { ok = false, err = 'Empty the machine first.' } end
    if not sameBucket(src, st) or #(GetEntityCoords(GetPlayerPed(src)) - vec3(st.x, st.y, st.z)) > Config.MaxInteractDistance then return { ok = false, err = 'Too far.' } end
    local kit = P.kits[st.type]
    if not Inv.canCarry(src, kit, 1) then return { ok = false, err = 'You cannot carry it.' } end
    -- remove before awaiting the DB so a second pack / a seize can't race this one
    local equipId = equipmentId(st)
    Stations.remove(id)
    Inv.add(src, kit, 1)
    MySQL.query.await('DELETE FROM nzmw_equipment WHERE id = ?', { equipId })
    return { ok = true }
end)

lib.callback.register('nzmw:seize', function(src, id)
    local st = Stations.list[id]
    if not st or not st.placed then return { ok = false, err = 'Nothing to seize.' } end
    if not NZ.isPoliceJob(Bridge.getJob(src)) then return { ok = false, err = 'Police only.' } end
    if not sameBucket(src, st) or #(GetEntityCoords(GetPlayerPed(src)) - vec3(st.x, st.y, st.z)) > Config.MaxInteractDistance then return { ok = false, err = 'Too far.' } end

    local p = Stations.priv[id]
    local b = p and p.batch and Batches.get(p.batch)
    local equipId = equipmentId(st)
    Stations.remove(id) -- before any await, so a racing pack can't hand the kit back
    local seized = 0
    if b then
        seized = b.amount
        Batches.remove(b.id)
    end
    MySQL.query.await('DELETE FROM nzmw_equipment WHERE id = ?', { equipId })

    local owner = Bridge.getSourceByIdentifier(st.owner)
    if owner then Bridge.notify(owner, 'Raided', ('Police seized your %s%s.'):format(st.label, st.facility and (' in unit #' .. st.facility) or ''), 'error', 10000) end
    Bridge.log('Equipment seized', { { 'Officer', Bridge.getName(src) }, { 'Owner', st.ownerName or '?' },
        { 'Type', st.type }, { 'Cash seized', NZ.money(seized) } })
    return { ok = true, seized = seized }
end)
