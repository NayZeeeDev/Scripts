--[[
    ox_inventory integration.
    Works with ESX, QBCore, Qbox, ox_core and ND on ox_inventory 2.30+. The optional bridge
    (ox_bridge/nayzeee) makes editor saves live without restarting ox_inventory.
]]
local RES = (Config.OxInventory and Config.OxInventory.resource) or Config.Editor.resource or 'ox_inventory'
local ox = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports[RES][fn](nil, ...) end end })

local function decode(s)
    if type(s) == 'table' then return s end
    if not s or s == '' then return {} end
    local ok, v = pcall(json.decode, s)
    return ok and type(v) == 'table' and v or {}
end

local function toOx(items)
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = { name = it.name, count = it.count, slot = it.slot, metadata = (it.metadata and next(it.metadata)) and it.metadata or nil }
    end
    return out
end

-- vehicle table columns differ per framework, read them once
local vehicleCols
local function vehicleColumns()
    if vehicleCols ~= nil then return vehicleCols end
    local rows = MySQL.query.await('SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { NZ.DB.vehicles }) or {}
    local have = {}
    for _, r in ipairs(rows) do have[r.c] = true end
    vehicleCols = { trunk = have.trunk, glovebox = have.glovebox, key = have.plate and 'plate' or NZ.DB.vcol }
    return vehicleCols
end

local function rows(query, params, fn)
    local list = MySQL.query.await(query, params or {}) or {}
    for i, r in ipairs(list) do
        fn(r)
        if i % 150 == 0 then Wait(0) end
    end
end

-- ─── bridge (live editor) ───────────────────────────────────────────────────
local function bridgeInfo()
    if GetResourceState(RES) ~= 'started' then return nil end
    local ok, info = pcall(function() return exports[RES]:nzInfo() end)
    if ok and type(info) == 'table' then return info end
end

-- ─── logging ────────────────────────────────────────────────────────────────
-- ESX cash lives in ox_inventory; moving it between inventories isn't income or spending
local function accountMove(slot, count, fromType, toType, fromInv, toInv)
    if type(slot) ~= 'table' or not IsAccountItem(slot.name) then return end
    count = tonumber(count) or slot.count or 0
    if (fromType == 'player' or fromType == 'otherplayer') and tonumber(fromInv) then AdjustBaseline(tonumber(fromInv), slot.name, -count) end
    if (toType == 'player' or toType == 'otherplayer') and tonumber(toInv) then AdjustBaseline(tonumber(toInv), slot.name, count) end
end

local function watch(log)
    local ids = {}
    ids[#ids + 1] = ox:registerHook('swapItems', function(p)
        local src = tonumber(p.source)
        if not src then return end
        local kind = log.Classify(p.fromType, p.toType, p.fromInventory, p.toInventory)
        accountMove(p.fromSlot, p.count, p.fromType, p.toType, p.fromInventory, p.toInventory)
        if p.action == 'swap' and type(p.toSlot) == 'table' then
            accountMove(p.toSlot, p.toSlot.count, p.toType, p.fromType, p.toInventory, p.fromInventory)
        end
        if type(p.fromSlot) == 'table' and p.fromInventory ~= p.toInventory then
            log.Rapid(src, p.fromSlot.name, p.fromInventory, p.toInventory, p.count)
        end
        if kind then
            log.Move(src, kind, p.fromSlot, p.count, p.fromInventory, p.toInventory)
            -- a swap moves the destination stack back the other way
            if p.action == 'swap' and type(p.toSlot) == 'table' then
                local back = log.Classify(p.toType, p.fromType, p.toInventory, p.fromInventory)
                if back then log.Move(src, back, p.toSlot, p.toSlot.count, p.toInventory, p.fromInventory) end
            end
        end
    end, { print = false })

    ids[#ids + 1] = ox:registerHook('buyItem', function(p)
        local src = tonumber(p.source)
        if not src then return end
        local item = p.itemName or 'unknown'
        local shop = ('%s%s'):format(p.shopType or 'shop', p.shopId and (' #' .. p.shopId) or '')
        local price = tonumber(p.totalPrice or p.price) or 0
        local currency = p.currency or 'money'
        log.Shop(src, item, p.count or 1, shop, price, currency, p.metadata, p.toInventory)
        if price > 0 and IsAccountItem(currency) then
            AdjustBaseline(src, currency, -price)
            LogMoneyChange(src, currency, -price, ('Shop: %s'):format(shop), RES)
        end
    end, { print = false })

    ids[#ids + 1] = ox:registerHook('craftItem', function(p)
        local src = tonumber(p.source)
        if not src then return end
        local recipe = type(p.recipe) == 'table' and p.recipe or {}
        log.Craft(src, recipe.name or 'unknown', recipe.count or 1, p.benchId, recipe.ingredients, recipe.metadata)
    end, { print = false })

    ids[#ids + 1] = ox:registerHook('createItem', function(p)
        local playerId = tonumber(p.inventoryId)
        local item = type(p.item) == 'table' and p.item.name or nil
        if not playerId or not item then return end
        log.Created(playerId, item, p.count, p.resource, p.metadata)
    end, { print = false })

    NZ.Print(('Watching ox_inventory: %d hooks registered.'):format(#ids))
    return function()
        for _, id in ipairs(ids) do pcall(function() ox:removeHooks(id) end) end
    end
end

-- ─── integration ────────────────────────────────────────────────────────────
Inventories.Register('ox_inventory', {
    label = 'ox_inventory',
    resource = RES,
    priority = 10,
    detect = function() return GetResourceState(RES) ~= 'missing' end,
    imagepath = function() return GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images') end,
    uniqueKeys = { 'serial' },
    accountItems = function()
        if NZ.Framework == 'esx' then return { money = true, black_money = true } end
    end,
    limits = function() return { slots = GetConvarInt('inventory:slots', 50), weight = GetConvarInt('inventory:weight', 30000) } end,
    weaponMeta = function(serial) return { durability = 100, ammo = 0, components = {}, serial = serial } end,
    ids = {
        trunk = function(plate) return 'trunk' .. plate end,
        glovebox = function(plate) return 'glove' .. plate end,
    },

    items = function()
        local out = {}
        for name, v in pairs(ox:Items() or {}) do
            if type(v) == 'table' and name ~= 'cash' then
                local c = type(v.client) == 'table' and v.client or {}
                out[name] = { label = v.label, weight = v.weight, stack = v.stack ~= false, weapon = v.weapon == true, description = v.description,
                    image = type(c.image) == 'string' and c.image or nil }
            end
        end
        return out
    end,

    getItems = function(inv)
        local ok, data = pcall(function() return ox:GetInventory(inv, false) end)
        if not ok or not data or not data.items then return nil end
        return data.items, { label = data.label, type = data.type, weight = data.weight, maxWeight = data.maxWeight, slots = data.slots, owner = data.owner }
    end,
    addItem = function(inv, name, count, metadata, slot)
        local ok, resp = ox:AddItem(inv, name, count, metadata, slot)
        return ok and true or false, resp
    end,
    removeItem = function(inv, name, count, metadata, slot)
        local have = slot and ((ox:GetSlot(inv, slot) or {}).count or 0) or (ox:GetItemCount(inv, name, metadata, false) or 0)
        local take = math.min(have, count)
        if take <= 0 then return 0 end
        return ox:RemoveItem(inv, name, take, metadata, slot) and take or 0
    end,
    canCarry = function(src, name, count, metadata) return ox:CanCarryItem(src, name, count, metadata) end,
    clear = function(src, keep) ox:ClearInventory(src, keep) end,
    owner = function(src)
        local ok, inv = pcall(function() return ox:GetInventory(src, false) end)
        if ok and inv and inv.owner then return tostring(inv.owner) end
    end,
    save = function()
        ExecuteCommand('saveinv')
        Wait(1500)
    end,

    -- offline characters: the character table's `inventory` column in ox format
    offline = {
        read = function(charId)
            local row = MySQL.single.await(('SELECT `inventory` FROM `%s` WHERE `%s` = ? LIMIT 1'):format(NZ.DB.players, NZ.DB.pcol), { charId })
            if not row then return nil end
            return decode(row.inventory)
        end,
        write = function(charId, items)
            return MySQL.update.await(('UPDATE `%s` SET `inventory` = ? WHERE `%s` = ?'):format(NZ.DB.players, NZ.DB.pcol), { json.encode(toOx(items)), charId }) ~= nil
        end,
        each = function(fn, like)
            local q = ('SELECT `%s` AS `id`, `inventory` FROM `%s` WHERE `inventory` IS NOT NULL AND `inventory` <> \'[]\''):format(NZ.DB.pcol, NZ.DB.players)
            local p = {}
            if like then q = q .. ' AND `inventory` LIKE ?' p[1] = '%"' .. like .. '"%' end
            rows(q, p, function(r) fn(r.id, decode(r.inventory)) end)
        end,
    },

    -- stashes (ox_inventory table), trunks and gloveboxes (vehicle table)
    storage = {
        each = function(fn, like, kinds)
            kinds = kinds or { stash = true, trunk = true, glovebox = true }
            local lk = like and ('%"' .. like .. '"%') or nil
            if kinds.stash then
                rows('SELECT `owner`, `name`, `data` FROM `ox_inventory`' .. (lk and ' WHERE `data` LIKE ?' or ''), { lk }, function(r)
                    local id = (r.owner and r.owner ~= '') and ('%s:%s'):format(r.name, r.owner) or r.name
                    fn(id, 'stash', r.name, decode(r.data), r.owner ~= '' and r.owner or nil)
                end)
            end
            local cols = vehicleColumns()
            for _, col in ipairs({ 'trunk', 'glovebox' }) do
                if kinds[col] and cols[col] then
                    local ok = pcall(rows, ('SELECT `%s` AS `k`, `%s` AS `data` FROM `%s` WHERE `%s` IS NOT NULL%s'):format(cols.key, col, NZ.DB.vehicles, col, lk and (' AND `' .. col .. '` LIKE ?') or ''), { lk }, function(r)
                        local id = (col == 'trunk' and 'trunk' or 'glove') .. tostring(r.k)
                        fn(id, col, tostring(r.k), decode(r.data))
                    end)
                    if not ok then vehicleCols = nil end
                end
            end
        end,
        read = function(id)
            local plate = id:match('^trunk(.+)$') or id:match('^glove(.+)$')
            if plate then
                local col = id:sub(1, 5) == 'trunk' and 'trunk' or 'glovebox'
                local cols = vehicleColumns()
                local ok, row = pcall(MySQL.single.await, ('SELECT `%s` AS `data` FROM `%s` WHERE `%s` = ? LIMIT 1'):format(col, NZ.DB.vehicles, cols.key), { plate })
                if ok and row then return decode(row.data), id end
                return nil
            end
            local name, owner = id:match('^(.-):(.+)$')
            local row = MySQL.single.await("SELECT `data` FROM `ox_inventory` WHERE `name` = ? AND `owner` = ? LIMIT 1", { name or id, owner or '' })
            if row then return decode(row.data), name or id end
        end,
        write = function(id, items)
            local data = json.encode(toOx(items))
            local plate = id:match('^trunk(.+)$') or id:match('^glove(.+)$')
            if plate then
                local col = id:sub(1, 5) == 'trunk' and 'trunk' or 'glovebox'
                return MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(NZ.DB.vehicles, col, vehicleColumns().key), { data, plate })
            end
            local name, owner = id:match('^(.-):(.+)$')
            return MySQL.update.await('UPDATE `ox_inventory` SET `data` = ? WHERE `name` = ? AND `owner` = ?', { data, name or id, owner or '' })
        end,
    },

    watch = watch,

    -- ─── editor ──────────────────────────────────────────────────────────────
    editor = {
        resource = RES,
        files = {
            items = { label = 'Items', kind = 'item', keyed = true, path = 'data/items.lua' },
            weapons = { label = 'Weapons', kind = 'weapon', keyed = true, categories = true, path = 'data/weapons.lua' },
            shops = { label = 'Shops', kind = 'shop', keyed = true, path = 'data/shops.lua' },
            stashes = { label = 'Stashes', kind = 'stash', keyed = false, path = 'data/stashes.lua' },
            crafting = { label = 'Crafting', kind = 'crafting', keyed = false, path = 'data/crafting.lua' },
            evidence = { label = 'Evidence', kind = 'evidence', keyed = false, path = 'data/evidence.lua' },
            licenses = { label = 'Licenses', kind = 'license', keyed = false, path = 'data/licenses.lua' },
            animations = { label = 'Animations', kind = 'anim', keyed = true, categories = true, path = 'data/animations.lua' },
            vehicles = { label = 'Vehicles', kind = 'vehicle', raw = true, path = 'data/vehicles.lua' },
        },
        order = { 'items', 'weapons', 'shops', 'stashes', 'crafting', 'evidence', 'licenses', 'animations', 'vehicles' },
        pages = {
            { key = 'ed_items', label = 'Items', icon = 'fas fa-box', files = { 'items' } },
            { key = 'ed_weapons', label = 'Weapons', icon = 'fas fa-gun', files = { 'weapons' } },
            { key = 'ed_shops', label = 'Shops', icon = 'fas fa-store', files = { 'shops' } },
            { key = 'ed_stashes', label = 'Stashes', icon = 'fas fa-warehouse', files = { 'stashes' } },
            { key = 'ed_crafting', label = 'Crafting', icon = 'fas fa-screwdriver-wrench', files = { 'crafting' } },
            { key = 'ed_other', label = 'Other data', icon = 'fas fa-folder-tree', files = { 'evidence', 'licenses', 'animations' } },
        },
        restartable = { RES },
        bridge = function()
            local info = bridgeInfo()
            if info then info.live = true end
            return info
        end,
        -- writes go through the bridge (it runs inside ox_inventory, which FiveM allows)
        write = function(path, content)
            local info = bridgeInfo()
            if info and (tonumber(info.version) or 0) >= 3 then
                local ok, res = pcall(function() return exports[RES]:nzWrite(path, content) end)
                if ok and type(res) == 'table' and res.ok then return true end
            end
        end,
        apply = function(file)
            if not bridgeInfo() then
                return { ok = true, live = false, note = 'Saved. Install the ox_inventory bridge from INSTALL.md to apply edits without a restart.' }
            end
            local ok, res = pcall(function() return exports[RES]:nzApply(file) end)
            if not ok then return { ok = false, err = tostring(res) } end
            return res
        end,
        image = {
            path = function(item) return ('web/images/%s.png'):format(item) end,
            live = function(item, dataUri)
                if not bridgeInfo() then return false end
                return pcall(function() exports[RES]:nzImage(item, dataUri) end)
            end,
        },
        sandbox = function(env)
            local police = json.decode(GetConvar('inventory:police', '["police", "sheriff"]'))
            if type(police) == 'string' then police = { police } end
            local p = {}
            for _, j in ipairs(police or {}) do p[j] = 0 end
            env.shared = {
                resource = RES, framework = GetConvar('inventory:framework', 'esx'), police = p,
                target = GetConvar('inventory:target', 'false') == 'true',
                playerslots = GetConvarInt('inventory:slots', 50), playerweight = GetConvarInt('inventory:weight', 30000),
            }
        end,
    },
})
