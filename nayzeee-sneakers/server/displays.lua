--[[
    Display cases: clear cases players place anywhere (houses too) and stack, each holding one pair.

    Every case is saved in KVP (display:<id>) with its spot, routing bucket, owner and the pair inside,
    and comes back after a restart. The case is a networked object in its bucket; every client spawns
    the door and the pair for itself from the case's state bag (nzs:dopen, nzs:dshoe), like the boxes.
]]

Displays = {}

local D = Config.Displays
local PREFIX = 'display:'
local records = {}      -- [id] = { id, type, x, y, z, h, bucket, owner, ownerName, pair }
local ents = {}         -- [id] = entity
local byEnt = {}        -- [entity] = id
local counter = 0

local function save(r) SetResourceKvp(PREFIX .. r.id, json.encode(r)) end

local function newId()
    counter = counter + 1
    return ('%x%x'):format(os.time(), counter)
end

local function setState(ent, key, value) Entity(ent).state:set(key, value, true) end

local function spawn(r)
    local t = D.Types[r.type]
    if not t then return nil end
    local ent = CreateObjectNoOffset(t.model, r.x, r.y, r.z, true, true, false)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(ent) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end
    SetEntityHeading(ent, r.h + 0.0)
    FreezeEntityPosition(ent, true)
    SetEntityRoutingBucket(ent, r.bucket or 0)
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, ent, 2) end   -- keep it with nobody around
    setState(ent, 'nzs:display', r.type)
    setState(ent, 'nzs:dopen', false)
    setState(ent, 'nzs:dbusy', false)
    setState(ent, 'nzs:dshoe', r.pair and r.pair.shoe or false)
    ents[r.id], byEnt[ent] = ent, r.id
    return ent
end

local function countAll()
    local n = 0
    for _ in pairs(records) do n = n + 1 end
    GlobalState.nzsDisplays = n
end

local function despawn(id)
    local ent = ents[id]
    if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
    if ent then byEnt[ent] = nil end
    ents[id] = nil
end

local function fromNet(netId)
    local ent = netId and NetworkGetEntityFromNetworkId(netId)
    local id = ent and byEnt[ent]
    if not id then return nil end
    return ent, records[id]
end

local function nearEnough(src, ent)
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(ent)) < 6.0
end

local function isOwner(src, r)
    return D.anyoneCanTake or r.owner == Bridge.GetIdentifier(src) or Bridge.IsAdmin(src)
end

local function countOwned(src)
    local me, n = Bridge.GetIdentifier(src), 0
    for _, r in pairs(records) do if r.owner == me then n = n + 1 end end
    return n
end

--- Something sitting on top of this case (in the same bucket)?
local function hasOnTop(r)
    local t = D.Types[r.type]
    local reach = math.max(t.size.x, t.size.y) * 0.5
    for id, o in pairs(records) do
        if id ~= r.id and (o.bucket or 0) == (r.bucket or 0) and o.z > r.z + t.size.z * 0.5
            and o.z < r.z + t.size.z + 0.3 and math.sqrt((o.x - r.x) ^ 2 + (o.y - r.y) ^ 2) < reach then
            return true
        end
    end
    return false
end

local function door(ent, open, wait)
    setState(ent, 'nzs:dopen', open)
    if wait then Wait(open and D.openTime or D.closeTime) end
end

local function busy(ent, on) setState(ent, 'nzs:dbusy', on) end

-- ------------------------------------------------------------------ placing

lib.callback.register('nayzeee-sneakers:placeDisplay', function(src, slot, typeId, coords, heading)
    local t = D.Enabled and D.Types[typeId]
    if not t or type(heading) ~= 'number' or type(coords) ~= 'vector3' and type(coords) ~= 'table' then return false end
    if not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z) then return false end
    coords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > 6.0 then return false end
    if countOwned(src) >= D.maxPerPlayer then
        Bridge.Notify(src, Config.Text.dispLimit, 'error')
        return false
    end
    local it = Inv.GetSlot(src, slot)
    if not it or it.name ~= t.item then it = Inv.Find(src, t.item) end
    if not it or not Inv.Remove(src, t.item, 1, it.slot) then return false end
    local r = {
        id = newId(), type = typeId, x = coords.x, y = coords.y, z = coords.z, h = heading % 360.0,
        bucket = GetPlayerRoutingBucket(src), owner = Bridge.GetIdentifier(src), ownerName = Bridge.GetName(src),
    }
    local ent = spawn(r)
    if not ent then
        Inv.Add(src, t.item, 1)
        return false
    end
    records[r.id] = r
    save(r)
    countAll()
    return NetworkGetNetworkIdFromEntity(ent)
end)

-- ------------------------------------------------------------------ using one

