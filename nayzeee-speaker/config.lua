--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗  
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝  
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
                                                           
███████╗██████╗ ███████╗ █████╗ ██╗  ██╗███████╗██████╗ 
██╔════╝██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝██╔══██╗
███████╗██████╔╝█████╗  ███████║█████╔╝ █████╗  ██████╔╝
╚════██║██╔═══╝ ██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗
███████║██║     ███████╗██║  ██║██║  ██╗███████╗██║  ██║
╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
                                                        

  Speakers, boomboxes & CarPlay  |  v2.0.0
  www.nayzeeedev.com  |  nayzeee-dev.gitbook.io/docs
]]

Config = {}

--  ██████╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔═══██╗██╔══██╗██╔════╝
-- ██║     ██║   ██║██████╔╝█████╗  
-- ██║     ██║   ██║██╔══██╗██╔══╝  
-- ╚██████╗╚██████╔╝██║  ██║███████╗
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

Config.Framework   = 'auto'      -- auto | esx | qbcore | qbox
Config.Inventory   = 'auto'      -- auto | ox_inventory | framework
Config.Target      = 'auto'      -- auto | ox_target | qb-target | none (none = [E] prompt on the speaker)
Config.Locale      = 'en'        -- file inside locales/
Config.Debug       = false       -- console prints + /nzspk_attach editor
Config.Version     = '2.0.0'     -- shown at the top of the player
Config.DirectLinks = true        -- also allow direct .mp3 / .ogg / .opus / .wav / .webm links

Config.Admin = {
    ace    = 'nayzeee.speaker.admin',            -- ace permission that counts as admin
    groups = { 'admin', 'superadmin', 'god' },   -- framework groups that count as admin
}

Config.Logs = {
    webhook = '',                -- Discord webhook for play / place / remove logs ('' = off)
}

--  █████╗ ██╗   ██╗██████╗ ██╗ ██████╗ 
-- ██╔══██╗██║   ██║██╔══██╗██║██╔═══██╗
-- ███████║██║   ██║██║  ██║██║██║   ██║
-- ██╔══██║██║   ██║██║  ██║██║██║   ██║
-- ██║  ██║╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝ 

