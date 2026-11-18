--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    MULTICHARACTER — CINEMATIC LOBBY  ·  2.0.0
    Discord: discord.gg/nayzeeedev

    Config files
      config.lua        general, UI, start screen, slots, registration, camera, lighting, audio, squad, spawn
      themes.lua        the 8 lobby scenes (slots, props, vehicles, lights, cameras, departure cutscenes)
      moods.lua         lighting / mood presets (Golden Hour, Midnight Neon, ...)
      poses.lua         solo poses + handheld props, couple animations
      weapons.lua       showcase weapon modes, whitelist, per-class hold animations
      pets.lua          companion pets + idle animations
      spawns.lua        spawn selector points
      server.lua        server-only (webhooks, tebex, admin ace)
]]

Config = {}

-- ███████╗███████╗████████╗██╗   ██╗██████╗
-- ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
-- ███████╗█████╗     ██║   ██║   ██║██████╔╝
-- ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
-- ███████║███████╗   ██║   ╚██████╔╝██║
-- ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝

Config.Framework = 'auto'           -- 'auto' | 'esx' | 'qb' | 'qbox'
Config.Locale    = 'en'             -- file in /locales
Config.Debug     = false            -- console prints for troubleshooting
Config.Doctor    = true             -- print an install report on server start

-- Each player waits in their own routing bucket while in the lobby (nobody sees the lobby peds / you)
Config.Bucket = {
    enabled      = true,
    base         = 7000,            -- bucket = base + server id
    noPopulation = true,            -- no ambient peds / traffic inside the lobby bucket
}

-- ██╗   ██╗██╗
-- ██║   ██║██║
-- ██║   ██║██║
-- ██║   ██║██║
-- ╚██████╔╝██║
--  ╚═════╝ ╚═╝

