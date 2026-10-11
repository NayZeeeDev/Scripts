--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
███╗   ███╗██╗   ██╗██╗  ████████╗██╗ ██████╗██╗  ██╗ █████╗ ██████╗  █████╗  ██████╗████████╗███████╗██████╗
████╗ ████║██║   ██║██║  ╚══██╔══╝██║██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██╔████╔██║██║   ██║██║     ██║   ██║██║     ███████║███████║██████╔╝███████║██║        ██║   █████╗  ██████╔╝
██║╚██╔╝██║██║   ██║██║     ██║   ██║██║     ██╔══██║██╔══██║██╔══██╗██╔══██║██║        ██║   ██╔══╝  ██╔══██╗
██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║╚██████╗██║  ██║██║  ██║██║  ██║██║  ██║╚██████╗   ██║   ███████╗██║  ██║
╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

    MULTICHARACTER SCRIPT - 1.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Framework = 'auto'           -- 'auto' | 'esx' | 'qb' | 'qbox'
Config.Locale    = 'en'             -- file in /locales
Config.Debug     = false            -- console prints for troubleshooting
Config.Doctor    = true             -- print an install report on server start (conflicts, ESX multichar flag, missing deps)

-- ██╗███╗   ██╗████████╗███████╗██████╗ ███████╗ █████╗  ██████╗███████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝█████╗  ███████║██║     █████╗
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══╝  ██╔══██║██║     ██╔══╝
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║  ██║╚██████╗███████╗
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝

Config.UI = {
    title    = 'Character Selection',          -- top-left title (no server branding by default)
    subtitle = 'Choose who you want to be today',

    theme = {                                  -- pushed to the NUI as CSS variables
        accent     = '#08afa2',
        accentHigh = '#0fd4c4',
        accentLow  = '#067d74',
        danger     = '#e5484d',
        background = '#08090a',
        panel      = '#0e1011',
    },

    scale       = 1.0,                         -- base UI scale (players can adjust their own in Settings)
    currency    = { locale = 'en-US', code = 'USD' },
    dateFormat  = 'MM/DD/YYYY',                -- how dates are DISPLAYED: 'MM/DD/YYYY' | 'DD/MM/YYYY' | 'YYYY-MM-DD'
    heightUnit  = 'both',                      -- 'metric' | 'imperial' | 'both'
    showOnline  = true,                        -- online player count in the top bar
    headshots   = true,                        -- live ped portraits on slot cards and the dossier
    nameplates  = true,                        -- clickable name tags above peds in overview
    sounds      = true,                        -- subtle UI sounds (synthesised, no files)

    store = { enabled = true, label = 'Store', url = 'https://your-store.tebex.io' },

    -- kinds: discord, youtube, tiktok, twitch, x, instagram, website, rules
    socials = {
        { kind = 'discord', url = 'https://discord.gg/your-server' },
        { kind = 'website', url = 'https://your-server.com' },
        -- { kind = 'youtube', url = 'https://youtube.com/@your-channel' },
        -- { kind = 'rules',   url = 'https://your-server.com/rules' },
    },

    -- Right-side bulletin shown on the selection screen. Set enabled = false to hide.
    bulletin = {
        enabled = true,
        items = {
            { tag = 'Update', title = 'New season is live', body = 'Fresh jobs, new businesses and a reworked economy. Check the Discord for full notes.', date = '2026-09-24' },
            { tag = 'Event',  title = 'Car meet Saturday',  body = 'Meet at the LS Car Meet at 8 PM EST. Bring your cleanest build.',                     date = '2026-09-27' },
        },
    },

    -- Credits modal. Leave groups empty to hide the button.
    credits = {
        enabled = true,
        groups = {
            { title = 'Management', people = { { name = 'Owner', role = 'Founder' } } },
            { title = 'Development', people = { { name = 'Developer', role = 'Scripts & UI' } } },
        },
    },

    -- Optional title card during the intro camera glide.
    welcome = { enabled = false, title = 'Welcome to the city', text = 'Pick up where you left off, or start a new story.' },
}

-- ███████╗██╗      ██████╗ ████████╗███████╗
-- ██╔════╝██║     ██╔═══██╗╚══██╔══╝██╔════╝
-- ███████╗██║     ██║   ██║   ██║   ███████╗
-- ╚════██║██║     ██║   ██║   ██║   ╚════██║
-- ███████║███████╗╚██████╔╝   ██║   ███████║
-- ╚══════╝╚══════╝ ╚═════╝    ╚═╝   ╚══════╝

