--[[ Usable items, player placement, pick-up and the remote prop ]]

Items = {}

local function vec(c) return vector3(c.x, c.y, c.z) end

local function countOwned(ident)
    local n = 0
    for _, tv in pairs(TV.list) do if tv.owner == ident and not tv.permanent then n = n + 1 end end
    return n
end

function Items.use(src, item)
    local def = Config.Items[item]
    if def then
        local prop = Props.Get(def.model)
        if not prop then return print(('^1[nayzeee_tv] item %s uses unknown model %s^7'):format(item, def.model)) end
        TriggerClientEvent('nztv:place', src, { item = item, model = def.model, label = def.label or prop.label })
        return
    end
    if Config.Remote.Item and item == Config.Remote.Item then
        TriggerClientEvent('nztv:universalRemote', src)
    end
end

AddEventHandler('nztv:bridgeReady', function()
    for item in pairs(Config.Items) do
        Bridge.registerUsable(item, function(src) Items.use(src, item) end)
    end
    if Config.Remote.Item then
        Bridge.registerUsable(Config.Remote.Item, function(src) Items.use(src, Config.Remote.Item) end)
    end
end)

RPC.place = function(src, data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return false end
    local def = Config.Items[data.item]
    if not def then return false end
    local pc = Perms.playerCoords(src)
    if not pc or #(pc - vec(data.coords)) > Config.PlayerScreens.PlaceDistance + 2.0 then return false, 'too_far' end

    local ident = Bridge.identifier(src)
    if countOwned(ident) >= Config.PlayerScreens.MaxPerPlayer then return false, 'max_screens' end
    if not Bridge.hasItem(src, data.item) or not Bridge.removeItem(src, data.item, 1) then return false, 'no_item' end

    local remote
    if Config.Remote.Enabled and Config.Remote.AutoPlace and type(data.remote) == 'table' then
        if #(vec(data.remote) - vec(data.coords)) < 6.0 then
            remote = { x = data.remote.x + 0.0, y = data.remote.y + 0.0, z = data.remote.z + 0.0, h = (data.remote.h or 0.0) + 0.0 }
        end
    end

    local tv = TV.create({
        model = def.model, kind = 'prop', coords = data.coords, heading = data.heading, pitch = data.pitch, roll = data.roll,
        label = def.label, owner = ident, ownerName = Bridge.name(src), item = data.item, remote = remote,
        perms = { public = Config.PlayerScreens.DefaultPublic, jobs = {}, gangs = {}, allowed = {} },
    })
    TV.spawn(tv)
    return tv.id, 'placed'
end

RPC.pickup = function(src, id)
    local tv = TV.get(id)
    if not tv or not Perms.canManage(src, tv) then return false, 'no_permission' end
    if tv.permanent and not Perms.isAdmin(src) then return false, 'no_permission' end
    local pc = Perms.playerCoords(src)
    if not Perms.isAdmin(src) and (not pc or #(pc - vec(tv.coords)) > 5.0) then return false, 'too_far' end
    TV.remove(id)
    if tv.item and Config.PlayerScreens.PickupReturnsItem then Bridge.addItem(src, tv.item, 1) end
    return true, 'picked_up'
end

-- ─── remote prop ───────────────────────────────────────────────
RPC.remoteTake = function(src, id)
    local tv = TV.get(id)
    if not tv or not tv.remote then return false end
    if tv.remoteHolder and tv.remoteHolder ~= src then return false, 'remote_taken' end
    local ok, why = Perms.canControl(src, tv)
    if not ok then return false, why end
    local pc = Perms.playerCoords(src)
    if not pc or #(pc - vec(tv.remote)) > Config.Remote.PickupDistance + 1.5 then return false, 'too_far' end
    tv.remoteHolder = src
    TV.patch(tv, { 'remoteHolder' })
    return true
end

RPC.remoteDrop = function(src, id, coords, heading)
    local tv = TV.get(id)
    if not tv or tv.remoteHolder ~= src then return false end
    if type(coords) == 'table' then
        local pc = Perms.playerCoords(src)
        if pc and #(pc - vec(coords)) < 4.0 and #(vec(coords) - vec(tv.coords)) < Config.Remote.Range then
            tv.remote = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, h = (heading or 0.0) + 0.0 }
        end
    end
    tv.remoteHolder = nil
    TV.patch(tv, { 'remote', 'remoteHolder' })
    TV.save(tv)
    return true, 'remote_dropped'
end

--- Owner / admin places (or moves) the remote for a screen.
RPC.remotePlace = function(src, id, coords, heading)
    local tv = TV.get(id)
    if not tv or not Perms.canManage(src, tv) or type(coords) ~= 'table' then return false, 'no_permission' end
    if #(vec(coords) - vec(tv.coords)) > Config.Remote.Range then return false, 'too_far' end
    tv.remote = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, h = (heading or 0.0) + 0.0 }
    tv.remoteHolder = nil
    TV.patch(tv, { 'remote', 'remoteHolder' })
    TV.save(tv)
    return true, 'remote_dropped'
end