Config.UI = {
    serverName = 'NAYZEEE',                    -- wordmark top-left + start screen
    tagline    = 'Roleplay',
    logo       = '',                           -- optional image url (nui://, https://). Empty = text wordmark
    accent     = 'teal',                       -- key from `accents` below, or a hex like '#08afa2'
    accents    = {                             -- players can't change this; it's your brand
        teal   = { '#0fd4c4', '#08afa2', '#067d74' },   -- high, base, low
        gold   = { '#f3d58a', '#d8b35a', '#9c7a2e' },
        orange = { '#ff8a4c', '#f2622e', '#b8401a' },
        violet = { '#b79bff', '#8b6cf6', '#5d40c4' },
        red    = { '#ff6b6f', '#e5484d', '#b8262b' },
    },
    scale      = 1.0,                          -- base UI scale (players can adjust their own in Settings)
    currency   = { locale = 'en-US', code = 'USD' },
    dateFormat = 'MM/DD/YYYY',                 -- DISPLAY format: 'MM/DD/YYYY' | 'DD/MM/YYYY' | 'YYYY-MM-DD'
    showOnline = true,                         -- online count in the top-right pill
    nameplates = true,                         -- floating name tags above lobby peds

    -- icon = discord | youtube | tiktok | twitch | x | instagram | website | store
    socials = {
        { icon = 'discord', label = 'Discord', url = 'https://discord.gg/your-server' },
        { icon = 'website', label = 'Website', url = 'https://your-server.com' },
        { icon = 'store',   label = 'Store',   url = 'https://your-store.tebex.io' },
    },

    -- Key hints shown bottom-left (purely visual – the keys are handled by the UI)
    keys = {
        deploy   = 'Enter',
        switch   = 'Q / E',
        camera   = 'Tab',
        customize = 'C',
        back     = 'Esc',
    },
}

-- "PRESS ENTER TO CONTINUE" title screen shown once the loading screen is gone (skipped on /relog)
Config.StartScreen = {
    enabled  = true,
    prompt   = 'Press ENTER to continue',
    subtitle = 'Connected as %s',              -- %s = FiveM player name
    orbit    = true,                           -- slow camera orbit around the lobby behind the title
    music    = '',                             -- optional audio url played on the start screen (empty = theme ambience)

    -- Loading screen -> title transition. Your loading screen should NOT close itself: add
    --   loadscreen_manual_shutdown 'yes'
    -- to its fxmanifest so it stays up while the lobby builds. If it closes early anyway, a black veil covers it.
    revealTime    = 1800,                      -- ms the black veil takes to dissolve over the scene
    pushInTime    = 4800,                      -- ms slow camera push-in onto the title shot
    pushBack      = 0.45,                      -- how far back the push-in starts (fraction of the camera distance)
    pushUp        = 1.1,                       -- metres higher the push-in starts
    interfaceLead = 900,                       -- after ENTER, lobby panels slide in this many ms before the camera lands
}

-- ███████╗██╗      ██████╗ ████████╗███████╗
-- ██╔════╝██║     ██╔═══██╗╚══██╔══╝██╔════╝
-- ███████╗██║     ██║   ██║   ██║   ███████╗
-- ╚════██║██║     ██║   ██║   ██║   ╚════██║
-- ███████║███████╗╚██████╔╝   ██║   ███████║
-- ╚══════╝╚══════╝ ╚═════╝    ╚═╝   ╚══════╝

Config.Slots = {
    default    = 3,        -- slots everyone gets
    max        = 8,        -- hard cap from all sources combined
    showLocked = 1,        -- locked teaser rows shown after the last unlocked slot (0 = hide)

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
    -- Slots granted with /mc_addslots, codes or Tebex stack ON TOP of the highest value above.
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
    deleteList    = {},                    -- licenses, used when deleteAccess = 'list'
    typeToConfirm = true,                  -- player must type the character's full name to delete
    autoSelect    = 'last',                -- 'last' (last played) | 'favorite' | 'first'
}

Config.Registration = {
    name = {
        min            = 2,
        max            = 16,
        autoCapitalize = true,             -- "jOHN" -> "John"
        uniqueFullName = true,             -- block duplicate first + last name across the server
        blacklist      = { 'admin', 'staff', 'moderator', 'owner', 'developer', 'police', 'test' },
    },
    dob = {
        minAge  = 18,
        maxAge  = 90,
        storage = 'DD/MM/YYYY',            -- ESX users.dateofbirth format (match esx_identity). QB always stores YYYY-MM-DD.
    },
    height      = { enabled = true, min = 150, max = 210, default = 175 },   -- centimetres
    nationality = { enabled = true, required = true, default = 'American' },
    backstory   = { enabled = false, required = false, min = 20, max = 600 },
    genders     = { 'm', 'f' },
}

-- Where a NEW character stands while the appearance editor is open (inside the lobby bucket)
Config.Creation = {
    coords = vec4(-1037.64, -2737.76, 20.17, 327.0),
}

-- Given once to every NEW character
Config.Starter = {
    money = { cash = 500, bank = 5000 },
    items = {
        { name = 'phone', count = 1 },
        { name = 'water', count = 2 },
        { name = 'bread', count = 2 },
    },
    frameworkDefaults = false,             -- QB/Qbox: also give QBCore.Shared.StarterItems
}

-- ███████╗ ██████╗███████╗███╗   ██╗███████╗
-- ██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝
-- ███████╗██║     █████╗  ██╔██╗ ██║█████╗
-- ╚════██║██║     ██╔══╝  ██║╚██╗██║██╔══╝
-- ███████║╚██████╗███████╗██║ ╚████║███████╗
-- ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═══╝╚══════╝

Config.Scene = {
    defaultTheme = 'supercar',             -- used when a character has no saved theme and no auto rule matches
    playerPick   = true,                   -- players can switch theme / mood in the lobby
    -- Auto-assign a theme by job when the character never picked one (job name -> theme id)
    autoByJob = {
        police    = 'helipad',
        sheriff   = 'helipad',
        ambulance = 'helipad',
        mechanic  = 'garage',
        tuner     = 'garage',
        realestate = 'penthouse',
        cardealer = 'supercar',
    },
    snapToGround = true,                   -- stand every lobby ped on the real floor
    footHeight   = 1.0,                    -- ped root height above the floor (nudge 0.98 / 1.02 if feet clip or float)
    ghostAlpha   = 120,                    -- translucent silhouette on an empty slot while creating
    walkIn       = true,                   -- switched character steps forward onto the mark
    walkInDistance = 1.4,                  -- metres behind the mark the walk-in starts
}

--  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
-- ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
-- ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
-- ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
-- ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
--  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

Config.Camera = {
    defaultMode = 'squad',                 -- 'squad' | 'duo' | 'body' | 'face'
    transition  = 1300,                    -- ms between camera modes / characters (eased)
    introTime   = 3200,                    -- ms glide from the start screen into the lobby
    ease        = 1,                       -- SetCamActiveWithInterp graph type (1 = ease in/out)

    -- Automatic framing when a theme doesn't override a mode. Distances in metres from the target.
    modes = {
        squad = { distance = 5.6, height = 0.35, lookHeight = 0.05, side = 0.0,  fov = 44.0, dof = false },
        duo   = { distance = 3.0, height = 0.45, lookHeight = 0.25, side = 0.15, fov = 38.0, dof = true },
        body  = { distance = 2.9, height = 0.05, lookHeight = -0.1, side = 0.35, fov = 40.0, dof = true },
        face  = { distance = 1.15, height = 0.62, lookHeight = 0.58, side = 0.12, fov = 34.0, dof = true },
    },

    -- Idle motion so the screen never feels static (players can turn sway off in Settings)
    sway  = { shake = 'HAND_SHAKE', amplitude = 0.14 },
    drift = { enabled = true, distance = 0.22, time = 9000 },     -- slow dolly back and forth (metres, ms per leg)
    dof   = { near = 0.2, strength = 0.85, bias = 1.25 },

    -- Spawn selector aerial preview
    aerial = { height = 140.0, back = 90.0, fov = 42.0, time = 1500 },
}

-- ██╗     ██╗ ██████╗ ██╗  ██╗████████╗██╗███╗   ██╗ ██████╗
-- ██║     ██║██╔════╝ ██║  ██║╚══██╔══╝██║████╗  ██║██╔════╝
-- ██║     ██║██║  ███╗███████║   ██║   ██║██╔██╗ ██║██║  ███╗
-- ██║     ██║██║   ██║██╔══██║   ██║   ██║██║╚██╗██║██║   ██║
-- ███████╗██║╚██████╔╝██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝
-- ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Artificial 3-point studio rig drawn every frame while the lobby is open (DrawLightWithRange / DrawSpotLight).
-- Offsets are relative to the main character: vec3(right, forward, up). Themes may replace it (theme.lights).
-- Moods tint the colours and scale the intensity (moods.lua).
Config.Lighting = {
    enabled = true,
    rig = {
        { name = 'key',  type = 'spot',  offset = vec3( 1.6,  2.2, 1.9), target = vec3(0.0, 0.0, 0.6), color = { 255, 236, 214 }, range = 7.0, intensity = 7.0, radius = 28.0, falloff = 18.0 },
        { name = 'fill', type = 'point', offset = vec3(-1.8,  1.6, 1.2), color = { 196, 214, 255 }, range = 4.5, intensity = 1.6 },
        { name = 'rim',  type = 'point', offset = vec3( 0.4, -1.4, 2.0), color = { 255, 255, 255 }, range = 3.5, intensity = 3.2 },
    },
    squadFill = { color = { 220, 228, 255 }, range = 3.2, intensity = 1.1, offset = vec3(0.0, 1.4, 1.3) },   -- soft fill per extra ped
    shadows   = false,                     -- shadowed lights look great but cost GPU; players in performance mode never get them
}

--  █████╗ ██╗   ██╗██████╗ ██╗ ██████╗
-- ██╔══██╗██║   ██║██╔══██╗██║██╔═══██╗
-- ███████║██║   ██║██║  ██║██║██║   ██║
-- ██╔══██║██║   ██║██║  ██║██║██║   ██║
-- ██║  ██║╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝

Config.Audio = {
    ambience = true,                       -- per-theme ambient soundscape (procedural Web Audio, or theme.ambience.url)
    uiSounds = true,                       -- hover / click / whoosh cues (Web Audio, no files)
    frontend = true,                       -- also play subtle GTA frontend sounds for select / back
    volume   = { ui = 0.6, ambience = 0.35 },   -- defaults; players adjust + mute from the lobby HUD
    sounds   = {                           -- GTA frontend sounds used when `frontend` is on
        select = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        back   = { 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        nav    = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        deploy = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' },
    },
}

-- ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗
-- ███████╗██║   ██║██║   ██║███████║██║  ██║
-- ╚════██║██║▄▄ ██║██║   ██║██╔══██║██║  ██║
-- ███████║╚██████╔╝╚██████╔╝██║  ██║██████╔╝
-- ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝

-- Persistent lobby squad + couple links. Both sides must accept; linked characters appear in each
-- other's lobby (even offline) wearing their saved outfit, pose and showcase weapon.
Config.Squad = {
    enabled    = true,
    couples    = true,                     -- allow Partner / Couple links (slot 2 + couple poses)
    maxLinks   = 3,                        -- accepted links per character (slots 2, 3, 4)
    maxPending = 5,                        -- outgoing pending requests per character
    searchMin  = 3,                        -- min characters for a name search (CitizenID / StateID is exact)
    searchBy   = { citizenid = true, stateid = true, name = true },   -- stateid = Qbox / custom column (see bridge)
    cooldown   = 10,                       -- seconds between requests
    promptInGame = true,                   -- online target gets an accept / decline prompt while playing
    plates = { partner = 'Partner', squad = 'Squad' },
}

-- ███████╗██████╗  █████╗ ██╗    ██╗███╗   ██╗
-- ██╔════╝██╔══██╗██╔══██╗██║    ██║████╗  ██║
-- ███████╗██████╔╝███████║██║ █╗ ██║██╔██╗ ██║
-- ╚════██║██╔═══╝ ██╔══██║██║███╗██║██║╚██╗██║
-- ███████║██║     ██║  ██║╚███╔███╔╝██║ ╚████║
-- ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═══╝

Config.Spawn = {
    selector     = true,                   -- spawn selector after Deploy (false = straight to last location)
    forNew       = false,                  -- new characters also get the selector (false = firstSpawn)
    lastLocation = true,                   -- "Last location" option
    houses       = true,                   -- owned houses / apartments from bridge/server/housing.lua
    firstSpawn   = vec4(-1037.64, -2737.76, 20.17, 327.0),   -- LSIA arrivals
    cutscene     = true,                   -- theme departure cutscene before entering the world
    fadeIn       = 1200,                   -- ms fade in once in the world

    -- Hand the player to another spawn resource instead (selector skipped, cutscene still plays).
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
    interact = 'textui',                   -- 'textui' (press E) | 'target' (ox_target)
    distance = 1.6,
}
