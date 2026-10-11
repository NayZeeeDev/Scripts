--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
 █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝
    Version 1.0.0  ·  discord.gg/nayzeeedev  ·  nayzeee-dev.gitbook.io/docs
]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝
Config.Locale          = 'en'           -- locales/<code>.lua
Config.Debug           = false          -- prints extra info to the F8 / server console
Config.AutoInstallSQL  = true           -- creates the database tables on first start
Config.Framework       = 'auto'         -- 'auto' | 'esx' | 'qb' | 'qbox' | 'standalone'
Config.Inventory       = 'auto'         -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'esx'
Config.ItemImages      = 'nui://ox_inventory/web/images/%s.png'  -- %s = item name
Config.VehicleImages   = 'https://docs.fivem.net/vehicles/%s.webp' -- %s = model name

-- Licenses listed here always have full access, even with an empty database.
-- Use license2 or license. Find yours in txAdmin or the server console on join.
Config.Owners = {
    -- 'license:0000000000000000000000000000000000000000',
}

Config.HierarchyProtection = true       -- staff can't act on staff at the same or a higher level
Config.DefaultDuty         = true       -- staff start on duty when they join
Config.StaffLoginNotify    = true       -- tell on-duty staff when a staff member joins

--  ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗ ███████╗
-- ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝
-- ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
-- key = false means no default key. Players can still bind it in Settings > Key Bindings > FiveM.
-- The panel and quick menu also close on their own key while they are open.
Config.Commands = {
    panel     = { name = 'admin',    key = 'F10',  enabled = true },  -- full panel
    quick     = { name = 'adminq',   key = 'F9',   enabled = true },  -- right side quick menu
    noclip    = { name = 'noclip',   key = false,  enabled = true },
    tpm       = { name = 'tpm',      key = false,  enabled = true },  -- teleport to waypoint
    back      = { name = 'back',     key = false,  enabled = true },  -- teleport to last position
    tp        = { name = 'tp',       enabled = true },                -- /tp id | /tp x y z
    bring     = { name = 'bring',    enabled = true },
    ['goto']  = { name = 'goto',     enabled = true },
    spectate  = { name = 'spectate', enabled = true },
    kick      = { name = 'kick',     enabled = true },
    ban       = { name = 'ban',      enabled = true },                -- /ban id 1d2h reason
    warn      = { name = 'warn',     enabled = true },
    jail      = { name = 'jail',     enabled = true },                -- /jail id 30m reason
    unjail    = { name = 'unjail',   enabled = true },
    sentence  = { name = 'sentence', enabled = true },                -- players check their jail time
    report    = { name = 'report',   key = false, enabled = true },   -- players open the report window
    staff     = { name = 'staff',    enabled = true },                -- list online staff
    announce  = { name = 'announce', enabled = true },
    duty      = { name = 'staffduty',enabled = true },
    admincar  = { name = 'admincar', enabled = true },                -- save the car you sit in to your garage
    names     = { name = 'names',    key = false, enabled = true },
    coords    = { name = 'coords',   enabled = true },
    inspector = { name = 'inspect',  key = false, enabled = true },
    palette   = { name = 'adminsearch', key = false, enabled = true },-- opens the panel straight into the search palette
    staffchat = { name = 'sc',       enabled = true },                -- /sc message · quick message to every staff member online
    revive    = { name = 'revive',   enabled = true },                -- /revive [id] · turn off if your ambulance job owns /revive
    heal      = { name = 'heal',     enabled = true },                -- /heal [id]
    car       = { name = 'car',      enabled = true },                -- /car model
    dv        = { name = 'dv',       enabled = true },                -- delete the vehicle you sit in or stand next to
    fix       = { name = 'fix',      enabled = true },                -- repair the vehicle you sit in
}

