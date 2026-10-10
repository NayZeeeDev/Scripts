--[[
    The RV: the owned vehicle out in the world, and the lab inside it.

    Inside, every owner is in their own routing bucket, so the interior (a shell or
    Trevor's trailer) can be shared by any number of players at the same coordinates.
    Placed equipment is stored relative to the interior origin.
]]

RV = {}

local vehicles = {}  -- owner src -> vehicle entity
local inside = {}    -- src -> { owner = ownerSrc, mode = 'shell' | 'ipl' }

local function interiorCfg(mode)
    return mode == 'ipl' and Config.RV.ipl or Config.RV.shell
end
RV.interiorCfg = interiorCfg

function RV.netOf(src)
    local veh = vehicles[src]
    if veh and DoesEntityExist(veh) then return NetworkGetNetworkIdFromEntity(veh) end
    return nil
end

function RV.vehicle(src)
    local veh = vehicles[src]
    return veh and DoesEntityExist(veh) and veh or nil
end

local function plateFor(P)
    if not P.rv.plate then
        P.rv.plate = ('%s%06d'):format(Config.RV.platePrefix, math.random(0, 999999)):sub(1, 8)
    end
    return P.rv.plate
end

local function prepare(src, veh)
    local P = Profile.get(src)
    SetVehicleNumberPlateText(veh, plateFor(P))
    if SetEntityOrphanMode then SetEntityOrphanMode(veh, 2) end
    Entity(veh).state:set('nzdeRV', Profile.identifier(src), true)
    Entity(veh).state:set('nzdeMission', nil, true)
    SetVehicleDoorsLocked(veh, 1)
    vehicles[src] = veh
    TriggerClientEvent('nzde:rv:net', src, NetworkGetNetworkIdFromEntity(veh))
end

--- the story RV becomes the player's
function RV.adopt(src, veh)
    local P = Profile.get(src)
    P.rv.owned = true
    prepare(src, veh)
    RV.savePos(src)
end

function RV.savePos(src)
    local P = Profile.get(src)
    local veh = RV.vehicle(src)
    if not P or not veh then return end
    local c, h = GetEntityCoords(veh), GetEntityHeading(veh)
    P.rv.pos = { x = c.x, y = c.y, z = c.z, w = h }
    Profile.dirty(src)
end

local function nearestLot(c)
    local best, bd
    for _, l in ipairs(Config.RV.towLots) do
        local d = #(vec3(l.x, l.y, l.z) - c)
        if not bd or d < bd then best, bd = l, d end
    end
    return best
end

function RV.spawn(src, at)
    local P = Profile.get(src)
    if not P or not P.rv.owned or RV.vehicle(src) then return end
    local c = at or P.rv.pos or Config.RV.towLots[1]
    local veh = CreateVehicleServerSetter(joaat(Config.RV.model), 'automobile', c.x, c.y, c.z + 0.3, c.w or 0.0)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(veh) then return end
    prepare(src, veh)
    Profile.sync(src)
end

function RV.store(src)
    local veh = RV.vehicle(src)
    if not veh then return end
    RV.savePos(src)
    DeleteEntity(veh)
    vehicles[src] = nil
end

--- client keeps the saved position fresh when the owner leaves the driver seat
RegisterNetEvent('nzde:rv:parked', function()
    local src = source
    if Guard.rate(src, 'park', 3000) then RV.savePos(src) end
end)

RegisterNetEvent('nzde:keys:qbx', function(net)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(net)
    if veh == 0 or (veh ~= RV.vehicle(src) and veh ~= NetworkGetEntityFromNetworkId(Story.missionNet(src) or -1)) then return end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
end)

--- phone app: tow a lost RV to the nearest lot
Guard.callback('nzde:rv:tow', function(src, account)
    local P = Profile.get(src)
    if not P or not P.rv.owned then return false, 'You don\'t own an RV' end
    if inside[src] then return false, 'Leave the RV first' end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    if not FW.removeMoney(src, account, Config.RV.towFee, 'drugempire-tow') then return false, 'Not enough money' end
    RV.store(src)
    local lot = nearestLot(GetEntityCoords(GetPlayerPed(src)))
    P.rv.pos = { x = lot.x, y = lot.y, z = lot.z, w = lot.w }
    RV.spawn(src, P.rv.pos)
    return true, lot
end)

--[[ ─────────────── inside ─────────────── ]]

function RV.inside(src)
    return inside[src]
end

local function worldOf(rec, obj)
    local o = interiorCfg(rec.mode).origin
    return vec3(o.x + obj.x, o.y + obj.y, o.z + obj.z)
end
RV.worldOf = worldOf

--- inside their own RV and within `max` metres of `obj`
function RV.nearObj(src, obj, max)
    local rec = inside[src]
    if not rec or rec.owner ~= src then return false end
    return Guard.near(src, worldOf(rec, obj), max or 3.5)
end

--- inside their own RV and near an interior point (relative)
function RV.nearPoint(src, rel, max)
    local rec = inside[src]
    if not rec or rec.owner ~= src or not rel then return false end
    local o = interiorCfg(rec.mode).origin
    return Guard.near(src, vec3(o.x + rel.x, o.y + rel.y, o.z + rel.z), max or 3.0)
end

--- everyone inside `owner`'s RV gets the new object state
function RV.push(owner, obj, removed)
    for s, rec in pairs(inside) do
        if rec.owner == owner then
            TriggerClientEvent('nzde:rv:obj', s, obj, removed == true, os.time())
        end
    end
end

Guard.callback('nzde:rv:enter', function(src, mode)
    local P = Profile.get(src)
    if not P or not P.rv.owned or inside[src] then return false end
    local veh = RV.vehicle(src)
    if not veh then return false, 'Your RV is gone. Tow it from the app.' end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 8.0 then return false end
    mode = mode == 'ipl' and 'ipl' or 'shell'
    inside[src] = { owner = src, mode = mode }
    SetPlayerRoutingBucket(src, Config.RV.bucketBase + src)
    if Config.RV.lockWhileInside then SetVehicleDoorsLocked(veh, 2) end
    RV.savePos(src)
    Quests.progress(src, 'rv:enter')
    return true, { objects = P.objects, now = os.time(), water = P.water, orders = Deliveries.rvReady(src) }
end)

local function leave(src)
    local rec = inside[src]
    if not rec then return nil end
    inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
    local veh = RV.vehicle(rec.owner)
    if not veh then return nil end
    if Config.RV.lockWhileInside then SetVehicleDoorsLocked(veh, 1) end
    local c, h = GetEntityCoords(veh), GetEntityHeading(veh)
    local r = math.rad(h)
    local off = Config.RV.entryOffset
    -- rotate the rear offset by the vehicle heading
    local x = c.x + off.x * math.cos(r) - off.y * math.sin(r)
    local y = c.y + off.x * math.sin(r) + off.y * math.cos(r)
    return { x = x, y = y, z = c.z, w = h + 180.0 }
end

Guard.callback('nzde:rv:exit', function(src)
    return leave(src) or false
end)

--[[ placing / picking up equipment ]]
local function newState(kind)
    local now = os.time()
    if kind == 'pot' or kind == 'tent' or kind == 'bed' then return { soil = 0, water = 0.0, growth = 0.0, t = now } end
    if kind == 'rack' then return { slots = {} } end
    return {}
end

local function typeForItem(item)
    for kind, s in pairs(Config.Stations) do
        if s.item == item then return kind, s end
    end
end

Guard.callback('nzde:rv:place', function(src, item, x, y, z, h)
    local P = Profile.get(src)
    local rec = inside[src]
    if not P or not rec or rec.owner ~= src then return false end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' or type(h) ~= 'number' then return false end
    local kind, st = typeForItem(item)
    if not kind then return false end
    if Profile.level(P) < (st.unlock or 1) then return false, ('Unlocks at %s'):format(Utils.rankLabel(st.unlock)) end
    if Utils.count(P.objects) >= Config.RV.maxObjects then return false, 'The RV is full' end
    local cfg = interiorCfg(rec.mode)
    if math.sqrt(x * x + y * y) > cfg.radius or z < cfg.floor - 1.0 or z > cfg.floor + 3.0 then return false, 'Out of bounds' end
    local o = cfg.origin
    if not Guard.near(src, vec3(o.x + x, o.y + y, o.z + z), 6.0) then return false end
    if not Inv.remove(src, item, 1) then return false, 'You don\'t have that' end
    local id = Profile.nextId(P, 'o')
    local obj = { id = id, type = kind, x = x, y = y, z = z, h = h % 360.0, st = newState(kind) }
    if kind == 'light' then Stations.tickAll(src) end
    P.objects[id] = obj
    Profile.dirty(src)
    RV.push(src, obj)
    Quests.progress(src, 'place:' .. kind)
    return true
end)

local function idle(obj)
    local st = obj.st
    if obj.type == 'pot' or obj.type == 'tent' or obj.type == 'bed' then return not st.seed end
    if obj.type == 'rack' then return #(st.slots or {}) == 0 end
    return not st.busy
end

Guard.callback('nzde:rv:pickup', function(src, id)
    local P = Profile.get(src)
    local obj = P and P.objects[id]
    if not obj or not RV.nearObj(src, obj, 3.5) then return false end
    if not idle(obj) then return false, 'Empty it first' end
    local item = Config.Stations[obj.type].item
    if not Inv.canCarry(src, item, 1) then return false, 'You can\'t carry that' end
    if obj.type == 'light' then Stations.tickAll(src) end
    P.objects[id] = nil
    Profile.dirty(src)
    Inv.add(src, item, 1)
    RV.push(src, obj, true)
    return true
end)

-- equipment the player is carrying (the "Set up equipment" menu inside the RV)
Guard.callback('nzde:rv:placeables', function(src)
    local P = Profile.get(src)
    if not P then return {} end
    local level, out = Profile.level(P), {}
    for kind, st in pairs(Config.Stations) do
        local n = Inv.count(src, st.item)
        if n > 0 then
            out[#out + 1] = { item = st.item, kind = kind, label = st.label, icon = st.icon, n = n, locked = level < (st.unlock or 1), rank = Utils.rankLabel(st.unlock or 1) }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

-- using an equipment item from the inventory starts placement (inside your RV)
CreateThread(function()
    for _, st in pairs(Config.Stations) do
        FW.registerUsable(st.item, function(src)
            local rec = inside[src]
            if not rec or rec.owner ~= src then
                TriggerClientEvent('nzde:notify', src, 'Set this up inside your RV', 'error')
                return
            end
            TriggerClientEvent('nzde:place', src, st.item)
        end)
    end
end)

AddEventHandler('nzde:server:unload', function(src)
    inside[src] = nil
    RV.store(src)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(inside) do SetPlayerRoutingBucket(src, 0) end
    for src in pairs(vehicles) do
        RV.savePos(src)
        Profile.save(src, true)
        local veh = vehicles[src]
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
end)

--- heartbeat
function RV.tick(src)
    local P = Profile.get(src)
    if not P or not P.rv.owned then return end
    if vehicles[src] and not DoesEntityExist(vehicles[src]) then
        vehicles[src] = nil
        TriggerClientEvent('nzde:notify', src, 'Your RV is gone. Tow it back from the Empire app.', 'error')
        Profile.sync(src)
    elseif vehicles[src] and not inside[src] then
        RV.savePos(src)
    end
end
