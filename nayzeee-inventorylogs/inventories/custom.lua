--[[
    ────────────────────────────────────────────────────────────────────────────
     Your own inventory
    ────────────────────────────────────────────────────────────────────────────
    Use this file to connect an inventory the manager doesn't support out of the box
    (qs-inventory, codem-inventory, core_inventory, tgiann, your own...).

    1. Set Config.Inventory = 'custom' in config.lua.
    2. Change RESOURCE below to your inventory's resource name.
    3. Fill in the functions. Only the four marked REQUIRED are needed for the panel to work;
       everything else switches a feature on (the comments say which).
    4. Restart nayzeee-inventorylogs. The console prints "Inventory: <label>" when it's picked up.

    Items always use one shape inside the manager, and every function below receives and returns
    that shape (convert to and from your inventory's own format inside the function):

        { slot = 1, name = 'water', count = 3, metadata = { serial = 'ABC123' } }

    Functions may also return your inventory's own item tables if they already use `slot`, `name`
    and `count` (or `amount`) and `metadata` (or `info`); the manager converts those for you.

    `inv` means either a player's server id (number) or an inventory id (string), for example a
    stash or trunk id in whatever format your inventory uses.

    Want it shipped with the script? Send it to NAYZEEE Development and we'll add it for everyone.
    ────────────────────────────────────────────────────────────────────────────
]]
local RESOURCE = 'my_inventory'   -- the resource name of your inventory

Inventories.Register('custom', {
    label = 'My inventory',            -- shown in the panel's sidebar and status bar
    resource = RESOURCE,
    auto = false,                      -- only used when Config.Inventory = 'custom'

    -- Where the inventory's item images are, used for thumbnails in the panel
    imagepath = ('nui://%s/html/images'):format(RESOURCE),

    -- Metadata fields that make one copy unique (anti-dupe looks for the same value in two places)
    uniqueKeys = { 'serial' },

    -- Database table for characters, when your inventory keeps player items somewhere else than the
    -- framework default (users.inventory on ESX, players.inventory on QBCore). Leave nil otherwise.
    -- db = { players = 'users', pcol = 'identifier' },

    -- Item names that are really money (ESX setups that keep cash as an item). nil if none.
    -- accountItems = { money = true, black_money = true },

    -- REQUIRED. Every item the inventory knows: { [name] = { label, weight, stack, weapon, description, image } }
    items = function()
        local out = {}
        -- for name, v in pairs(exports[RESOURCE]:GetItemList()) do
        --     out[name] = { label = v.label, weight = v.weight, stack = not v.unique, weapon = v.type == 'weapon', description = v.description, image = v.image }
        -- end
        return out
    end,

    -- REQUIRED. Items in a loaded inventory. Return nil when it isn't loaded.
    -- Second return value (optional): { label, type, weight, maxWeight, slots }
    getItems = function(inv)
        -- local data = exports[RESOURCE]:GetInventory(inv)
        -- if not data then return nil end
        -- return data.items, { label = data.label, maxWeight = data.maxWeight, slots = data.slots }
        return nil
    end,

    -- REQUIRED. Add an item. Return true, or false plus a reason.
    addItem = function(inv, name, count, metadata, slot)
        -- return exports[RESOURCE]:AddItem(inv, name, count, metadata, slot)
        return false, 'addItem is not set up in inventories/custom.lua'
    end,

    -- REQUIRED. Remove up to `count` copies (only ones whose metadata contains `metadata`, and only
    -- from `slot` when given). Return how many were removed.
    removeItem = function(inv, name, count, metadata, slot)
        -- local have = exports[RESOURCE]:GetItemCount(inv, name, metadata)
        -- local take = math.min(have, count)
        -- if take > 0 and exports[RESOURCE]:RemoveItem(inv, name, take, metadata, slot) then return take end
        return 0
    end,

    -- Optional: player inventory size, used when editing offline characters
    limits = function() return { slots = 50, weight = 30000 } end,

    -- Optional: metadata for a weapon given by staff when your inventory doesn't create its own
    -- weaponMeta = function(serial) return { serial = serial, durability = 100, ammo = 0 } end,

    -- Optional: can this player carry it? Used by give actions unless "ignore weight" is ticked.
    canCarry = function(src, name, count, metadata)
        return true
    end,

    -- Optional: wipe a player's inventory (keep = list of item names to keep, may be nil)
    clear = function(src, keep)
        -- exports[RESOURCE]:ClearInventory(src, keep)
    end,

    -- Optional: character id that owns a player's inventory (only needed if your framework isn't detected)
    -- owner = function(src) return nil end,

    -- Optional: write everything held in memory to the database before a scan reads it
    save = function()
        -- exports[RESOURCE]:SaveAll()
    end,

    -- Optional: offline characters. Turns on offline editing, offline search, anti-dupe and find item
    -- for players who aren't online.
    offline = {
        -- read = function(charId)
        --     local row = MySQL.single.await('SELECT `inventory` FROM `users` WHERE `identifier` = ?', { charId })
        --     return row and json.decode(row.inventory or '[]') or nil
        -- end,
        -- write = function(charId, items)
        --     MySQL.update.await('UPDATE `users` SET `inventory` = ? WHERE `identifier` = ?', { json.encode(items), charId })
        -- end,
        -- each = function(fn, like)   -- call fn(charId, items) for every character; `like` is an item name you may filter on
        --     for _, r in ipairs(MySQL.query.await('SELECT `identifier`, `inventory` FROM `users`') or {}) do
        --         fn(r.identifier, json.decode(r.inventory or '[]'))
        --     end
        -- end,
    },

    -- Optional: stashes, trunks and gloveboxes. Turns on the Stashes browser, find item and anti-dupe for them.
    storage = {
        -- each = function(fn, like, kinds)   -- fn(id, kind, label, items, owner); kind = 'stash' | 'trunk' | 'glovebox'
        -- end,
        -- read = function(id) return items, label end,
        -- write = function(id, items) end,
    },

    -- Optional: how your inventory names vehicle storage
    ids = {
        -- trunk = function(plate) return 'trunk:' .. plate end,
        -- glovebox = function(plate) return 'glovebox:' .. plate end,
    },

    -- Optional: live item logs. `log` has:
    --   log.Classify(fromType, toType, fromInv, toInv)       -> log type ('give', 'stash_put', 'drop', ...)
    --        types: 'player', 'otherplayer', 'drop', 'stash', 'trunk', 'glovebox', 'container', 'evidence', 'backpack'
    --   log.Move(src, kind, { name, label, metadata }, count, fromInv, toInv)
    --   log.Rapid(src, itemName, fromInv, toInv, count)      -> dupe-attempt detector, call on every move
    --   log.Shop(src, item, count, shopLabel, price, currency, metadata)
    --   log.Craft(src, item, count, bench, { ingredient = amount }, metadata)
    --   log.Created(playerId, item, count, resourceThatAddedIt, metadata, reason)
    -- Return a function that removes your listeners (called when the manager stops).
    --
    -- If your inventory has no events to listen to, it (or any script) can report instead:
    --   exports['nayzeee-inventorylogs']:LogMove({ source = src, item = 'water', count = 1, fromType = 'player', toType = 'stash', from = src, to = 'police_locker' })
    --   exports['nayzeee-inventorylogs']:LogShop({ source = src, item = 'water', count = 1, shop = '24/7', price = 5, currency = 'cash' })
    --   exports['nayzeee-inventorylogs']:LogCraft({ source = src, item = 'lockpick', count = 1, bench = 'mechanic' })
    --   exports['nayzeee-inventorylogs']:LogCreated({ source = src, item = 'weed_bag', count = 5 })
    watch = nil,
    -- watch = function(log)
    --     local handler = AddEventHandler('my_inventory:itemMoved', function(src, item, count, fromType, toType, fromId, toId)
    --         local kind = log.Classify(fromType, toType, fromId, toId)
    --         log.Rapid(src, item.name, fromId, toId, count)
    --         if kind then log.Move(src, kind, item, count, fromId, toId) end
    --     end)
    --     return function() RemoveEventHandler(handler) end
    -- end,

    -- Optional: the live data-file editor. Each file is a Lua table the panel can edit.
    --   path  = file inside `resource`
    --   root  = where the table is: nil for a file that ends in `return { ... }`, or a path such as
    --           'Config.Items' for `Config.Items = { ... }`
    --   kind  = form to show: 'qbitem', 'item' (ox style), 'shop', 'stash' ... or 'raw' for code only
    -- The panel can only write into another resource if server.cfg allows it:
    --   add_filesystem_permission nayzeee-inventorylogs write my_inventory
    -- or if that resource includes bridge/nz_writer.lua (see INSTALL.md).
    editor = nil,
    -- editor = {
    --     resource = RESOURCE,
    --     files = {
    --         items = { label = 'Items', kind = 'qbitem', keyed = true, path = 'shared/items.lua', root = 'Config.Items', inline = true },
    --     },
    --     order = { 'items' },
    --     pages = { { key = 'ed_items', label = 'Items', icon = 'fas fa-box', files = { 'items' } } },
    --     apply = function(file, before, after) return { ok = true, live = false, note = 'Saved. Restart the inventory to apply.' } end,
    -- },
})
