--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ██████╗  █████╗  ██████╗██╗███╗   ██╗ ██████╗
    ██╔══██╗██╔══██╗██╔════╝██║████╗  ██║██╔════╝
    ██████╔╝███████║██║     ██║██╔██╗ ██║██║  ███╗
    ██╔══██╗██╔══██║██║     ██║██║╚██╗██║██║   ██║
    ██║  ██║██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝
    nayzeee-racing · v1.1.0
    Discord: discord.gg/nayzeeedev  ·  Docs: nayzeee-dev.gitbook.io/docs
]]

Config = {}

Config.Debug    = false       -- Draws checkpoint lines and prints race debug info
Config.LogLevel = 'warn'      -- debug | info | warn | error

-- ======================================================================
--   ___ ___ _  _ ___ ___    _   _
--  / __| __| \| | __| _ \  /_\ | |
-- | (_ | _|| .' | _||   / / _ \| |__
--  \___|___|_|\_|___|_|_\/_/ \_\____|
-- ======================================================================
Config.General = {
    OpenByCommand = false,                                   -- Allow opening the tablet with a command / keybind
    Command       = 'racing',                                -- Command name (only if OpenByCommand = true)
    OpenKey       = 'F5',                                    -- Default keybind for the command (players can rebind)
    Item          = 'racing_tablet',                         -- Usable item that opens the tablet (false to disable)
    TabletProp    = true,                                    -- Hold a tablet prop + animation while the UI is open
    Tablet        = `imp_prop_impexp_tablet`,                -- Tablet prop model
    Blur          = true,                                    -- Blur the game behind the tablet
    VehicleImagesUrl = 'https://docs.fivem.net/vehicles/{car}.webp', -- Vehicle images in the vehicle picker ({car} = spawn name)
    DnfCommand    = 'dnf',                                   -- Command to give up / disqualify from your current race
}

-- ======================================================================
--  ___ ___  ___  ___ ___ _    ___ ___
-- | _ \ _ \/ _ \| __|_ _| |  | __/ __|
-- |  _/   / (_) | _| | || |__| _|\__ \
-- |_| |_|_\\___/|_| |___|____|___|___/
-- ======================================================================
Config.Profiles = {
    StartingElo       = 500,                                 -- ELO for new racer profiles
    AllowCustomImages = false,                               -- Allow image URLs as profile pictures
    AllowAllDomains   = true,                                -- Allow image URLs from any domain
    AllowedDomains    = { 'imgur.com', 'discordapp.com', 'discordapp.net' }, -- Used when AllowAllDomains = false
    AllowAvatars      = true,                                -- Allow generated avatars
    AvatarTypes       = { 'avataaars-neutral', 'pixel-art', 'fun-emoji' }, -- avataaars-neutral | pixel-art | fun-emoji
    AliasMin          = 3,                                   -- Minimum alias length
    AliasMax          = 20,                                  -- Maximum alias length
    Colors            = { '#08afa2', '#e5484d', '#e5a50a', '#3c83f6', '#a855f7', '#ec4899', '#22c55e', '#f97316', '#ffffff' }, -- Profile / crew colour swatches
}

-- ======================================================================
--   ___ ___ _____      _____
--  / __| _ \ __\ \    / / __|
-- | (__|   / _| \ \/\/ /\__ \
--  \___|_|_\___| \_/\_/ |___/
-- ======================================================================
Config.Crews = {
    MemberCap         = nil,                                 -- Max members per crew (nil = unlimited)
    AllowCustomImages = false,                               -- Allow image URLs as crew logos
    AllowAllDomains   = true,                                -- Allow logo URLs from any domain
    AllowedDomains    = { 'imgur.com', 'discordapp.com', 'discordapp.net' }, -- Used when AllowAllDomains = false
    AllowAvatars      = true,                                -- Allow generated crew logos
    AvatarTypes       = { 'avataaars-neutral', 'pixel-art' }, -- Generated logo styles
    TagMin            = 2,                                   -- Crew tag length (letters / numbers only)
    TagMax            = 4,
}

-- ======================================================================
--  _____ ___    _   ___ _  _____
-- |_   _| _ \  /_\ / __| |/ / __|
--   | | |   / / _ \ (__| ' <\__ \
--   |_| |_|_\/_/ \_\___|_|\_\___/
-- ======================================================================
Config.Trackbuilder = {
    AdminOnly        = true,                                 -- Only admins may create / edit / delete tracks
    AllowCreation    = true,                                 -- If AdminOnly = false: true = everyone, false = AcePermission only
    AcePermission    = 'nayzeee.racing.trackbuilder',        -- ACE used when AllowCreation = false
    MaxCheckpoints   = 99,                                   -- Maximum checkpoints per track
    MinCheckpoints   = 2,                                    -- Minimum checkpoints per track
    CheckpointModel  = 'prop_offroad_tyres02',               -- Gate post model
    StartpointModel  = 'prop_offroad_tyres01',               -- Start / finish gate post model
    DistanceBetweenCheckpoints = 20.0,                       -- Minimum metres between two checkpoints
    CircuitMinimumDistanceBetweenFirstAndLastCheckpoint = 30.0, -- Circuits: last checkpoint must be within this of the start
    DefaultWidth     = 6.0,                                  -- Starting gate width (metres)
    CrewTracks       = true,                                 -- Crew-only tracks + crew records boards
    CrewCanBuild     = true,                                 -- Crew members with "Manage crew" may build crew-only tracks (even when AdminOnly)
}

-- ======================================================================
--  ___    _   ___ ___ ___
-- | _ \  /_\ / __| __/ __|
-- |   / / _ \ (__| _|\__ \
-- |_|_\/_/ \_\___|___|___/
-- ======================================================================
Config.Races = {
    DefaultTracks        = true,                             -- Seed the bundled public tracks on first boot
    MobilizeTimer        = 10000,                            -- ms to line up before the countdown
    CountdownTimer       = 3000,                             -- ms countdown before the race starts
    FreezeDuringCountdown = true,                            -- Freeze racers during the countdown
    ToggleVehicleDrift   = true,                             -- Drift races: enable drift tyres for the race, restored after
    MinCrewSize          = 2,                                -- Crew races: minimum accepted racers per crew
    AllowUnevenCrewSize  = false,                            -- Crew races: allow 2v3, 3v4 ...
    RequirePlayersInStartRadius = true,                      -- Everyone must be near the start line to start
    StartRadius          = 100.0,                            -- Radius around the start line (metres)
    AllowStarredLobbies  = true,                             -- Mark ranked lobbies with a high average ELO
    MinimumAverageForStarredLobby = 2000,                    -- Average ELO needed for a star
    RequiredParticipantsForRankedLobby = 4,                  -- Accepted racers needed to start a ranked race
    MaxParticipants      = 16,                               -- Highest "Number of racers" allowed when creating
    MaxLaps              = 20,                               -- Highest lap count allowed when creating
    WagerCurrencies      = { 'money' },                      -- Wager currencies (empty = wagers disabled). 'money' | 'crypto'
    MaxWager             = 1000000,                          -- Highest wager allowed
    Deadline             = 1000 * 60,                        -- Minimum ms the rest of the field gets after the winner finishes
    FinishedLobbyVisibilityTime = 1000 * 60 * 5,             -- How long finished lobbies stay in the list (ms)
    ResultsTime          = 12000,                            -- How long the results card stays on screen (ms)
    MaxCheckpointSpeed   = 150.0,                            -- Anti-cheat: highest average m/s allowed between two checkpoints
    CheckpointTolerance  = 30.0,                             -- Anti-cheat: extra metres allowed from a gate when it is crossed

    Elimination = {                                          -- Elimination mode: last place is out at the end of every lap
        MinRacers = 3,                                       -- Ready racers needed to start
        MinLaps   = 2,                                       -- Circuits only, at least this many laps
    },

    Respawn = {                                              -- Reset to your last checkpoint while racing
        Enabled  = true,                                     -- Enable the respawn key
        Key      = 'X',                                      -- Default key (players can rebind)
        HoldMs   = 1000,                                     -- Hold time before respawning
        Penalty  = 3000,                                     -- ms added to your time per respawn (0 = none)
        Cooldown = 5000,                                     -- ms between respawns
    },

    Ghostmode = {
        distance     = 20.0,                                 -- Distance at which other racers become ghosts (must be > a car length)
        alpha        = 200,                                  -- Ghost alpha (0-255)
        scanInterval = 100,                                  -- ms between distance scans
    },

    GatherSmoke = {
        enabled = true,                                      -- Flare at the start line when you are accepted into a lobby
        scale   = 1.0,
        rgb     = { r = 8.0, g = 175.0, b = 162.0 },         -- Flare colour
    },

    Sounds = {                                               -- Frontend sounds (players can mute in settings)
        Start      = { name = 'GO_NON_RACE',                 set = 'HUD_MINI_GAME_SOUNDSET' },
        Countdown  = { name = '3_2_1_NON_RACE',              set = 'HUD_MINI_GAME_SOUNDSET' },
        Checkpoint = { name = 'CHECKPOINT_NORMAL',           set = 'HUD_MINI_GAME_SOUNDSET' },
        Lap        = { name = 'CHECKPOINT_PERFECT',          set = 'HUD_MINI_GAME_SOUNDSET' },
        DNF        = { name = 'LOSER',                       set = 'HUD_AWARDS' },
        Finish     = { name = 'FLIGHT_SCHOOL_LESSON_PASSED', set = 'HUD_AWARDS' },
    },

    Cleanup = {
        Enable = true,                                       -- Remove knocked-over street clutter near you while racing
        Radius = 80.0,                                       -- Scan radius (metres)
        OnRoadModels = {                                     -- Removed when they end up on the road
            `prop_dumpster_01a`, `prop_dumpster_02a`, `prop_dumpster_02b`, `prop_dumpster_3a`, `prop_dumpster_4a`,
            `prop_dumpster_4b`, `prop_bin_01a`, `prop_bin_14b`, `prop_bin_14a`, `prop_bin_08a`, `prop_bin_05a`,
            `prop_bin_07c`, `prop_rub_binbag_03`, `prop_rub_binbag_01b`, `prop_rub_binbag_06`,
        },
    },
}

-- Featured lobbies: highlighted on the home page and announced to everyone
Config.Events = {
    AllowCreation = false,                                   -- true = everyone may create featured lobbies
    AcePermission = 'nayzeee.racing.events',                 -- ACE needed when AllowCreation = false (admins always can)
}

-- ======================================================================
--   PRACTICE · SPECTATE · SPLITS · QUICK RACE
-- ======================================================================
Config.Practice = {                                          -- Solo run of any track. No lobby, no wager. Sets PBs and world records
    Enabled        = true,
    MobilizeTimer  = 3000,                                   -- ms before the countdown
    MaxLaps        = 10,                                     -- Highest lap count for circuit practice
    CountsForStats = false,                                  -- false = practice runs never add races / wins to profiles and boards
    RetryKey       = 38,                                     -- Key to race again after a practice run (38 = E, false = off)
}

Config.Spectate = {                                          -- Watch a live race through a chase camera
    Enabled      = true,
    AutoOnFinish = true,                                     -- Watch the rest of the field after you finish or DNF
    Anyone       = true,                                     -- Anyone can watch a live lobby from the tablet (false = racers + host only)
    HostOnly     = true,                                     -- Hosts may run a lobby without racing in it and watch instead
    CullingRadius = 4000.0,                                  -- Racers stay visible to spectators within this many metres (OneSync)
    Camera       = { distance = 7.5, height = 2.4, smooth = 6.0 },
    Keys         = { next = 175, prev = 174, exit = 177 },   -- Right arrow, left arrow, backspace
}

Config.Splits = {                                            -- +/- against your PB and the world record at every checkpoint
    Enabled         = true,
    AnnounceRecords = true,                                  -- Tell everyone with a profile when a world record falls
}

Config.QuickRace = {                                         -- One tap: join the best open lobby for your car's class, or create one
    Enabled     = true,
    AllowWagers = false,                                     -- May join lobbies that take a wager
    Create = {                                               -- Lobby created when nothing fits
        Max         = 8,
        Laps        = 2,                                     -- Circuits (sprints ignore it)
        Ghost       = true,
        MaxDistance = 2500.0,                                -- Picks the closest public track within this range, else the most played one
    },
}

-- ======================================================================
--   PINK SLIPS · BETTING
-- ======================================================================
Config.PinkSlips = {                                         -- Race for the car itself. The winner takes every loser's title
    Enabled     = true,                                      -- false = nobody can create pink slip lobbies
    MaxRacers   = 2,                                         -- Highest lobby size for pink slips
    AllowRanked = false,                                     -- Allow pink slips on ranked lobbies
    DnfLoses    = true,                                      -- Leaving / disconnecting / DNF after the start still hands the car over
}

Config.Betting = {                                           -- Non-racers bet on a racer in a waiting lobby. Pool is split between winning bets
    Enabled  = true,
    Currency = 'money',                                      -- 'money' | 'crypto'
    Min      = 100,
    Max      = 50000,
    HouseCut = 0.05,                                         -- Share of the pool removed (money sink). 0.05 = 5%
    RefundIfNoWinner = true,                                 -- Nobody backed the winner / nobody finished: refund every bet (false = house keeps it)
}

-- ======================================================================
--   SEASONS · CHALLENGES
-- ======================================================================
Config.Seasons = {                                           -- ELO resets on a schedule, top racers get paid and a badge
    Enabled          = true,
    LengthDays       = 30,
    Reset            = 'soft',                               -- 'soft' = pulled towards StartingElo by SoftFactor | 'hard' = back to StartingElo
    SoftFactor       = 0.5,                                  -- soft: keeps this share of the distance from StartingElo
    MinRankedRaces   = 5,                                    -- Ranked races in the season needed to place
    ResetRankRewards = false,                                -- true = rank-up rewards can be earned again every season
    Rewards = {                                              -- Placement rewards, sent to the inbox
        { from = 1, to = 1,  badge = 'champion', money = 50000 },
        { from = 2, to = 3,  badge = 'podium',   money = 25000 },
        { from = 4, to = 10, badge = 'top10',    money = 10000 },
    },
    Badges = {
        champion = { label = 'Champion', icon = 'crown',        color = '#e8c35a' },
        podium   = { label = 'Podium',   icon = 'medal',        color = '#c9d0d6' },
        top10    = { label = 'Top 10',   icon = 'ranking-star', color = '#08afa2' },
    },
}

-- Daily and weekly challenges, the same for everyone. Rewards land in the inbox.
-- event: race | finish | win | podium | distance (metres). Filters: mode, type, track ('circuit' | 'sprint'), practice = true
Config.Challenges = {
    Enabled   = true,
    MinRacers = 2,                                           -- Racers a race needs to count (stops solo farming). Practice only counts with practice = true
    Daily = {
        Count = 3,
        Pool = {
            { id = 'd_finish',  label = 'Finish %d races',         event = 'finish',   goal = 3,     reward = { type = 'money', amount = 1000 } },
            { id = 'd_win',     label = 'Win a race',              event = 'win',      goal = 1,     reward = { type = 'money', amount = 1500 } },
            { id = 'd_podium',  label = 'Finish on the podium %d times', event = 'podium', goal = 2, reward = { type = 'money', amount = 1250 } },
            { id = 'd_drift',   label = 'Finish %d drift races',   event = 'finish',   goal = 2,     mode = 'drift', reward = { type = 'money', amount = 1250 } },
            { id = 'd_circuit', label = 'Finish %d circuit races', event = 'finish',   goal = 2,     track = 'circuit', reward = { type = 'money', amount = 1000 } },
            { id = 'd_dist',    label = 'Race 25 km',              event = 'distance', goal = 25000, reward = { type = 'money', amount = 1000 } },
            { id = 'd_practice', label = 'Finish %d practice runs', event = 'finish',   goal = 3,     practice = true, reward = { type = 'money', amount = 500 } },
        },
    },
    Weekly = {
        Count = 3,
        Pool = {
            { id = 'w_drift',   label = 'Win %d drift races',      event = 'win',      goal = 3,     mode = 'drift', reward = { type = 'money', amount = 7500 } },
            { id = 'w_circuit', label = 'Finish %d circuits',      event = 'finish',   goal = 5,     track = 'circuit', reward = { type = 'money', amount = 5000 } },
            { id = 'w_ranked',  label = 'Finish %d ranked races',  event = 'finish',   goal = 5,     type = 'ranked', reward = { type = 'money', amount = 7500 } },
            { id = 'w_wins',    label = 'Win %d races',            event = 'win',      goal = 5,     reward = { type = 'money', amount = 10000 } },
            { id = 'w_elim',    label = 'Top 3 in %d elimination races', event = 'podium', goal = 2,  mode = 'elimination', reward = { type = 'money', amount = 6000 } },
            { id = 'w_dist',    label = 'Race 150 km',             event = 'distance', goal = 150000, reward = { type = 'item', item = 'repairkit', amount = 3 } },
        },
    },
}

-- ======================================================================
--   ANTI-CHEAT
-- ======================================================================
Config.AntiCheat = {
    ModdedVehicles  = true,                                  -- Compare the car's power / top speed with its base handling at the start and during the race
    AccelTolerance  = 1.35,                                  -- Allowed acceleration vs base (engine upgrades fit inside this)
    SpeedTolerance  = 1.15,                                  -- Allowed estimated top speed vs base
    MaxTopSpeedModifier = 0.0,                               -- Highest ModifyVehicleTopSpeed value allowed (raise it if a tuning script uses it)
    IgnoreModels    = {},                                    -- Models never checked, e.g. { `sultanrs` }
    SwapDetection   = true,                                  -- DNF when the racer's car (model or plate) changes mid-race
    Action          = 'dq',                                  -- 'dq' = disqualify from the race | 'kick' = drop from the server
}

-- ======================================================================
--  _  _  ___ _____ ___ _____   __
-- | \| |/ _ \_   _|_ _| __\ \ / /
-- | .' | (_) || |  | || _| \ V /
-- |_|\_|\___/ |_| |___|_|   |_|
-- ======================================================================
Config.Notifications = {
    NewLobby      = 'profiles',                              -- 'all' | 'profiles' (players with a racer profile) | false
    LobbyStarting = 'participants',                          -- 'all' | 'profiles' | 'participants' | false
}

-- Client notification. Players can mute / disable racing notifications in the tablet settings.
Config.Notify = function(message, kind)
    lib.notify({ description = message, type = kind or 'inform', position = 'top' })
end

-- Hide / show your HUD while racing (client side). Leave empty if not needed.
Config.Hud = {
    OnRaceStart = function()
        -- exports['nayzeee-hud']:SetVisible(false)
    end,
    OnRaceEnd = function()
        -- exports['nayzeee-hud']:SetVisible(true)
    end,
}

-- ======================================================================
--  _   _ ___
-- | | | |_ _|
-- | |_| || |
--  \___/|___|
-- ======================================================================
Config.UI = {
    Accent     = '#08afa2',                                  -- Accent colour (tablet, HUD, checkpoints)
    Danger     = '#e5484d',                                  -- Danger colour (close pill, DNF, errors)
    Scale      = 1.0,                                        -- Tablet scale
    HudScale   = 1.0,                                        -- Race HUD scale
    RouteColor = 12,                                         -- GPS route colour between checkpoints (HUD colour id)
    BlipColor  = 5,                                          -- Checkpoint blip colour
    Locales    = { en = 'English' },                         -- Languages players can pick (file in locales/)

    -- Map behind track previews. Players pick a style in Settings.
    -- Your own image: put it in web/maps/, then get its bounds with install/map-calibrator.html
    -- Your server's streamed map (minimap_sea_*.ytd): uncomment the 'server' entry below, no image or calibration needed
    Maps = {
        Default = 'road',
        List = {
            road      = { label = 'Road',      image = 'maps/road.webp',      bounds = { minX = -3621.43, maxX = 4175.99, minY = -3803.99, maxY = 7758.54 } },
            satellite = { label = 'Satellite', image = 'maps/satellite.webp', bounds = { minX = -3621.43, maxX = 4175.99, minY = -3803.99, maxY = 7758.54 } },
            dark      = { label = 'Dark',      image = 'maps/dark.webp',      bounds = { minX = -3621.43, maxX = 4175.99, minY = -3803.99, maxY = 7758.54 } },
            -- mymap  = { label = 'My Server', image = 'maps/mymap.png',     bounds = { minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0 } },
            -- server = {
            --     label  = 'Server Map',
            --     stream = { dict = 'minimap_sea_%d_%d', texture = 'minimap_sea_%d_%d', rows = 3, cols = 2 }, -- %d_%d = row_col
            --     bounds = { minX = -4140.0, maxX = 4860.0, minY = -5100.0, maxY = 8400.0 },               -- GTA's minimap tile grid, do not change
            -- },
        },
    },
    DefaultLocale = 'en',
}

-- ======================================================================
--  ___ _  ___   __
-- | __| \| \ \ / /
-- | _|| .' |\ V /
-- |___|_|\_| \_/
-- ======================================================================
Config.Env = {
    Framework = 'auto',                                      -- auto | esx | qbcore | qbox | standalone
    Inventory = 'auto',                                      -- auto | ox_inventory | qb-inventory | ps-inventory | lj-inventory | qs-inventory
                                                             -- | codem-inventory | core_inventory | origen_inventory | tgiann-inventory | mf-inventory | tprp_inventory | none
    Accounts  = { wager = 'money', payout = 'bank' },        -- Accounts used for wagers and payouts ('money' = cash)
    ImportFromBablo = true,                                  -- One-time import of profiles, crews, tracks and history from bablo-racing tables
}

-- ======================================================================
--  _    ___   ___ ___
-- | |  / _ \ / __/ __|
-- | |_| (_) | (_ \__ \
-- |____\___/ \___|___/
-- ======================================================================
Config.Logs = {
    Webhook = '',                                            -- Discord webhook (empty = off)
    Results = true,                                          -- Race results
    Wagers  = true,                                          -- Wagers taken / paid
    Tracks  = true,                                          -- Tracks created / deleted
    Crews   = true,                                          -- Crews created / deleted
    Bets    = true,                                          -- Bets placed / paid
    PinkSlips = true,                                        -- Cars that changed owner
    Seasons = true,                                          -- Season results
    AntiCheat = true,                                        -- Modded / swapped vehicles
}

-- ======================================================================
-- __   _____ _  _ ___ ___ _    ___ ___
-- \ \ / / __| || |_ _/ __| |  | __/ __|
--  \ V /| _|| __ || | (__| |__| _|\__ \
--   \_/ |___|_||_|___\___|____|___|___/
-- ======================================================================
Config.Vehicles = {}
Config.Vehicles.Classes = { 'D', 'C', 'B', 'A', 'S', 'S+', 'M-', 'M', 'M+' } -- Lobby classes ('Open' is always available)

-- Return the class of a vehicle model. Return nil to hide the vehicle from the picker, 'All' to allow it in every class,
-- 'auto' to work the class out from the car's handling (see AutoClass below).
-- Runs on client and server. Example: return exports['my-dealer']:GetClassByHash(hash) or 'auto'
Config.Vehicles.GetClass = function(hash)
    return 'auto'
end

-- Automatic class from the handling file (top speed, acceleration, braking, traction).
-- Use /racingclass in a car to see its performance index, then tune the thresholds.
Config.Vehicles.AutoClass = {
    Cars  = { { class = 'D', min = 0 }, { class = 'C', min = 640 }, { class = 'B', min = 720 }, { class = 'A', min = 780 }, { class = 'S', min = 840 }, { class = 'S+', min = 900 } },
    Bikes = { { class = 'M-', min = 0 }, { class = 'M', min = 760 }, { class = 'M+', min = 860 } },
    Hidden  = { 13, 14, 15, 16, 21 },                        -- GTA vehicle classes never offered: cycles, boats, helicopters, planes, trains
    Command = 'racingclass',                                 -- Prints the performance index + class of your car (false = off)
}

-- Return true to block a vehicle from racing
Config.Vehicles.IsBlacklisted = function(hash)
    return false
end

-- ======================================================================
--  ___ _____      ___   ___ ___  ___
-- | _ \ __\ \    / /_\ | _ \   \/ __|
-- |   / _| \ \/\/ / _ \|   / |) \__ \
-- |_|_\___| \_/\_/_/ \_\_|_\___/|___/
-- ======================================================================
Config.Rewards = {
    Winners = 3,                                             -- Top X that share the wager pot and count as "topX"
    Xp = { participant = 2, topX = 5, winner = 10 },         -- XP per result (nil to disable, needs GiveXp in bridge/server.lua)
    DefaultCurrency = 'money',                               -- Currency for ranked payouts
    Currencies = {
        money  = { label = 'Money' },
        crypto = { label = 'Crypto' },
    },
}

-- Ranked payout per finisher. status: 'winner' | 'topX' | 'participant'
Config.Rewards.RacePayout = function(source, status)
    if status == 'winner' then return 100 end
    if status == 'topX' then return 50 end
    return 5
end

-- Ranked item rewards per finisher. Return a list of { item, amount, metadata } or nil
Config.Rewards.Loottable = function(source, status)
    if status == 'winner' or status == 'topX' then
        return { { item = 'repairkit', amount = 1, metadata = {} } }
    end
    return nil
end

-- ======================================================================
--  ___ _    ___
-- | __| |  / _ \
-- | _|| |_| (_) |
-- |___|____\___/
-- ======================================================================
Config.ELO = {
    K = 32,                                                  -- ELO K-factor (higher = bigger swings)
    Ranks = {
        { name = 'Rookie',   min = 0,    max = 999,   rewards = nil },
        { name = 'Amateur',  min = 1000, max = 1999,  rewards = { { type = 'money', amount = 250 } } },
        { name = 'Trainee',  min = 2000, max = 2999,  rewards = { { type = 'money', amount = 500 } } },
        { name = 'Novice',   min = 3000, max = 3999,  rewards = { { type = 'money', amount = 750 } } },
        { name = 'Sprinter', min = 4000, max = 4999,  rewards = { { type = 'money', amount = 1000 } } },
        { name = 'Rider',    min = 5000, max = 6499,  rewards = { { type = 'money', amount = 1500 } } },
        { name = 'Outlaw',   min = 6500, max = 7999,  rewards = { { type = 'money', amount = 2000 } } },
        { name = 'Titan',    min = 8000, max = 8999,  rewards = { { type = 'item', item = 'furniture', amount = 1, metadata = { model = 'ch_prop_ch_trophy_racer_01a' } } } },
        { name = 'Apex',     min = 9000, max = 10000, rewards = {
            { type = 'item', item = 'furniture', amount = 1, metadata = { model = 'm25_2_prop_m52_trpy_100races' } },
            { type = 'money', amount = 1500 },
        } },
    },
    -- Ranked lobbies: minimum ELO to create / join a lobby of this class
    ClassRestrictions = {
        ['D'] = 0, ['C'] = 2000, ['B'] = 3000, ['A'] = 4000, ['S'] = 5000, ['S+'] = 6000,
        ['M-'] = 1000, ['M'] = 3000, ['M+'] = 5000,
    },
}

-- Achievements shown on racer profiles. stat: races | wins | podiums | streak | distance (metres) | time (seconds) | ranked
Config.Achievements = {
    { id = 'first_victory', label = 'First Victory',  desc = 'Win your first race',            icon = 'trophy',          stat = 'wins',     value = 1 },
    { id = 'regular',       label = 'Regular',        desc = 'Finish 25 races',                icon = 'flag-checkered',  stat = 'races',    value = 25 },
    { id = 'veteran',       label = 'Veteran',        desc = 'Finish 100 races',               icon = 'medal',           stat = 'races',    value = 100 },
    { id = 'podium_master', label = 'Podium Master',  desc = 'Finish on the podium 25 times',  icon = 'ranking-star',    stat = 'podiums',  value = 25 },
    { id = 'speed_demon',   label = 'Speed Demon',    desc = 'Win 25 races',                   icon = 'bolt',            stat = 'wins',     value = 25 },
    { id = 'unbeatable',    label = 'Unbeatable',     desc = 'Win 5 races in a row',           icon = 'crown',           stat = 'streak',   value = 5 },
    { id = 'distance',      label = 'Distance Runner', desc = 'Race 500 km',                   icon = 'road',            stat = 'distance', value = 500000 },
    { id = 'marathon',      label = 'Marathon',       desc = 'Spend 10 hours racing',          icon = 'stopwatch',       stat = 'time',     value = 36000 },
}

Config.Leaderboard = {
    Size = 10,                                               -- Rows per leaderboard
    MinRacesForWinRate = 5,                                  -- Races needed to appear on the win rate board
    CacheSeconds = 60,                                       -- Leaderboard cache
}

-- ======================================================================
--  _  _______   _____
-- | |/ / __\ \ / / __|
-- | ' <| _| \ V /\__ \
-- |_|\_\___| |_| |___/
-- ======================================================================
Config.KEYS = {                                              -- Track builder controls
    ARROW_UP = 188, ARROW_DOWN = 187, ARROW_LEFT = 189, ARROW_RIGHT = 190,
    LEFT_SHIFT = 21, LEFT_CTRL = 60, ENTER = 191, F10 = 57, Z = 20, DELETE = 178, ESC = 200,
}