Config.Audio = {
    --[[
        WHERE THE SOUND COMES FROM - this decides whether the 3D effects below can work at all.

        A song played through YouTube's embedded player belongs to YouTube's own frame, and the
        browser will not let the game touch it. In that mode ONLY volume works: no direction,
        no muffling, no echo, no doppler, no EQ.

        For the effects to work the game needs a real audio file. 'source' picks how it gets one:
          'auto'   -> try the public instances below, then your own API, then fall back to the embed
          'api'    -> only your own nayzeee-speaker-api server (most reliable, needs hosting)
          'iframe' -> always the embedded player (effects off, nothing to set up)
    ]]
    source    = 'auto',
    instances = {
        -- Public Invidious / Piped servers. Free and need no setup, but they are run by volunteers:
        -- they go down, get rate limited and change often. Keep a few, newest-working first.
        -- Current lists: https://api.invidious.io  and  https://piped-instances.kavin.rocks
        'https://inv.nadeko.net',
        'https://invidious.nerdvpn.de',
        'https://pipedapi.kavin.rocks',
    },
    apiUrl = '',                 -- your own API, e.g. 'https://music.nayzeeedev.com' (see nayzeee-speaker-api)
    apiKey = '',

    updateRate      = 120,       -- ms between spatial updates (every value glides across this gap, so 120 is smooth)
    panning         = 'HRTF',    -- HRTF (true 3D) | equalpower (cheaper)
    reverb          = true,      -- room / hall / street echo from the space around the speaker (a few raycasts, cached)
    reverbLevel     = 1.0,       -- how much of that echo you hear (0 = dry, 1 = default, 2 = very wet)
    maxCeiling      = 25.0,      -- highest ceiling checked when working out the space
    interiorMuffle  = true,      -- speaker in a building sounds muffled from outside (and vice versa)
    vehicleMuffle   = true,      -- car music is muffled outside the car (bass still thumps), opens up with windows / doors / roof
    occlusion       = true,      -- walls between you and the speaker dampen it (3 rays, so doorways sound half open)
    occlusionRate   = 250,       -- ms between wall checks per speaker
    roomRate        = 2500,      -- ms between space checks for a speaker that moves (placed speakers check once)
    doppler         = true,      -- pitch shifts as a car with music drives past you
    dopplerAmount   = 0.6,       -- 0 = off, 0.6 = subtle (default), 1 = realistic, 2 = exaggerated
    maxDoppler      = 0.03,      -- the most the pitch can bend (0.03 = 3 %)
    distanceMuffle  = true,      -- far speakers lose their highs, like real air does
    fullVolumeDistance = 1.5,    -- metres around a speaker that hear it at full level
    rolloff         = 3.0,       -- how quickly it fades past that (higher = drops sooner); it is always silent at the range
    closeStereo     = 1.2,       -- closer than this (or in the car / carrying it) you hear the speaker's real stereo
    syncCheck       = true,      -- pulls lagging / alt-tabbed players back to the live position
    driftTolerance  = 1.5,       -- seconds out of sync before a resync
    unloadDistance  = 1.35,      -- songs are unloaded past range * this (frees memory)

    --[[
        Each speaker's own sound. hp = low cut in Hz, low / mid / high = dB at lowHz (shelf),
        midHz (peak, midQ wide-ness) and highHz (shelf). Remove a line to use the built-in voice.
    ]]
    voices = {
        ['nayzeee_audio_a'] = { hp = 35,  low = 2.5,  lowHz = 110, mid = -1.0, midHz = 650,  midQ = 0.7, high = 1.5,  highHz = 8000 }, -- Pulse Tower: party bass, crisp top
        ['nayzeee_audio_b'] = { hp = 70,  low = -1.0, lowHz = 150, mid = 1.0,  midHz = 2200, midQ = 0.8, high = 0.5,  highHz = 7000 }, -- Echo Column: lean, clear vocals
        ['nayzeee_audio_c'] = { hp = 45,  low = 2.0,  lowHz = 130, mid = 1.5,  midHz = 280,  midQ = 1.1, high = -1.5, highHz = 6000 }, -- Drum Hub: round barrel boom
        ['nayzeee_audio_d'] = { hp = 110, low = -4.5, lowHz = 180, mid = 1.0,  midHz = 1800, midQ = 0.8, high = 1.0,  highHz = 7500 }, -- Orb: small, light low end
        ['nayzeee_audio_e'] = { hp = 75,  low = -1.5, lowHz = 160, mid = 1.5,  midHz = 1500, midQ = 0.8, high = -0.5, highHz = 6500 }, -- Carry Cube: punchy mids
        ['nayzeee_audio_f'] = { hp = 95,  low = -2.0, lowHz = 150, mid = 3.0,  midHz = 1400, midQ = 0.7, high = -4.0, highHz = 6500 }, -- Roll Bar: mid-forward 80s boombox
        ['nayzeee_audio_g'] = { hp = 40,  low = 1.5,  lowHz = 120, mid = 0.5,  midHz = 900,  midQ = 0.7, high = -2.5, highHz = 7000 }, -- Turntable: warm vintage
        ['nayzeee_audio_h'] = { hp = 25,  low = 0.5,  lowHz = 100, mid = 0.0,  midHz = 1100, midQ = 0.7, high = 0.5,  highHz = 9000 }, -- Studio Set: full range
        vehicle             = { hp = 28,  low = 2.0,  lowHz = 90,  mid = -0.5, midHz = 500,  midQ = 0.7, high = 0.5,  highHz = 8000 }, -- car systems
    },

    eq = {                       -- starting EQ for every player, in dB (-12 to 12). They can change it themselves.
        bass = 0.0, mid = 0.0, treble = 0.0,
    },
}

-- ██╗     ██╗███╗   ███╗██╗████████╗███████╗
-- ██║     ██║████╗ ████║██║╚══██╔══╝██╔════╝
-- ██║     ██║██╔████╔██║██║   ██║   ███████╗
-- ██║     ██║██║╚██╔╝██║██║   ██║   ╚════██║
-- ███████╗██║██║ ╚═╝ ██║██║   ██║   ███████║
-- ╚══════╝╚═╝╚═╝     ╚═╝╚═╝   ╚═╝   ╚══════╝

Config.Limits = {
    rateLimit      = 2.5,        -- seconds between starting new songs
    actionCooldown = 0.05,       -- seconds between seek / volume / range changes
    maxQueue       = 25,         -- songs per speaker queue
    maxDuration    = 900,        -- longest song allowed in seconds (0 = no limit)
    history        = 30,         -- recent songs kept per player
    favorites      = 100,        -- favorites kept per player
}

Config.Ranges = {
    boombox = { default = 10.0, min = 4.0, max = 30.0 },   -- hearing distance players can pick
    vehicle = { default = 15.0, min = 4.0, max = 25.0 },
}

Config.DeleteBoomboxWhenOwnerQuit = false  -- true = placed boomboxes disappear when the owner leaves
Config.StopMusicWhenVehicleIsEmpty = false -- true = car music pauses when nobody is inside
Config.DisableGTARadio            = true  -- turns the GTA radio off and hides the radio wheel in every vehicle

--  ██████╗ █████╗ ██████╗ ██████╗ ██╗      █████╗ ██╗   ██╗
-- ██╔════╝██╔══██╗██╔══██╗██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝
-- ██║     ███████║██████╔╝██████╔╝██║     ███████║ ╚████╔╝ 
-- ██║     ██╔══██║██╔══██╗██╔═══╝ ██║     ██╔══██║  ╚██╔╝  
-- ╚██████╗██║  ██║██║  ██║██║     ███████╗██║  ██║   ██║   
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   