Config.Slots = {
    default    = 3,        -- slots everyone gets
    max        = 10,       -- hard cap from all sources combined
    showLocked = 2,        -- extra locked cards shown after the last unlocked slot (0 = hide)

    -- ACE permission -> total slots (highest match wins).  add_ace group.vip nayzeee.slots.vip allow
    ace = {
        ['nayzeee.slots.vip']   = 5,
        ['nayzeee.slots.staff'] = 6,
    },

    -- Specific licenses -> total slots
    licenses = {
        -- ['license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'] = 8,
    },

    -- Discord roles -> total slots (bot token in server.cfg: set nzm_discord_token "BOT_TOKEN")
    discord = {
        enabled = false,
        guild   = '',
        roles   = {
            -- ['123456789012345678'] = 5,
        },
        cacheMinutes = 10,
    },

    -- Slots granted with /mc_addslots or Tebex codes stack ON TOP of the highest value above.
}

--  ██████╗██╗  ██╗ █████╗ ██████╗  █████╗  ██████╗████████╗███████╗██████╗ ███████╗
-- ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
-- ██║     ███████║███████║██████╔╝███████║██║        ██║   █████╗  ██████╔╝███████╗
-- ██║     ██╔══██║██╔══██║██╔══██╗██╔══██║██║        ██║   ██╔══╝  ██╔══██╗╚════██║
-- ╚██████╗██║  ██║██║  ██║██║  ██║██║  ██║╚██████╗   ██║   ███████╗██║  ██║███████║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

