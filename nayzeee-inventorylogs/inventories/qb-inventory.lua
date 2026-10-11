--[[
    qb-inventory integration (qb-inventory 2.x, the version with the `inventories` table).
    Item logging needs 2.2 or newer (AddHook / AddListener). Older builds and forks still get
    admin tools, scans, rollbacks, money logs and the editor, just not per-move logs.

    Editor files:
      Items    qb-core/shared/items.lua     (QBShared.Items)    applied live through qb-core's exports
      Weapons  qb-core/shared/weapons.lua   (QBShared.Weapons)  applied on the next server restart
      Shops    qb-shops/config.lua          (Config.Locations and Config.Products), qb-shops restarts to apply
]]
local C = Config.QBInventory or {}
local RES = C.resource or 'qb-inventory'
local CORE = C.core or 'qb-core'
local SHOPS = C.shops or 'qb-shops'

local QBCore
local function core()
    if not QBCore and GetResourceState(CORE) == 'started' then
        local ok, obj = pcall(function() return exports[CORE]:GetCoreObject() end)
        if ok then QBCore = obj end
    end
    return QBCore
end
-- qb-core raises this after AddItem / UpdateItem / RemoveItem
AddEventHandler('QBCore:Server:UpdateObject', function()
    if Inv.id ~= 'qb-inventory' then return end
    QBCore = nil
    Inv.RefreshItems()
end)

local function sharedItems()
    local c = core()
    return c and c.Shared and c.Shared.Items or {}
end

local function getPlayer(src)
    local ok, p = pcall(function() return exports[CORE]:GetPlayer(src) end)
    if ok and p then return p end
    local c = core()
    return c and c.Functions.GetPlayer(src) or nil
end

local function decode(s)
    if type(s) == 'table' then return s end
    if not s or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return ok and type(v) == 'table' and v or {}
end

--- qb-inventory's own limits, read from its config file once
local limits
local function qbLimits()
    if limits then return limits end
    limits = { weight = 120000, slots = 40 }
    local src = LoadResourceFile(RES, 'config/config.lua') or ''
    limits.weight = tonumber(src:match('MaxWeight%s*=%s*(%d+)')) or limits.weight
    limits.slots = tonumber(src:match('MaxSlots%s*=%s*(%d+)')) or limits.slots
    return limits
end

