--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
    ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
    ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
    ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

    Inventory Manager · v3.2.0
    Discord: discord.gg/nayzeeedev
]]

Config = {}


-- ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
-- ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
-- █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
-- ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
-- ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

Config.Framework = 'auto'           -- 'auto' | 'esx' | 'qbcore' | 'qbx'
Config.Debug = false                -- print extra detail to the server console
Config.NotifyStaff = true           -- tell online staff when someone gives, removes, wipes or rolls back
Config.AllowRemoteView = true       -- let staff open any stash/trunk/glovebox from a log line
Config.BackpackPrefixes = { 'bag_', 'backpack_' } -- stash ids that are backpacks (wasabi_backpack uses bag_)

-- ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
-- ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
-- ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
-- ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
-- ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
-- ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

-- Which inventory the panel works with. 'auto' picks the first one installed:
-- ox_inventory, then qb-inventory. Use 'custom' for your own (fill in inventories/custom.lua).
-- The panel changes to match: its sidebar, editor pages, stashes and item images all follow this.
Config.Inventory = 'auto'           -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'custom'

-- Folder names, only change these if you renamed a resource
Config.OxInventory = { resource = 'ox_inventory' }
Config.QBInventory = { resource = 'qb-inventory', core = 'qb-core', shops = 'qb-shops' }

-- ██████╗ ███████╗██████╗ ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔══██╗████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝█████╗  ██████╔╝██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ██╔═══╝ ██╔══╝  ██╔══██╗██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ██║     ███████╗██║  ██║██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Framework groups for each tier. You can also grant a tier with the ACE `nayzeee.inventory.<tier>`,
-- for example: add_ace group.admin nayzeee.inventory.view allow
-- Any tier also grants `view`. Groups that are not listed get nothing.
Config.Permissions = {
    view     = { 'admin', 'superadmin', 'god', 'owner' },  -- open the panel, read logs, look at inventories
    manage   = { 'admin', 'superadmin', 'god', 'owner' },  -- give, remove, set amounts, wipe one player
    global   = { 'superadmin', 'god', 'owner' },           -- give to everyone, remove an item server-wide
    editor   = { 'god', 'owner' },                         -- edit ox_inventory items, shops, stashes, crafting
    rollback = { 'god', 'owner' },                         -- money + inventory snapshots and rollbacks
    wipe     = { 'god', 'owner' },                         -- delete logs
}

--  ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗ ███████╗
-- ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝
-- ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝

Config.Commands = {
    open      = 'inventorymanager',  -- opens the panel
    give      = 'igive',             -- /igive [id] [item] [amount]      (set to false to disable)
    remove    = 'iremove',           -- /iremove [id] [item] [amount]
    giveAll   = 'igiveall',          -- /igiveall [item] [amount]
    removeAll = 'iremoveall',        -- /iremoveall [item]
}
Config.OpenKey = ''                  -- optional keybind, e.g. 'F10' (players can rebind it in settings)

-- ██╗███╗   ██╗████████╗███████╗██████╗ ███████╗ █████╗  ██████╗███████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝█████╗  ███████║██║     █████╗
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══╝  ██╔══██║██║     ██╔══╝
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║  ██║╚██████╗███████╗
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝

Config.UI = {
    scale = 1.0,               -- 0.8 to 1.2, whole panel size
    accent = '#08afa2',        -- main accent colour
    danger = '#e5484d',        -- destructive actions and the Close pill
    sounds = true,             -- quiet UI clicks
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Logs = {
    PerPage = 50,                -- rows per page in the log view
    LiveRefreshSeconds = 5,      -- how often live mode checks for new rows while the panel is open
    RetentionDays = 0,           -- delete logs older than this (0 keeps everything)
    AuditRetentionDays = 0,      -- same for the staff audit trail
    ExportLimit = 10000,         -- max rows in a CSV export

    -- set any type to false to stop recording it
    Enabled = {
        drop = true, pickup = true, give = true, take = true,
        stash_put = true, stash_take = true, trunk_put = true, trunk_take = true,
        glovebox_put = true, glovebox_take = true, container_put = true, container_take = true,
        evidence_put = true, evidence_take = true, backpack_put = true, backpack_take = true,
        shop = true, craft = true, created = true, suspicious = true, money = true,
        admin_give = true, admin_remove = true, global_give = true, global_remove = true, rollback = true,
        dupe = true, dupe_attempt = true, supply_spike = true,
    },

    -- order and labels of the type filter in the panel
    Types = {
        { id = 'all', label = 'Everything' },
        { id = 'admin', label = 'Staff actions' },
        { id = 'suspicious', label = 'Flagged' },
        { id = 'dupes', label = 'Dupe alerts' },
        { id = 'dupe', label = 'Duplicate found' },
        { id = 'dupe_attempt', label = 'Dupe attempt' },
        { id = 'supply_spike', label = 'Supply spike' },
        { id = 'created', label = 'Item created' },
        { id = 'give', label = 'Player to player' },
        { id = 'take', label = 'Taken from player' },
        { id = 'drop', label = 'Dropped' },
        { id = 'pickup', label = 'Picked up' },
        { id = 'stash_put', label = 'Stash deposit' },
        { id = 'stash_take', label = 'Stash withdrawal' },
        { id = 'trunk_put', label = 'Trunk deposit' },
        { id = 'trunk_take', label = 'Trunk withdrawal' },
        { id = 'glovebox_put', label = 'Glovebox deposit' },
        { id = 'glovebox_take', label = 'Glovebox withdrawal' },
        { id = 'backpack_put', label = 'Backpack deposit' },
        { id = 'backpack_take', label = 'Backpack withdrawal' },
        { id = 'container_put', label = 'Container deposit' },
        { id = 'container_take', label = 'Container withdrawal' },
        { id = 'evidence_put', label = 'Evidence deposit' },
        { id = 'evidence_take', label = 'Evidence withdrawal' },
        { id = 'shop', label = 'Shop purchase' },
        { id = 'craft', label = 'Crafting' },
        { id = 'money', label = 'Money' },
        { id = 'admin_give', label = 'Staff gave' },
        { id = 'admin_remove', label = 'Staff removed' },
        { id = 'global_give', label = 'Server-wide give' },
        { id = 'global_remove', label = 'Server-wide removal' },
        { id = 'rollback', label = 'Rollback' },
    },

    -- badge colours in the panel
    Colors = {
        drop = '#e5484d', pickup = '#46a758', give = '#4c9aff', take = '#f76b15',
        stash_put = '#e5a50a', stash_take = '#e5a50a', trunk_put = '#8e4ec6', trunk_take = '#8e4ec6',
        glovebox_put = '#12a594', glovebox_take = '#12a594', container_put = '#9ea5aa', container_take = '#9ea5aa',
        evidence_put = '#f76b15', evidence_take = '#f76b15', backpack_put = '#ad7f58', backpack_take = '#ad7f58',
        shop = '#ffc53d', craft = '#d6409f', created = '#08afa2', suspicious = '#e5484d', money = '#3e63dd',
        admin_give = '#46a758', admin_remove = '#e5484d', global_give = '#46a758', global_remove = '#e5484d', rollback = '#e5a50a',
        dupe = '#e5484d', dupe_attempt = '#f76b15', supply_spike = '#e5a50a',
    },
}

-- ██╗    ██╗███████╗██████╗ ██╗  ██╗ ██████╗  ██████╗ ██╗  ██╗███████╗
-- ██║    ██║██╔════╝██╔══██╗██║  ██║██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
-- ██║ █╗ ██║█████╗  ██████╔╝███████║██║   ██║██║   ██║█████╔╝ ███████╗
-- ██║███╗██║██╔══╝  ██╔══██╗██╔══██║██║   ██║██║   ██║██╔═██╗ ╚════██║
-- ╚███╔███╔╝███████╗██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║  ██╗███████║
--  ╚══╝╚══╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

--[[
    HOW DISCORD LOGS ARE ROUTED
    Every log has a type (give, stash_put, money...). It's sent to the first webhook it finds:

        1. its own type in `types`          e.g. types.stash_put
        2. `groups.weapons`                 only when the item is a weapon
        3. its group in `groups`            e.g. groups.storage
        4. `everything`

    Leave a URL empty ('') and that step is skipped. If nothing matches, that log isn't sent.

    Quick start:  one channel for everything → paste one URL into `everything`.
    Most servers: one channel per group     → fill `groups`, leave `types` empty.
    Split one out: e.g. stash withdrawals    → fill `types.stash_take` as well.
]]
Config.Webhooks = {
    everything = '',                -- catch-all for any log without a URL below

    groups = {
        players  = '',              -- player to player: give, take (search/rob), drop, pickup
        storage  = '',              -- stashes, backpacks, containers, evidence: put in / take out
        vehicles = '',              -- trunks and gloveboxes: put in / take out
        weapons  = '',              -- any weapon moving anywhere (goes here instead of the groups above)
        shops    = '',              -- shop purchases and crafting
        created  = '',              -- items a script put into a player's inventory (drug sales, jobs, heists...)
        money    = '',              -- money in and out, with the script and reason (see Config.MoneyLogs.webhookMinimum)
        security = '',              -- flagged items, money spikes, duplicate items, dupe attempts, supply spikes
        staff    = '',              -- staff gives/removes, server-wide actions, rollbacks, data editor saves
    },

    types = {                       -- optional: send one type to its own channel instead of its group
        give = '', take = '', drop = '', pickup = '',
        stash_put = '', stash_take = '', backpack_put = '', backpack_take = '',
        container_put = '', container_take = '', evidence_put = '', evidence_take = '',
        trunk_put = '', trunk_take = '', glovebox_put = '', glovebox_take = '',
        shop = '', craft = '', created = '', money = '',
        suspicious = '',            -- flagged items and money spikes
        dupe = '',                  -- duplicate items, dupe attempts, supply spikes
        admin_give = '', admin_remove = '',
        global = '',                -- server-wide give/remove
        rollback = '', editor = '',
    },
}

-- How the logs look in Discord
Config.DiscordLogs = {
    name = 'Inventory Manager',     -- name the webhook posts as
    avatar = '',                    -- picture the webhook posts with (image URL, optional)
    footer = 'Inventory Manager',   -- small text at the bottom of every log
    showServerName = true,          -- add your server name to the footer
    showIdentifiers = true,         -- Discord mention, character id and license on player cards (IPs are never sent)
    showCoords = true,              -- where it happened
    showMetadata = true,            -- serial, durability, ammo and other item details
    itemImages = '',                -- item picture next to each log: a public https link with %s for the item name,
                                    -- e.g. 'https://cdn.yoursite.com/items/%s.png'. Empty = use your inventory's
                                    -- image path when it's an https link, otherwise no picture
    batchSeconds = 2,               -- logs for the same channel are sent together (up to 10 per message) so Discord doesn't rate limit you

    mentions = {                    -- ping a role on important logs: '<@&ROLE_ID>'. Works per group or per type
        security = '',
        -- dupe = '<@&123456789012345678>',
    },

    colors = {                      -- side colour per group or type (types win)
        players = 0x4C9AFF, storage = 0xE5A50A, vehicles = 0x8E4EC6, shops = 0xFFC53D, created = 0x08AFA2,
        security = 0xE5484D, staff = 0x46A758,
        drop = 0xE5484D, pickup = 0x46A758, take = 0xF76B15, craft = 0xD6409F,
        weapon = 0xB8262B, money_in = 0x46A758, money_out = 0xE5484D,
        admin_remove = 0xE5484D, global = 0xE5A50A, rollback = 0xE5A50A, editor = 0x08AFA2,
    },
}

-- ██████╗ ███████╗████████╗███████╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║  ██║█████╗     ██║   █████╗  ██║        ██║   ██║██║   ██║██╔██╗ ██║
-- ██║  ██║██╔══╝     ██║   ██╔══╝  ██║        ██║   ██║██║   ██║██║╚██╗██║
-- ██████╔╝███████╗   ██║   ███████╗╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

-- Every item that lands in a player's inventory is checked with the resource that created it.
Config.Suspicious = {
    enabled = true,
    notifyStaff = true,                 -- in-game alert to online staff
    flagWeapons = true,                 -- any WEAPON_ item from an untrusted resource is flagged
    watchlist = { 'money', 'black_money', 'gold', 'diamond', 'goldbar' },
    thresholds = {                      -- flag when a single add is at least this much
        money = 50000,
        black_money = 25000,
        gold = 10,
        diamond = 5,
    },
    -- items created by these resources are never flagged (shops, crafting and ox commands run inside ox_inventory)
    trustedResources = { 'ox_inventory', 'nayzeee-inventorylogs' },
    -- always flag anything these resources create, even if it isn't on the watchlist
    alwaysCheckResources = {},
}

-- "Item created" logs: which script created each item, for every player
Config.CreationLogs = {
    enabled = true,
    ignoreItems = { 'money', 'black_money' },  -- money already has its own logs
    ignoreResources = {},                      -- skip noisy resources here
}

-- ███╗   ███╗ ██████╗ ███╗   ██╗███████╗██╗   ██╗
-- ████╗ ████║██╔═══██╗████╗  ██║██╔════╝╚██╗ ██╔╝
-- ██╔████╔██║██║   ██║██╔██╗ ██║█████╗   ╚████╔╝
-- ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══╝    ╚██╔╝
-- ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████╗   ██║
-- ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝

-- Install framework_bridge/nayzeee.lua (INSTALL.md) to see which script paid or charged each player.
Config.MoneyLogs = {
    enabled = true,
    minimumAmount = 0,          -- ignore changes smaller than this
    webhookMinimum = 1000,      -- only send webhooks for changes this big
    esxPollSeconds = 15,        -- ESX: how often balances are checked for cash that moved inside ox_inventory
    velocity = {
        enabled = true,
        windowMinutes = 5,      -- rolling window
        amount = 250000,        -- flag a character whose NET gain (all accounts together) hits this inside the window
    },
}

--  █████╗ ███╗   ██╗████████╗██╗    ██████╗ ██╗   ██╗██████╗ ███████╗
-- ██╔══██╗████╗  ██║╚══██╔══╝██║    ██╔══██╗██║   ██║██╔══██╗██╔════╝
-- ███████║██╔██╗ ██║   ██║   ██║    ██║  ██║██║   ██║██████╔╝█████╗
-- ██╔══██║██║╚██╗██║   ██║   ██║    ██║  ██║██║   ██║██╔═══╝ ██╔══╝
-- ██║  ██║██║ ╚████║   ██║   ██║    ██████╔╝╚██████╔╝██║     ███████╗
-- ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝    ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝

Config.AntiDupe = {
    enabled = true,
    notifyStaff = true,
    scanMinutes = 30,              -- full scan of every inventory on this interval
    keys = {},                     -- extra metadata fields that must be unique (the inventory adds its own: serial on ox, serie on qb)
    ignoreValues = { 'POL' },      -- values that are shared on purpose (ox police armoury uses serial POL)
    includeOffline = true,         -- scan offline characters too
    includeStashes = true,
    includeVehicles = true,
    supply = {
        enabled = true,
        percent = 40,              -- flag an item whose server-wide total grows this much between scans
        minimum = 50,              -- ...and by at least this many
        keepDays = 7,              -- history kept for the supply charts
        ignore = { 'money', 'black_money' },
    },
    rapid = {
        enabled = true,            -- same item moved between the same two inventories over and over
        moves = 15,
        seconds = 10,
    },
}

-- ███████╗████████╗ █████╗ ███████╗███████╗    ██████╗  ██████╗  █████╗ ██████╗ ██████╗
-- ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝    ██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔══██╗
-- ███████╗   ██║   ███████║█████╗  █████╗      ██████╔╝██║   ██║███████║██████╔╝██║  ██║
-- ╚════██║   ██║   ██╔══██║██╔══╝  ██╔══╝      ██╔══██╗██║   ██║██╔══██║██╔══██╗██║  ██║
-- ███████║   ██║   ██║  ██║██║     ██║         ██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝         ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝

Config.StaffBoard = {
    itemsPerDay = 500,             -- highlight staff who hand out more items than this per day
    moneyPerDay = 1000000,         -- highlight staff who hand out more money than this per day
}

-- ██████╗  ██████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗
-- ██╔══██╗██╔═══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
-- ██████╔╝██║   ██║██║     ██║     ██████╔╝███████║██║     █████╔╝
-- ██╔══██╗██║   ██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗
-- ██║  ██║╚██████╔╝███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗
-- ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

Config.Rollback = {
    enabled = true,
    money = true,               -- snapshot money accounts
    inventory = true,           -- snapshot player inventories
    interval = 300,             -- seconds between snapshots
    keep = 24,                  -- snapshots kept per kind (24 x 5 min = 2 hours)
}

--  ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗
-- ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║
-- ██║  ███╗██║     ██║   ██║██████╔╝███████║██║
-- ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗
--  ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

Config.GlobalActions = {
    maxGive = 1000,             -- largest amount one give can hand out (per player)
    scanLimit = 5000,           -- max rows read per table when searching for an item
}

-- ███████╗██████╗ ██╗████████╗ ██████╗ ██████╗
-- ██╔════╝██╔══██╗██║╚══██╔══╝██╔═══██╗██╔══██╗
-- █████╗  ██║  ██║██║   ██║   ██║   ██║██████╔╝
-- ██╔══╝  ██║  ██║██║   ██║   ██║   ██║██╔══██╗
-- ███████╗██████╔╝██║   ██║   ╚██████╔╝██║  ██║
-- ╚══════╝╚═════╝ ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

-- In-panel editor for ox_inventory/data/*.lua. Install the bridge from INSTALL.md for live updates.
Config.Editor = {
    enabled = true,
    liveApply = true,           -- push edits to the running server and every player right away
    backups = 25,               -- automatic backups kept per file (restorable from the panel)
    imageMaxKB = 256,           -- largest PNG you can upload for an item

    -- Edits made OUTSIDE the game (FTP, txAdmin file editor, VS Code...) are picked up and applied live.
    -- A broken file is never applied: staff get the error and the old version keeps running.
    watchFiles = true,          -- watch the data files (items.lua, weapons.lua, shops.lua...)
    watchImages = true,         -- new or replaced pictures in the image folder show for players without a restart (ox_inventory + bridge)
    watchSeconds = 3,           -- how often to look for changes
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝

Config.Discord = {
    enabled = false,            -- show Discord avatars on player cards
    botToken = '',              -- bot with the Server Members intent
    guildId = '',
    cacheSeconds = 600,
}