-- Extra admin actions you can put on a key. They show in Settings > Key Bindings > FiveM
-- under this resource. '' = no default key (each staff member binds what they want), false = not registered.
-- Nothing here runs a loop, a key press just fires the action once.
Config.Keybinds = {
    duty       = '',    -- toggle duty
    god        = '',    -- god mode
    invis      = '',    -- invisibility
    ids        = '',    -- player IDs over heads
    freeze     = '',    -- freeze yourself
    heal       = '',    -- heal yourself
    revive     = '',    -- revive yourself
    repair     = '',    -- repair your vehicle
    flip       = '',    -- flip your vehicle
    delveh     = '',    -- delete your vehicle / the closest one
    copycoords = '',    -- copy vec4 to clipboard
    reports    = '',    -- open the panel on Reports
    players    = '',    -- open the panel on Players
}

-- ███╗   ███╗ ██████╗ ██████╗ ███████╗██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ████╗ ████║██╔═══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██╔████╔██║██║   ██║██║  ██║█████╗  ██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██║╚██╔╝██║██║   ██║██║  ██║██╔══╝  ██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
-- ██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
Config.Bans = {
    SkipIdentifiers = { 'ip' },         -- keep 'ip' here if you run behind a proxy, or everyone shares one IP
    UseTokens       = true,             -- also match hardware tokens (catches most alt accounts)
    Message         = 'You are banned.\nReason: %s\nExpires: %s\nBan ID: #%s\nAppeal: discord.gg/yourserver',
    Presets = {                          -- quick picks in the ban window
        { label = 'Cheating',          duration = 'perm' },
        { label = 'Combat logging',    duration = '3d'   },
        { label = 'RDM / VDM',         duration = '1d'   },
        { label = 'Metagaming',        duration = '12h'  },
        { label = 'Staff disrespect',  duration = '2d'   },
    },
    Durations = { '1h', '6h', '12h', '1d', '3d', '7d', '30d', 'perm' },
}

Config.Warnings = {
    MaxBeforeBan    = 3,                -- 0 turns off auto bans
    AutoBanDuration = '1d',
    AutoBanReason   = 'Maximum warnings reached',
    ScreenSeconds   = 12,               -- how long the warning covers the player's screen
    Presets = { 'Fail RP', 'Power gaming', 'NLR', 'Toxicity', 'Ignoring staff' },
}

Config.Flags = {                         -- labels you can pin to players (shown over heads with names on)
    { id = 'suspicious', label = 'Suspicious', color = '#e5484d' },
    { id = 'watch',      label = 'Watchlist',  color = '#e5a50a' },
    { id = 'trusted',    label = 'Trusted',    color = '#08afa2' },
    { id = 'streamer',   label = 'Streamer',   color = '#9146ff' },
}

--      ██╗ █████╗ ██╗██╗
--      ██║██╔══██╗██║██║
--      ██║███████║██║██║
-- ██   ██║██╔══██║██║██║
-- ╚█████╔╝██║  ██║██║███████╗
--  ╚════╝ ╚═╝  ╚═╝╚═╝╚══════╝
Config.Jail = {
    Enabled     = true,
    TimeMode    = 'playtime',           -- 'playtime' counts down only while online | 'date' expires at a fixed time
    CheckEvery  = 5000,                 -- ms between leash checks on the jailed player (not a per-frame loop)
    ReleaseAt   = vector4(432.76, -982.06, 30.70, 274.96), -- used when the saved position is missing
    RemoveWeapons = true,
    Cells = {
        { name = 'Cell 1', coords = vector4(459.57, -1001.68, 24.9, 266.29), radius = 5.0 },
        { name = 'Cell 2', coords = vector4(458.89, -998.03,  24.9, 269.29), radius = 5.0 },
        { name = 'Cell 3', coords = vector4(460.50, -994.34,  24.9, 269.29), radius = 5.0 },
    },
}