lib.callback.register('nayzeee-sneakers:displayDoor', function(src, netId)
    local ent, r = fromNet(netId)
    if not ent or not nearEnough(src, ent) or Entity(ent).state['nzs:dbusy'] then return false end
    if not D.anyoneCanOpen and not isOwner(src, r) then
        Bridge.Notify(src, Config.Text.dispNotYours, 'error')
        return false
    end
    door(ent, not Entity(ent).state['nzs:dopen'])
    return true
end)

lib.callback.register('nayzeee-sneakers:displayPut', function(src, netId, slot)
    local ent, r = fromNet(netId)
    if not ent or not nearEnough(src, ent) or Entity(ent).state['nzs:dbusy'] then return false end
    if not isOwner(src, r) then Bridge.Notify(src, Config.Text.dispNotYours, 'error') return false end
    if r.pair then Bridge.Notify(src, Config.Text.dispFull, 'error') return false end
    local it = Inv.GetSlot(src, slot)
    if not it or it.name ~= Config.Items.shoes or not it.metadata or not Config.Shoes[it.metadata.shoe] then return false end
    if not D.Types[r.type].fits[Shared.BoxTypeForShoe(it.metadata.shoe)] then return false end
    local meta = Items.Clean(it.metadata)
    if not Inv.Remove(src, Config.Items.shoes, 1, slot) then return false end
    r.pair = meta
    save(r)
    CreateThread(function()
        busy(ent, true)
        local wasOpen = Entity(ent).state['nzs:dopen']
        if not wasOpen then door(ent, true, true) end
        setState(ent, 'nzs:dshoe', meta.shoe)
        Wait(900)
        door(ent, false, true)
        busy(ent, false)
    end)
    return D.openTime + 900 + D.closeTime
end)

lib.callback.register('nayzeee-sneakers:displayTake', function(src, netId)
    local ent, r = fromNet(netId)
    if not ent or not nearEnough(src, ent) or Entity(ent).state['nzs:dbusy'] then return false end
    if not isOwner(src, r) then Bridge.Notify(src, Config.Text.dispNotYours, 'error') return false end
    if not r.pair then return false end
    if not Items.GivePair(src, r.pair, false) then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    r.pair = nil
    save(r)
    CreateThread(function()
        busy(ent, true)
        if not Entity(ent).state['nzs:dopen'] then door(ent, true, true) end
        setState(ent, 'nzs:dshoe', false)
        Wait(700)
        door(ent, false, true)
        busy(ent, false)
    end)
    return D.openTime + 700 + D.closeTime
end)

--- The pair inside, for the inspect card (anyone)
lib.callback.register('nayzeee-sneakers:displayPair', function(src, netId)
    local ent, r = fromNet(netId)
    if not ent or not nearEnough(src, ent) then return nil end
    return r.pair
end)

lib.callback.register('nayzeee-sneakers:displayPickUp', function(src, netId)
    local ent, r = fromNet(netId)
    if not ent or not nearEnough(src, ent) or Entity(ent).state['nzs:dbusy'] then return false end
    if not isOwner(src, r) then Bridge.Notify(src, Config.Text.dispNotYours, 'error') return false end
    if r.pair then Bridge.Notify(src, Config.Text.dispNotEmpty, 'error') return false end
    if hasOnTop(r) then Bridge.Notify(src, Config.Text.dispStacked, 'error') return false end
    if not Inv.Add(src, D.Types[r.type].item, 1) then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    despawn(r.id)
    records[r.id] = nil
    DeleteResourceKvp(PREFIX .. r.id)
    countAll()
    return true
end)

-- ------------------------------------------------------------------ items

CreateThread(function()
    if not D.Enabled then return end
    for id, t in pairs(D.Types) do
        Inv.RegisterUsable(t.item, function(src, it)
            TriggerClientEvent('nayzeee-sneakers:client:placeDisplay', src, it.slot, id)
        end)
    end
end)

-- ------------------------------------------------------------------ start / stop

CreateThread(function()
    if not D.Enabled then return end
    local h, n = StartFindKvp(PREFIX), 0
    if h ~= -1 then
        while true do
            local k = FindKvp(h)
            if not k then break end
            local ok, r = pcall(json.decode, GetResourceKvpString(k) or '')
            if ok and type(r) == 'table' and r.id and D.Types[r.type] then records[r.id] = r end
        end
        EndFindKvp(h)
    end
    for _, r in pairs(records) do
        if spawn(r) then n = n + 1 end
    end
    countAll()
    if n > 0 then print(('^2[nayzeee-sneakers]^7 %d display case(s) put back'):format(n)) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(ents) do despawn(id) end
end)

--- Admins: remove every case a player (identifier) owns, e.g. after a house is deleted
exports('RemovePlayerDisplays', function(identifier, giveBack)
    local n = 0
    for id, r in pairs(records) do
        if r.owner == identifier then
            despawn(id)
            records[id] = nil
            DeleteResourceKvp(PREFIX .. id)
            if giveBack and r.pair then Pending.Add(identifier, r.pair, false) end
            n = n + 1
        end
    end
    countAll()
    return n
end)