Config.Carplay = {
    enabled    = true,           -- music in vehicles
    key        = 'J',            -- opens the car player (players can rebind in FiveM key bindings)
    keepInput  = true,           -- keep driving while the player is open (mouse still works)
    controlBy  = 'occupants',    -- driver | occupants  (who can change the music)

    install = {
        use       = false,       -- true = a unit item must be installed before the car can play music
        item      = 'nayzeee_carplay',
        ownerOnly = false,       -- true = only the vehicle owner can remove the unit
        install   = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 16, duration = 5000 },
        remove    = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 16, duration = 10000 },
    },
}

--

-- ██████╗ ██████╗  █████╗ ███╗   ██╗██████╗ ██╗███╗   ██╗ ██████╗ 
-- ██╔══██╗██╔══██╗██╔══██╗████╗  ██║██╔══██╗██║████╗  ██║██╔════╝ 
-- ██████╔╝██████╔╝███████║██╔██╗ ██║██║  ██║██║██╔██╗ ██║██║  ███╗
-- ██╔══██╗██╔══██╗██╔══██║██║╚██╗██║██║  ██║██║██║╚██╗██║██║   ██║
-- ██████╔╝██║  ██║██║  ██║██║ ╚████║██████╔╝██║██║ ╚████║╚██████╔╝
-- ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ 
--  Put your own logo at html/img/logo.png (square png, 128px or larger) and it shows in the
--      top-left of the player and on the phone app. Delete the file or turn this off for no logo.

Config.Brand = {
    watermark = true,            -- show a logo in the player and phone app
    logo      = 'img/logo.png',  -- file inside the html folder ('' = use the built-in mark)
    name      = '',              -- optional text beside the logo ('' = none)
}
-- ███╗   ██╗ ██████╗ ██╗    ██╗
-- ████╗  ██║██╔═══██╗██║    ██║
-- ██╔██╗ ██║██║   ██║██║ █╗ ██║
-- ██║╚██╗██║██║   ██║██║███╗██║
-- ██║ ╚████║╚██████╔╝╚███╔███╔╝
-- ╚═╝  ╚═══╝ ╚═════╝  ╚══╝╚══╝ 
-- ██████╗ ██╗      █████╗ ██╗   ██╗██╗███╗   ██╗ ██████╗ 
-- ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██║████╗  ██║██╔════╝ 
-- ██████╔╝██║     ███████║ ╚████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██║██║╚██╗██║██║   ██║
-- ██║     ███████╗██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝ 
--  The small card that shows what song you're hearing. Players can move it, resize it or
--      turn it off in the player's Settings tab; these are the defaults.