-- ██████╗ ███████╗██████╗  ██████╗ ██████╗ ████████╗███████╗
-- ██╔══██╗██╔════╝██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝█████╗  ██████╔╝██║   ██║██████╔╝   ██║   ███████╗
-- ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║██╔══██╗   ██║   ╚════██║
-- ██║  ██║███████╗██║     ╚██████╔╝██║  ██║   ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝
Config.Reports = {
    Enabled       = true,
    MaxOpen       = 1,                  -- open reports per player
    Cooldown      = 60,                 -- seconds between new reports
    MaxLength     = 500,
    Categories    = { 'General', 'Player report', 'Bug', 'Stuck', 'Question' },
    SoundForStaff = true,
}

Config.Chats = {
    MaxLength       = 500,
    HistoryPerRoom  = 80,               -- messages loaded when a room opens
}

-- ███████╗████████╗ █████╗ ███████╗███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝
-- ███████╗   ██║   ███████║█████╗  █████╗
-- ╚════██║   ██║   ██╔══██║██╔══╝  ██╔══╝
-- ███████║   ██║   ██║  ██║██║     ██║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝
Config.Staff = {
    TrackDuty     = true,               -- duty sessions + daily totals
    Sprites       = true,               -- on-duty staff see each other on the map
    SpriteRefresh = 4000,               -- ms, only runs while you are on duty
    DutyOutfits   = true,               -- equip the group outfit when going on duty
    NameDistance  = 45.0,               -- names / IDs over heads range
}

-- Default groups created on first start. Edit them in the panel afterwards.
Config.DefaultGroups = {
    { name = 'owner',     label = 'Owner',     hierarchy = 100, color = '#e5484d', permissions = { '*' } },
    { name = 'admin',     label = 'Admin',     hierarchy = 80,  color = '#08afa2', permissions = { '*' } },
    { name = 'moderator', label = 'Moderator', hierarchy = 50,  color = '#58a6ff', permissions = {
        'self.panel', 'self.quickmenu', 'self.noclip', 'self.teleport', 'self.player_names', 'self.player_ids', 'self.show_coords',
        'player.spectate', 'player.teleport', 'player.kick', 'player.warn', 'player.freeze', 'player.revive', 'player.heal',
        'player.jail', 'player.jail_remove', 'player.view_notes', 'player.create_notes', 'player.notify', 'player.ban',
        'reports.view', 'reports.close', 'chats.view', 'logs.view', 'moderation.view.warnings', 'moderation.view.bans',
        'moderation.view.jail', 'statistics.view', 'staff.view', 'map.view',
    } },
    { name = 'support',   label = 'Support',   hierarchy = 20,  color = '#e5a50a', permissions = {
        'self.panel', 'self.quickmenu', 'self.noclip', 'self.teleport', 'player.teleport', 'player.spectate',
        'reports.view', 'reports.close', 'chats.view', 'player.notify', 'player.revive',
    } },
}

