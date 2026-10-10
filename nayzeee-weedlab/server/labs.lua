--[[
    Labs: the RV (a real vehicle out in the world) and the two warehouses.

    Inside, every owner is in their own routing bucket, so an interior can be shared by any
    number of players at the same coordinates without anybody seeing anybody else.
    Placed equipment is stored per lab, relative to the interior origin.
]]

Labs = {}

local vehicles = {}  -- owner src -> RV entity
local inside = {}    -- src -> { lab = 'rv'|'small'|'warehouse', mode = 'shell'|'ipl'|nil }

local function now() return os.time() end

function Labs.inside(src)
    return inside[src]
end

function Labs.cfg(rec)
    return Utils.labInterior(rec.lab, rec.mode)
end

function Labs.objects(P, lab)
    return P.labs[lab].objects
end

--[[ ─────────────── the RV vehicle ─────────────── ]]

function Labs.rvNet(src)
    local veh = vehicles[src]
    if veh and DoesEntityExist(veh) then return NetworkGetNetworkIdFromEntity(veh) end
    return nil
end

function Labs.vehicle(src)
    local veh = vehicles[src]
    return veh and DoesEntityExist(veh) and veh or nil
end

local function plateFor(P)
    if not P.labs.rv.plate then
        P.labs.rv.plate = ('%s%05d'):format(Config.RV.platePrefix, math.random(0, 99999)):sub(1, 8)
    end
    return P.labs.rv.plate
end

local function prepare(src, veh)
    local P = Profile.get(src)
    SetVehicleNumberPlateText(veh, plateFor(P))
    if SetEntityOrphanMode then SetEntityOrphanMode(veh, 2) end
    Entity(veh).state:set('nzwlRV', Profile.identifier(src), true)
    Entity(veh).state:set('nzwlMission', nil, true)
    SetVehicleDoorsLocked(veh, 1)
    vehicles[src] = veh
    TriggerClientEvent('nzwl:rv:net', src, NetworkGetNetworkIdFromEntity(veh))
end

function Labs.savePos(src)
    local P = Profile.get(src)
    local veh = Labs.vehicle(src)
    if not P or not veh then return end
    local c, h = GetEntityCoords(veh), GetEntityHeading(veh)
    P.labs.rv.pos = { x = c.x, y = c.y, z = c.z, w = h }
    Profile.dirty(src)
end

--- the stolen story RV becomes the player's lab
function Labs.adoptRV(src, veh)
    local P = Profile.get(src)
    P.labs.rv.owned = true
    prepare(src, veh)
    Labs.savePos(src)
end

function Labs.spawnRV(src, at)
    local P = Profile.get(src)
    if not P or not P.labs.rv.owned or Labs.vehicle(src) then return end
    local c = at or P.labs.rv.pos or Config.RV.towLots[1]
    local veh = CreateVehicleServerSetter(joaat(Config.RV.model), 'automobile', c.x, c.y, c.z + 0.3, c.w or 0.0)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(veh) then return end
    prepare(src, veh)
    Profile.sync(src)
end

function Labs.storeRV(src)
    local veh = Labs.vehicle(src)
    if not veh then return end
    Labs.savePos(src)
    DeleteEntity(veh)
    vehicles[src] = nil
end

RegisterNetEvent('nzwl:rv:parked', function()
    local src = source
    if Guard.rate(src, 'park', 3000) then Labs.savePos(src) end
end)

RegisterNetEvent('nzwl:keys:qbx', function(net)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(net)
    if veh == 0 or (veh ~= Labs.vehicle(src) and veh ~= NetworkGetEntityFromNetworkId(Story.missionNet(src) or -1)) then return end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
end)

local function nearestLot(c)
    local best, bd
    for _, l in ipairs(Config.RV.towLots) do
        local d = #(vec3(l.x, l.y, l.z) - c)
        if not bd or d < bd then best, bd = l, d end
    end
    return best
end

