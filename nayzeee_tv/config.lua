--[[
    NAYZEEE TELEVISION — configuration
    ─────────────────────────────────────────────────────────────
    Every option is documented. Anything left on 'auto' is detected
    at start-up from the resources running on your server.
]]

Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ─────────────────────────────────────────────────────────────
-- Integrations
-- ─────────────────────────────────────────────────────────────
Config.Framework = 'auto'   -- 'auto' | 'qbx' | 'qb' | 'esx' | 'standalone'
Config.Inventory = 'auto'   -- 'auto' | 'ox_inventory' | 'qb' | 'esx' | 'none'
Config.Target    = 'auto'   -- 'auto' | 'ox_target' | 'qb-target' | 'none' (built-in key prompt)
Config.Storage   = 'auto'   -- 'auto' | 'oxmysql' | 'json'  (json writes to data/screens.json)

-- ─────────────────────────────────────────────────────────────
-- Admin access
-- ─────────────────────────────────────────────────────────────
Config.AdminAce    = 'nayzeee_tv.admin'           -- add_ace group.admin nayzeee_tv.admin allow
Config.AdminGroups = { 'god', 'admin', 'superadmin' } -- framework permission groups that count as admin

Config.Commands = {
    admin  = 'tvadmin',   -- opens the admin menu
    panel  = 'tv',        -- opens the media panel for the TV you are looking at / nearest
    remote = 'tvremote',  -- opens the remote for the nearest TV you can control
}

-- ─────────────────────────────────────────────────────────────
-- Branding (shown on the TV boot screen, menus and phone app)
-- ─────────────────────────────────────────────────────────────
Config.Brand = {
    name    = 'NAYZEEE',
    product = 'Television',
    os      = 'NAYZEEE OS',
    tagline = 'Smart TV & Cinema',
    version = '1.0.0',
}

-- ─────────────────────────────────────────────────────────────
-- Rendering & performance
-- ─────────────────────────────────────────────────────────────
Config.Render = {
    MaxScreens      = 6,        -- max screens rendering video at once per client (each one is a browser)
    Resolution      = { 1280, 720 },
    CinemaResolution= { 1920, 1080 }, -- used by screens flagged hd = true (cinema, billboards)
    StreamDistance  = 80.0,     -- props spawn within this distance (client-side local objects)
    RenderPadding   = 15.0,     -- extra metres beyond a screen's audio range where the picture still draws
    TickIdle        = 750,      -- ms between scans when nothing is close  (≈0.00 ms resmon)
    TickNear        = 250,      -- ms between scans when a screen is close
    DoubleSided     = false,    -- draw the picture on the back of screens too
    Glow            = true,     -- soft light spill in front of powered screens
    GlowColor       = { 160, 190, 255 },
    GlowIntensity   = 0.35,
    ScreenOffset    = 0.006,    -- metres the picture floats in front of the glass (prevents z-fighting)
}

-- ─────────────────────────────────────────────────────────────
-- 3D audio
-- ─────────────────────────────────────────────────────────────
Config.Audio = {
    DefaultVolume  = 0.55,      -- 0.0 – 1.0 for newly placed screens
    Rolloff        = 1.65,      -- higher = sound falls off faster with distance
    InnerRadius    = 0.18,      -- fraction of a screen's range heard at full volume
    WallVolume     = 0.45,      -- volume multiplier when a wall is between you and the screen
    RoomVolume     = 0.22,      -- multiplier when you are in another interior room
    WallLowpass    = 1300,      -- Hz low-pass when muffled by a wall (direct / HLS / local media)
    RoomLowpass    = 650,       -- Hz low-pass when in another room
    Stereo         = true,      -- pan audio left / right from where you are looking
    UpdateRate     = 120,       -- ms between audio updates
    GroupSingleSource = true,   -- linked screens: only the loudest one plays sound (no echo in bars/clubs)
}

-- ─────────────────────────────────────────────────────────────
-- Synchronisation
-- ─────────────────────────────────────────────────────────────
Config.Sync = {
    Interval     = 2500,   -- ms between drift checks
    SeekDrift    = 1.25,   -- seconds of drift before a hard seek
    NudgeDrift   = 0.12,   -- seconds of drift before playback-rate nudging (direct / HLS / local)
    ClockResync  = 60000,  -- ms between server clock re-calibrations
}

-- ─────────────────────────────────────────────────────────────
-- Media sources
-- ─────────────────────────────────────────────────────────────
Config.Media = {
    YouTube   = true,
    Twitch    = true,
    Kick      = true,
    -- more platforms (see README → Platforms for what each one can do)
    TikTok      = true,
    Vimeo       = true,
    SoundCloud  = true,
    Streamable  = true,
    Medal       = true,
    Instagram   = true,   -- best effort: Instagram's embed needs a tap, the TV taps it for you
    Dailymotion = true,
    Reddit      = true,
    Rumble      = true,
    GoogleDrive = true,
    Direct    = true,   -- .mp4 / .webm / .ogg / .mp3 / .m3u8
    Images    = true,   -- .png / .jpg / .gif / .webp (venue boards, menus, posters)
    Local     = true,   -- files in html/media (see Config.Library)

    -- the YouTube API key, Plex and channel playlists live in config_server.lua (never sent to players)
    KickResolve   = true, -- try to resolve Kick channels to HLS for full audio control (falls back to embed)

    Blacklist = { },    -- domains that can never be played e.g. { 'example.com' }
    Whitelist = nil,    -- set to a table of domains to ONLY allow those for direct links

    MaxQueue     = 50,
    MaxHistory   = 30,
    MaxFavorites = 40,
    MaxUrlLength = 512,
}