Config.Characters = {
    allowDelete   = true,
    deleteAccess  = 'everyone',            -- 'everyone' | 'ace' | 'list'
    deleteAce     = 'nayzeee.multichar.delete',
    deleteList    = {                     -- used when deleteAccess = 'list'
        -- 'license:xxxxxxxx',
    },
    typeToConfirm = true,                  -- player must type the character's full name to delete
    autoSelect    = 'last',                -- 'last' (last played) | 'favorite' | 'first'

    -- Dossier fields (turn off anything you don't want shown)
    fields = {
        citizenid   = true,
        dob         = true,
        age         = true,
        zodiac      = true,
        gender      = true,
        nationality = true,
        height      = true,
        job         = true,
        phone       = true,
        playtime    = true,
        lastPlayed  = true,
        backstory   = true,
        cash        = true,
        bank        = true,
    },

    -- Extra dossier rows computed SERVER-SIDE. Return nil to hide the row for that character.
    -- fn(char) receives the normalised character: char.id, char.slot, char.raw (framework row).
    custom = {
        -- { label = 'Vehicles', icon = 'fa-car', fn = function(char)
        --     return MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE owner = ?', { char.id })
        -- end },
    },
}

-- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   ██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
-- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Registration = {
    name = {
        min           = 2,
        max           = 16,
        autoCapitalize = true,              -- "jOHN" -> "John"
        uniqueFullName = true,              -- block duplicate first + last name across the server
        blacklist     = { 'admin', 'staff', 'moderator', 'owner', 'developer', 'police', 'test', 'nigger', 'nigga', 'faggot' },
    },
    dob = {
        minAge  = 18,
        maxAge  = 90,
        storage = 'DD/MM/YYYY',             -- ESX users.dateofbirth format (match esx_identity). QB always stores YYYY-MM-DD.
    },
    height = { enabled = true, min = 150, max = 210, default = 175 },   -- centimetres
    nationality = { enabled = true, required = true, default = 'American' },
    backstory   = { enabled = true, required = false, min = 20, max = 600 },
    genders     = { 'm', 'f' },
}

-- ███████╗ ██████╗███████╗███╗   ██╗███████╗
-- ██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝
-- ███████╗██║     █████╗  ██╔██╗ ██║█████╗
-- ╚════██║██║     ██╔══╝  ██║╚██╗██║██╔══╝
-- ███████║╚██████╗███████╗██║ ╚████║███████╗
-- ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═══╝╚══════╝

Config.Scene = {
    pick        = 'random',      -- 'random' | 'first' | a scene id from config/scenes.lua. Players can override in Settings.
    playerPick  = true,          -- allow players to choose a scene in Settings
    intro       = true,          -- glide from the scene's intro camera into the overview
    introTime   = 3500,          -- ms
    dof         = true,          -- depth of field on focus shots (players can disable with FPS mode)
    shake       = { enabled = true, type = 'HAND_SHAKE', amplitude = 0.12 },
    focusTime   = 1100,          -- ms camera fly time between characters
    ghostEmpty  = true,          -- translucent silhouette ped on empty slots
    ghostAlpha  = 110,           -- 0-255
    lockedAlpha = 45,
    distance    = { close = 1.55, normal = 2.1, far = 2.9 },   -- focus shot distance per Settings choice
    snapToGround = true,         -- stand every lineup ped on the real floor (fixes peds sunk into / floating over the ground)
    footHeight  = 1.0,           -- ped root height above the floor; nudge (e.g. 0.98 / 1.02) only if feet clip or float
}

-- Poses players can pick per character (Pose button). Positions with lockPose = true keep their scene animation.
Config.Poses = {
    { id = 'relaxed',  label = 'Relaxed',     dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss' },
    { id = 'guard',    label = 'Confident',   dict = 'anim@amb@nightclub@peds@',            clip = 'rcmme_amanda1_stand_loop_cop' },
    { id = 'crossed',  label = 'Arms crossed', scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    { id = 'phone',    label = 'On the phone', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { id = 'coffee',   label = 'Coffee',      scenario = 'WORLD_HUMAN_AA_COFFEE' },
    { id = 'smoke',    label = 'Smoking',     scenario = 'WORLD_HUMAN_SMOKING' },
    { id = 'lean',     label = 'Leaning',     scenario = 'WORLD_HUMAN_LEANING' },
    { id = 'impatient',label = 'Impatient',   scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    { id = 'flex',     label = 'Flex',        scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
    { id = 'cheer',    label = 'Hyped',       scenario = 'WORLD_HUMAN_CHEERING' },
    { id = 'tourist',  label = 'Photo',       scenario = 'WORLD_HUMAN_TOURIST_MOBILE' },
    { id = 'drink',    label = 'Drinking',    scenario = 'WORLD_HUMAN_DRINKING' },
}

--  ██████╗██████╗ ███████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║     ██████╔╝█████╗  ███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
-- ╚██████╗██║  ██║███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Creation = {
    -- Where the new character stands while the appearance editor is open (routing bucket keeps it private).
    appearanceCoords = vec4(-1037.64, -2737.76, 20.17, 327.0),
    -- Seconds of "find a good spot" countdown before the editor opens (0 = off)
    countdown = 0,
}

-- ███████╗████████╗ █████╗ ██████╗ ████████╗███████╗██████╗     ██████╗  █████╗  ██████╗██╗  ██╗
-- ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔══██╗    ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
-- ███████╗   ██║   ███████║██████╔╝   ██║   █████╗  ██████╔╝    ██████╔╝███████║██║     █████╔╝
-- ╚════██║   ██║   ██╔══██║██╔══██╗   ██║   ██╔══╝  ██╔══██╗    ██╔═══╝ ██╔══██║██║     ██╔═██╗
-- ███████║   ██║   ██║  ██║██║  ██║   ██║   ███████╗██║  ██║    ██║     ██║  ██║╚██████╗██║  ██╗
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

-- Given once to every NEW character.
Config.Starter = {
    money = { cash = 500, bank = 5000 },
    items = {
        { name = 'phone', count = 1 },
        { name = 'water', count = 2 },
        { name = 'bread', count = 2 },
        -- { name = 'id_card', count = 1, metadata = function(src, char) return { firstname = char.firstname, lastname = char.lastname } end },
    },
    frameworkDefaults = false,      -- QB/Qbox: also give QBCore.Shared.StarterItems
}

-- Optional shop after creation: spend a starting budget on items and vehicles.
Config.StarterShop = {
    enabled   = true,
    budget    = 6500,
    refundLeftover = true,     -- unspent budget goes to the bank account
    imagePath = 'nui://ox_inventory/web/images/%s.png',   -- %s = item name. Vehicles use `image` or the car icon.
    items = {
        { type = 'item',    name = 'sandwich',    label = 'Sandwich',     price = 300,  max = 5 },
        { type = 'item',    name = 'water',       label = 'Water',        price = 150,  max = 5 },
        { type = 'item',    name = 'phone',       label = 'Phone',        price = 1500, max = 1 },
        { type = 'item',    name = 'radio',       label = 'Radio',        price = 900,  max = 1 },
        { type = 'item',    name = 'bandage',     label = 'Bandage',      price = 250,  max = 5 },
        { type = 'item',    name = 'lockpick',    label = 'Lockpick',     price = 600,  max = 2 },
        { type = 'vehicle', name = 'blista',      label = 'Blista',       price = 3500, max = 1 },
        { type = 'vehicle', name = 'faggio',      label = 'Faggio',       price = 1200, max = 1 },
        { type = 'vehicle', name = 'bmx',         label = 'BMX',          price = 600,  max = 1 },
    },
}

-- ███████╗██████╗  █████╗ ██╗    ██╗███╗   ██╗
-- ██╔════╝██╔══██╗██╔══██╗██║    ██║████╗  ██║
-- ███████╗██████╔╝███████║██║ █╗ ██║██╔██╗ ██║
-- ╚════██║██╔═══╝ ██╔══██║██║███╗██║██║╚██╗██║
-- ███████║██║     ██║  ██║╚███╔███╔╝██║ ╚████║
-- ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═══╝

Config.Spawn = {
    selector      = true,       -- show the spawn selector after picking a character
    forNew        = false,      -- new characters also get the selector (false = they spawn at firstSpawn)
    lastLocation  = true,       -- "Last location" option
    houses        = true,       -- owned houses from bridge/server/housing.lua
    firstSpawn    = vec4(-1037.64, -2737.76, 20.17, 327.0),   -- LSIA arrivals
    transition    = 'switch',   -- 'switch' (GTA sky zoom) | 'fade'
    preview       = { height = 140.0, back = 90.0, fov = 42.0, time = 1400 },   -- aerial preview camera over each point

    -- Hand the player to another spawn resource instead (the selector is skipped).
    -- The event fires client-side with (charId, isNew) after the character is loaded.
    custom = { enabled = false, event = 'my-spawn:client:open', newOnly = false },
}
-- Spawn points live in config/spawns.lua

-- ██████╗ ███████╗██╗      ██████╗  ██████╗
-- ██╔══██╗██╔════╝██║     ██╔═══██╗██╔════╝
-- ██████╔╝█████╗  ██║     ██║   ██║██║  ███╗
-- ██╔══██╗██╔══╝  ██║     ██║   ██║██║   ██║
-- ██║  ██║███████╗███████╗╚██████╔╝╚██████╔╝
-- ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝

Config.Relog = {
    command  = { enabled = true, name = 'relog', ace = false, cooldown = 30 },   -- ace = false (everyone) or 'nayzeee.multichar.relog'
    points   = {
        { coords = vec3(-1045.07, -2750.11, 21.36), label = 'Change character', blip = true },
    },
    blip     = { sprite = 480, color = 2, scale = 0.8, name = 'Change Character' },
    interact = 'textui',          -- 'textui' (press E) | 'target' (ox_target)
    distance = 1.6,
}

-- ██████╗  █████╗ ██████╗ ████████╗███╗   ██╗███████╗██████╗
-- ██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝████╗  ██║██╔════╝██╔══██╗
-- ██████╔╝███████║██████╔╝   ██║   ██╔██╗ ██║█████╗  ██████╔╝
-- ██╔═══╝ ██╔══██║██╔══██╗   ██║   ██║╚██╗██║██╔══╝  ██╔══██╗
-- ██║     ██║  ██║██║  ██║   ██║   ██║ ╚████║███████╗██║  ██║
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝

-- /partner [id] [couple|friend] while playing. The partner's character appears next to yours in the lineup.
Config.Partner = {
    enabled = true,
    command = 'partner',
    offset  = vec3(0.95, 0.15, 0.0),     -- partner position relative to your character (right, forward, up)
    poses   = {
        couple = { dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss' },
        friend = { scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    },
}

-- ███╗   ███╗██╗   ██╗███████╗██╗ ██████╗
-- ████╗ ████║██║   ██║██╔════╝██║██╔════╝
-- ██╔████╔██║██║   ██║███████╗██║██║
-- ██║╚██╔╝██║██║   ██║╚════██║██║██║
-- ██║ ╚═╝ ██║╚██████╔╝███████║██║╚██████╗
-- ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝ ╚═════╝

-- Background music on the selection screen. YouTube links or direct .mp3/.ogg streams. Players can mute or change it.
Config.Music = {
    enabled = false,
    url     = 'https://www.youtube.com/watch?v=jfKfPfyJRdk',
    volume  = 0.15,
}

-- ██╗    ██╗ ██████╗ ██████╗ ██╗     ██████╗
-- ██║    ██║██╔═══██╗██╔══██╗██║     ██╔══██╗
-- ██║ █╗ ██║██║   ██║██████╔╝██║     ██║  ██║
-- ██║███╗██║██║   ██║██╔══██╗██║     ██║  ██║
-- ╚███╔███╔╝╚██████╔╝██║  ██║███████╗██████╔╝
--  ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝

Config.World = {
    routingBucket = true,     -- isolate each player while in character selection
    bucketBase    = 7000,     -- bucket = bucketBase + server id
    noPopulation  = true,     -- no ambient peds or traffic inside the selection bucket
    weathers      = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'SMOG', 'FOGGY', 'RAIN', 'THUNDER', 'CLEARING', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN' },
    filters       = {         -- timecycle modifiers players can pick
        { id = '',                        label = 'None' },
        { id = 'MP_corona_heist_DOF',     label = 'Soft focus' },
        { id = 'cinema',                  label = 'Cinema' },
        { id = 'MP_Arena_theme_night',    label = 'Night neon' },
        { id = 'NG_filmic02',             label = 'Filmic' },
        { id = 'hud_def_desat_Neutral',   label = 'Desaturated' },
        { id = 'MP_Powerplay_blend',      label = 'Vivid' },
    },
}
