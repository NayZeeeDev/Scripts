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
                                                        

  Speakers, boomboxes & CarPlay  |  v1.0.0
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
Config.Version     = '1.0.1'     -- shown at the top of the player
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

    updateRate      = 120,       -- ms between spatial updates (lower = smoother, more CPU)
    panning         = 'HRTF',    -- HRTF (true 3D) | equalpower (cheaper)
    reverb          = true,      -- room echo based on ceiling height + walls (costs a few raycasts)
    maxCeiling      = 25.0,      -- highest ceiling checked for reverb
    interiorMuffle  = true,      -- speaker in a building sounds muffled from outside (and vice versa)
    vehicleMuffle   = true,      -- car music is muffled outside the car, opens up with windows / doors / roof
    occlusion       = true,      -- walls between you and the speaker dampen it
    doppler         = true,      -- pitch shifts as a car with music drives past you
    dopplerAmount   = 0.6,       -- 0 = off, 0.6 = subtle (default), 1 = realistic, 2 = exaggerated
    distanceMuffle  = true,      -- far speakers lose their highs, like real air does
    syncCheck       = true,      -- pulls lagging / alt-tabbed players back to the live position
    driftTolerance  = 1.5,       -- seconds out of sync before a resync
    unloadDistance  = 1.35,      -- songs are unloaded past range * this (frees memory)

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
        label = 'Turntable', model = 'nayzeee_audio_g', portable = false, vinyl = true, -- plays records only
        anim  = { dict = 'nayzeee_audio_g', clip = 'nayzeee_audio_g' },
    },
    ['nayzeee_audio_h'] = {
        label = 'Studio Set', model = 'nayzeee_audio_h', portable = false,
        anim  = { dict = 'nayzeee_audio_h', clip = 'nayzeee_audio_h' },
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