Config.NowPlaying = {
    enabled  = true,             -- let players see the card at all
    nearby   = true,             -- also show it for boomboxes you can hear, not only your car
    minLevel = 0.08,             -- how loud a speaker must be for you before the card shows it (0-1)
    x        = 98.5,             -- default position, % from the left edge (card's right side)
    y        = 3.0,              -- default position, % from the top
    scale    = 1.0,              -- default size (0.8 - 1.4)

    -- Starting look of the card. Every player can change all of this in the player's Settings tab.
    skin    = 'compact',         -- compact | boxy | gallery | minimal | macos | shell | bar
    cover   = 'square',          -- square | canvas | vinyl | none
    glow    = false,             -- soft glow behind the album cover
    blur    = false,             -- blurred cover as the card's background
    font    = 'Lexend',          -- Lexend | System | Inter | Roboto | Montserrat | Oswald | Bebas Neue | Courier New
    animIn  = 'fade',            -- fade | slideLeft | slideRight | slideTop | slideBottom | grow | shrink
    animOut = 'fade',            --   | swingLeft | swingRight | tiltLeft | tiltRight
}


-- ███████╗███████╗ █████╗ ██████╗  ██████╗██╗  ██╗
-- ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝██║  ██║
-- ███████╗█████╗  ███████║██████╔╝██║     ███████║
-- ╚════██║██╔══╝  ██╔══██║██╔══██╗██║     ██╔══██║
-- ███████║███████╗██║  ██║██║  ██║╚██████╗██║  ██║
-- ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
--  Lets players search for songs by name instead of pasting links (phone app and player).
--      Works with no key by reading public results, but a free YouTube Data API key is far more
--      reliable: console.cloud.google.com -> enable 'YouTube Data API v3' -> create an API key.

Config.Search = {
    enabled       = true,
    youtubeApiKey = '',          -- optional, strongly recommended
    results       = 12,          -- results shown per search
}

-- ███████╗██████╗  ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ██╔════╝██╔══██╗██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ███████╗██████╔╝██║   ██║   ██║   ██║█████╗   ╚████╔╝ 
-- ╚════██║██╔═══╝ ██║   ██║   ██║   ██║██╔══╝    ╚██╔╝  
-- ███████║██║     ╚██████╔╝   ██║   ██║██║        ██║   
-- ╚══════╝╚═╝      ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝   
--  Spotify will not let any other app play its audio, so this does NOT stream Spotify.
--      What it does: read an album or playlist link you paste and find each track to play.
--      Needs a free app at developer.spotify.com/dashboard (client id + secret).

Config.Spotify = {
    enabled      = false,
    clientId     = '',
    clientSecret = '',
}

-- ██╗     ██╗███╗   ██╗██╗  ██╗███████╗██████╗ 
-- ██║     ██║████╗  ██║██║ ██╔╝██╔════╝██╔══██╗
-- ██║     ██║██╔██╗ ██║█████╔╝ █████╗  ██║  ██║
-- ██║     ██║██║╚██╗██║██╔═██╗ ██╔══╝  ██║  ██║
-- ███████╗██║██║ ╚████║██║  ██╗███████╗██████╔╝
-- ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝╚═════╝ 
-- ███████╗██████╗ ███████╗ █████╗ ██╗  ██╗███████╗██████╗ ███████╗
-- ██╔════╝██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔════╝
-- ███████╗██████╔╝█████╗  ███████║█████╔╝ █████╗  ██████╔╝███████╗
-- ╚════██║██╔═══╝ ██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗╚════██║
-- ███████║██║     ███████╗██║  ██║██║  ██╗███████╗██║  ██║███████║
-- ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝
--  Link speakers together and they play one song in step: house parties, club rooms, car convoys.

Config.Links = {
    enabled  = true,
    maxGroup = 8,                -- speakers in one link group
    distance = 60.0,             -- how far apart two speakers can be and still link
    owner    = false,            -- true = only the owner of both speakers may link them
}

-- ██████╗ ███████╗███████╗████████╗██████╗ ██╗   ██╗ ██████╗████████╗██╗██████╗ 
-- ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔══██╗██║   ██║██╔════╝╚══██╔══╝██║██╔══██╗
-- ██║  ██║█████╗  ███████╗   ██║   ██████╔╝██║   ██║██║        ██║   ██║██████╔╝
-- ██║  ██║██╔══╝  ╚════██║   ██║   ██╔══██╗██║   ██║██║        ██║   ██║██╔══██╗
-- ██████╔╝███████╗███████║   ██║   ██║  ██║╚██████╔╝╚██████╗   ██║   ██║██████╔╝
-- ╚═════╝ ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚═╝╚═════╝ 
-- ██╗     ███████╗
-- ██║     ██╔════╝
-- ██║     █████╗  
-- ██║     ██╔══╝  
-- ███████╗███████╗
-- ╚══════╝╚══════╝
--  Speakers can be shot, rammed or blown up. Health is per speaker; at 0 it breaks,
--      the music stops and it either drops as an item or is destroyed outright.

Config.Damage = {
    enabled     = true,
    health      = 100,           -- hit points of a placed speaker
    bullet      = 25,            -- damage per bullet
    melee       = 12,            -- damage per melee hit
    vehicle     = 45,            -- damage when a vehicle hits it
    explosion   = 100,           -- damage from an explosion
    dropOnBreak = true,          -- true = broken speaker returns as the item, false = gone for good
    effect      = true,          -- sparks + smoke when it breaks
    cooldown    = 250,           -- ms between damage ticks from one player
}

-- ██████╗ ██╗      █████╗ ██╗   ██╗██╗     ██╗███████╗████████╗███████╗
-- ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██║     ██║██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝██║     ███████║ ╚████╔╝ ██║     ██║███████╗   ██║   ███████╗
-- ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██║     ██║╚════██║   ██║   ╚════██║
-- ██║     ███████╗██║  ██║   ██║   ███████╗██║███████║   ██║   ███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝╚══════╝   ╚═╝   ╚══════╝
--  Players build playlists and can share them with the city or keep them private.

Config.Playlists = {
    enabled    = true,
    perPlayer  = 20,             -- playlists one player may own
    maxTracks  = 100,            -- songs per playlist
    sharing    = true,           -- allow sharing a playlist with everyone
}


-- ███████╗ ██████╗  ██████╗██╗ █████╗ ██╗     
-- ██╔════╝██╔═══██╗██╔════╝██║██╔══██╗██║     
-- ███████╗██║   ██║██║     ██║███████║██║     
-- ╚════██║██║   ██║██║     ██║██╔══██║██║     
-- ███████║╚██████╔╝╚██████╗██║██║  ██║███████╗
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚═╝  ╚═╝╚══════╝
--  Our own takes on listening together. These are this script's features, not Spotify's.
--      Jam: members hear the host's music in their own ears anywhere in the city.

Config.Social = {
    jam          = true,         -- listening sessions anyone can join
    jamMax       = 20,           -- people in one jam
    blend        = true,         -- build a playlist from what two players both like
    collab       = true,         -- let named players add to one of your playlists
    mixed        = true,         -- crossfade between songs instead of cutting
    mixedFade    = 4.0,          -- seconds of crossfade on a mixed playlist
    prompted     = true,         -- build a playlist from a sentence
    promptedSize = 20,           -- songs a prompted playlist aims for
}
-- ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗     █████╗ ██████╗ ██████╗ 
-- ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝    ██╔══██╗██╔══██╗██╔══██╗
-- ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗      ███████║██████╔╝██████╔╝
-- ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝      ██╔══██║██╔═══╝ ██╔═══╝ 
-- ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗    ██║  ██║██║     ██║     
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝  ╚═╝╚═╝     ╚═╝     
--  Control any speaker you have access to without walking up to it. Set 'app' to the phone
--      you run; 'auto' picks whichever of lb-phone / qs-smartphone / yseries is started.

Config.Phone = {
    enabled  = true,
    app      = 'auto',           -- auto | lb-phone | qs-smartphone | yseries | none
    name     = 'Speaker',        -- app name on the phone
    range    = 0,                -- 0 = control any speaker you own anywhere; >0 = must be within this many metres
    needItem = '',               -- optional item required to use the app ('' = none)
    insets   = { top = 0, bottom = 0 },  -- px the app keeps clear for the phone's status bar / home bar (0 = that phone's default)
}
-- ██████╗  ██████╗  ██████╗ ███╗   ███╗██████╗  ██████╗ ██╗  ██╗███████╗███████╗
-- ██╔══██╗██╔═══██╗██╔═══██╗████╗ ████║██╔══██╗██╔═══██╗╚██╗██╔╝██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║   ██║██╔████╔██║██████╔╝██║   ██║ ╚███╔╝ █████╗  ███████╗
-- ██╔══██╗██║   ██║██║   ██║██║╚██╔╝██║██╔══██╗██║   ██║ ██╔██╗ ██╔══╝  ╚════██║
-- ██████╔╝╚██████╔╝╚██████╔╝██║ ╚═╝ ██║██████╔╝╚██████╔╝██╔╝ ██╗███████╗███████║
-- ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝
--  portable = can be carried. attach is the hand position while carrying (tune it live with
--      /nzspk_attach <item> when Config.Debug = true). anim is the prop's own speaker animation.

