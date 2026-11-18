--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

████████╗███████╗██╗     ███████╗██╗   ██╗██╗███████╗██╗ ██████╗ ███╗   ██╗
╚══██╔══╝██╔════╝██║     ██╔════╝██║   ██║██║██╔════╝██║██╔═══██╗████╗  ██║
   ██║   █████╗  ██║     █████╗  ██║   ██║██║███████╗██║██║   ██║██╔██╗ ██║
   ██║   ██╔══╝  ██║     ██╔══╝  ╚██╗ ██╔╝██║╚════██║██║██║   ██║██║╚██╗██║
   ██║   ███████╗███████╗███████╗ ╚████╔╝ ██║███████║██║╚██████╔╝██║ ╚████║
   ╚═╝   ╚══════╝╚══════╝╚══════╝  ╚═══╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝

    NayZeee Development  ·  nayzeee-television  ·  v1.0.0
    Docs     ·  https://nayzeee-dev.gitbook.io/docs
    Store    ·  https://www.nayzeeedev.com
    Discord  ·  Support tickets on the NayZeee Development Discord

    This file is downloaded by every player. Keys, tokens and webhooks go in
    config_server.lua, which stays on the server.
    Delete any option you don't need — its default is used instead.
]]

Config = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀▀░█▀▀░█▀█░█▀▀░█▀▄░█▀█░█░░
--  ░█░█░█▀▀░█░█░█▀▀░█▀▄░█▀█░█░░
--  ░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Debug            = false          -- Prints screen/DUI/render diagnostics to F8 + server console
Config.Framework        = 'auto'         -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.Inventory        = 'auto'         -- 'auto' | 'ox_inventory' | 'framework'  (ox_inventory enables remote pairing via metadata)
Config.Target           = 'auto'         -- 'auto' | 'ox_target' | 'qb-target' | 'none' (none = NAYZEEE [E] prompts)
Config.Notify           = 'nayzeee'      -- 'nayzeee' (built-in toasts) | 'ox_lib' | 'esx' | 'qb' | 'native'
Config.Storage          = 'auto'         -- 'auto' | 'oxmysql' | 'json' (json writes to data/*.json)
Config.AdminAce         = 'nztv.admin'   -- ACE that opens the admin menu (add_ace group.admin nztv.admin allow)
Config.AdminGroups      = { 'admin', 'superadmin', 'god' } -- Framework groups that also count as TV admins
Config.AdminCommand     = 'tvadmin'      -- Opens the admin menu
Config.CalibrateCommand = 'tvcalibrate'  -- Calibrate the screen you are looking at (admin)
Config.PanelCommand     = 'tv'           -- Media panel for the screen you are looking at
Config.RemoteCommand    = 'tvremote'     -- Opens the on-screen remote for the nearest TV you can control (false = disabled)
Config.SettingsCommand  = 'tvsettings'   -- Personal TV settings (volume for me, streamer mode)

Config.Brand = {
    name    = 'NAYZEEE',
    product = 'Television',
    os      = 'NAYZEEE OS',
    version = '1.0.0',
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀▄░█▀▀░█▀█░█▀▄░█▀▀░█▀▄
--  ░█▀▄░█▀▀░█░█░█░█░█▀▀░█▀▄
--  ░▀░▀░▀▀▀░▀░▀░▀▀░░▀▀▀░▀░▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Render = {
    Resolution       = { 1280, 720 },   -- DUI resolution. 1280x720 is the sweet spot for quality vs. CEF cost
    CinemaResolution = { 1920, 1080 },  -- Used by cinema screens, big displays and wall screens
    MaxActive        = 6,               -- Max live DUIs at once (linked screens share one). Nearest screens win
    MaxDrawn         = 10,              -- Max screens drawn per frame (linked screens each count)
    StreamDistance   = 60.0,            -- Spawn/despawn distance for TV props
    Tick             = 750,             -- ms between nearby-screen scans when nothing is close (idle cost lives here)
    VisibilityCull   = true,            -- Skip drawing screens that are off camera
    -- 'overlay'      = every TV gets its own picture (recommended)
    -- 'rendertarget' = pixel-perfect on props that have a built-in screen. GTA shares a render target between every
    --                  copy of a model, so it's only used when that model's screen isn't already showing something else
    Prefer           = 'overlay',
    ScreenOffset     = 0.006,           -- Metres the picture floats in front of the glass (stops z-fighting)
    DoubleSided      = false,           -- Also draw the picture on the back of screens
    Glow             = true,            -- Soft light spill in front of playing screens
    GlowColor        = { 160, 190, 255 },
    GlowIntensity    = 0.35,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀█░█░█░█▀▄░▀█▀░█▀█
--  ░█▀█░█░█░█░█░░█░░█░█
--  ░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Audio = {
    DefaultVolume   = 35,              -- 0-100, volume a TV starts at
    Rolloff         = 1.6,             -- Higher = volume falls off faster with distance
    InnerRadius     = 2.5,             -- Full volume inside this many metres
    WallMuffle      = 0.32,            -- Volume multiplier when a wall is between you and the screen
    RoomMuffle      = 0.20,            -- Volume multiplier when you are in a different room / building
    LowpassHz       = 900,             -- Muffle filter cutoff for direct video/audio (YouTube/Twitch use volume only)
    LineOfSight     = true,            -- Raycast between camera and screen to detect walls
    StereoPan       = true,            -- Pan direct video/audio left/right by camera angle
    Update          = 200,             -- ms between audio updates sent to the screen
    LinkedOneSource = true,            -- Linked screens: only the loudest one near you plays sound (no echo)
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀▀░█░█░█▀█░█▀▀
--  ░▀▀█░░█░░█░█░█░░
--  ░▀▀▀░░▀░░▀░▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Sync = {
    DriftSeek       = 1.25,            -- Seconds of drift before a hard seek
    DriftNudge      = 0.30,            -- Seconds of drift before playback-rate nudging (direct video only)
    ClockResync     = 60,              -- Seconds between clock re-syncs with the server
    HistorySize     = 16,              -- Recently played kept per TV
    QueueSize       = 50,              -- Max queue length per TV
    PersistState    = true,            -- Remember volume, picture settings, history and queue across restarts
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▄█░█▀▀░█▀▄░▀█▀░█▀█
--  ░█░█░█▀▀░█░█░░█░░█▀█
--  ░▀░▀░▀▀▀░▀▀░░▀▀▀░▀░▀
-- ═══════════════════════════════════════════════════════════════════════════
-- The YouTube API key lives in config_server.lua
Config.Media = {
    YouTubeHost     = 'www.youtube-nocookie.com', -- Embed host
    TwitchParent    = 'auto',          -- 'auto' = cfx-nui-<resource>
    AllowDirect     = true,            -- Allow direct .mp4/.webm/.m3u8/.mp3 URLs
    AllowImages     = true,            -- Allow .png/.jpg/.gif/.webp (menus, posters, signage)
    BlockedHosts    = { 'pornhub.com', 'xvideos.com', 'xnxx.com', 'onlyfans.com' }, -- Never playable
    BlockedWords    = {},              -- Titles containing these are refused
    MaxUrlLength    = 400,             -- Hard cap on submitted links
    Cooldown        = 1200,            -- ms between media changes per player (anti-spam)
    MaxFavorites    = 40,
    KickResolve     = true,            -- Resolve Kick channels to HLS for full audio control (falls back to the embed)

    -- Platforms (see the README for what each one supports). false = off
    YouTube = true, TikTok = true, Twitch = true, Kick = true, Vimeo = true, SoundCloud = true,
    Streamable = true, Medal = true, Instagram = true, Dailymotion = true, Reddit = true, Rumble = true,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀▄░█▀▀░█▄█░█▀█░▀█▀░█▀▀
--  ░█▀▄░█▀▀░█░█░█░█░░█░░█▀▀
--  ░▀░▀░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Remote = {
    Item            = 'tv_remote',     -- Remote item name (universal remote / paired remote). false = no item
    Model           = 'prop_cs_remote_01', -- Held + placed remote prop (swap for a custom streamed prop)
    Range           = 18.0,            -- Max distance from the TV a remote works
    RequireRemote   = false,           -- true = no virtual remote at the TV: you need the remote, the remote item or the phone app
    PlaceWithTV     = true,            -- A remote prop is set down next to every new TV (with a floating marker)
    GiveOnPlace     = false,           -- Also give the owner a remote item paired to their TV (ox_inventory metadata)
    PickupDistance  = 1.6,
    MarkerDistance  = 7.0,             -- Distance the floating marker shows above a set-down remote
    MarkerColor     = { 8, 175, 162, 190 },
    MarkerType      = 2,
    MarkerScale     = 0.12,
    HoldAnim        = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
    Bone            = 28422,           -- Right hand
    Offset          = { 0.04, 0.0, -0.01, -80.0, 0.0, 0.0 }, -- x, y, z, rx, ry, rz
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀█░█░█░█▀█░█▀█░█▀▀
--  ░█▀▀░█▀█░█░█░█░█░█▀▀
--  ░▀░░░▀░▀░▀▀▀░▀░▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Phone = {
    Enabled         = true,
    Range           = 25.0,            -- Phone remote reaches TVs within this distance
    Name            = 'TV Remote',
    Description     = 'Control any TV near you when the remote goes missing',
    Developer       = 'NayZeee Development',
    Identifier      = 'nayzeee-television',
    LBPhone         = true,            -- Registers an lb-phone custom app if lb-phone is running
    YSeries         = true,            -- Registers a YSeries custom app if yseries is running
    YSeriesResource = 'yseries',
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀█░█░░░█▀█░█▀▀░█▀▀░█▄█░█▀▀░█▀█░▀█▀
--  ░█▀▀░█░░░█▀█░█░░░█▀▀░█░█░█▀▀░█░█░░█░
--  ░▀░░░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░▀░░▀░
-- ═══════════════════════════════════════════════════════════════════════════
Config.Placement = {
    MaxDistance     = 7.5,             -- How far from you a prop can be placed
    MaxPerPlayer    = 6,               -- TVs a single character can own
    PickupReturns   = true,            -- Picking up a TV gives the item back
    OwnerShare      = true,            -- Owners can share control with other players (by server id)
    -- Server-side hook: return false to block a placement (housing zones, no-build areas, etc.)
    CanPlace = function(source, coords, model)
        return true
    end,
}

-- Usable TV items -> props. Add as many as you like (also add them to your inventory, see install/)
Config.Items = {
    tv_flat_32     = { model = 'prop_tv_flat_03',       label = 'Flat TV 32"' },
    tv_flat_42     = { model = 'prop_tv_flat_02',       label = 'Flat TV 42"' },
    tv_flat_55     = { model = 'prop_tv_flat_01',       label = 'Flat TV 55"' },
    tv_flat_65     = { model = 'prop_tv_flat_michael',  label = 'Flat TV 65"' },
    tv_flat_wall   = { model = 'ex_prop_ex_tv_flat_01', label = 'Wall Mount TV' },
    tv_crt         = { model = 'prop_tv_03',            label = 'CRT TV' },
    tv_retro       = { model = 'prop_tv_06',            label = 'Retro TV' },
    tv_monitor     = { model = 'prop_monitor_w_large',  label = 'Desktop Monitor' },
    tv_laptop      = { model = 'prop_laptop_01a',       label = 'Laptop' },
    tv_projector   = { model = 'prop_huge_display_01',  label = 'Projector Screen' },
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█▀█░█▀▀░█▀▀░█▀▀░█▀▀░█▀▀
--  ░█▀█░█░░░█░░░█▀▀░▀▀█░▀▀█
--  ░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.Access = {
    DefaultMode     = 'public',        -- New admin TVs: 'public' (anyone) | 'restricted' (jobs / gangs / ace you pick)
    PlayerDefault   = 'owner',         -- New player TVs: 'owner' (owner + shared players) | 'public'
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░▀█▀░█░█░░░█▀█░█▀▀
--  ░░█░░▀▄▀░░░█░█░▀▀█
--  ░░▀░░░▀░░░░▀▀▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
Config.OS = {
    ScreensaverMin  = 6,               -- Minutes idle (no media, no input) before ambient mode. 0 = off
    InfoBarSeconds  = 4,               -- How long the player info bar stays after a button press
    HeroSeconds     = 9,               -- Featured banner rotation
    SleepOptions    = { 0, 15, 30, 60, 90 }, -- Sleep timer steps (minutes)
    -- Apps on the home screen, in order. Remove any you don't want
    Apps = {
        'youtube', 'tiktok', 'twitch', 'kick', 'vimeo', 'soundcloud', 'plex', 'pluto', 'medal', 'streamable',
        'instagram', 'dailymotion', 'reddit', 'rumble', 'web', 'library', 'queue', 'channels', 'settings',
    },
    -- Picture presets: brightness/contrast/saturation in %, warmth -50..50
    Picture = {
        standard = { brightness = 100, contrast = 100, saturation = 100, warmth = 0 },
        vivid    = { brightness = 106, contrast = 114, saturation = 128, warmth = 0 },
        movie    = { brightness = 94,  contrast = 104, saturation = 96,  warmth = 18 },
        game     = { brightness = 104, contrast = 110, saturation = 112, warmth = -6 },
        night    = { brightness = 82,  contrast = 96,  saturation = 90,  warmth = 34 },
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█░░░▀█▀░█▀▄░█▀▄░█▀█░█▀▄░█░█
--  ░█░░░░█░░█▀▄░█▀▄░█▀█░█▀▄░░█░
--  ░▀▀▀░▀▀▀░▀▀░░▀░▀░▀░▀░▀░▀░░▀░
-- ═══════════════════════════════════════════════════════════════════════════
-- What every TV shows on its home screen. These are examples — swap for your city's channels.
--   featured  Home screen hero banner
--   live      Live tab + CH▲ / CH▼  (also add M3U playlists such as Pluto TV in config_server.lua)
--   movie     Library → Cinema
--   music     Library → Music
-- 'ytlive:<channel id>' plays whatever a YouTube channel is streaming right now.
Config.Library = {
    -- Featured banners (home screen hero)
    { type = 'featured', title = 'Big Buck Bunny', subtitle = 'Now showing at the Vinewood cinema',
      url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg' },
    { type = 'featured', title = 'Tears of Steel', subtitle = 'Sci-fi night, every Friday',
      url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg' },
    { type = 'featured', title = 'Sintel', subtitle = 'A girl, a dragon and a long way home',
      url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg' },

    -- Live TV channels (CH+ / CH- flips through these)
    { type = 'live', category = 'News',  title = 'NASA Live',       url = 'ytlive:UCLA_DiR1FfKNvjuUpBHmylQ' },
    { type = 'live', category = 'News',  title = 'Sky News',        url = 'ytlive:UCoMdktPbSTixAyNGwb-UYkQ' },
    { type = 'live', category = 'Music', title = 'Lofi Radio',      url = 'https://www.youtube.com/watch?v=jfKfPfyJRdk' },
    { type = 'live', category = 'Music', title = 'Monstercat',      url = 'https://www.twitch.tv/monstercat' },
    { type = 'live', category = 'Test',  title = 'Mux Test Stream', url = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8' },

    -- Cinema library
    { type = 'movie', category = 'Animation', title = 'Big Buck Bunny',  url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg' },
    { type = 'movie', category = 'Animation', title = 'Elephants Dream', url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg' },
    { type = 'movie', category = 'Sci-Fi',    title = 'Tears of Steel',  url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg' },
    { type = 'movie', category = 'Fantasy',   title = 'Sintel',          url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      image = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg' },

    -- Music (audio files, YouTube, SoundCloud links all work)
    { type = 'music', category = 'Chill', title = 'Lofi Radio', url = 'https://www.youtube.com/watch?v=jfKfPfyJRdk' },
}

-- Files you drop in html/media/ (play as local:<file>). Served from the resource - no internet needed.
Config.LocalMedia = {
    -- { file = 'weazel_intro.mp4', title = 'Weazel News Intro', image = '' },
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░█░░░█▀█░█▀▀░█▀▀
--  ░█░░░█░█░█░█░▀▀█
--  ░▀▀▀░▀▀▀░▀▀▀░▀▀▀
-- ═══════════════════════════════════════════════════════════════════════════
-- The Discord webhook lives in config_server.lua
Config.Logs = {
    LogMedia        = true,            -- Log every media change (who played what, on which TV)
    Keep            = 150,             -- In-memory entries shown in /tvadmin > Logs
}

-- ═══════════════════════════════════════════════════════════════════════════
--  ░▀█▀░█▀▀░█░█░▀█▀
--  ░░█░░█▀▀░▄▀▄░░█░
--  ░░▀░░▀▀▀░▀░▀░░▀░
-- ═══════════════════════════════════════════════════════════════════════════
Config.Text = {
    no_permission    = 'You can\'t control this TV',
    locked           = 'This TV is locked',
    no_tv_near       = 'No TV you can control is in range',
    too_far          = 'Too far from the TV',
    placed           = 'TV placed',
    picked_up        = 'TV picked up',
    max_screens      = 'You already own the max number of TVs',
    cant_place       = 'You can\'t place that here',
    blocked_url      = 'That link isn\'t allowed',
    invalid_url      = 'That link can\'t be played',
    cooldown         = 'Slow down',
    remote_dropped   = 'Remote set down',
    remote_taken     = 'Somebody else is holding that remote',
    remote_paired    = 'Remote paired to %s',
    need_remote      = 'Grab the remote (or use the phone app) to control this TV',
    favorite_added   = 'Saved to favorites',
    favorite_removed = 'Removed from favorites',
    calibrated       = 'Screen calibration saved for every %s',
    search_disabled  = 'Search needs a YouTube API key. Paste a link instead',
    added_queue      = 'Added to the queue',
    stopped          = 'Playback stopped',
    saved            = 'Changes saved',
    created          = 'Screen created',
    deleted          = 'Screen removed',
    linked           = 'Screens linked — they now mirror each other',
    unlinked         = 'Screen unlinked',
    sleep_set        = 'Sleep timer: %s',
    plex_web         = 'Plex\'s website can\'t play on TVs. Use the Live tab for Plex channels, or the Plex app for your own server.',
}
