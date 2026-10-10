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
    return {
        id = 'p' .. row.id, type = row.type, x = row.x, y = row.y, z = row.z, h = row.h,
        placed = true, owner = row.owner, ownerName = row.owner_name, share = row.share,
        opLabel = (row.owner_name ~= '' and row.owner_name or 'Private') .. "'s setup",
        equipmentId = row.id,
    }
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
    if ownedCount(cid) >= P.maxPerPlayer then return { ok = false, err = ('You already run %d machines.'):format(P.maxPerPlayer) } end
    if P.interiorOnly and not inInterior then return { ok = false, err = 'This needs to be set up indoors.' } end
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > P.maxDistance + 2.0 then return { ok = false, err = 'Too far away.' } end
    for _, z in ipairs(P.blacklist) do
        if #(coords - z.coords) < z.radius then return { ok = false, err = 'Not here. Way too much attention.' } end
    end
    for _, st in pairs(Stations.list) do
        if #(coords - vec3(st.x, st.y, st.z)) < P.minSpacing then return { ok = false, err = 'Too close to another machine.' } end
    end

    local share
    if P.share == 'gang' then
        local g = Bridge.getGang(src)
        share = g and ('gang:' .. g.name) or nil
    elseif P.share == 'job' then
        share = 'job:' .. (Bridge.getJob(src).name or 'none')
    end

    if not Inv.remove(src, P.kits[stType], 1) then return { ok = false, err = 'Could not use the kit.' } end
    local name = Bridge.getName(src)
    local id = MySQL.insert.await('INSERT INTO nzmw_equipment (type, owner, owner_name, share, x, y, z, h) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { stType, cid, name, share, coords.x, coords.y, coords.z, heading })
    if not id then
        Inv.add(src, P.kits[stType], 1)
        return { ok = false, err = 'Database error.' }
    end
    Stations.add(Placement.def({ id = id, type = stType, owner = cid, owner_name = name, share = share,
        x = coords.x, y = coords.y, z = coords.z, h = heading }))
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
    if Bridge.getIdentifier(src) ~= st.owner then return { ok = false, err = 'Not yours.' } end
    if st.state ~= 'idle' then return { ok = false, err = 'Empty the machine first.' } end
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(st.x, st.y, st.z)) > Config.MaxInteractDistance then return { ok = false, err = 'Too far.' } end
    local kit = P.kits[st.type]
    if not Inv.canCarry(src, kit, 1) then return { ok = false, err = 'You cannot carry it.' } end
    MySQL.query.await('DELETE FROM nzmw_equipment WHERE id = ?', { equipmentId(st) })
    Stations.remove(id)
    Inv.add(src, kit, 1)
    return { ok = true }
end)

lib.callback.register('nzmw:seize', function(src, id)
    local st = Stations.list[id]
    if not st or not st.placed then return { ok = false, err = 'Nothing to seize.' } end
    if not NZ.isPoliceJob(Bridge.getJob(src)) then return { ok = false, err = 'Police only.' } end
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(st.x, st.y, st.z)) > Config.MaxInteractDistance then return { ok = false, err = 'Too far.' } end

    local p = Stations.priv[id]
    local b = p and p.batch and Batches.get(p.batch)
    local seized = 0
    if b then
        seized = b.amount
        Batches.remove(b.id)
    end
    MySQL.query.await('DELETE FROM nzmw_equipment WHERE id = ?', { equipmentId(st) })
    Stations.remove(id)

    local owner = Bridge.getSourceByIdentifier(st.owner)
    if owner then Bridge.notify(owner, 'Raided', ('Police seized your %s.'):format(st.label), 'error', 10000) end
    Bridge.log('Equipment seized', { { 'Officer', Bridge.getName(src) }, { 'Owner', st.ownerName or '?' },
        { 'Type', st.type }, { 'Cash seized', NZ.money(seized) } })
    return { ok = true, seized = seized }
end)