--- tablet: tow a lost RV to the nearest lot
Guard.callback('nzwl:rv:tow', function(src, account)
    local P = Profile.get(src)
    if not P or not P.labs.rv.owned then return false, 'You don\'t have an RV' end
    if inside[src] then return false, 'Leave the lab first' end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    if not FW.removeMoney(src, account, Config.RV.towFee, 'weedlab-tow') then return false, 'Not enough money' end
    Labs.storeRV(src)
    local lot = nearestLot(GetEntityCoords(GetPlayerPed(src)))
    P.labs.rv.pos = { x = lot.x, y = lot.y, z = lot.z, w = lot.w }
    Labs.spawnRV(src, P.labs.rv.pos)
    return true, { x = lot.x, y = lot.y, z = lot.z }
end)

--[[ ─────────────── entering / leaving ─────────────── ]]

local function worldOf(rec, obj)
    local o = Labs.cfg(rec).origin
    return vec3(o.x + obj.x, o.y + obj.y, o.z + obj.z)
end
Labs.worldOf = worldOf

--- inside their own lab and within `max` metres of `obj`
function Labs.nearObj(src, obj, max)
    local rec = inside[src]
    if not rec then return false end
    return Guard.near(src, worldOf(rec, obj), max or 3.5)
end

--- inside their own lab and near an interior point (relative)
function Labs.nearPoint(src, rel, max)
    local rec = inside[src]
    if not rec or not rel then return false end
    local o = Labs.cfg(rec).origin
    return Guard.near(src, vec3(o.x + rel.x, o.y + rel.y, o.z + rel.z), max or 3.0)
end

--- the object `oid` in the lab the player is standing in (and close to it)
function Labs.obj(src, oid, max)
    local P = Profile.get(src)
    local rec = inside[src]
    if not P or not rec then return nil end
    local obj = P.labs[rec.lab].objects[oid]
    if not obj or not Labs.nearObj(src, obj, max or 3.5) then return nil end
    return obj, P, rec
end

--- the owner gets the new object state (only while inside that lab)
function Labs.push(src, obj, removed)
    local rec = inside[src]
    if not rec or rec.lab ~= obj.lab then return end
    TriggerClientEvent('nzwl:lab:obj', src, obj, removed == true, now())
end

local function entrance(lab, P)
    local L = Config.Labs[lab]
    return L.entrances and L.entrances[P.labs[lab].entrance or 1]
end
Labs.entrance = entrance

Guard.callback('nzwl:lab:enter', function(src, lab, mode)
    local P = Profile.get(src)
    local L = Config.Labs[lab]
    if not P or not L or inside[src] or not P.labs[lab] or not P.labs[lab].owned then return false end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    if lab == 'rv' then
        local veh = Labs.vehicle(src)
        if not veh then return false, 'Your RV is gone. Tow it from the tablet.' end
        if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 8.0 then return false end
        mode = mode == 'ipl' and 'ipl' or 'shell'
        if Config.RV.lockWhileInside then SetVehicleDoorsLocked(veh, 2) end
        Labs.savePos(src)
    else
        local e = entrance(lab, P)
        if not e or not Guard.near(src, e.door, 4.0) then return false end
        mode = nil
    end
    inside[src] = { lab = lab, mode = mode }
    SetPlayerRoutingBucket(src, Config.Buckets.base + src)
    Stations.tickAll(src)
    return true, { objects = P.labs[lab].objects, now = now(), water = P.water }
end)

local function leave(src)
    local rec = inside[src]
    if not rec then return nil end
    inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
    local P = Profile.get(src)
    if rec.lab == 'rv' then
        local veh = Labs.vehicle(src)
        if not veh then return nil end
        if Config.RV.lockWhileInside then SetVehicleDoorsLocked(veh, 1) end
        local c, h = GetEntityCoords(veh), GetEntityHeading(veh)
        local off = Config.RV.entryOffset
        local x, y = Utils.rotate(off.x + 0.6, off.y, h)
        return { x = c.x + x, y = c.y + y, z = c.z, w = h - 90.0 }
    end
    local e = P and entrance(rec.lab, P)
    if not e then return nil end
    return { x = e.door.x, y = e.door.y, z = e.door.z, w = e.door.w + 180.0 }
end

Guard.callback('nzwl:lab:exit', function(src)
    return leave(src) or false
end)

--[[ ─────────────── placing equipment ─────────────── ]]

local function newState(kind)
    if Config.Equipment[kind].grow then return { soil = 0, water = 0.0, growth = 0.0, t = now() } end
    if kind == 'dryrack' then return { slots = {} } end
    return {}
