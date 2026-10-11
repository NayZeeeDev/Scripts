-- Inventory layer. Every feature talks to `Inv`, never to an inventory resource directly.
-- Integrations live in inventories/*.lua and register themselves with Inventories.Register.
-- Items passed around the manager always use one shape:
--   { slot = 1, name = 'water', count = 3, metadata = { ... } }
Inventories = { list = {}, order = {} }
Inv = { id = 'none', label = 'No inventory', resource = nil, a = {} }

--- Called by each file in inventories/. `def` is the integration (see inventories/custom.lua).
function Inventories.Register(id, def)
    if type(id) ~= 'string' or type(def) ~= 'table' then return end
    def.id = id
    def.label = def.label or id
    def.resource = def.resource or id
    if not Inventories.list[id] then Inventories.order[#Inventories.order + 1] = id end
    Inventories.list[id] = def
end

local function installed(res) return res and GetResourceState(res) ~= 'missing' end

--- Pick the integration from Config.Inventory ('auto' tries each registered one in order)
local function pick()
    local want = Config.Inventory or 'auto'
    if want ~= 'auto' then
        local def = Inventories.list[want]
        if def then return def end
        NZ.Print(('Config.Inventory is "%s" but no integration with that name is registered. Falling back to auto.'):format(want), 'warn')
    end
    local order = {}
    for i, id in ipairs(Inventories.order) do order[i] = id end
    table.sort(order, function(a, b)
        local pa, pb = Inventories.list[a].priority or 50, Inventories.list[b].priority or 50
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    -- running inventories win over ones that are only in the resources folder
    for _, id in ipairs(order) do
        local def = Inventories.list[id]
        local state = GetResourceState(def.resource)
        if def.auto ~= false and (state == 'started' or state == 'starting') then return def end
    end
    for _, id in ipairs(order) do
        local def = Inventories.list[id]
        if def.auto ~= false then
            local ok, yes = pcall(def.detect or function() return installed(def.resource) end)
            if ok and yes then return def end
        end
    end
end

function Inv.Select()
    local def = pick()
    if not def then
        NZ.Print('No supported inventory found. Set Config.Inventory, or add your own integration in inventories/custom.lua.', 'error')
        return
    end
    Inv.a = def
    Inv.id, Inv.label, Inv.resource = def.id, def.label, def.resource
    NZ.SetDBLayout(def.id, def.db)
    NZ.Print(('Inventory: %s (%s)'):format(def.label, GetResourceState(def.resource)))
end

function Inv.Ready() return Inv.resource ~= nil and GetResourceState(Inv.resource) == 'started' end
function Inv.Has(fn) return type(Inv.a[fn]) == 'function' end

local function call(fn, ...)
    local f = Inv.a[fn]
    if type(f) ~= 'function' then return nil end
    local ok, a, b, c = pcall(f, ...)
    if not ok then NZ.Debug(('%s.%s failed: %s'):format(Inv.id, fn, tostring(a))) return nil end
    return a, b, c
end
Inv.Call = call

-- ─── catalogue ──────────────────────────────────────────────────────────────
local catalogue, catalogueMap, catalogueAt = nil, {}, 0

local function loadCatalogue(force)
    if catalogue and not force and os.time() - catalogueAt < 60 then return end
    local raw = call('items') or {}
    local list, map = {}, {}
    for name, v in pairs(raw) do
        if type(v) == 'table' then
            name = v.name or name
            local e = {
                name = name, label = v.label or name, weight = tonumber(v.weight) or 0, stack = v.stack ~= false,
                weapon = v.weapon == true, description = v.description, image = v.image,
            }
            list[#list + 1] = e
            map[name] = e
        end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    catalogue, catalogueMap, catalogueAt = list, map, os.time()
end

function Inv.Items(force) loadCatalogue(force) return catalogue end
function Inv.Item(name)
    if not name then return end
    loadCatalogue()
    local v = catalogueMap[name] or catalogueMap[tostring(name):lower()]
    if not v and os.time() - catalogueAt > 5 then loadCatalogue(true) v = catalogueMap[name] end
    return v
end
function Inv.Label(name) local v = Inv.Item(name) return v and v.label or name end
function Inv.RefreshItems() catalogue = nil end
AddEventHandler('nzinv:catalogueChanged', Inv.RefreshItems)

-- ─── one inventory ──────────────────────────────────────────────────────────
local function metaMatch(meta, want)
    if type(want) ~= 'table' or next(want) == nil then return true end
    if type(meta) ~= 'table' then return false end
    for k, v in pairs(want) do if tostring(meta[k]) ~= tostring(v) then return false end end
    return true
end
Inv.MetaMatch = metaMatch

--- Clean list in the common shape, sorted by slot
function Inv.Normalize(items)
    local out = {}
    for slot, it in pairs(items or {}) do
        if type(it) == 'table' and it.name then
            out[#out + 1] = {
                slot = tonumber(it.slot) or tonumber(slot), name = it.name,
                count = tonumber(it.count or it.amount) or 1,
                metadata = type(it.metadata) == 'table' and it.metadata or type(it.info) == 'table' and it.info or {},
            }
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end

--- Loaded (live) inventory: a player server id or an inventory id. Returns items, info or nil.
function Inv.Get(inv)
    local items, info = call('getItems', inv)
    if not items then return nil end
    return Inv.Normalize(items), info or {}
end

function Inv.Count(inv, name, metadata)
    local items = Inv.Get(inv)
    local n = 0
    for _, it in ipairs(items or {}) do
        if it.name == name and metaMatch(it.metadata, metadata) then n = n + it.count end
    end
    return n
end

function Inv.Slot(inv, slot)
    for _, it in ipairs(Inv.Get(inv) or {}) do if it.slot == slot then return it end end
end

function Inv.Add(inv, name, count, metadata, slot)
    local ok, err = call('addItem', inv, name, count, metadata, slot)
    return ok and true or false, err
end

--- Removes up to `count` copies. Returns how many were removed.
function Inv.Remove(inv, name, count, metadata, slot)
    return tonumber(call('removeItem', inv, name, count, metadata, slot)) or 0
end

function Inv.CanCarry(src, name, count, metadata)
    if not Inv.Has('canCarry') then return true end
    return call('canCarry', src, name, count, metadata) and true or false
end

function Inv.Clear(src, keep) return call('clear', src, keep) end

--- Owner character of a player's inventory, for integrations that know it
function Inv.Owner(src) return call('owner', src) end

-- ─── saved data ─────────────────────────────────────────────────────────────
--- Ask the inventory to write what it holds in memory to the database
function Inv.Save()
    if Inv.Has('save') then call('save') end
end

local function part(name) return type(Inv.a[name]) == 'table' and Inv.a[name] or {} end

function Inv.OfflineRead(charId)
    local f = part('offline').read
    if not f then return nil end
    local ok, items = pcall(f, charId)
    if not ok or not items then return nil end
    return Inv.Normalize(items)
end

function Inv.OfflineWrite(charId, items)
    local f = part('offline').write
    if not f then return false end
    local ok, r = pcall(f, charId, Inv.Normalize(items))
    return ok and r ~= false
end

--- fn(charId, items). `like` is an item name hint so integrations can filter in SQL.
function Inv.EachOffline(fn, like)
    local f = part('offline').each
    if not f then return end
    local ok, err = pcall(f, function(charId, items) fn(tostring(charId), Inv.Normalize(items)) end, like)
    if not ok then NZ.Print('Reading offline inventories failed: ' .. tostring(err), 'warn') end
end

--- fn(id, kind, label, items, owner). kind = 'stash' | 'trunk' | 'glovebox' | anything else
function Inv.EachStorage(fn, like, kinds)
    local f = part('storage').each
    if not f then return end
    local ok, err = pcall(f, function(id, kind, label, items, owner) fn(tostring(id), kind or 'stash', label or tostring(id), Inv.Normalize(items), owner) end, like, kinds)
    if not ok then NZ.Print('Reading stashes failed: ' .. tostring(err), 'warn') end
end

--- Any inventory by id. Uses the live copy when it is loaded, otherwise saved data.
function Inv.Read(id)
    local items, info = Inv.Get(tonumber(id) or id)
    if items then info.live = true return items, info end
    local f = part('storage').read
    if not f then return nil end
    local ok, saved, label = pcall(f, id)
    if ok and saved then return Inv.Normalize(saved), { label = label or id, live = false } end
end

--- Remove from any inventory by id (live when loaded, saved data otherwise). Returns removed count.
function Inv.RemoveFrom(id, name, count, metadata, slot)
    local key = tonumber(id) or id
    if Inv.Get(key) then return Inv.Remove(key, name, count, metadata, slot) end
    local S = part('storage')
    if not S.read or not S.write then return 0 end
    local ok, saved = pcall(S.read, id)
    if not ok or not saved then return 0 end
    local list, removed = Inv.Normalize(saved), 0
    for _, it in ipairs(list) do
        if removed >= count then break end
        if it.name == name and (not slot or it.slot == slot) and metaMatch(it.metadata, metadata) then
            local take = math.min(it.count, count - removed)
            it.count = it.count - take
            removed = removed + take
        end
    end
    if removed == 0 then return 0 end
    local keep = {}
    for _, it in ipairs(list) do if it.count > 0 then keep[#keep + 1] = it end end
    pcall(S.write, id, keep)
    return removed
end

--- Id the inventory uses for a vehicle's trunk or glovebox
function Inv.VehicleId(kind, plate)
    local f = part('ids')[kind]
    if f then return f(plate) end
    return (kind == 'trunk' and 'trunk' or 'glove') .. tostring(plate)
end

-- ─── facts the panel shows ──────────────────────────────────────────────────
--- Player inventory size: { slots, weight }
function Inv.Limits()
    local l = call('limits')
    l = type(l) == 'table' and l or {}
    return { slots = tonumber(l.slots) or 50, weight = tonumber(l.weight) or 30000 }
end

--- Metadata a freshly given weapon gets when the inventory doesn't make its own
function Inv.NewWeaponMeta(serial)
    local m = call('weaponMeta', serial)
    if type(m) == 'table' then return m end
    return { durability = 100, ammo = 0, components = {}, [Inv.UniqueKeys()[1] or 'serial'] = serial }
end

function Inv.ImagePath()
    local p = Inv.a.imagepath
    if type(p) == 'function' then p = p() end
    return p or ''
end

function Inv.UniqueKeys()
    local keys, seen = {}, {}
    for _, k in ipairs((Config.AntiDupe and Config.AntiDupe.keys) or {}) do if not seen[k] then keys[#keys + 1] = k seen[k] = true end end
    for _, k in ipairs(Inv.a.uniqueKeys or { 'serial' }) do if not seen[k] then keys[#keys + 1] = k seen[k] = true end end
    return keys
end

--- ESX servers on ox_inventory keep cash as an item; integrations list those item names here
function IsAccountItem(name)
    local list = Inv.a.accountItems
    if type(list) == 'function' then list = list() end
    return type(list) == 'table' and list[name] == true
end

function Inv.Version()
    if not Inv.resource then return nil end
    return GetResourceState(Inv.resource) == 'started' and GetResourceMetadata(Inv.resource, 'version', 0) or nil
end

--- Boot info for the panel
function Inv.Info()
    local E = Inv.a.editor
    local pages = {}
    if type(E) == 'table' and Config.Editor.enabled then
        for _, p in ipairs(E.pages or {}) do
            local files = {}
            for _, f in ipairs(p.files or {}) do
                local def = E.files and E.files[f]
                if def and (not def.when or def.when()) then files[#files + 1] = { id = f, label = def.tab or def.label } end
            end
            if #files > 0 then pages[#pages + 1] = { key = p.key, label = p.label, icon = p.icon, files = files } end
        end
    end
    return {
        id = Inv.id, label = Inv.label, resource = Inv.resource, version = Inv.Version(), running = Inv.Ready(),
        imagepath = Inv.ImagePath(), pages = pages, storage = type(Inv.a.storage) == 'table' and Inv.a.storage.each ~= nil,
        logging = Inv.a.watch ~= nil, uniqueKeys = Inv.UniqueKeys(),
    }
end

-- ─── logging hookup ─────────────────────────────────────────────────────────
local stopWatch
function Inv.StartWatching()
    if stopWatch then pcall(stopWatch) stopWatch = nil end
    if not Inv.Has('watch') then
        NZ.Print(('%s has no live logging hookup. Admin actions, money and scans still work. Scripts can report moves through the exports in inventories/custom.lua.'):format(Inv.label), 'warn')
        return
    end
    if not Inv.Ready() then
        NZ.Print(('%s is not started, item logging waits until it starts.'):format(Inv.label), 'warn')
        return
    end
    local ok, stop = pcall(Inv.a.watch, InvLog)
    if ok then stopWatch = stop else NZ.Print(('Could not hook into %s: %s'):format(Inv.label, tostring(stop)), 'error') end
end

AddEventHandler('onServerResourceStart', function(r)
    if r == Inv.resource then
        -- the inventory restarted with fresh hook tables; removing our old ids now could hit someone else's
        stopWatch = nil
        Inv.RefreshItems()
        if Inv.Has('start') then call('start') end
        SetTimeout(1500, Inv.StartWatching)
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r == NZ.Resource and stopWatch then pcall(stopWatch) end
end)
