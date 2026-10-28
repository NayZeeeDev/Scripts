Config = {}

--[[
    nayzeee-streamer - Pulse
    Every option is explained next to it. Docs: https://docs.nayzeeedev.com

    Secrets never go in this file. Add these two lines to server.cfg:
        set pulse_server_key "pk_..."                                          -- from pulse_register_server()
        set pulse_api_url "https://<ref>.supabase.co/functions/v1/pulse-api"   -- optional, overrides Config.Network.Url
]]

Config.Debug = false              -- extra prints in F8 and the server console
Config.Locale = 'en'              -- file name in locales/
Config.Framework = 'auto'         -- 'auto' | 'esx' | 'qbcore' | 'qbox'
Config.Inventory = 'auto'         -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'esx' | 'framework' | 'custom'
                                  -- 'framework' uses your framework's own item functions (ps-inventory, lj-inventory, qs-inventory)
                                  -- 'custom' reads bridge/inventory/custom.lua
Config.Notify = 'auto'            -- 'auto' | 'nayzeee-notify' | 'ox_lib' | 'esx' | 'qb' | 'native' | 'custom'
Config.Target = 'auto'            -- 'auto' | 'ox_target' | 'qb-target' | 'textui'
Config.Phone = 'auto'             -- 'auto' | 'lb-phone' | 'yseries' | 'qs-smartphone-pro' | 'qs-smartphone' | 'npwd' | 'gksphone' | 'okokPhone' | 'roadphone' | 'none'
Config.Identity = 'character'     -- 'character' = one channel per character | 'license' = one channel per player

-- Only used when Config.Notify = 'custom'. Runs on the client.
-- Config.CustomNotify = function(message, notifyType, title)
--     exports['my-notify']:Show(title, message, notifyType)
-- end
Config.CustomNotify = nil

-- Name and colours the players see in the app.
Config.Brand = {
    Name = 'Pulse',
    Currency = 'Sparks',          -- paid currency
    Points = 'Charge',            -- free watch-time points (streamers can rename theirs)
    Accent = '#08afa2',
    Tagline = 'Live from Los Santos.',
}

-- The shared network. Every server on the same Supabase project sees the same channels.
Config.Network = {
    Url = 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/pulse-api',   -- convar pulse_api_url wins if set
    KeyConvar = 'pulse_server_key',   -- name of the convar that holds this server's key. Use set, not setr
    Timeout = 10000,                  -- ms per gateway request
    PollInterval = 15,                -- seconds between live list refreshes
    PointsInterval = 60,              -- seconds between watch-time point payouts
    HiddenServers = {},               -- server slugs you don't want to show, e.g. { 'other-city' }
    ShowMature = true,                -- false hides streams marked 18+
}

-- How players open the app.
-- Prop Offset is in metres and Rotation in degrees, both on the Bone. Adjust them if a prop sits wrong.
-- Flag 49 = upper body only, loops, player can walk.
Config.Devices = {
    RequireDevice = true,             -- false lets /pulse open the app without a laptop or tablet
    Command = 'pulse',                -- /pulse, /pulse laptop, /pulse tablet, /pulse phone

    Laptop = {
        Items = { 'streamer_laptop' },
        Prop = 'prop_laptop_01a',
        Anim = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base' },
        Flag = 49,
        Bone = 60309,                 -- PH_L_Hand
        Offset = vec3(0.12, 0.02, -0.03),
        Rotation = vec3(-100.0, 175.0, 0.0),
        Placeable = true,             -- players can also set the laptop down on a table (gear)
    },

    Tablet = {
        Items = { 'streamer_tablet' },
        Prop = 'prop_cs_tablet',
        Anim = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base' },
        Flag = 49,
        Bone = 60309,                 -- PH_L_Hand
        Offset = vec3(0.03, 0.002, -0.0),
        Rotation = vec3(10.0, 160.0, 0.0),
    },

    Phone = {
        App = true,                   -- add a Pulse app to the detected phone (see Config.Phone)
        Name = 'Pulse',
        Description = 'Watch and go live.',
        Icon = 'html/img/app-icon.png',
        -- Used when no phone resource is running and the built-in phone frame opens
        Prop = 'prop_npc_phone_02',
        Anim = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        Flag = 49,
        Bone = 28422,                 -- PH_R_Hand
        Offset = vec3(0.0, 0.0, 0.0),
        Rotation = vec3(0.0, 0.0, 0.0),
    },
}