end

local function counts(objects)
    local all, grow = 0, 0
    for _, o in pairs(objects) do
        all = all + 1
        if Config.Equipment[o.type] and Config.Equipment[o.type].grow then grow = grow + 1 end
    end
    return all, grow
end

local function overlaps(objects, kind, x, y)
    local e = Config.Equipment[kind]
    if e.overlap then return false end
    for _, o in pairs(objects) do
        local oe = Config.Equipment[o.type]
        if oe and not oe.overlap then
            local min = (e.footprint or 0.4) * 0.5 + (oe.footprint or 0.4) * 0.5
            local dx, dy = o.x - x, o.y - y
            if dx * dx + dy * dy < (min * 0.85) ^ 2 then return true end
        end
    end
    return false
end
Labs.overlaps = overlaps

Guard.callback('nzwl:lab:place', function(src, item, x, y, z, h)
    local P = Profile.get(src)
    local rec = inside[src]
    if not P or not rec then return false end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' or type(h) ~= 'number' then return false end
    local kind, e = Utils.equipmentOf(item)
    if not kind then return false end
    if Profile.level(P) < (e.level or 0) then return false, ('Unlocks at level %d'):format(e.level) end
    local L, cfg = Config.Labs[rec.lab], Labs.cfg(rec)
    local objects = P.labs[rec.lab].objects
    local all, grow = counts(objects)
    if all >= L.maxObjects then return false, ('The %s is full'):format(L.label) end
    if e.grow and grow >= L.maxGrow then return false, ('The %s fits %d growing stations. Upgrade to grow more.'):format(L.label, L.maxGrow) end
    if not Utils.inBounds(cfg, x, y, z) then return false, 'Out of bounds' end
    if overlaps(objects, kind, x, y) then return false, 'Too close to something else' end
    local o = cfg.origin
    if not Guard.near(src, vec3(o.x + x, o.y + y, o.z + z), 7.0) then return false end
    if not Inv.remove(src, item, 1) then return false, 'You don\'t have that' end
    Stations.tickAll(src)
    local id = Profile.nextId(P, 'o')
    local obj = { id = id, lab = rec.lab, type = kind, x = x, y = y, z = z, h = h % 360.0, st = newState(kind) }
    objects[id] = obj
    Profile.dirty(src)
    Labs.push(src, obj)
    return true
end)

local function idle(obj)
    local st = obj.st
    if Config.Equipment[obj.type].grow then return not st.seed end
    if obj.type == 'dryrack' then return #(st.slots or {}) == 0 end
    return not st.busy
end

Guard.callback('nzwl:lab:pickup', function(src, oid)
    local obj, P, rec = Labs.obj(src, oid)
    if not obj then return false end
    if not idle(obj) then return false, 'Empty it first' end
    local item = Config.Equipment[obj.type].item
    local light = obj.type == 'rack' and obj.st.light and Config.Lights[obj.st.light]
    if not Inv.canCarry(src, item, 1) or (light and not Inv.canCarry(src, light.item, 1)) then return false, 'You can\'t carry that' end
    Stations.tickAll(src)
    P.labs[rec.lab].objects[oid] = nil
    Profile.dirty(src)
    Inv.add(src, item, 1)
    if light then Inv.add(src, light.item, 1) end
    Labs.push(src, obj, true)
    return true
end)

--[[ ─────────────── grow lights on suspension racks ─────────────── ]]

Guard.callback('nzwl:lab:hang', function(src, oid, item)
    local obj, P = Labs.obj(src, oid)
    if not obj or obj.type ~= 'rack' then return false end
    if obj.st.light then return false, 'Take the light down first' end
    local kind, l = Utils.lightOf(item)
    if not kind then return false end
    if Profile.level(P) < (l.level or 0) then return false, ('Unlocks at level %d'):format(l.level) end
    if not Inv.remove(src, item, 1) then return false, 'You don\'t have that light' end
    Stations.tickAll(src)
    obj.st.light = kind
    Profile.dirty(src)
    Labs.push(src, obj)
    return true
end)