--- common list -> the array qb saves in players.inventory / inventories.items
local function toQbSaved(items)
    local shared = sharedItems()
    local out = {}
    for _, it in ipairs(items) do
        local def = shared[it.name] or {}
        out[#out + 1] = { name = it.name, amount = it.count, info = (it.metadata and next(it.metadata)) and it.metadata or {}, type = def.type or 'item', slot = it.slot }
    end
    return out
end

--- common list -> full slot-keyed items qb-inventory keeps in memory
local function toQbLive(items)
    local shared = sharedItems()
    local out = {}
    for _, it in ipairs(items) do
        local def = shared[it.name]
        if def then
            out[it.slot] = {
                name = def.name or it.name, amount = it.count, info = (it.metadata and next(it.metadata)) and it.metadata or {},
                label = def.label, description = def.description or '', weight = def.weight, type = def.type, unique = def.unique,
                useable = def.useable, image = def.image, shouldClose = def.shouldClose, slot = it.slot, combinable = def.combinable,
            }
        end
    end
    return out
end

local function rows(query, params, fn)
    local list = MySQL.query.await(query, params or {}) or {}
    for i, r in ipairs(list) do
        fn(r)
        if i % 150 == 0 then Wait(0) end
    end
end

local function kindOf(id)
    if id:find('^trunk%-') then return 'trunk' end
    if id:find('^glovebox%-') then return 'glovebox' end
    return 'stash'
end

-- ─── logging ────────────────────────────────────────────────────────────────
local TYPES = { player = 'player', inventory = 'stash', trunk = 'trunk', glovebox = 'glovebox', drop = 'drop' }

local function slotItem(inv, slot)
    for _, it in pairs(type(inv) == 'table' and inv.items or {}) do
        if type(it) == 'table' and tonumber(it.slot) == tonumber(slot) then return it end
    end
end

local function watch(log)
    local ok = pcall(function() return exports[RES].AddListener end)
    local hooks, listeners = {}, {}
    local pending = {}
    local viewing = {}   -- target server id -> staff/player who has their inventory open (robbery, frisk)
    local function key(d, sub) return table.concat({ tostring(d.fromId), tostring(d.toId), tostring(d.fromSlot), tostring(d.toSlot), tostring(sub) }, '|') end

    local function addHook(t, fn)
        local idx = exports[RES]:AddHook(t, fn)
        if idx then hooks[#hooks + 1] = { t, idx } end
        return idx
    end
    local function addListener(t, fn)
        local idx = exports[RES]:AddListener(t, fn)
        if idx then listeners[#listeners + 1] = { t, idx } end
        return idx
    end

    local good = ok and pcall(function()
        -- before a move: remember what sat in the slots (the listener only sees the result)
        addHook('ItemMoved', function(sub, d)
            if type(d) ~= 'table' then return end
            pending[key(d, sub)] = { from = slotItem(d.fromInventory, d.fromSlot), to = slotItem(d.toInventory, d.toSlot), at = os.time() }
        end)

        addListener('ItemMoved', function(sub, d)
            if type(d) ~= 'table' then return end
            local k = key(d, sub)
            local pre = pending[k]
            pending[k] = nil
            if not pre or not pre.from then return end
            local ft, tt = TYPES[d.fromType] or d.fromType, TYPES[d.toType] or d.toType
            local fromId, toId = d.fromId, d.toId
            local src
            if ft == 'player' and tt == 'player' then
                -- someone searching another player: taking from them, or putting into them
                if sub ~= 'given' and viewing[tonumber(fromId)] == tonumber(toId) then
                    ft, src = 'otherplayer', tonumber(toId)
                elseif sub ~= 'given' and viewing[tonumber(toId)] == tonumber(fromId) then
                    tt, src = 'otherplayer', tonumber(fromId)
                else
                    src = tonumber(fromId)
                end
            elseif ft == 'player' then src = tonumber(fromId)
            elseif tt == 'player' then src = tonumber(toId) end
            if not src then return end
            local kind = log.Classify(ft, tt, fromId, toId)
            local item = { name = pre.from.name, label = pre.from.label, metadata = type(pre.from.info) == 'table' and pre.from.info or nil }
            log.Rapid(src, item.name, fromId, toId, d.amount)
            if kind then log.Move(src, kind, item, tonumber(d.amount) or pre.from.amount, fromId, toId) end
            if sub == 'swapped' and pre.to then
                local back = log.Classify(tt, ft, toId, fromId)
                if back then
                    log.Move(src, back, { name = pre.to.name, label = pre.to.label, metadata = type(pre.to.info) == 'table' and pre.to.info or nil }, pre.to.amount, toId, fromId)
                end
            end
        end)

        addListener('InventoryOpened', function(sub, d)
            if sub ~= 'player' or type(d) ~= 'table' then return end
            local target, viewer = tonumber(d.inventoryId), tonumber(d.source)
            if target and viewer and target ~= viewer then viewing[target] = viewer end
        end)

        addListener('ItemDropped', function(_, d)
            if type(d) ~= 'table' or type(d.item) ~= 'table' then return end
            local it = d.item
            log.Move(d.source, 'drop', { name = it.name, label = it.label, metadata = type(it.info) == 'table' and it.info or nil }, d.amount or it.amount, d.source, d.dropId or 'ground')
        end)

        addListener('ItemBought', function(_, d)
            if type(d) ~= 'table' or type(d.item) ~= 'table' then return end
            local shop = type(d.shop) == 'table' and (d.shop.label or d.shop.name) or d.shopType or 'shop'
            log.Shop(d.toId, d.item.name, d.amount, shop, d.totalPrice, 'cash', type(d.item.info) == 'table' and d.item.info or nil)
        end)

        addListener('ItemAdded', function(_, d)
            if type(d) ~= 'table' or type(d.item) ~= 'table' then return end
            if d.toType ~= 'player' or not tonumber(d.toId) then return end
            local res = d.resource
            local reason = tostring(d.reason or '')
            -- qb-inventory's own adds are moves, purchases and gives (already logged above). Purchases
            -- and gives run inside qb-core callbacks, so their resource reads as qb-core: go by reason.
            if res == RES or res == NZ.Resource then return end
            if reason == 'shop-purchase' or reason:find('^Item given from ID') then return end
            log.Created(d.toId, d.item.name, d.amount, res, type(d.item.info) == 'table' and d.item.info or nil, d.reason)
        end)
    end)

    if not good then
        NZ.Print(('%s has no AddHook/AddListener exports (needs qb-inventory 2.2+). Per-move item logs are off; everything else works.'):format(RES), 'warn')
        return nil
    end
    NZ.Print(('Watching %s: %d hooks, %d listeners registered.'):format(RES, #hooks, #listeners))

    local dropHandler = AddEventHandler('playerDropped', function()
        local src = source
        viewing[src] = nil
        for t, v in pairs(viewing) do if v == src then viewing[t] = nil end end
    end)

    CreateThread(function()
        while #listeners > 0 do
            Wait(60000)
            local now = os.time()
            for k, v in pairs(pending) do if now - v.at > 30 then pending[k] = nil end end
        end
    end)

    return function()
        for _, h in ipairs(hooks) do pcall(function() exports[RES]:RemoveHook(h[1], h[2]) end) end
        for _, l in ipairs(listeners) do pcall(function() exports[RES]:RemoveListener(l[1], l[2]) end) end
        listeners = {}
        RemoveEventHandler(dropHandler)
    end
end

-- ─── editor: live apply ─────────────────────────────────────────────────────
local function sig(v)
    local t = type(v)
    if t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for i, k in ipairs(keys) do parts[i] = tostring(k) .. '=' .. sig(v[k]) end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    return tostring(v)
end

local function applyItems(before, after)
    if GetResourceState(CORE) ~= 'started' then
        return { ok = true, live = false, note = 'Saved. It applies when qb-core starts.' }
    end
    if not before then QBCore = nil before = sharedItems() end   -- Apply button: compare with what's running
    after = after or {}
    local changed, failed = 0, 0
    local function run(fn, ...)
        local args = { ... }
        local ok, res = pcall(function() return exports[CORE][fn](nil, table.unpack(args)) end)
        if ok and res ~= false then changed = changed + 1 else failed = failed + 1 end
    end
    for name, item in pairs(after) do
        if type(item) == 'table' then
            if before[name] == nil then run('AddItem', name, item)
            elseif sig(before[name]) ~= sig(item) then run('UpdateItem', name, item) end
        end
    end
    for name in pairs(before) do
        if after[name] == nil then run('RemoveItem', name) end
    end
    QBCore = nil
    Inv.RefreshItems()
    if failed > 0 and changed == 0 then
        return { ok = true, live = false, note = 'Saved. This qb-core build has no AddItem/UpdateItem exports, so it applies after a server restart.' }
    end
    return { ok = true, live = true, changed = changed, note = failed > 0 and ('%d item(s) could not be applied live and need a restart.'):format(failed) or nil }
end

local function restartShops()
    if GetResourceState(SHOPS) ~= 'started' then
        return { ok = true, live = false, note = ('Saved. %s is not running.'):format(SHOPS) }
    end
    ExecuteCommand('restart ' .. SHOPS)
    return { ok = true, live = true, note = ('%s is restarting so shops and peds reload. If shops don\'t change, see INSTALL.md → qb-inventory setup.'):format(SHOPS) }
end

-- ─── integration ────────────────────────────────────────────────────────────
Inventories.Register('qb-inventory', {
    label = 'qb-inventory',
    resource = RES,
    priority = 20,
    detect = function() return GetResourceState(RES) ~= 'missing' end,
    db = { players = 'players', pcol = 'citizenid', vehicles = 'player_vehicles', vcol = 'plate' },
    imagepath = ('nui://%s/html/images'):format(RES),
    uniqueKeys = { 'serie' },
    limits = function() return qbLimits() end,
    weaponMeta = function(serial) return { serie = serial, quality = 100, ammo = 0 } end,
    ids = {
        trunk = function(plate) return 'trunk-' .. plate end,
        glovebox = function(plate) return 'glovebox-' .. plate end,
    },

    start = function() QBCore = nil limits = nil end,

    items = function()
        local out = {}
        for name, v in pairs(sharedItems()) do
            if type(v) == 'table' then
                out[v.name or name] = { label = v.label, weight = v.weight, stack = not v.unique, weapon = v.type == 'weapon',
                    description = v.description, image = v.image }
            end
        end
        return out
    end,

    getItems = function(inv)
        if tonumber(inv) then
            local p = getPlayer(tonumber(inv))
            if not p or not p.PlayerData then return nil end
            local L = qbLimits()
            return p.PlayerData.items or {}, { label = GetPlayerName(inv), type = 'player', maxWeight = L.weight, slots = L.slots, owner = p.PlayerData.citizenid }
        end
        local ok, data = pcall(function() return exports[RES]:GetInventory(inv) end)
        if not ok or type(data) ~= 'table' or not data.items then return nil end
        return data.items, { label = data.label or inv, type = kindOf(tostring(inv)), maxWeight = data.maxweight, slots = data.slots }
    end,
    addItem = function(inv, name, count, metadata, slot)
        local def = sharedItems()[name]
        if not def then return false, 'unknown item' end
        local info = (metadata and next(metadata)) and metadata or false
        -- unique items (weapons, ids) sit one per slot
        if def.unique and count > 1 then
            for _ = 1, count do
                if not exports[RES]:AddItem(inv, name, 1, false, info, NZ.Resource) then return false, 'no room' end
            end
            return true
        end
        local ok = exports[RES]:AddItem(inv, name, count, slot or false, info, NZ.Resource)
        return ok and true or false, ok and nil or 'no room'
    end,
    removeItem = function(inv, name, count, metadata, slot)
        local items = Inv.Get(inv)
        if not items then return 0 end
        local removed = 0
        for _, it in ipairs(items) do
            if removed >= count then break end
            if it.name == name and (not slot or it.slot == slot) and Inv.MetaMatch(it.metadata, metadata) then
                local take = math.min(it.count, count - removed)
                if exports[RES]:RemoveItem(inv, name, take, it.slot, NZ.Resource) then removed = removed + take end
            end
        end
        return removed
    end,
    canCarry = function(src, name, count) return exports[RES]:CanAddItem(src, name, count) end,
    clear = function(src, keep) exports[RES]:ClearInventory(src, keep) end,
    owner = function(src)
        local p = getPlayer(src)
        return p and p.PlayerData and p.PlayerData.citizenid or nil
    end,

    offline = {
        read = function(charId)
            local row = MySQL.single.await('SELECT `inventory` FROM `players` WHERE `citizenid` = ? LIMIT 1', { charId })
            if not row then return nil end
            return decode(row.inventory)
        end,
        write = function(charId, items)
            return MySQL.update.await('UPDATE `players` SET `inventory` = ? WHERE `citizenid` = ?', { json.encode(toQbSaved(items)), charId }) ~= nil
        end,
        each = function(fn, like)
            local q = 'SELECT `citizenid` AS `id`, `inventory` FROM `players` WHERE `inventory` IS NOT NULL AND `inventory` <> \'[]\''
            local p = {}
            if like then q = q .. ' AND `inventory` LIKE ?' p[1] = '%"' .. like .. '"%' end
            rows(q, p, function(r) fn(r.id, decode(r.inventory)) end)
        end,
    },

    -- stashes, trunks and gloveboxes all live in the `inventories` table
    storage = {
        each = function(fn, like, kinds)
            kinds = kinds or { stash = true, trunk = true, glovebox = true }
            local q = 'SELECT `identifier`, `items` FROM `inventories`'
            local p = {}
            if like then q = q .. ' WHERE `items` LIKE ?' p[1] = '%"' .. like .. '"%' end
            rows(q, p, function(r)
                local id = tostring(r.identifier)
                local kind = kindOf(id)
                if kinds[kind] then fn(id, kind, id:gsub('^trunk%-', ''):gsub('^glovebox%-', ''), decode(r.items)) end
            end)
        end,
        read = function(id)
            local ok, data = pcall(function() return exports[RES]:GetInventory(id) end)
            if ok and type(data) == 'table' and data.items then return data.items, data.label or id end
            local row = MySQL.single.await('SELECT `items` FROM `inventories` WHERE `identifier` = ? LIMIT 1', { id })
            if row then return decode(row.items), id end
        end,
        write = function(id, items)
            local ok, data = pcall(function() return exports[RES]:GetInventory(id) end)
            if ok and type(data) == 'table' then pcall(function() exports[RES]:SetInventory(id, toQbLive(items), NZ.Resource) end) end
            return MySQL.update.await('UPDATE `inventories` SET `items` = ? WHERE `identifier` = ?', { json.encode(toQbLive(items)), id })
        end,
    },

    watch = watch,

    -- ─── editor ──────────────────────────────────────────────────────────────
    editor = {
        resource = CORE,
        files = {
            items = { label = 'Items', kind = 'qbitem', keyed = true, resource = CORE, path = 'shared/items.lua', root = 'QBShared.Items', inline = true },
            weapons = { label = 'Weapons', kind = 'qbweapon', keyed = true, resource = CORE, path = 'shared/weapons.lua', root = 'QBShared.Weapons', inline = true, hashKeys = true },
            shops = { label = 'Shops', tab = 'Locations', kind = 'qbshop', keyed = true, resource = SHOPS, path = 'config.lua', root = 'Config.Locations',
                refs = { products = { file = 'products', format = "Config.Products['%s']" } }, bracketKeys = true,
                when = function() return GetResourceState(SHOPS) ~= 'missing' end },
            products = { label = 'Product lists', tab = 'Product lists', kind = 'qbproducts', keyed = true, resource = SHOPS, path = 'config.lua', root = 'Config.Products',
                when = function() return GetResourceState(SHOPS) ~= 'missing' end, codeHidden = true, backupKey = 'shops',
                -- a list that shops still sell can't be renamed or deleted
                guard = function(key)
                    local src = LoadResourceFile(SHOPS, 'config.lua') or ''
                    local at = src:find('Config%.Locations%s*=')
                    if not at then return end
                    local body = src:sub(at)
                    local k = tostring(key):gsub('%p', '%%%0')
                    local n = select(2, body:gsub('Config%.Products%[%s*[\'"]' .. k .. '[\'"]%s*%]', ''))
                    n = n + select(2, body:gsub('Config%.Products%.' .. k .. '[^%w_]', ''))
                    if n > 0 then return ('%d shop(s) still sell the "%s" list. Point them at another list first.'):format(n, key) end
                end },
            config = { label = 'Inventory config', kind = 'raw', raw = true, resource = RES, path = 'config/config.lua' },
            vehicles = { label = 'Trunk sizes', kind = 'raw', raw = true, resource = RES, path = 'config/vehicles.lua' },
        },
        order = { 'items', 'weapons', 'shops', 'products', 'config', 'vehicles' },
        pages = {
            { key = 'ed_items', label = 'Items', icon = 'fas fa-box', files = { 'items' } },
            { key = 'ed_weapons', label = 'Weapons', icon = 'fas fa-gun', files = { 'weapons' } },
            { key = 'ed_shops', label = 'Shops', icon = 'fas fa-store', files = { 'shops', 'products' } },
        },
        restartable = { SHOPS },
        bridge = function()
            if GetResourceState(CORE) ~= 'started' then return nil end
            return { live = true, via = CORE }
        end,
        apply = function(file, before, after)
            if file == 'items' then return applyItems(before, after) end
            if file == 'shops' or file == 'products' then return restartShops() end
            if file == 'weapons' then return { ok = true, live = false, note = 'Saved. qb-core reads weapons.lua when it starts, so this applies after the next server restart.' } end
            return { ok = true, live = false, note = ('Saved. %s reads this file when it starts, so restart it or the server to apply.'):format(RES) }
        end,
        image = {
            resource = RES,
            -- every item gets its own <item>.png, so a shared picture like placeholder.png is never overwritten
            path = function(item) return ('html/images/%s.png'):format(item) end,
            -- and the item's `image` field is pointed at it
            field = { file = 'items', path = { 'image' }, value = function(item) return item .. '.png' end },
        },
        sandbox = function(env)
            env.QBShared = {}
            env.QBCore = { Shared = env.QBShared }
            env.Config = {}
            env.Lang = setmetatable({}, { __index = function() return function(_, k) return tostring(k or '') end end })
        end,
    },
})
