--[[
    NAYZEEE AMBULANCE - Medical bag (server): bag storage, world bags, carry, access

    A medical bag is a storage container with an id ('MB-7K2QF'). The id lives in the medbag
    item's metadata, so the contents follow the bag from the ground to an inventory and back.
    Storage is server-side (table nza_bags), items move with Bridge.Inv (works with every
    inventory). Every move is validated here: viewer, distance (server coords), access, item
    rules, slot capacity, weight, rate limit and a per-bag lock.

    Bags on the ground are networked objects created by the SERVER (Entity state bag
    'nzaMedbag' = { id, owner (name), locked, name, colour }). A bag has a colour (one streamed model
    per colour, Config.Medbag.Bag.colours) and an optional name the owner sets in the window. A bag in someone's hand is a networked prop the
    carrier spawns and registers with a one-use token (nza:medbag:held). Ground bags survive a
    restart (Config.Medbag.Bag.persist).

    Table: nza_bags (id PK, owner, items LONGTEXT)  items = JSON { v, slots = { { s, n, c, m } },
           locked, ownerName, colour, name, world = { x, y, z, h, b } }

    Callbacks (lib.callback) - every reply is a table { ok = true, ... } | { ok = false, err, msg }
      nza:medbag:put (token|nil, coords, heading)   item → ground (token from the usable item) or hand → ground
      nza:medbag:open (id|nil)                      → { bag, me, kit = { { name, label, image, count } }, colours }
                                                     (nil id = the bag in your hand; kit = the par list)
      nza:medbag:move (id, { dir = 'in'|'out'|'bag', from, to?, count = n|'all', name })
                                                     → { bag, me, moved = { name, label, image, count, dir } }
      nza:medbag:action (id, 'sort'|'lock'|'kit'|'empty'|'style', data) → { bag, me, movedList = { ... }, msg }
                                                     style: { name, colour } (owner / admin; colour from Config.Medbag.Bag.colours)
      nza:medbag:carry (id)                         ground → hand  → { token, models }
      nza:medbag:held (token, net)                  register the hand prop
      nza:medbag:pickup (id)                        ground → inventory
      nza:medbag:stow ()                            hand → inventory
      nza:medbag:me ()                              → your pockets view (while a bag is open)
    Net events
      C→S nza:medbag:close (id)                     the window was closed
      S→C nza:medbag:place (token)                  the item was used: put a bag down in front of you
      S→C nza:medbag:sync (id, bagView, { moved, by }|nil)   another viewer changed the bag
      S→C nza:medbag:closed (id, reason)            close the window (gone / far / access / down)
      S→C nza:medbag:carryEnd ()                    the server took the bag out of your hand
    Bus (server) emitted: medbag:placed (src, id), medbag:picked (src, id), medbag:moved (src, id, moved)
    Shared helpers for medbag_body.lua: NZA.Medbag.SpawnObject, DeleteNet, HandsFull, Fail, L, Cfg
    Exports: GetMedbagContents(id) → { { name, count, metadata } } | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Medbag = NZA.Medbag or {}
local MB = NZA.Medbag

MB.bags    = MB.bags or {}     -- [id] = { id, owner, ownerName, slots = { [slot] = entry }, locked, world, dirty }
MB.world   = MB.world or {}    -- [id] = { ent, net, coords = vector3, heading, bucket, by }
MB.carry   = MB.carry or {}    -- [src] = id (bag in the hand)
MB.held    = MB.held or {}     -- [src] = { kind = 'medbag'|'body', id, token, net, at }
MB.viewers = MB.viewers or {}  -- [id] = { [src] = true }
MB.viewing = MB.viewing or {}  -- [src] = id
MB.lastPos = MB.lastPos or {}  -- [src] = { coords, heading, bucket }

local pendingPlace = {}        -- [src] = { token, bagId, slot, meta, at }
local locks = {}
local infoCache = {}
local ownItems = nil

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function C(section)
    local c = Config.Medbag or {}
    if not section then return c end
    return c[section] or {}
end
MB.Cfg = C

local function L(key, ...) return NZA.L('medbag.' .. key, ...) end
MB.L = L

local function fail(err, ...)
    return { ok = false, err = err, msg = L('err_' .. err, ...) }
end
MB.Fail = fail

local function online(src) return NZA.Core.Online(src) end

local function rate(src, bucket, n, ms)
    return NZA.Core.Rate('medbag:' .. bucket, src, n, ms)
end

local function ped(src)
    local p = GetPlayerPed(src)
    if not p or p == 0 or not DoesEntityExist(p) then return 0 end
    return p
end

local function srcCoords(src)
    local p = ped(src)
    if p == 0 then return nil end
    return GetEntityCoords(p)
end

local function v3(t)
    if type(t) == 'vector3' or type(t) == 'vector4' then return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
    if type(t) ~= 'table' then return nil end
    local x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
    if not x or not y or not z then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end
MB.V3 = v3

local function playerAlive(src)
    local p = NZA.Patients and NZA.Patients.GetBySource(src)
    return not p or p.state == 'alive'
end
MB.PlayerAlive = playerAlive

local function inVehicle(src)
    local p = ped(src)
    return p ~= 0 and GetVehiclePedIsIn(p, false) ~= 0
end
MB.InVehicle = inVehicle

local function bucketOf(src)
    local ok, b = pcall(GetPlayerRoutingBucket, src)
    return ok and tonumber(b) or 0
end
MB.BucketOf = bucketOf

local function notify(src, msg, kind)
    NZA.Core.Notify(src, msg, kind or 'info', L('title'))
end

local function itemName() return Config.Items and Config.Items.medbag or 'medbag' end

local function colourList()
    local c = C('Bag').colours
    return type(c) == 'table' and c or {}
end

local function colourOf(id)
    for _, c in ipairs(colourList()) do if c.id == id then return c end end
    return nil
end

local function baseModel()
    return C('Bag').model or (Config.Props and Config.Props.medbag) or 'nz_amb_medbag'
end

-- every model that counts as a medical bag (colours, base, fallback, extras)
local function bagModels()
    local b = C('Bag')
    local list, seen = {}, {}
    local function add(m) if type(m) == 'string' and not seen[m] then seen[m] = true list[#list + 1] = m end end
    add(baseModel())
    for _, c in ipairs(colourList()) do add(c.model) end
    add(Config.PropFallbacks and Config.PropFallbacks.medbag)
    for _, m in ipairs(b.extraModels or {}) do add(m) end
    return list
end
MB.BagModels = bagModels

-- the model of one bag (its colour)
local function modelFor(bag)
    local c = bag and colourOf(bag.colour)
    return (c and c.model) or baseModel()
end
MB.ModelFor = modelFor

local function modelOk(ent, models)
    local h = GetEntityModel(ent)
    for _, m in ipairs(models) do
        local mh = type(m) == 'number' and m or joaat(m)
        if h == mh or (h % 4294967296) == (mh % 4294967296) then return true end
    end
    return false
end
MB.ModelOk = modelOk

function MB.HandsFull(src)
    if MB.carry[src] then return true end
    if MB.BodyCarrying and MB.BodyCarrying(src) then return true end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- WORLD OBJECTS (server-created, OneSync)
-- ════════════════════════════════════════════════════════════════════════

-- → entity, netId (0, nil on failure). Call from a thread / callback.
function MB.SpawnObject(model, coords, heading, bucket, opts)
    opts = opts or {}
    local hash = type(model) == 'number' and model or joaat(model)
    local ent = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, true, true, false)
    local t = GetGameTimer()
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and GetGameTimer() - t < 3000 do Wait(0) end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return 0, nil end
    SetEntityHeading(ent, (tonumber(heading) or 0.0) + 0.0)
    FreezeEntityPosition(ent, opts.freeze ~= false)
    if bucket and bucket ~= 0 then SetEntityRoutingBucket(ent, bucket) end
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, ent, 2) end
    local net = NetworkGetNetworkIdFromEntity(ent)
    return ent, net
end

function MB.DeleteEnt(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
end

function MB.DeleteNet(net)
    net = tonumber(net)
    if not net then return end
    local ent = NetworkGetEntityFromNetworkId(net)
    MB.DeleteEnt(ent)
end

function MB.EntFromNet(net)
    net = tonumber(net)
    if not net then return 0 end
    local ent = NetworkGetEntityFromNetworkId(net)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return 0 end
    return ent
end

-- ════════════════════════════════════════════════════════════════════════
-- ITEMS: rules, weights, labels
-- ════════════════════════════════════════════════════════════════════════

local function buildOwnItems()
    ownItems = {}
    for _, name in pairs(Config.Items or {}) do ownItems[name] = true end
end

local function allowed(name)
    if type(name) ~= 'string' or name == '' then return false end
    local s = C('Storage')
    if name == itemName() then return false end
    if s.blockWeapons ~= false and name:upper():sub(1, 7) == 'WEAPON_' then return false end
    for _, b in ipairs(s.blocked or {}) do if b == name then return false end end
    if s.mode == 'all' then return true end
    if not ownItems then buildOwnItems() end
    if ownItems[name] then return true end
    for _, e in ipairs(s.extra or {}) do if e == name then return true end end
    return false
end
MB.Allowed = allowed

local function itemDef(name)
    return Bridge and Bridge.ItemDef and Bridge.ItemDef(name) or nil
end

local function unitWeight(name, raw, count)
    local s = C('Storage')
    if s.weights and tonumber(s.weights[name]) then return tonumber(s.weights[name]) end
    local def = itemDef(name)
    if def and tonumber(def.weight) then return tonumber(def.weight) end
    raw = tonumber(raw)
    if raw and raw > 0 then
        local res = NZA.Core.B('Inv.Resource')
        if res == 'ox_inventory' and count and count > 0 then return raw / count end
        return raw
    end
    return tonumber(s.defaultWeight) or 100
end

local function capFor(name)
    local def = itemDef(name)
    if def and def.stack == false then return 1 end
    return math.max(1, math.floor(tonumber(C('Storage').maxStack) or 50))
end

local function info(name)
    local c = infoCache[name]
    if c then return c end
    local def = itemDef(name)
    c = {
        label = NZA.Core.B('Inv.Label', name) or (def and def.label) or name,
        image = NZA.Core.B('Inv.Image', name) or '',
        desc = def and def.description or nil,
        cat = def and def.category or 'other',
    }
    infoCache[name] = c
    return c
end

-- canonical string of a metadata table (stack identity)
local function canon(v, depth)
    depth = depth or 0
    if type(v) ~= 'table' then return tostring(v) end
    if depth > 4 then return '{}' end
    local list = {}
    for k, val in pairs(v) do list[#list + 1] = { tostring(k), val } end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = e[1] .. '=' .. canon(e[2], depth + 1) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function cleanMeta(meta)
    if type(meta) ~= 'table' or next(meta) == nil then return nil end
    return meta
end

-- up to 4 short metadata lines for tooltips
local SKIP_META = { image = true, imageurl = true, label = true, weight = true, durability = true, ammo = true, components = true }
local function metaLines(meta)
    if type(meta) ~= 'table' then return nil end
    local out = {}
    if type(meta.description) == 'string' and #meta.description <= 80 then out[#out + 1] = { v = meta.description } end
    local keys = {}
    for k, v in pairs(meta) do
        if type(k) == 'string' and k ~= 'description' and not SKIP_META[k] and k:sub(1, 1) ~= '_' and (type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean') then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if #out >= 4 then break end
        local v = meta[k]
        if type(v) == 'string' and #v > 40 then v = v:sub(1, 38) .. '…' end
        out[#out + 1] = { k = k, v = tostring(v) }
    end
    return #out > 0 and out or nil
end

-- ════════════════════════════════════════════════════════════════════════
-- BAG RECORDS & PERSISTENCE
-- ════════════════════════════════════════════════════════════════════════

local ID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function genId()
    local t = {}
    for i = 1, 5 do
        local n = math.random(1, #ID_CHARS)
        t[i] = ID_CHARS:sub(n, n)
    end
    return 'MB-' .. table.concat(t)
end

local function slotCount(bag)
    local n = math.max(1, math.floor(tonumber(C('Storage').slots) or 20))
    for slot in pairs(bag.slots) do if slot > n then n = slot end end
    return n
end

local function encode(bag)
    local slots = {}
    for slot, e in pairs(bag.slots) do slots[#slots + 1] = { s = slot, n = e.name, c = e.count, m = e.meta } end
    table.sort(slots, function(a, b) return a.s < b.s end)
    return json.encode({ v = 1, slots = slots, locked = bag.locked or nil, ownerName = bag.ownerName, world = bag.world,
        colour = bag.colour, name = bag.name })
end

local function decode(id, owner, raw)
    local data = type(raw) == 'string' and json.decode(raw) or nil
    if type(data) ~= 'table' then data = {} end
    local bag = { id = id, owner = owner, ownerName = data.ownerName, slots = {}, locked = data.locked == true, world = data.world,
        colour = type(data.colour) == 'string' and data.colour or nil, name = type(data.name) == 'string' and data.name or nil }
    for _, e in ipairs(data.slots or {}) do
        local slot, name, count = tonumber(e.s), e.n, math.floor(tonumber(e.c) or 0)
        if slot and slot >= 1 and type(name) == 'string' and count > 0 then
            local meta = cleanMeta(e.m)
            bag.slots[slot] = { name = name, count = count, meta = meta, mk = meta and canon(meta) or '' }
        end
    end
    return bag
end

local function save(bag)
    bag.dirty = true
end
MB.Touch = save

local function flush(bag)
    bag.dirty = false
    MySQL.insert('INSERT INTO nza_bags (id, owner, items) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items), owner = VALUES(owner)',
        { bag.id, bag.owner or '', encode(bag) })
end

function MB.Load(id)
    if type(id) ~= 'string' or #id > 32 then return nil end
    local bag = MB.bags[id]
    if bag then return bag end
    local ok, row = pcall(MySQL.single.await, 'SELECT owner, items FROM nza_bags WHERE id = ?', { id })
    if not ok or not row then return nil end
    bag = MB.bags[id] or decode(id, row.owner, row.items)
    MB.bags[id] = bag
    return bag
end

function MB.Create(src, wanted)
    local id = type(wanted) == 'string' and #wanted <= 32 and wanted or nil
    if id and MB.bags[id] then id = nil end
    local tries = 0
    while not id and tries < 20 do
        tries = tries + 1
        local cand = genId()
        if not MB.bags[cand] then
            local ok, row = pcall(MySQL.scalar.await, 'SELECT id FROM nza_bags WHERE id = ?', { cand })
            if ok and not row then id = cand end
        end
    end
    if not id then return nil end
    local bag = { id = id, owner = NZA.Core.Identifier(src), ownerName = NZA.Core.Name(src), slots = {}, locked = false,
        colour = C('Bag').defaultColour }
    MB.bags[id] = bag
    flush(bag)
    return bag
end

local function bagWeight(bag)
    local w = 0
    for _, e in pairs(bag.slots) do w = w + unitWeight(e.name) * e.count end
    return w
end

local function bagStats(bag)
    local n, items = 0, 0
    for _, e in pairs(bag.slots) do n = n + 1; items = items + e.count end
    return n, items
end

local function itemMeta(bag)
    local _, items = bagStats(bag)
    local meta = { bagId = bag.id, description = L('item_desc', bag.id, items, bagWeight(bag) / 1000) }
    if bag.name and bag.name ~= '' then
        meta.label = bag.name
        meta.description = bag.name .. ' · ' .. meta.description
    end
    if bag.colour then meta.colour = bag.colour end
    return meta
end
MB.ItemMeta = itemMeta

-- ════════════════════════════════════════════════════════════════════════
-- ACCESS
-- ════════════════════════════════════════════════════════════════════════

local function staff(src)
    local ok, r = pcall(NZA.Staff.Get, src)
    return ok and type(r) == 'table' and r or {}
end

local function onDutyRec(rec)
    if Config.Jobs and Config.Jobs.requireDuty == false then return true end
    return rec.onDuty == true or rec.ignoreDuty == true
end

function MB.IsOwner(src, bag)
    local me = NZA.Core.Identifier(src)
    return me ~= nil and bag.owner ~= nil and bag.owner ~= '' and bag.owner == me
end

function MB.CanAccess(src, bag)
    local a = C('Access')
    if a.admins ~= false and NZA.Core.IsAdmin(src) then return true end
    local owner = MB.IsOwner(src, bag)
    if bag.locked and a.lock ~= false then
        if owner then return true end
        return false, 'locked'
    end
    if owner and a.owner ~= false then return true end
    if a.anyone then return true end
    local rec = staff(src)
    if a.medics ~= false and rec.medic and onDutyRec(rec) then
        if not a.perm or a.perm == '' or NZA.Staff.Can(src, a.perm) then return true end
    end
    if a.police and rec.police and onDutyRec(rec) then return true end
    return false, 'no_access'
end

local function accessFail(why, bag)
    if why == 'locked' then return fail('locked', bag.ownerName or '?') end
    return fail('no_access')
end

-- where the bag is now (vector3) or nil
function MB.BagPos(id)
    local w = MB.world[id]
    if w then
        if w.ent and DoesEntityExist(w.ent) then return GetEntityCoords(w.ent) end
        return w.coords
    end
    for src, bid in pairs(MB.carry) do
        if bid == id then return srcCoords(src) or (MB.lastPos[src] and MB.lastPos[src].coords) end
    end
    return nil
end

local function carrierOf(id)
    for src, bid in pairs(MB.carry) do if bid == id then return src end end
    return nil
end

local function nearBag(src, id, range)
    if MB.carry[src] == id then return true end
    local pos, me = MB.BagPos(id), srcCoords(src)
    if not pos or not me then return false end
    return #(pos - me) <= range
end

-- ════════════════════════════════════════════════════════════════════════
-- VIEWS (what the NUI gets)
-- ════════════════════════════════════════════════════════════════════════

function MB.BagView(bag, src)
    local items = {}
    local max = slotCount(bag)
    for slot = 1, max do
        local e = bag.slots[slot]
        if e then
            local i = info(e.name)
            items[#items + 1] = {
                slot = slot, name = e.name, label = i.label, image = i.image, count = e.count,
                weight = unitWeight(e.name), desc = i.desc, cat = i.cat, meta = metaLines(e.meta),
            }
        end
    end
    local mine = src and MB.IsOwner(src, bag) or false
    local col = colourOf(bag.colour)
    return {
        id = bag.id, owner = bag.ownerName, mine = mine, locked = bag.locked == true,
        name = bag.name, colour = col and col.id or nil, hex = col and col.hex or nil,
        canStyle = mine or (src and NZA.Core.IsAdmin(src)) or false,
        canLock = mine and C('Access').lock ~= false or (src and NZA.Core.IsAdmin(src) and bag.locked) or false,
        slots = max, items = items, weight = bagWeight(bag),
        maxWeight = tonumber(C('Storage').maxWeight) or 18000,
        held = src and MB.carry[src] == bag.id or false,
    }
end

local function personalMax(src, used)
    local s = C('Storage')
    local setting = s.personalMax
    if setting == false then return nil, used end
    if type(setting) == 'number' then return setting, used end
    local fallback = tonumber(s.personalFallback) or 30000
    if GetResourceState('ox_inventory') == 'started' then
        local ok, inv = pcall(function() return exports.ox_inventory:GetInventory(src, false) end)
        if ok and type(inv) == 'table' and tonumber(inv.maxWeight) then
            return tonumber(inv.maxWeight), tonumber(inv.weight) or used
        end
    end
    if GetResourceState('qb-core') == 'started' and GetResourceState('qbx_core') ~= 'started' then
        local ok, mw = pcall(function()
            local QB = exports['qb-core']:GetCoreObject()
            return QB and QB.Config and QB.Config.Player and QB.Config.Player.MaxWeight
        end)
        if ok and tonumber(mw) then return tonumber(mw), used end
    end
    if GetResourceState('es_extended') == 'started' then
        local ok, mw = pcall(function()
            local ESX = exports.es_extended:getSharedObject()
            local xp = ESX and ESX.GetPlayerFromId(src)
            if not xp then return nil end
            if xp.getMaxWeight then return xp.getMaxWeight() end
            return xp.maxWeight
        end)
        if ok and tonumber(mw) then
            mw = tonumber(mw)
            if mw < 1000 then mw = mw * 1000 end   -- ESX limits written in kg
            return mw, used
        end
    end
    return fallback, used
end

function MB.MeView(src)
    local list = NZA.Core.B('Inv.GetItems', src) or {}
    local items, total = {}, 0
    for _, it in ipairs(list) do
        local count = tonumber(it.count) or 0
        if count > 0 and type(it.name) == 'string' then
            local i = info(it.name)
            local per = unitWeight(it.name, it.weight, count)
            total = total + per * count
            local ok = allowed(it.name)
            items[#items + 1] = {
                slot = it.slot, name = it.name, label = it.label or i.label, image = i.image, count = count,
                weight = per, desc = i.desc, cat = i.cat, meta = metaLines(it.metadata),
                allowed = ok,
            }
        end
    end
    local max, used = personalMax(src, total)
    return { items = items, weight = used or total, maxWeight = max }
end

-- ════════════════════════════════════════════════════════════════════════
-- VIEWERS
-- ════════════════════════════════════════════════════════════════════════

local function addViewer(src, id)
    local old = MB.viewing[src]
    if old and old ~= id and MB.viewers[old] then MB.viewers[old][src] = nil end
    MB.viewing[src] = id
    MB.viewers[id] = MB.viewers[id] or {}
    MB.viewers[id][src] = true
end

local function removeViewer(src)
    local id = MB.viewing[src]
    MB.viewing[src] = nil
    if id and MB.viewers[id] then
        MB.viewers[id][src] = nil
        if next(MB.viewers[id]) == nil then MB.viewers[id] = nil end
    end
end

local function kick(src, reason)
    local id = MB.viewing[src]
    removeViewer(src)
    if id then TriggerClientEvent('nza:medbag:closed', src, id, reason) end
end

local function kickAll(id, reason, except)
    for s in pairs(MB.viewers[id] or {}) do
        if s ~= except then kick(s, reason) end
    end
end
MB.KickAll = kickAll

local function syncViewers(bag, except, moved)
    local extra = nil
    if moved and except then extra = { moved = moved, by = NZA.Core.Name(except) } end
    for s in pairs(MB.viewers[bag.id] or {}) do
        if s ~= except then TriggerClientEvent('nza:medbag:sync', s, bag.id, MB.BagView(bag, s), extra) end
    end
end

local function worldState(bag)
    local w = MB.world[bag.id]
    if not w or not w.ent or not DoesEntityExist(w.ent) then return end
    Entity(w.ent).state:set('nzaMedbag', { id = bag.id, owner = bag.ownerName, locked = bag.locked == true,
        name = bag.name, colour = bag.colour }, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- PLACE / CARRY / PICK UP
-- ════════════════════════════════════════════════════════════════════════

local function placeWorld(bag, coords, heading, bucket, by, opts)
    local ent, net = MB.SpawnObject(modelFor(bag), coords, heading, bucket, opts)
    if ent == 0 then return false end
    MB.world[bag.id] = { ent = ent, net = net, coords = coords, heading = heading, bucket = bucket, by = by }
    bag.world = { x = coords.x, y = coords.y, z = coords.z, h = heading, b = bucket ~= 0 and bucket or nil }
    save(bag)
    worldState(bag)
    return true, net
end
MB.PlaceWorld = placeWorld

local function removeWorld(id)
    local w = MB.world[id]
    MB.world[id] = nil
    if w then MB.DeleteEnt(w.ent) end
    local bag = MB.bags[id]
    if bag then
        bag.world = nil
        save(bag)
    end
end

local function deleteHeld(src)
    local h = MB.held[src]
    MB.held[src] = nil
    if h and h.net then MB.DeleteNet(h.net) end
end
MB.DeleteHeld = deleteHeld

local function countOut(src)
    local me = NZA.Core.Identifier(src)
    local n = 0
    for _, w in pairs(MB.world) do if w.by and w.by == me then n = n + 1 end end
    return n
end

local function validSpot(src, coords)
    local me = srcCoords(src)
    if not me or not coords then return false end
    local flat = #(vector2(me.x, me.y) - vector2(coords.x, coords.y))
    return flat <= 3.0 and math.abs(me.z - coords.z) <= 2.6
end

-- server fallback when nobody can tell us where the ground is: drop with physics
local function dropAt(bag, coords, heading, bucket)
    local ok = placeWorld(bag, vector3(coords.x, coords.y, coords.z + 0.25), heading or 0.0, bucket or 0, nil, { freeze = false })
    if not ok then return false end
    local id = bag.id
    SetTimeout(4000, function()
        local w = MB.world[id]
        if not w or not w.ent or not DoesEntityExist(w.ent) then return end
        FreezeEntityPosition(w.ent, true)
        w.coords = GetEntityCoords(w.ent)
        local b = MB.bags[id]
        if b then
            b.world = { x = w.coords.x, y = w.coords.y, z = w.coords.z, h = w.heading, b = w.bucket ~= 0 and w.bucket or nil }
            save(b)
        end
    end)
    return true
end

-- the carrier can't put it down themselves (dropped, went down without answering)
function MB.ForceDrop(src, reason)
    local id = MB.carry[src]
    if not id then return end
    MB.carry[src] = nil
    deleteHeld(src)
    local bag = MB.bags[id]
    local last = MB.lastPos[src]
    local pos = srcCoords(src) or (last and last.coords)
    if bag and pos then
        dropAt(bag, pos, last and last.heading or 0.0, last and last.bucket or 0)
    elseif bag then
        NZA.Warn(('medbag %s had no position to drop at (kept in storage)'):format(id))
    end
    if online(src) then
        TriggerClientEvent('nza:medbag:carryEnd', src)
        if reason ~= 'silent' then notify(src, L('dropped'), 'warning') end
    end
end

lib.callback.register('nza:medbag:put', function(src, token, coords, heading)
    if not rate(src, 'put', 3, 2000) then return fail('rate') end
    if not playerAlive(src) then return fail('down') end
    if inVehicle(src) then return fail('vehicle') end
    coords = v3(coords)
    heading = tonumber(heading) or 0.0
    if not coords or not validSpot(src, coords) then return fail('bad_spot') end
    local bucket = bucketOf(src)

    if token ~= nil then
        local pend = pendingPlace[src]
        if not pend or pend.token ~= token or os.time() - pend.at > 20 then return fail('no_item') end
        pendingPlace[src] = nil
        if MB.HandsFull(src) then return fail('carrying') end
        local name = itemName()
        local bagId = pend.bagId
        if bagId and (MB.world[bagId] or carrierOf(bagId)) then return fail('already_out') end
        local maxOut = tonumber(C('Bag').maxOut) or 0
        if maxOut > 0 and countOut(src) >= maxOut then return fail('max_out', maxOut) end

        -- the item must still be there
        local slot = pend.slot
        if slot then
            local it = NZA.Core.B('Inv.GetSlot', src, slot)
            local itBag = it and type(it.metadata) == 'table' and it.metadata.bagId or nil
            if not it or it.name ~= name or itBag ~= bagId then slot = nil end
        end
        if not slot then
            local have = NZA.Core.B('Inv.Count', src, name, bagId and { bagId = bagId } or nil) or 0
            if have < 1 then return fail('no_item') end
        end
        local removed = NZA.Core.B('Inv.RemoveItem', src, name, 1, (not slot and bagId) and { bagId = bagId } or nil, slot)
        if not removed then return fail('no_item') end

        local bag = bagId and MB.Load(bagId) or nil
        if not bag then bag = MB.Create(src, bagId) end
        if not bag then
            NZA.Core.B('Inv.AddItem', src, name, 1, pend.meta)
            return fail('failed')
        end
        if not bag.ownerName or bag.ownerName == '' then bag.ownerName = NZA.Core.Name(src) end
        local ok, net = placeWorld(bag, coords, heading, bucket, NZA.Core.Identifier(src))
        if not ok then
            NZA.Core.B('Inv.AddItem', src, name, 1, itemMeta(bag))
            return fail('failed')
        end
        NZA.Bus.Emit('medbag:placed', src, bag.id)
        return { ok = true, id = bag.id, net = net, msg = L('ok_placed') }
    end

    -- from the hand
    local id = MB.carry[src]
    if not id then return fail('not_carrying') end
    local bag = MB.bags[id]
    if not bag then
        MB.carry[src] = nil
        deleteHeld(src)
        return fail('no_bag')
    end
    local ok, net = placeWorld(bag, coords, heading, bucket, NZA.Core.Identifier(src))
    if not ok then return fail('failed') end
    MB.carry[src] = nil
    deleteHeld(src)
    NZA.Bus.Emit('medbag:placed', src, id)
    return { ok = true, id = id, net = net, msg = L('ok_placed') }
end)

lib.callback.register('nza:medbag:carry', function(src, id)
    if not rate(src, 'carry', 3, 2000) then return fail('rate') end
    if C('Bag').Carry and C('Bag').Carry.enabled == false then return fail('failed') end
    if MB.HandsFull(src) then return fail('carrying') end
    if not playerAlive(src) then return fail('down') end
    if inVehicle(src) then return fail('vehicle') end
    local bag = type(id) == 'string' and MB.bags[id] or nil
    if not bag or not MB.world[id] then return fail('no_bag') end
    if not nearBag(src, id, (tonumber(C('Bag').distance) or 2.0) + 1.5) then return fail('too_far') end
    local okA, why = MB.CanAccess(src, bag)
    if not okA then return accessFail(why, bag) end
    removeWorld(id)
    MB.carry[src] = id
    local token = NZA.Util.uid('mbh')
    MB.held[src] = { kind = 'medbag', id = id, token = token, at = os.time() }
    local models = { modelFor(bag) }
    for _, m in ipairs(bagModels()) do if m ~= models[1] then models[#models + 1] = m end end
    return { ok = true, id = id, token = token, models = models }
end)

lib.callback.register('nza:medbag:held', function(src, token, net)
    local h = MB.held[src]
    if not h or h.token ~= token or h.net then return fail('failed') end
    local ent = MB.EntFromNet(net)
    if ent == 0 then return fail('failed') end
    local models = h.kind == 'body' and MB.BodyModels and MB.BodyModels() or bagModels()
    if not modelOk(ent, models) then return fail('failed') end
    local me = srcCoords(src)
    if not me or #(GetEntityCoords(ent) - me) > 6.0 then return fail('too_far') end
    h.net = tonumber(net)
    if h.kind == 'body' and MB.BodyHeld then MB.BodyHeld(src, h) end
    return { ok = true }
end)

lib.callback.register('nza:medbag:pickup', function(src, id)
    if not rate(src, 'pickup', 3, 2000) then return fail('rate') end
    if not playerAlive(src) then return fail('down') end
    if inVehicle(src) then return fail('vehicle') end
    local bag = type(id) == 'string' and MB.bags[id] or nil
    if not bag or not MB.world[id] then return fail('no_bag') end
    if not nearBag(src, id, (tonumber(C('Bag').distance) or 2.0) + 1.5) then return fail('too_far') end
    local okA, why = MB.CanAccess(src, bag)
    if not okA then return accessFail(why, bag) end
    local name = itemName()
    if NZA.Core.B('Inv.CanCarry', src, name, 1) == false then return fail('pockets_full') end
    -- lock the bag so nobody moves items while it is packed away
    if locks[id] then return fail('busy') end
    locks[id] = true
    local added = NZA.Core.B('Inv.AddItem', src, name, 1, itemMeta(bag))
    locks[id] = nil
    if not added then return fail('pockets_full') end
    removeWorld(id)
    kickAll(id, 'gone')
    NZA.Bus.Emit('medbag:picked', src, id)
    return { ok = true, msg = L('ok_picked') }
end)

lib.callback.register('nza:medbag:stow', function(src)
    if not rate(src, 'stow', 3, 2000) then return fail('rate') end
    local id = MB.carry[src]
    if not id then return fail('not_carrying') end
    local bag = MB.bags[id]
    if not bag then
        MB.carry[src] = nil
        deleteHeld(src)
        return fail('no_bag')
    end
    local name = itemName()
    if NZA.Core.B('Inv.CanCarry', src, name, 1) == false then return fail('pockets_full') end
    if locks[id] then return fail('busy') end
    locks[id] = true
    local added = NZA.Core.B('Inv.AddItem', src, name, 1, itemMeta(bag))
    locks[id] = nil
    if not added then return fail('pockets_full') end
    MB.carry[src] = nil
    deleteHeld(src)
    kickAll(id, 'gone')
    NZA.Bus.Emit('medbag:picked', src, id)
    return { ok = true, msg = L('ok_picked') }
end)

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE
-- ════════════════════════════════════════════════════════════════════════

function MB.ColourView()
    local out = {}
    for _, c in ipairs(colourList()) do out[#out + 1] = { id = c.id, hex = c.hex, label = L('colour_' .. c.id) } end
    return out
end

-- the par list (restock targets) as the window shows it; only items a bag may hold
local function kitView()
    local out, seen = {}, {}
    for _, k in ipairs(C('Storage').kit or {}) do
        local name, count = k.item, math.floor(tonumber(k.count) or 0)
        if type(name) == 'string' and count > 0 and allowed(name) and not seen[name] then
            seen[name] = true
            local i = info(name)
            out[#out + 1] = { name = name, label = i.label, image = i.image, count = count }
        end
    end
    return out
end

lib.callback.register('nza:medbag:open', function(src, id)
    if not rate(src, 'open', 4, 2000) then return fail('rate') end
    if not playerAlive(src) then return fail('down') end
    if id == nil then id = MB.carry[src] end
    local bag = type(id) == 'string' and MB.bags[id] or nil
    if not bag or not (MB.world[id] or carrierOf(id)) then return fail('no_bag') end
    local carrier = carrierOf(id)
    if carrier and carrier ~= src then return fail('held') end
    if not nearBag(src, id, (tonumber(C('Bag').distance) or 2.0) + 1.5) then return fail('too_far') end
    local okA, why = MB.CanAccess(src, bag)
    if not okA then return accessFail(why, bag) end
    addViewer(src, id)
    return { ok = true, bag = MB.BagView(bag, src), me = MB.MeView(src), kit = kitView(), colours = MB.ColourView() }
end)

-- pockets refresh while the window is open (items that arrived from elsewhere)
lib.callback.register('nza:medbag:me', function(src)
    if not MB.viewing[src] then return nil end
    if not rate(src, 'me', 2, 2000) then return nil end
    return MB.MeView(src)
end)

RegisterNetEvent('nza:medbag:close', function()
    removeViewer(source)
end)

-- ════════════════════════════════════════════════════════════════════════
-- MOVES
-- ════════════════════════════════════════════════════════════════════════

local function withLock(id, fn)
    local t = GetGameTimer()
    while locks[id] do
        if GetGameTimer() - t > 2500 then return fail('busy') end
        Wait(15)
    end
    locks[id] = true
    local ok, res = pcall(fn)
    locks[id] = nil
    if not ok then
        NZA.Warn(('medbag move failed: %s'):format(tostring(res)))
        return fail('failed')
    end
    return res
end

-- plan where `count` units of (name, meta) go → { { slot, add } }, units that fit
local function plan(bag, name, mk, count, to, exclude)
    local cap = capFor(name)
    local max = math.max(1, math.floor(tonumber(C('Storage').slots) or 20))
    local out, left, used = {}, count, {}
    local function try(slot)
        if left <= 0 or used[slot] or slot == exclude or slot < 1 or slot > max then return end
        local e = bag.slots[slot]
        local room = 0
        if not e then room = cap
        elseif e.name == name and e.mk == mk then room = cap - e.count end
        if room > 0 then
            local add = math.min(room, left)
            out[#out + 1] = { slot = slot, add = add }
            used[slot] = true
            left = left - add
        end
    end
    if to then try(to) end
    for slot = 1, max do
        local e = bag.slots[slot]
        if e and e.name == name and e.mk == mk then try(slot) end
    end
    for slot = 1, max do
        if not bag.slots[slot] then try(slot) end
    end
    return out, count - left
end

local function apply(bag, name, meta, mk, list)
    for _, p in ipairs(list) do
        local e = bag.slots[p.slot]
        if e then e.count = e.count + p.add
        else bag.slots[p.slot] = { name = name, count = p.add, meta = meta, mk = mk } end
    end
end

local function weightRoom(bag, name)
    local uw = unitWeight(name)
    if uw <= 0 then return math.huge end
    local room = (tonumber(C('Storage').maxWeight) or 18000) - bagWeight(bag)
    return math.max(0, math.floor((room + 0.0001) / uw))
end

local function movedInfo(name, count, dir)
    local i = info(name)
    return { name = name, label = i.label, image = i.image, count = count, dir = dir }
end

local function wantCount(raw, have)
    if raw == 'all' then return have end
    local n = math.floor(tonumber(raw) or 1)
    if n < 1 then n = 1 end
    return math.min(n, have)
end

-- pockets → bag
local function deposit(src, bag, data)
    local from = tonumber(data.from)
    if not from then return fail('empty_slot') end
    local it = NZA.Core.B('Inv.GetSlot', src, from)
    if not it or (tonumber(it.count) or 0) < 1 then return fail('changed') end
    if data.name and it.name ~= data.name then return fail('changed') end
    local name = it.name
    if not allowed(name) then return fail('not_allowed', info(name).label) end
    local meta = cleanMeta(it.metadata)
    local mk = meta and canon(meta) or ''
    local want = wantCount(data.count, tonumber(it.count) or 1)
    local wfit = weightRoom(bag, name)
    if wfit < 1 then return fail('heavy', ('%.1f %s'):format((tonumber(C('Storage').maxWeight) or 18000) / 1000, L('ui_kg'))) end
    local n = math.min(want, wfit)
    local list, fits = plan(bag, name, mk, n, tonumber(data.to))
    if fits < 1 then return fail('full') end
    n = fits
    local removed = NZA.Core.B('Inv.RemoveItem', src, name, n, meta, from)
    if not removed then return fail('remove') end
    apply(bag, name, meta, mk, list)
    return { ok = true, moved = movedInfo(name, n, 'in') }
end

-- bag → pockets
local function withdraw(src, bag, data)
    local from = tonumber(data.from)
    local e = from and bag.slots[from]
    if not e then return fail('empty_slot') end
    if data.name and e.name ~= data.name then return fail('changed') end
    local n = wantCount(data.count, e.count)
    -- largest amount the inventory takes
    local tries = 0
    while n > 0 and NZA.Core.B('Inv.CanCarry', src, e.name, n) == false and tries < 6 do
        n = (n > 1) and math.floor(n / 2) or 0
        tries = tries + 1
    end
    if n < 1 then return fail('pockets_full') end
    local name, meta = e.name, e.meta
    e.count = e.count - n
    if e.count <= 0 then bag.slots[from] = nil end
    local added = NZA.Core.B('Inv.AddItem', src, name, n, meta)
    if not added then
        local cur = bag.slots[from]
        if cur then cur.count = cur.count + n
        else bag.slots[from] = { name = name, count = n, meta = meta, mk = e.mk } end
        return fail('pockets_full')
    end
    return { ok = true, moved = movedInfo(name, n, 'out') }
end

-- slot → slot inside the bag
local function rearrange(bag, data)
    local from, to = tonumber(data.from), tonumber(data.to)
    local max = slotCount(bag)
    local e = from and bag.slots[from]
    if not e then return fail('empty_slot') end
    if not to or to < 1 or to > max or to == from then return { ok = true } end
    local n = wantCount(data.count, e.count)
    local t = bag.slots[to]
    if not t then
        if n >= e.count then
            bag.slots[to], bag.slots[from] = e, nil
        else
            bag.slots[to] = { name = e.name, count = n, meta = e.meta, mk = e.mk }
            e.count = e.count - n
        end
    elseif t.name == e.name and t.mk == e.mk then
        local add = math.min(capFor(e.name) - t.count, n)
        if add < 1 then return fail('full') end
        t.count = t.count + add
        e.count = e.count - add
        if e.count <= 0 then bag.slots[from] = nil end
    else
        bag.slots[to], bag.slots[from] = e, t   -- swap whole stacks
    end
    return { ok = true, moved = movedInfo(e.name, n, 'bag') }
end

local function checkViewer(src, id)
    local bag = type(id) == 'string' and MB.bags[id] or nil
    if not bag then return nil, fail('no_bag') end
    if MB.viewing[src] ~= id then return nil, fail('no_access') end
    if not (MB.world[id] or MB.carry[src] == id) then return nil, fail('no_bag') end
    if not nearBag(src, id, (tonumber(C('Bag').openRange) or 3.5) + 1.0) then return nil, fail('too_far') end
    local okA, why = MB.CanAccess(src, bag)
    if not okA then return nil, accessFail(why, bag) end
    if not playerAlive(src) then return nil, fail('down') end
    return bag
end

local function finishMove(src, bag, res)
    if res.ok then
        save(bag)
        syncViewers(bag, src, res.moved or (res.movedList and res.movedList[1]) or nil)
        if res.moved then NZA.Bus.Emit('medbag:moved', src, bag.id, res.moved) end
    end
    res.bag = MB.BagView(bag, src)
    res.me = MB.MeView(src)
    return res
end

lib.callback.register('nza:medbag:move', function(src, id, data)
    local mr = C('Storage').moveRate or {}
    if not rate(src, 'move', tonumber(mr.count) or 10, tonumber(mr.window) or 1000) then return fail('rate') end
    if type(data) ~= 'table' then return fail('failed') end
    local bag, err = checkViewer(src, id)
    if not bag then return err end
    return withLock(id, function()
        local res
        if data.dir == 'in' then res = deposit(src, bag, data)
        elseif data.dir == 'out' then res = withdraw(src, bag, data)
        elseif data.dir == 'bag' then res = rearrange(bag, data)
        else res = fail('failed') end
        return finishMove(src, bag, res)
    end)
end)

-- ── bulk actions ─────────────────────────────────────────────────────────

local CAT_ORDER = { first_aid = 1, wound_care = 2, medication = 3, fluids = 4, orthopedic = 5, airway = 6, surgery = 7, equipment = 8, documents = 9 }

local function sortBag(bag)
    local list = {}
    for _, e in pairs(bag.slots) do list[#list + 1] = e end
    -- merge equal stacks first
    local merged, byKey = {}, {}
    for _, e in ipairs(list) do
        local key = e.name .. '|' .. e.mk
        local cap = capFor(e.name)
        local left = e.count
        local stacks = byKey[key] or {}
        byKey[key] = stacks
        for _, s in ipairs(stacks) do
            if left <= 0 then break end
            local add = math.min(cap - s.count, left)
            if add > 0 then s.count = s.count + add; left = left - add end
        end
        while left > 0 do
            local add = math.min(cap, left)
            local s = { name = e.name, count = add, meta = e.meta, mk = e.mk }
            stacks[#stacks + 1] = s
            merged[#merged + 1] = s
            left = left - add
        end
    end
    table.sort(merged, function(a, b)
        local ia, ib = info(a.name), info(b.name)
        local ca, cb = CAT_ORDER[ia.cat] or 50, CAT_ORDER[ib.cat] or 50
        if ca ~= cb then return ca < cb end
        if ia.label ~= ib.label then return ia.label < ib.label end
        return a.count > b.count
    end)
    bag.slots = {}
    for i, s in ipairs(merged) do bag.slots[i] = s end
end

local function packKit(src, bag)
    local movedList, total = {}, 0
    for _, k in ipairs(C('Storage').kit or {}) do
        local name, target = k.item, math.floor(tonumber(k.count) or 0)
        if type(name) == 'string' and target > 0 and allowed(name) then
            local have = 0
            for _, e in pairs(bag.slots) do if e.name == name and e.mk == '' then have = have + e.count end end
            local need = target - have
            if need > 0 then
                local pockets = NZA.Core.B('Inv.Count', src, name) or 0
                local n = math.min(need, pockets, weightRoom(bag, name))
                if n > 0 then
                    local list, fits = plan(bag, name, '', n)
                    if fits > 0 and NZA.Core.B('Inv.RemoveItem', src, name, fits) then
                        apply(bag, name, nil, '', list)
                        movedList[#movedList + 1] = movedInfo(name, fits, 'in')
                        total = total + fits
                    end
                end
            end
        end
    end
    return movedList, total
end

local function emptyBag(src, bag)
    local movedList, total = {}, 0
    local max = slotCount(bag)
    for slot = 1, max do
        local e = bag.slots[slot]
        if e then
            local res = withdraw(src, bag, { from = slot, count = 'all' })
            if not res.ok then break end
            movedList[#movedList + 1] = res.moved
            total = total + res.moved.count
        end
    end
    return movedList, total
end

lib.callback.register('nza:medbag:action', function(src, id, action, data)
    if not rate(src, 'action', 3, 1500) then return fail('rate') end
    local bag, err = checkViewer(src, id)
    if not bag then return err end
    return withLock(id, function()
        local res = { ok = true }
        if action == 'sort' then
            sortBag(bag)
            res.msg = L('ok_sorted')
        elseif action == 'lock' then
            local on = type(data) == 'table' and data.on == true
            local admin = NZA.Core.IsAdmin(src)
            if not MB.IsOwner(src, bag) and not (admin and not on) then return finishMove(src, bag, fail('not_owner')) end
            if C('Access').lock == false and on then return finishMove(src, bag, fail('not_owner')) end
            bag.locked = on
            worldState(bag)
            res.msg = on and L('ok_locked') or L('ok_unlocked')
            -- viewers who lost access
            for s in pairs(MB.viewers[id] or {}) do
                if s ~= src and not MB.CanAccess(s, bag) then kick(s, 'access') end
            end
        elseif action == 'style' then
            if not MB.IsOwner(src, bag) and not NZA.Core.IsAdmin(src) then return finishMove(src, bag, fail('not_owner')) end
            data = type(data) == 'table' and data or {}
            if data.colour ~= nil then
                local col = colourOf(data.colour)
                if col then bag.colour = col.id end
            end
            if data.name ~= nil then
                local name = type(data.name) == 'string' and data.name or ''
                name = name:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
                local max = math.floor(tonumber(C('Bag').nameLength) or 20)
                if #name > max then name = name:sub(1, max) end
                bag.name = name ~= '' and name or nil
            end
            -- the ground prop takes the new colour at once
            local w = MB.world[id]
            if w and w.ent and DoesEntityExist(w.ent) and not modelOk(w.ent, { modelFor(bag) }) then
                local coords, heading, bucket, by = GetEntityCoords(w.ent), w.heading, w.bucket, w.by
                MB.DeleteEnt(w.ent)
                MB.world[id] = nil
                placeWorld(bag, coords, heading or 0.0, bucket or 0, by)
            end
            worldState(bag)
            res.msg = L('ok_styled')
        elseif action == 'kit' then
            local list, total = packKit(src, bag)
            if total < 1 then return finishMove(src, bag, fail('nothing')) end
            res.movedList = list
            res.msg = L('ok_kit', total)
        elseif action == 'empty' then
            local list, total = emptyBag(src, bag)
            if total < 1 then return finishMove(src, bag, fail(next(bag.slots) and 'pockets_full' or 'nothing')) end
            res.movedList = list
            res.msg = L('ok_empty', total)
        else
            return finishMove(src, bag, fail('failed'))
        end
        return finishMove(src, bag, res)
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM
-- ════════════════════════════════════════════════════════════════════════

local function onUse(src, item)
    if C('Bag').enabled == false then return end
    if not rate(src, 'use', 2, 2000) then return end
    if MB.HandsFull(src) then return notify(src, L('err_carrying'), 'error') end
    if not playerAlive(src) then return end
    if inVehicle(src) then return notify(src, L('err_vehicle'), 'error') end
    if C('Bag').whoCanPlace == 'medic' then
        local rec = staff(src)
        if not (rec.medic and onDutyRec(rec)) and not NZA.Core.IsAdmin(src) then return notify(src, L('err_job'), 'error') end
    end
    local meta = type(item) == 'table' and type(item.metadata) == 'table' and item.metadata or {}
    local bagId = type(meta.bagId) == 'string' and meta.bagId or nil
    if bagId and (MB.world[bagId] or carrierOf(bagId)) then return notify(src, L('err_already_out'), 'error') end
    local maxOut = tonumber(C('Bag').maxOut) or 0
    if maxOut > 0 and countOut(src) >= maxOut then return notify(src, L('err_max_out', maxOut), 'error') end
    local token = NZA.Util.uid('mbp')
    pendingPlace[src] = { token = token, bagId = bagId, slot = item and tonumber(item.slot) or nil, meta = meta, at = os.time() }
    TriggerClientEvent('nza:medbag:place', src, token)
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

local function forget(src)
    removeViewer(src)
    pendingPlace[src] = nil
    if MB.carry[src] then MB.ForceDrop(src, 'silent') end
    deleteHeld(src)
end

AddEventHandler('playerDropped', function()
    local src = source
    forget(src)
    MB.lastPos[src] = nil
end)

NZA.Bus.On('player:unloaded', function(src)
    if src then forget(src) end
end)

-- a carrier who goes down lets go of the bag
NZA.Bus.On('state:changed', function(p, old, new)
    if not p or p.kind ~= 'player' or not p.src or new == 'alive' then return end
    local src = p.src
    if MB.viewing[src] then kick(src, 'down') end
    if MB.carry[src] then MB.ForceDrop(src) end
end)

local function respawnWorld(id, bag)
    local w = bag.world
    if type(w) ~= 'table' then return end
    local coords = v3(w)
    if not coords then return end
    local ok = placeWorld(bag, coords, tonumber(w.h) or 0.0, tonumber(w.b) or 0, nil)
    if not ok then NZA.Warn(('medbag %s could not be put back in the world'):format(id)) end
end

CreateThread(function()
    local ok, err = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS `nza_bags` (
            `id` VARCHAR(32) NOT NULL,
            `owner` VARCHAR(64) NULL DEFAULT NULL,
            `items` LONGTEXT NULL,
            PRIMARY KEY (`id`),
            KEY `owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    if not ok then NZA.Warn('medbag: could not create nza_bags: ' .. tostring(err)) end

    -- usable item (bridge applies it again when the inventory restarts)
    if Bridge and Bridge.Inv and Bridge.Inv.RegisterUsable and Config.Items and Config.Items.medbag then
        Bridge.Inv.RegisterUsable(Config.Items.medbag, onUse)
    end

    -- bags that were left on the ground
    if C('Bag').persist ~= false then
        Wait(2000)
        local okRows, rows = pcall(MySQL.query.await, 'SELECT id, owner, items FROM nza_bags WHERE items LIKE ?', { '%"world":%' })
        if okRows and type(rows) == 'table' then
            for _, row in ipairs(rows) do
                if not MB.bags[row.id] then
                    local bag = decode(row.id, row.owner, row.items)
                    if type(bag.world) == 'table' then
                        MB.bags[row.id] = bag
                        respawnWorld(row.id, bag)
                    end
                end
            end
        end
    end
end)

-- saves + watchdog
CreateThread(function()
    local tick = 0
    while true do
        Wait(1000)
        tick = tick + 1

        -- positions of carriers (for drops after a disconnect)
        for src in pairs(MB.carry) do
            local p = ped(src)
            if p ~= 0 then MB.lastPos[src] = { coords = GetEntityCoords(p), heading = GetEntityHeading(p), bucket = bucketOf(src) } end
        end

        -- viewers: distance, access, bag gone
        for src, id in pairs(MB.viewing) do
            if not online(src) then
                removeViewer(src)
            else
                local bag = MB.bags[id]
                local pos = MB.BagPos(id)
                if not bag or not pos then
                    kick(src, 'gone')
                elseif MB.carry[src] ~= id then
                    local me = srcCoords(src)
                    if not me or #(me - pos) > (tonumber(C('Bag').openRange) or 3.5) + 1.0 then
                        kick(src, 'far')
                    elseif tick % 3 == 0 and not MB.CanAccess(src, bag) then
                        kick(src, 'access')
                    end
                end
            end
        end

        -- carriers that left without the client noticing
        for src in pairs(MB.carry) do
            if not online(src) then MB.ForceDrop(src, 'silent') end
        end

        -- ground bags removed by something else (cleanup scripts) come back
        if tick % 5 == 0 then
            for id, w in pairs(MB.world) do
                if not w.ent or not DoesEntityExist(w.ent) then
                    local bag = MB.bags[id]
                    MB.world[id] = nil
                    if bag and w.coords then
                        local ok = placeWorld(bag, w.coords, w.heading or 0.0, w.bucket or 0, w.by)
                        if not ok then NZA.Warn(('medbag %s vanished and could not be respawned'):format(id)) end
                    end
                end
            end
            for _, bag in pairs(MB.bags) do
                if bag.dirty then flush(bag) end
            end
        end

        -- old placement tokens
        if tick % 30 == 0 then
            local now = os.time()
            for src, pend in pairs(pendingPlace) do
                if now - pend.at > 60 then pendingPlace[src] = nil end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, bag in pairs(MB.bags) do
        if bag.dirty then pcall(flush, bag) end
    end
    -- bags in hands go back into the carrier's inventory
    for src, id in pairs(MB.carry) do
        local bag = MB.bags[id]
        if bag and online(src) then pcall(Bridge.Inv.AddItem, src, itemName(), 1, itemMeta(bag)) end
    end
    for src in pairs(MB.held) do
        local h = MB.held[src]
        if h and h.net then MB.DeleteNet(h.net) end
    end
    for _, w in pairs(MB.world) do MB.DeleteEnt(w.ent) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('GetMedbagContents', function(id)
    local bag = MB.Load(id)
    if not bag then return nil end
    local out = {}
    for slot, e in pairs(bag.slots) do out[#out + 1] = { slot = slot, name = e.name, count = e.count, metadata = e.meta } end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end)