Config.Boomboxes = {
    ['nayzeee_audio_a'] = {
        label = 'Pulse Tower', model = 'nayzeee_audio_a', portable = true,
        anim  = { dict = 'nayzeee_audio_a', clip = 'nayzeee_audio_a' },
        attach = {
            bone = 57005, offset = vector3(0.13, 0.02, -0.03), rotation = vector3(-80.0, 0.0, -10.0),
            dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 51,
        },
    },
    ['nayzeee_audio_b'] = {
        label = 'Echo Column', model = 'nayzeee_audio_b', portable = true,
        attach = {
            bone = 57005, offset = vector3(0.13, 0.02, -0.03), rotation = vector3(-80.0, 0.0, -10.0),
            dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 51,
        },
    },
    ['nayzeee_audio_c'] = {
        label = 'Drum Hub', model = 'nayzeee_audio_c', portable = true,
        anim  = { dict = 'nayzeee_audio_c', clip = 'nayzeee_audio_c' },
        attach = {
            bone = 60309, offset = vector3(0.08, 0.0, 0.07), rotation = vector3(-97.0, 0.6, 1.8),
            dict = 'impexp_int-0', clip = 'mp_m_waremech_01_dual-0', flag = 51,
        },
    },
    ['nayzeee_audio_d'] = {
        label = 'Orb', model = 'nayzeee_audio_d', portable = true,
        attach = {
            bone = 60309, offset = vector3(0.08, 0.0, 0.07), rotation = vector3(-97.0, 0.6, 1.8),
            dict = 'impexp_int-0', clip = 'mp_m_waremech_01_dual-0', flag = 51,
        },
    },
    ['nayzeee_audio_e'] = {
        label = 'Carry Cube', model = 'nayzeee_audio_e', portable = true,
        anim  = { dict = 'nayzeee_audio_e', clip = 'nayzeee_audio_e' },
        attach = {
            bone = 57005, offset = vector3(0.22, 0.0, -0.03), rotation = vector3(1.0, -81.4, -19.7),
            dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 51,
        },
    },
    ['nayzeee_audio_f'] = {
        label = 'Roll Bar', model = 'nayzeee_audio_f', portable = true,
        anim  = { dict = 'nayzeee_audio_f', clip = 'nayzeee_audio_f' },
        attach = {
            bone = 57005, offset = vector3(0.22, 0.0, -0.03), rotation = vector3(1.0, -81.4, -19.7),
            dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 51,
        },
    },
    ['nayzeee_audio_g'] = {
        -- Record Console upgrade (optional, nayzeee-speaker-assets/README.md): once its files are in stream/,
        -- set model = 'nayzeee_console' and delete the anim line (the console has no .ycd clip).
        -- The label stays 'Turntable' while this is the pack's own turntable prop ('Record Console' fits after the upgrade).
        label = 'Turntable', model = 'nayzeee_audio_g', portable = false, vinyl = true, -- plays records only
        anim  = { dict = 'nayzeee_audio_g', clip = 'nayzeee_audio_g' },
    },
    ['nayzeee_audio_h'] = {
        label = 'Studio Set', model = 'nayzeee_audio_h', portable = false,
        anim  = { dict = 'nayzeee_audio_h', clip = 'nayzeee_audio_h' },
    },
}