-- Local server media — drop files in nayzeee_tv/html/media and list them here.
Config.Library = {
    -- { file = 'intro.mp4',  title = 'City Intro',       subtitle = 'Server trailer' },
    -- { file = 'menu.png',   title = 'Bar Menu',         subtitle = 'Image' },
}

-- Hero banner rotation on the TV home screen.
Config.Featured = {
    { title = 'Welcome to the city', subtitle = 'Press OK on your remote to browse', url = nil, image = nil, accent = '#08afa2' },
}

-- Presets shown in the Live tab and reachable with CH ▲ / ▼ on the remote.
Config.Channels = {
    -- { number = 1, name = 'City News',   url = 'https://www.twitch.tv/yourchannel' },
    -- { number = 2, name = 'Lo-fi Radio', url = 'https://www.youtube.com/watch?v=jfKfPfyJRdk' },
}

-- ─────────────────────────────────────────────────────────────
-- Player-placed TVs
-- ─────────────────────────────────────────────────────────────
Config.PlayerScreens = {
    Persist          = true,   -- keep player TVs after restarts
    MaxPerPlayer     = 6,
    PickupReturnsItem= true,
    PlaceDistance    = 8.0,    -- max metres from the player when placing
    DefaultPublic    = false,  -- false: only the owner (and people they allow) can control
}

-- Usable items → models. Each item places that TV. Add as many as you like.
-- ox_inventory: see README for the item snippets.
Config.Items = {
    tv_flat       = { model = 'prop_tv_flat_01',    label = 'Flat Screen TV'   },
    tv_flat_large = { model = 'prop_tv_flat_michael', label = 'Large Flat TV'  },
    tv_crt        = { model = 'prop_tv_03',         label = 'Classic CRT TV'   },
    tv_crt_old    = { model = 'prop_tv_01',         label = 'Old CRT TV'       },
    tv_monitor    = { model = 'prop_monitor_w_large', label = 'Large Monitor'  },
    tv_laptop     = { model = 'prop_laptop_01a',    label = 'Laptop'           },
    tv_tablet     = { model = 'prop_cs_tablet',     label = 'Tablet'           },
    tv_projector  = { model = 'v_ilev_mm_screen2',  label = 'Projector Screen' },
}

-- ─────────────────────────────────────────────────────────────
-- Remote (placeable prop + held remote + NUI remote)
-- ─────────────────────────────────────────────────────────────
Config.Remote = {
    Enabled        = true,
    Model          = 'prop_cs_remote_01',
    AutoPlace      = true,        -- a remote is placed next to every new TV automatically
    Item           = 'tv_remote', -- usable universal remote item (pairs to the TV you look at). nil to disable
    Marker = {
        Enabled = true,
        Type    = 2,              -- downward cone (any GTA marker id works)
        Scale   = 0.12,
        Height  = 0.28,
        Color   = { 8, 175, 162, 190 },
        Distance= 7.0,
        Bob     = true,
    },
    Hold = {
        Bone   = 28422,
        Offset = vector3(0.05, 0.02, -0.02),
        Rot    = vector3(-80.0, 0.0, 0.0),
        Dict   = 'amb@world_human_stand_mobile@male@text@base',
        Clip   = 'base',
    },
    Range          = 18.0,        -- how far the remote reaches its TV
    PickupDistance = 1.6,
}

-- ─────────────────────────────────────────────────────────────
-- Phone apps (lost the remote? control from your phone)
-- ─────────────────────────────────────────────────────────────
Config.Phone = {
    Identifier = 'nayzeee-tv',
    Name       = 'SmartView',
    Description= 'Control nearby TVs and screens',
    Developer  = 'NAYZEEE',
    Range      = 30.0,           -- TVs within this distance show up in the app
    LbPhone    = true,
    YSeries    = true,
    -- yseries export names differ between versions; adjust if your build uses different ones
    YSeriesResource = 'yseries',
}

-- ─────────────────────────────────────────────────────────────
-- Interaction (when no target system is used)
-- ─────────────────────────────────────────────────────────────
Config.Interact = {
    Distance = 2.4,
    Keys = {
        Open   = 38,  -- E
        Remote = 47,  -- G
        Pickup = 74,  -- H
    },
}

-- ─────────────────────────────────────────────────────────────
-- Default permissions for admin-created screens
-- ─────────────────────────────────────────────────────────────
Config.DefaultPermissions = {
    public = true,
    jobs   = {},   -- { police = 0, ambulance = 2 }  job name → minimum grade
    gangs  = {},   -- { ballas = 0 }
    ace    = nil,  -- 'nayzeee_tv.cinema'
}