-- Camera tiers. Owning a better camera raises resolution, frame rate, bitrate and the look.
-- filter: 'webcam' (soft, a little noise) | 'clean' | 'cinema' (graded, letterbox-ready)
-- hold: the prop and animation used for the Handheld scene.
--       view = 'selfie' films you from the front, 'pov' films what is in front of you.
Config.Cameras = {
    stream_webcam = {
        tier = 1, label = 'Webcam', model = 'prop_ing_camera_01',
        width = 854, height = 480, fps = 24, bitrate = 900, filter = 'webcam', dof = false,
        hold = {
            view = 'selfie',
            model = 'prop_ing_camera_01',
            anim = { dict = 'cellphone@self', clip = 'selfie' },
            flag = 49,
            bone = 28422,             -- PH_R_Hand
            offset = vec3(0.02, 0.0, 0.0),
            rotation = vec3(0.0, 0.0, 180.0),
        },
    },
    stream_camera_hd = {
        tier = 2, label = 'HD Camera', model = 'prop_pap_camera_01',
        width = 1280, height = 720, fps = 30, bitrate = 2500, filter = 'clean', dof = false,
        hold = {
            view = 'selfie',
            model = 'prop_pap_camera_01',
            anim = { dict = 'cellphone@self', clip = 'selfie' },
            flag = 49,
            bone = 28422,
            offset = vec3(0.02, 0.0, 0.0),
            rotation = vec3(0.0, 0.0, 180.0),
        },
    },
    stream_camera_cinema = {
        tier = 3, label = 'Cinema Camera', model = 'prop_v_cam_01',
        width = 1920, height = 1080, fps = 30, bitrate = 4500, filter = 'cinema', dof = true,
        hold = {
            view = 'pov',             -- shoulder rig, films what you look at
            model = 'prop_v_cam_01',
            anim = { dict = 'missfinale_c2mcs_1', clip = 'fin_c2_mcs_1_camman' },
            flag = 49,
            bone = 57005,             -- SKEL_R_Hand
            offset = vec3(0.0, 0.0, 0.0),
            rotation = vec3(0.0, 0.0, 0.0),
        },
    },
}

-- Gameplay scene (streaming your own view from a laptop).
Config.Gameplay = { width = 1280, height = 720, fps = 30, bitrate = 2500, filter = 'screen' }

-- Phone scene: vertical selfie video.
Config.PhoneCamera = {
    width = 540, height = 960, fps = 24, bitrate = 1200, filter = 'phone',
    model = 'prop_npc_phone_02',
    anim = { dict = 'cellphone@self', clip = 'selfie' },
    flag = 49,
    bone = 28422,                     -- PH_R_Hand
    offset = vec3(0.0, 0.0, 0.0),
    rotation = vec3(0.0, 0.0, 0.0),
}

-- Microphone tiers. 'none' is used when the player owns no mic item.
-- highpass / lowpass in Hz, bitrate in kbps, noise = added hiss (0 to 0.02), gain = output level.
Config.Microphones = {
    none = {
        tier = 0, label = 'Built-in mic',
        bitrate = 24, highpass = 300, lowpass = 3400, compressor = false, noise = 0.012, gain = 0.9,
        noiseSuppression = true, echoCancellation = true,
    },
    stream_mic_headset = {
        tier = 1, label = 'Headset', model = 'prop_headphones_01',
        bitrate = 32, highpass = 160, lowpass = 7000, compressor = false, noise = 0.004, gain = 1.0,
        noiseSuppression = true, echoCancellation = true,
    },
    stream_mic_usb = {
        tier = 2, label = 'USB Mic', model = 'prop_table_mic_01',
        bitrate = 64, highpass = 90, lowpass = 14000, compressor = true, noise = 0.0, gain = 1.05,
        noiseSuppression = true, echoCancellation = true,
    },
    stream_mic_studio = {
        tier = 3, label = 'Studio Mic', model = 'p_ing_microphonel_01',
        bitrate = 96, highpass = 60, lowpass = 20000, compressor = true, noise = 0.0, gain = 1.1,
        noiseSuppression = false, echoCancellation = true,   -- keeps the raw voice
    },
}

-- Hand-held mic for IRL streams. Using one of these items puts the mic in your hand, use again to put it away.
Config.MicHold = {
    Enabled = true,
    Items = { 'stream_mic_studio' },
    Model = 'p_ing_microphonel_01',
    Anim = { dict = 'missheistdocksprep1hold_cellphone', clip = 'hold_cellphone' },
    Flag = 49,
    Bone = 60309,                     -- PH_L_Hand
    Offset = vec3(0.055, 0.05, 0.0),
    Rotation = vec3(240.0, 0.0, 0.0),
}