-- ██╗      ██████╗  ██████╗ ██╗  ██╗███████╗
-- ██║     ██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
-- ██║     ██║   ██║██║   ██║█████╔╝ ███████╗
-- ██║     ██║   ██║██║   ██║██╔═██╗ ╚════██║
-- ███████╗╚██████╔╝╚██████╔╝██║  ██╗███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
--  The speakers restyled while the server runs: new colours and designs, the NAYZEEE logo and
--      animated RGB lights. Nothing in stream/ is changed (the looks are images in html/looks/ that
--      are swapped in at runtime); stop the resource and the props look exactly as shipped.

Config.Looks = {
    enabled   = true,            -- false = the speakers look exactly as the pack ships them
    logo      = true,            -- logo on the speakers: true = NAYZEEE | 'nayzeee_teal' | false = the pack's BZOOMBOX badge
    record    = true,            -- record on the turntable: true = NAYZEEE | 'teal_vinyl' | 'crimson_vinyl' | 'smoke_vinyl' | false = the pack's
    recordArt = true,            -- the album cover on that record while an album plays on the nearest turntable
                                 --   (the record console upgrade has its own: Config.Turntable.labelArt)

    -- A colour / design per texture of the pack ('original' = as shipped). Every look is a file:
    --   html/looks/<texture>/<look>.png  (add your own there and list it in html/looks/library.json)
    --   fabrics: original | graphite | teal | crimson | violet | cobalt | arctic | carbon | honeycomb | stripe | camo | sunset
    --   drivers: original | graphite | chrome | teal | crimson | violet | gold | carbon | honeycomb
    textures = {
        sp1   = 'violet',        -- fabric of the Pulse Tower
        sp2   = 'honeycomb',     -- fabric of the Echo Column AND the Carry Cube (one texture, so they always match)
        sp3   = 'cobalt',        -- fabric of the Drum Hub
        sp4   = 'sunset',        -- fabric of the Orb
        sp5   = 'crimson',       -- fabric of the Roll Bar
        repro = 'chrome',        -- drivers on both ends of the Roll Bar
    },

    -- Animated lights. The Carry Cube and Roll Bar always get them; the other speakers keep their
    -- light inside the model (see builtIn). The Turntable has none.
    rgb = {
        enabled    = true,       -- animated lights (players can still turn them off for themselves in Settings)
        mode       = 'rainbow',  -- rainbow | fade | pulse | static | music (follows the music you hear)
        colors     = { '#08afa2', '#7b2ff7', '#ff2d75' },   -- fade / pulse go through these, static uses the first
        speed      = 1.0,        -- 0.25 = slow drift, 1 = default, 3 = fast
        brightness = 1.0,        -- 0 - 1
        saturation = 1.0,        -- 0 = white light, 1 = full colour
        distance   = 60.0,       -- metres: the lights only run while one of these speakers is this close
        builtIn    = true,       -- also try the lights built into the Pulse Tower, Echo Column, Drum Hub, Orb and
                                 --   Studio Set (if the game doesn't allow it they simply keep their own colours)
    },
}

--
-- ██╗   ██╗██╗███╗   ██╗██╗   ██╗██╗     
-- ██║   ██║██║████╗  ██║╚██╗ ██╔╝██║     
-- ██║   ██║██║██╔██╗ ██║ ╚████╔╝ ██║     
-- ╚██╗ ██╔╝██║██║╚██╗██║  ╚██╔╝  ██║     
--  ╚████╔╝ ██║██║ ╚████║   ██║   ███████╗
--   ╚═══╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝
--  Records for the turntable. Every record is its own item and holds a whole album.
--      Put it on the turntable to play the album in order; take it off to get the record back.
--      tracks: YouTube links (or video IDs) in album order. cover: any image link for the sleeve art.

Config.VinylReturn = 'ejector'  -- ejector = whoever takes the record off gets it | owner = whoever put it on

--  The record console upgrade (nayzeee_console): the record goes on from the player's hand, the platter
--      spins up and the tonearm drops the needle the moment the music starts, then creeps inward.
--      Needs the converted upgrade in stream/ (nayzeee_console, nayzeee_tt_platter, nayzeee_tt_arm,
--      nayzeee_vinyl) and Config.Boomboxes['nayzeee_audio_g'].model = 'nayzeee_console'. On the old
--      turntable prop none of this shows (it has its own platter and record; see Config.Looks.recordArt).

Config.Turntable = {
    consoleModel = 'nayzeee_console',   -- the upgrade's model: platter / tonearm / record only appear on this one
    visuals    = true,           -- show the platter, tonearm and record on placed consoles
    distance   = 35.0,           -- metres around you that turntable props exist
    needleDrop = 'auto',         -- music waits for the needle to land: 'auto' (once the upgrade's parts are in stream/) | true | false
    labelArt   = true,           -- album cover on the record label of the nearest playing console
    labelSize  = 512,            -- label texture size in px (256 = lighter, 1024 = sharper)
    putAnim    = { dict = 'mp_common', clip = 'givetake1_a', flag = 48, duration = 1400 },  -- putting a record on
    takeAnim   = { dict = 'mp_common', clip = 'givetake1_b', flag = 48, duration = 1400 },  -- taking it off
}

-- ██████╗ ███████╗ ██████╗ ██████╗ ██████╗ ██████╗     ███████╗██╗  ██╗ ██████╗ ██████╗ 
-- ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗    ██╔════╝██║  ██║██╔═══██╗██╔══██╗
-- ██████╔╝█████╗  ██║     ██║   ██║██████╔╝██║  ██║    ███████╗███████║██║   ██║██████╔╝
-- ██╔══██╗██╔══╝  ██║     ██║   ██║██╔══██╗██║  ██║    ╚════██║██╔══██║██║   ██║██╔═══╝ 
-- ██║  ██║███████╗╚██████╗╚██████╔╝██║  ██║██████╔╝    ███████║██║  ██║╚██████╔╝██║     
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     
--  Walk up to the counter and the records stand above it in a row you browse, listen to and buy.
--      Sells every record in vinyls.lua plus everything /vinylimport adds (price / genre / description
--      come from vinyls.lua, or from `records` below for imported ones).
--      With the record console upgrade in stream/ (its nayzeee_sleeve_a/_b/_c + nayzeee_vinyl) the sleeves
--      are real 3D props with the album cover on them; without it the same shop shows cover cards instead.

Config.RecordShop = {
    enabled      = true,
    currency     = 'cash',       -- cash | bank | item (pays with the inventory item below)
    moneyItem    = 'money',      -- only used with currency = 'item'
    defaultPrice = 250,          -- records without their own price in vinyls.lua
    maxCopies    = 0,            -- most copies of one record a player can hold when buying (0 = no limit)
    sort         = 'artist',     -- artist | album | year | price
    genres       = { 'Hip-Hop', 'R&B', 'Pop', 'Classics' },   -- filter chip order (any other genre follows A-Z)

    -- price / genre / description for imported records, or to override vinyls.lua (price = false = not sold)
    records = {
        -- ['vinyl_myalbum'] = { price = 400, genre = 'Hip-Hop', description = 'One short line.' },
    },

    preview = {
        enabled  = true,         -- L / Listen plays a bit of the record's first song, only for that player
        length   = 30,           -- seconds
        at       = 0.3,          -- where in the song it starts (0.3 = 30 % in)
        start    = 30,           -- seconds in, for a song whose length isn't known yet (YouTube embed)
        volume   = 0.8,          -- on top of each player's own music volume
        cooldown = 2.0,          -- seconds between previews per player
    },

    -- COUNTER DISPLAY
    display        = 'auto',     -- auto (3D once the upgrade's sleeves are in stream/) | 3d | 2d (cover cards only)
    turn           = 'sway',     -- sway (the featured sleeve rocks gently) | spin (turns all the way round)
    swayAngle      = 14.0,       -- degrees either way for sway
    spinSpeed      = 14.0,       -- degrees per second for spin
    transitionTime = 420,        -- ms for the slide between records
    sideSleeves    = true,       -- show the previous / next record either side
    sideAngle      = 32.0,       -- how far the side sleeves turn in
    sideAlpha      = 170,        -- 0 - 255, how strongly the side sleeves show
    lean           = 6.0,        -- the sleeves lean back a little, like on a stand
    coverSize      = 512,        -- cover texture size in px on the 3D sleeves (256 = lighter, 1024 = sharper)
    depthOfField   = true,       -- soft-focus the shop behind the counter
    sounds         = true,       -- GTA menu sounds when browsing / buying

    -- Tills, monitors and the like near the display are hidden for the shopper only, then come back.
    -- Props baked into an MLO can only be hidden by model name.
    hideProps = {
        enabled = true,
        radius  = 1.6,           -- metres around the sleeves
        maxSize = 1.6,           -- anything bigger is left alone (counters, shelves, walls)
        models  = {
            'prop_till_01', 'prop_till_02', 'prop_till_03', 'prop_cash_register_01', 'v_ret_gc_cashreg',
            'v_ret_ta_till', 'prop_monitor_01a', 'prop_monitor_01b', 'prop_keyboard_01a', 'prop_mouse_01',
        },
    },

    -- HOW PLAYERS GET IN (target on the shopkeeper, or an [E] prompt with Config.Target = 'none')
    interactDistance = 2.5,          -- metres from the shopkeeper
    pedDistance      = 60.0,         -- shopkeepers only exist while someone is this close
    command          = 'recordshop', -- admins: opens the shop where you stand, for testing ('' = off)

    locations = {
        {
            label   = 'Record Shop',
            -- EXAMPLE SPOT: the counter of the 24/7 on Innocence Blvd. Move it to your own shop.
            -- coords = where the shopkeeper stands, heading = the way they face (towards the customer)
            coords  = vector3(24.47, -1346.62, 29.50),
            heading = 271.66,
            ped     = 'a_m_y_hipster_01',    -- shopkeeper model (false = no shopkeeper, a marker instead)
            -- scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
            blip    = { sprite = 52, color = 26, scale = 0.7, label = 'Record Shop' },   -- false = no blip

            -- Where the records stand. Without `point` it's worked out from the shopkeeper:
            --   forward  metres in front of them, height  above their coords (the featured sleeve's bottom edge)
            --   camDistance / camHeight  how far back and up the camera stands, on the customer's side
            --   point = exact spot of the featured sleeve's bottom edge, cam = exact camera spot
            --   heading = the way the display faces the customer (default: the shopkeeper's heading)
            display = {
                forward     = 0.75,
                height      = 0.05,
                camDistance = 1.05,
                camHeight   = 0.08,
                fov         = 40.0,
                -- point = vector3(25.22, -1346.60, 29.55),
                -- cam   = vector3(26.27, -1346.57, 29.79),
            },
        },
    },
}

-- Records live in vinyls.lua (next to this file) so this config stays readable.

--  █████╗  ██████╗████████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
-- ███████║██║        ██║   ██║██║   ██║██╔██╗ ██║███████╗
-- ██╔══██║██║        ██║   ██║██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

Config.Actions = {
    place = {
        selectLocation = true,   -- true = aim a preview to place it, false = drops in front of you
        timeout        = 30000,  -- ms before placement cancels itself
        offset         = vector4(0.75, 0.0, 0.0, 180.0), -- used when selectLocation = false
        distance       = 8.0,    -- furthest you can place from yourself
        keys           = { accept = 38, cancel = 47, hold = 74 },  -- E / G / H (control ids)
        anim           = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1, duration = 1500 },
    },
    dropKey  = 'X',              -- puts down a carried boombox (rebindable)
    pickup   = 'owner',          -- owner | anyone  (who can carry / pack up a placed boombox)
    control  = 'anyone',         -- default access for new boomboxes: anyone | owner (owner can switch it in the player)
    useRange = 3.0,              -- how close you must be to open / control a boombox
}

-- ██████╗ ██╗      █████╗  ██████╗██╗  ██╗██╗     ██╗███████╗████████╗███████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝██║     ██║██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝██║     ███████║██║     █████╔╝ ██║     ██║███████╗   ██║   ███████╗
-- ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ ██║     ██║╚════██║   ██║   ╚════██║
-- ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗███████╗██║███████║   ██║   ███████║
-- ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝╚══════╝   ╚═╝   ╚══════╝
--  Boomboxes can't be placed inside these zones and cars can't start music in them.
--      Dying in one while carrying a boombox returns it to your inventory.

Config.BlacklistedZones = {
    { coords = vector3(455.5, -994.3, 27.0), radius = 45.0 },   -- Mission Row PD
    { coords = vector3(320.8, -591.0, 45.0), radius = 40.0 },   -- Pillbox Medical
}

Config.BlacklistedVehicles = {
    classes = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true }, -- bikes, cycles, boats, helis, planes
    models  = { [`issi2`] = true },
}

-- ███████╗████████╗██████╗ ███████╗ █████╗ ███╗   ███╗███████╗██████╗ 
-- ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗
-- ███████╗   ██║   ██████╔╝█████╗  ███████║██╔████╔██║█████╗  ██████╔╝
-- ╚════██║   ██║   ██╔══██╗██╔══╝  ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗
-- ███████║   ██║   ██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝
--  Streamer mode mutes every song for that player only and hides track names on screen,
--      so nobody's stream catches a copyright strike. Saved per player.

Config.StreamerMode = {
    enabled = true,              -- let players use streamer mode
    command = 'streamermode',    -- toggle command ('' = only from the player's Settings tab)
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝ 
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝  
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║   
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝   

Config.Notify = function(msg, kind, duration)
    kind, duration = kind or 'inform', duration or 5000
    if GetResourceState('ox_lib') == 'started' then
        return TriggerEvent('ox_lib:notify', { title = 'Speaker', description = msg, type = kind, duration = duration })
    end
    if GetResourceState('okokNotify') == 'started' then
        return exports['okokNotify']:Alert('Speaker', msg, duration, kind == 'inform' and 'info' or kind)
    end
    if GetResourceState('es_extended') == 'started' then
        return TriggerEvent('esx:showNotification', msg, kind == 'inform' and 'info' or kind, duration)
    end
    if GetResourceState('qb-core') == 'started' then
        return TriggerEvent('QBCore:Notify', msg, kind == 'inform' and 'primary' or kind, duration)
    end
    print(('[speaker] %s'):format(msg))
end