Guard.callback('nzwl:lab:unhang', function(src, oid)
    local obj = Labs.obj(src, oid)
    if not obj or obj.type ~= 'rack' or not obj.st.light then return false end
    local l = Config.Lights[obj.st.light]
    if not Inv.canCarry(src, l.item, 1) then return false, 'You can\'t carry that' end
    Stations.tickAll(src)
    obj.st.light = nil
    Profile.dirty(src)
    Inv.add(src, l.item, 1)
    Labs.push(src, obj)
    return true
end)

--- growth multiplier for a pot: a tent has its own light; pots take the best light whose rack covers them
function Labs.boostFor(objects, obj)
    local e = Config.Equipment[obj.type]
    if e.boost then return e.boost end
    local best, area = 1.0, Config.Equipment.rack.area
    for _, o in pairs(objects) do
        if o.type == 'rack' and o.st.light then
            local lx, ly = Utils.rotate(obj.x - o.x, obj.y - o.y, -(o.h or 0.0))
            if math.abs(lx) <= area.x and math.abs(ly) <= area.y then
                best = math.max(best, Config.Lights[o.st.light].boost)
            end
        end
    end
    return best
end

-- equipment the player is carrying (the "Set up equipment" menu inside a lab)
Guard.callback('nzwl:lab:placeables', function(src)
    local P = Profile.get(src)
    if not P then return {} end
    local level, out = Profile.level(P), {}
    for kind, e in pairs(Config.Equipment) do
        local n = Inv.count(src, e.item)
        if n > 0 then
            out[#out + 1] = { item = e.item, kind = kind, label = e.label, icon = e.icon, n = n, locked = level < (e.level or 0), level = e.level or 0 }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

-- equipment items used from the inventory start placement (inside your lab)
CreateThread(function()
    for _, e in pairs(Config.Equipment) do
        FW.registerUsable(e.item, function(src)
            if not inside[src] then
                TriggerClientEvent('nzwl:notify', src, 'Set this up inside your lab', 'error')
                return
            end
            TriggerClientEvent('nzwl:place', src, e.item)
        end)
    end
    for _, l in pairs(Config.Lights) do
        FW.registerUsable(l.item, function(src)
            TriggerClientEvent('nzwl:notify', src, 'Hang it on a suspension rack in your lab', 'info')
        end)
    end
end)

--[[ ─────────────── buying a warehouse ─────────────── ]]

Guard.callback('nzwl:lab:buy', function(src, lab, entranceIdx, account)
    local P = Profile.get(src)
    local L = Config.Labs[lab]
    if not P or not L or lab == 'rv' or not L.entrances then return false end
    if P.labs[lab].owned then return false, 'You already own it' end
    if Profile.level(P) < (L.level or 0) then return false, ('Unlocks at level %d'):format(L.level) end
    entranceIdx = math.floor(tonumber(entranceIdx) or 0)
    if not L.entrances[entranceIdx] then return false end
    if not Guard.rate(src, 'buylab', 3000) then return false end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    if not FW.removeMoney(src, account, L.price, 'weedlab-' .. lab) then return false, 'Not enough money' end
    P.labs[lab].owned = true
    P.labs[lab].entrance = entranceIdx
    P.stats.spent = (P.stats.spent or 0) + L.price
    Profile.dirty(src)
    Profile.save(src, true)
    Logs.send('Lab bought', ('%s bought the %s (%s) for %s'):format(P.name or src, L.label, L.entrances[entranceIdx].label, Utils.money(L.price)), 3447003)
    Profile.sync(src)
    return true
end)

AddEventHandler('nzwl:server:unload', function(src)
    inside[src] = nil
    Labs.storeRV(src)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(inside) do SetPlayerRoutingBucket(src, 0) end
    for src in pairs(vehicles) do
        Labs.savePos(src)
        Profile.save(src, true)
        local veh = vehicles[src]
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
end)

--- heartbeat
function Labs.tick(src)
    local P = Profile.get(src)
    if not P or not P.labs.rv.owned then return end
    if vehicles[src] and not DoesEntityExist(vehicles[src]) then
        vehicles[src] = nil
        TriggerClientEvent('nzwl:notify', src, 'Your RV is gone. Tow it back from the tablet.', 'error')
        Profile.sync(src)
    elseif vehicles[src] and not inside[src] then
        Labs.savePos(src)
    end
end