-- Scenes the streamer can switch between. icon = Font Awesome name without fa-
Config.Scenes = {
    gameplay = { enabled = true, label = 'Gameplay', icon = 'gamepad' },       -- needs a laptop
    tripod   = { enabled = true, label = 'Tripod', icon = 'video' },           -- needs a placed tripod with a camera
    handheld = { enabled = true, label = 'Handheld', icon = 'camera', distance = 0.85, height = 0.62, fov = 50.0 },
    phone    = { enabled = true, label = 'Phone', icon = 'mobile-screen', distance = 0.55, height = 0.66, fov = 60.0 },
    orbit    = { enabled = true, label = 'Orbit', icon = 'arrows-spin', minTier = 3, radius = 2.6, height = 0.55, speed = 6.0, fov = 45.0 },
                                      -- speed in degrees per second
}

-- Photo booth used for avatars and banners.
Config.PhotoBooth = { distance = 1.0, height = 0.65, fov = 32.0 }

-- Placeable studio gear.
Config.Studio = {
    Persist = true,                   -- false keeps placed gear until the next restart only
    MaxGearPerPlayer = 6,
    ShareGear = false,                -- true lets anyone use and adjust anyone's gear
    PlaceDistance = 6.0,              -- how far from you gear can be placed
    UseDistance = 15.0,               -- how far you can be from your tripod while streaming from it

    -- Studio camera on a stand. Mount any camera item on it to set the quality.
    Tripod = {
        Item = 'stream_tripod',
        Model = 'prop_tv_cam_02',
        LensOffset = vec3(0.0, 0.42, 1.48),     -- x right, y forward, z up from the model origin
        MountOffset = vec3(0.0, 0.05, 1.40),    -- where a mounted camera prop sits
        ShowCamera = false,                     -- true attaches the mounted camera's model (for bare tripod models)
        Defaults = { pan = 0, tilt = 0, fov = 50, focus = 2.5 },
    },

    -- Light on a stand. Glow draws a lit ring on the lamp head, the light itself is a real in-game light.
    RingLight = {
        Item = 'stream_ringlight',
        Model = 'prop_studio_light_02',
        RingOffset = vec3(0.0, 0.16, 1.72),     -- centre of the ring from the model origin
        RingRadius = 0.22,
        DrawDistance = 30.0,
        Glow = true,
        Defaults = { on = true, brightness = 8.0, range = 6.0, temperature = 5600, color = nil },
        Presets = {
            { id = 'daylight', label = 'Daylight', temperature = 5600 },
            { id = 'warm', label = 'Warm', temperature = 3200 },
            { id = 'neutral', label = 'Neutral', temperature = 4500 },
            { id = 'cool', label = 'Cool', temperature = 7000 },
            { id = 'teal', label = 'Teal', color = { r = 8, g = 175, b = 162 } },
            { id = 'red', label = 'Red', color = { r = 229, g = 72, b = 77 } },
            { id = 'purple', label = 'Purple', color = { r = 145, g = 70, b = 255 } },
            { id = 'pink', label = 'Pink', color = { r = 255, g = 92, b = 170 } },
        },
    },

    -- A laptop set down on a table. Gameplay scene works within 3 m of it.
    Laptop = {
        Model = 'prop_laptop_01a',
        UseOffset = vec3(0.0, -0.6, 0.0),       -- where you stand to use it, from the laptop
        UseAnim = { dict = 'anim@amb@clubhouse@boss@male@', clip = 'computer_idle' },
        SeatedAnim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
    },

    --[[ Custom streamed models (see stream/README.md)
    Tripod.Model = 'nz_tripod_01', Tripod.ShowCamera = true
    RingLight.Model = 'nz_ringlight_01', RingLight.RingOffset = vec3(0.0, 0.0, 1.62), RingLight.RingRadius = 0.25
    ]]
}

-- Sparks, cash out and spark cards.
Config.Economy = {
    MoneyAccount = 'bank',            -- 'bank' | 'cash' used to buy Sparks
    CurrencySymbol = '$',
    Packages = {
        { sparks = 100, price = 1000 },
        { sparks = 500, price = 4750 },
        { sparks = 1500, price = 13500 },
        { sparks = 5000, price = 42500 },
    },
    SparkCards = {                    -- item = Sparks it adds when used
        spark_card_500 = 500,
        spark_card_2500 = 2500,
    },
    Cashout = {
        Enabled = true,
        Rate = 7,                     -- money paid per 1 earning
        Min = 100,                    -- smallest cash out, in earnings
        DailyMax = 50000,             -- most earnings one channel can cash out per day on this server
        Account = 'bank',             -- 'bank' | 'cash'
        From = 'trusted',             -- which earnings count: 'all' servers | 'trusted' servers | 'own' server only
    },
}

