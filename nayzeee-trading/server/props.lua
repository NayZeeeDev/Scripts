Props = { list = {}, inUse = {} }

local L = Config.Laptop

local function view(p)
    return { id = p.id, owner = p.owner, x = p.x, y = p.y, z = p.z, h = p.h }
end

local function near(src, p, range)
    local pc = GetEntityCoords(GetPlayerPed(src))
    return #(pc - vec3(p.x, p.y, p.z)) <= range
end

function Props.Init()
    for _, r in ipairs(DB.GetProps()) do
        Props.list[r.id] = { id = r.id, owner = r.owner, x = r.x, y = r.y, z = r.z, h = r.heading }
    end
end

function Props.Release(src)
    for id, user in pairs(Props.inUse) do
        if user == src then Props.inUse[id] = nil end
    end
end

lib.callback.register('nz_trading:props:list', function()
    local out = {}
    for _, p in pairs(Props.list) do out[#out + 1] = view(p) end
    return out
end)

lib.callback.register('nz_trading:props:place', function(src, coords, heading)
    local owner = Bridge.GetIdentifier(src)
    if not owner or type(coords) ~= 'vector3' or type(heading) ~= 'number' then return false end

    local pc = GetEntityCoords(GetPlayerPed(src))
    if #(pc - coords) > L.placeDistance + 1.5 then return false, 'Too far away' end

    local count = 0
    for _, p in pairs(Props.list) do
        if p.owner == owner then count = count + 1 end
    end
    if count >= L.maxPerPlayer then return false, ('You can only place %d laptops'):format(L.maxPerPlayer) end
    if not Bridge.RemoveItem(src, L.item) then return false, 'You need a trading laptop' end

    local id = DB.InsertProp(owner, coords.x, coords.y, coords.z, heading)
    if not id then
        Bridge.AddItem(src, L.item)
        return false, 'Could not place laptop'
    end
    local p = { id = id, owner = owner, x = coords.x, y = coords.y, z = coords.z, h = heading }
    Props.list[id] = p
    TriggerClientEvent('nz_trading:props:add', -1, view(p))
    return true
end)

lib.callback.register('nz_trading:props:use', function(src, id)
    local p = Props.list[id]
    if not p then return false, 'Laptop not found' end
    if not near(src, p, 3.0) then return false, 'Too far away' end
    local user = Props.inUse[id]
    if user and user ~= src and GetPlayerPing(user) > 0 then return false, 'Someone is using this laptop' end
    if not L.anyoneCanUse and p.owner ~= Bridge.GetIdentifier(src) then return false, 'This laptop is locked' end
    Props.inUse[id] = src
    return true
end)

RegisterNetEvent('nz_trading:props:release', function(id)
    if Props.inUse[id] == source then Props.inUse[id] = nil end
end)

lib.callback.register('nz_trading:props:pickup', function(src, id)
    local p = Props.list[id]
    if not p then return false, 'Laptop not found' end
    if not near(src, p, 3.0) then return false, 'Too far away' end
    if Props.inUse[id] and Props.inUse[id] ~= src then return false, 'Someone is using this laptop' end
    if not L.anyoneCanPickup and p.owner ~= Bridge.GetIdentifier(src) then return false, 'This is not your laptop' end
    if not Bridge.AddItem(src, L.item) then return false, 'Your inventory is full' end

    Props.list[id], Props.inUse[id] = nil, nil
    DB.DeleteProp(id)
    TriggerClientEvent('nz_trading:props:remove', -1, id)
    return true
end)

Bridge.RegisterUsable(L.item, function(src)
    TriggerClientEvent('nz_trading:client:placeLaptop', src)
end)

Bridge.RegisterUsable(Config.Tablet.item, function(src)
    TriggerClientEvent('nz_trading:client:useTablet', src)
end)

lib.callback.register('nz_trading:hasItem', function(src, item)
    if item ~= L.item and item ~= Config.Tablet.item then return false end
    return Bridge.HasItem(src, item)
end)

lib.callback.register('nz_trading:me', function(src)
    return Bridge.GetIdentifier(src)
end)