-- Optional: mirror groups into ACE so other resources that check ACE see your staff.
Config.Ace = {
    Enabled = false,
    Principal = 'group.%s',             -- %s = group name
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝
-- Role sync: members of a Discord role are given the linked group automatically on join.
-- Link a role to a group in Staff > Groups. Needs a bot in your guild with the Server Members intent.
Config.Discord = {
    RoleSync = false,
    Guild    = '',
    Token    = '',                      -- keep this private, it is only read on the server
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝
Config.Logs = {
    Enabled    = true,
    KeepDays   = 14,                    -- older rows are removed once a day
    TagDiscord = true,                  -- mention the player's Discord in webhooks
    Deaths     = true,                  -- log deaths with killer, weapon and position (feeds the death heatmap)
    Joins      = true,
    Chat       = false,                 -- chat logs can be very heavy on busy servers
    Webhooks = {                         -- leave '' to skip Discord for that category
        staff       = '',
        moderation  = '',
        reports     = '',
        joins       = '',
        deaths      = '',
        money       = '',
        developer   = '',
        screenshots = '',
        chat        = '',
    },
}

-- ██╗    ██╗ ██████╗ ██████╗ ██╗     ██████╗
-- ██║    ██║██╔═══██╗██╔══██╗██║     ██╔══██╗
-- ██║ █╗ ██║██║   ██║██████╔╝██║     ██║  ██║
-- ██║███╗██║██║   ██║██╔══██╗██║     ██║  ██║
-- ╚███╔███╔╝╚██████╔╝██║  ██║███████╗██████╔╝
--  ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝
Config.Weather = {
    Builtin  = false,                   -- true = this resource syncs weather/time itself
    Resource = 'auto',                  -- when Builtin is false: 'auto' (qb-weathersync if running, else builtin) | 'qb-weathersync' | 'custom' (config/hooks.lua)
    Types    = { 'EXTRASUNNY', 'CLEAR', 'NEUTRAL', 'SMOG', 'FOGGY', 'OVERCAST', 'CLOUDS', 'CLEARING', 'RAIN', 'THUNDER', 'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN' },
}

Config.Props = {
    StreamDistance = 150.0,             -- persistent props spawn inside this range
    StreamInterval = 1500,              -- ms between distance checks
}

Config.VehicleWipe = {
    Countdown = { 60, 30, 10 },         -- seconds before the wipe that players are warned
    SkipOccupied = true,
    SkipOwned    = true,                -- keep vehicles whose plate is in the owned vehicles table
}

Config.Map = {
    -- Drop a GTA map image into web/img/ and point to it here, or use any https URL.
    -- Bounds are the world coordinates of the image corners.
    Image  = '',
    Bounds = { minX = -4000.0, maxX = 6000.0, minY = -4000.0, maxY = 8000.0 },
    Refresh = 2000,                     -- ms between position pushes while the map is open
}

-- ██╗███╗   ██╗████████╗███████╗ ██████╗ ██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██║  ███╗██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██║   ██║██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
-- ██║██║ ╚████║   ██║   ███████╗╚██████╔╝██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
Config.Integrations = {
    Notify     = 'auto',                -- 'auto' | 'nayzeee-notify' | 'ox_lib' | 'esx' | 'qb'
    Revive     = 'auto',                -- 'auto' | 'wasabi_ambulance' | 'esx_ambulancejob' | 'qb-ambulancejob' | 'qbx_medical' | 'native'
    Keys       = 'auto',                -- 'auto' | 'wasabi_carlock' | 'qb-vehiclekeys' | 'qbx_vehiclekeys' | 'MrNewbVehicleKeys' | 'none'
    Fuel       = 'auto',                -- 'auto' | 'ox_fuel' | 'LegacyFuel' | 'cdn-fuel' | 'none'
    Clothing   = 'auto',                -- 'auto' | 'illenium-appearance' | 'fivem-appearance' | 'qb-clothing' | 'esx_skin'
    Voice      = 'pma-voice',           -- staff call channel. 'pma-voice' | 'none'
    Screenshot = 'screenshot-basic',    -- 'screenshot-basic' | 'none'
    StaffCallChannel = 9000,            -- call channels start here, one per staff member
}

-- Owned vehicle table. Defaults match ESX Legacy and QBCore.
Config.VehicleTable = {
    esx  = { table = 'owned_vehicles',  owner = 'owner',     plate = 'plate', props = 'vehicle', stored = 'stored', storedValue = 1 },
    qb   = { table = 'player_vehicles', owner = 'citizenid', plate = 'plate', props = 'mods',    stored = 'state',  storedValue = 1, model = 'vehicle', hash = 'hash', license = 'license', garage = 'garage', defaultGarage = 'pillboxgarage' },
}

-- ██╗   ██╗██╗
-- ██║   ██║██║
-- ██║   ██║██║
-- ██║   ██║██║
-- ╚██████╔╝██║
--  ╚═════╝ ╚═╝
Config.UI = {
    Accent   = '#08afa2',
    Danger   = '#e5484d',
    Scale    = 1.0,                     -- players can change their own scale in Settings
    Sounds   = true,
    AnnouncementSeconds = 10,
}