-- Electronics shop. Buyers pay from Account.
Config.Shop = {
    Enabled = true,
    Account = 'bank',                 -- 'bank' | 'cash'
    MaxAmount = 10,                   -- most of one item per purchase
    Shops = {
        {
            id = 'digital_den',
            label = 'Digital Den',
            coords = vec4(-656.69, -857.98, 24.49, 0.0),      -- outside the Digital Den, Little Seoul
            ped = 'a_m_y_hipster_01',                        -- false for no ped (target sphere only)
            blip = { sprite = 521, color = 26, scale = 0.7, label = 'Digital Den' },
            items = {
                { item = 'streamer_laptop', price = 4500 },
                { item = 'streamer_tablet', price = 2500 },
                { item = 'stream_webcam', price = 750 },
                { item = 'stream_camera_hd', price = 6500 },
                { item = 'stream_camera_cinema', price = 22000 },
                { item = 'stream_mic_headset', price = 400 },
                { item = 'stream_mic_usb', price = 1800 },
                { item = 'stream_mic_studio', price = 6500 },
                { item = 'stream_tripod', price = 1500 },
                { item = 'stream_ringlight', price = 1200 },
                { item = 'spark_card_500', price = 5000 },
                { item = 'spark_card_2500', price = 23500 },
            },
        },
    },
}

Config.Notifications = {
    GoLive = true,                    -- tell followers on this server when a channel they follow goes live
}

-- Default keys. Players can change them in Settings > Key Bindings > FiveM.
Config.Keys = {
    Deck = 'F7',                      -- stream deck while live, the app otherwise
    Chat = 'U',                       -- type in the overlay chat
    Privacy = '',                     -- be right back card (no default key)
    Scene = '',                       -- next scene (no default key)
}

-- Staff. Grant with: add_ace group.admin nayzeee.streamer.admin allow
Config.Admin = {
    Ace = 'nayzeee.streamer.admin',
    Groups = { 'admin', 'superadmin', 'god' },   -- framework groups that also count as staff
    Command = 'pulseadmin',
}

-- TVs that can be tuned to a live stream. rt = the model's render target.
Config.Screens = {
    Enabled = true,
    DrawDistance = 12.0,
    Models = {
        { model = 'prop_tv_flat_01', rt = 'tvscreen' },
        { model = 'prop_tv_flat_02', rt = 'tvscreen' },
        { model = 'prop_tv_flat_02b', rt = 'tvscreen' },
        { model = 'prop_tv_flat_03', rt = 'tvscreen' },
        { model = 'prop_tv_flat_03b', rt = 'tvscreen' },
        { model = 'prop_tv_flat_michael', rt = 'tvscreen' },
        { model = 'prop_trev_tv_01', rt = 'tvscreen' },
        { model = 'prop_tv_02', rt = 'tvscreen' },
        { model = 'prop_tv_03', rt = 'tvscreen' },
        { model = 'des_tvsmash_start', rt = 'tvscreen' },
        { model = 'prop_monitor_w_large', rt = 'tvscreen' },
        { model = 'prop_monitor_02', rt = 'tvscreen' },
        { model = 'v_ilev_lest_bigscreen', rt = 'tvscreen' },
        { model = 'v_ilev_mm_screen2', rt = 'tvscreen' },
        { model = 'ex_prop_ex_tv_flat_01', rt = 'ex_tvscreen' },
        { model = 'xm_prop_x17_tv_flat_01', rt = 'tv_flat_01' },
        { model = 'sm_prop_smug_tv_flat_01', rt = 'tv_flat_01' },
        { model = 'prop_huge_display_01', rt = 'big_disp' },
        { model = 'prop_huge_display_02', rt = 'big_disp' },
        { model = 'v_ilev_cin_screen', rt = 'cinscreen' },
    },
}

Config.Viewer = {
    MiniPlayer = true,                -- keep watching in a small player while you play
    DefaultVolume = 0.8,
}

-- Stream languages players can pick.
Config.Languages = { 'en', 'es', 'fr', 'de', 'pt', 'nl', 'it', 'pl', 'tr', 'ar' }

-- Only used when Config.Target = 'textui' (or no target resource is running).
-- control ids: https://docs.fivem.net/docs/game-references/controls/
Config.TextUI = {
    Keys = {
        { key = 'E', control = 38 },
        { key = 'G', control = 47 },
        { key = 'H', control = 74 },
    },
}
