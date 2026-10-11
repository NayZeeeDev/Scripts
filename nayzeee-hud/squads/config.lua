--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ███████╗
    ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗██╔════╝
    ███████╗██║   ██║██║   ██║███████║██║  ██║███████╗
    ╚════██║██║▄▄ ██║██║   ██║██╔══██║██║  ██║╚════██║
    ███████║╚██████╔╝╚██████╔╝██║  ██║██████╔╝███████║
    ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝

    Squads · v2.2.0
    Discord: discord.gg/nayzeeedev
]]

SquadsConfig = {}


--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

-- The squads module ships inside nayzeee-hud. Set false to run the HUD without squads.
-- If you still have the standalone nayzeee-squads resource, remove it from server.cfg.
SquadsConfig.Enabled   = true

SquadsConfig.Version   = '2.2.0'
SquadsConfig.Framework = 'auto'           -- 'auto' | 'esx' | 'qbcore' | 'qbx' | 'standalone'
SquadsConfig.Debug     = false            -- print extra detail to the server console

SquadsConfig.Command        = 'squads'      -- opens the menu
SquadsConfig.OpenKey        = ''            -- optional keybind (e.g. 'F6'), '' = none
SquadsConfig.MaxMembers     = 8             -- hard ceiling for squad size
SquadsConfig.MinMembers     = 2
SquadsConfig.UseCharacterName = true        -- framework character name instead of FiveM name

-- ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗     ████████╗██╗   ██╗██████╗ ███████╗███████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗    ╚══██╔══╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔════╝
-- ███████╗██║   ██║██║   ██║███████║██║  ██║       ██║    ╚████╔╝ ██████╔╝█████╗  ███████╗
-- ╚════██║██║▄▄ ██║██║   ██║██╔══██║██║  ██║       ██║     ╚██╔╝  ██╔═══╝ ██╔══╝  ╚════██║
-- ███████║╚██████╔╝╚██████╔╝██║  ██║██████╔╝       ██║      ██║   ██║     ███████╗███████║
-- ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝        ╚═╝      ╚═╝   ╚═╝     ╚══════╝╚══════╝

-- Players pick one when they create a squad.
--   temporary : a quick group for one session. Never saved, never rated, no ELO or K/D/A.
--               Gone when the last member leaves or the server restarts.
--   permanent : a real crew. Saved to the database, keeps its roster, ranks, ELO and K/D/A.
SquadsConfig.SquadTypes = {
    AllowTemporary = true,
    AllowPermanent = true,     -- forced off when SquadsConfig.Persistence is false
    Default        = 'permanent',
    TempMaxHours   = 0,        -- auto-close a temp squad after this many hours (0 = never)
}

-- ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ███████╗███████╗
-- ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
-- ██║  ██║███████║   ██║   ███████║██████╔╝███████║███████╗█████╗
-- ██║  ██║██╔══██║   ██║   ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝
-- ██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝██║  ██║███████║███████╗
-- ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

-- true  : permanent squads live in the database and survive restarts (needs oxmysql + the SQL file)
-- false : every squad is temporary, and no stats are tracked
SquadsConfig.Persistence     = true
SquadsConfig.DisbandOnEmpty  = false        -- true: delete a squad once the last member leaves
SquadsConfig.InactiveDays    = 30           -- delete stored squads untouched for this long (0 = never)
SquadsConfig.MaxSquadsPerPlayer = 1         -- stored squads a player can own

-- ██╗   ██╗ █████╗ ██╗     ██╗██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██║   ██║██╔══██╗██║     ██║██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║   ██║███████║██║     ██║██║  ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ╚██╗ ██╔╝██╔══██║██║     ██║██║  ██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
--  ╚████╔╝ ██║  ██║███████╗██║██████╔╝██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
--   ╚═══╝  ╚═╝  ╚═╝╚══════╝╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

SquadsConfig.NameMin = 3
SquadsConfig.NameMax = 24
SquadsConfig.TagMin  = 2
SquadsConfig.TagMax  = 4
SquadsConfig.BlockedWords = { 'admin', 'staff', 'nigger', 'faggot' }
SquadsConfig.ImageHosts = { 'i.imgur.com', 'cdn.discordapp.com', 'media.discordapp.net', 'r2.fivemanage.com' } -- {} = allow any https image
SquadsConfig.ChatMaxLength   = 180
SquadsConfig.ChatHistory     = 60
SquadsConfig.ChatCooldownMs  = 600
SquadsConfig.InviteExpireSec = 60

--  █████╗ ███████╗███████╗██╗██╗     ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██║██║     ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
-- ███████║█████╗  █████╗  ██║██║     ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
-- ██╔══██║██╔══╝  ██╔══╝  ██║██║     ██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║██║     ██║     ██║███████╗██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝╚══════╝╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Squads can ally with each other. Allies see each other's blips and nametags, optionally can't
-- damage each other, and never trade ELO. Set MaxPerSquad to 0 to turn the whole system off.
SquadsConfig.Affiliations = {
    MaxPerSquad   = 2,      -- how many allies one squad may hold
    RequireBoth   = true,   -- both sides must accept; false makes it one-sided and instant
    Friendly      = true,   -- allies can't damage each other
    ShareBlips    = true,   -- see allied squad members on the map
    ShareTags     = true,   -- see allied nametags
    ShareChat     = false,  -- allies share the squad chat
    IgnoreInElo   = true,   -- kills between allies never score a fight
    RequestExpiry = 120,    -- seconds an ally request stays open
    MinRankPerm   = 'edit', -- rank permission needed to offer or accept an alliance
}

-- ███████╗███████╗ █████╗ ████████╗██╗   ██╗██████╗ ███████╗███████╗
-- ██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║   ██║██╔══██╗██╔════╝██╔════╝
-- █████╗  █████╗  ███████║   ██║   ██║   ██║██████╔╝█████╗  ███████╗
-- ██╔══╝  ██╔══╝  ██╔══██║   ██║   ██║   ██║██╔══██╗██╔══╝  ╚════██║
-- ██║     ███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║███████╗███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

SquadsConfig.Features = {
    Relations   = true,   -- squad members can't damage each other
    Blips       = true,
    Tags        = true,   -- nametags
    Hud         = true,
    Pings       = true,
    Waypoint    = true,
    Combat      = true,   -- kills / deaths / assists + ELO (needs Persistence)
    Revive      = true,
    ReadyCheck  = true,
    Rally       = true,
    DownedAlert = true,   -- auto-ping a squadmate's position when they go down
    TargetInvite = true,  -- invite with ox_target by looking at a player
    Leaderboard = true,
    Affiliations = true,  -- allied squads
    SquadBlips  = true,   -- each squad picks its own blip colour and sprite
    AutoRadio   = true,   -- join the squad radio channel automatically (needs pma-voice)
}

SquadsConfig.VitalsIntervalMs = 750     -- server HUD sync rate (only sends changes)
SquadsConfig.CoordsEveryTicks = 2       -- include coords for off-scope blips every N vitals ticks

-- Shot feed for the team HUD: each player's client times the shots they fire and sends them in small batches,
-- so squadmates' cards flash in step with the gunfire (about 10 tiny events a second per player while firing).
SquadsConfig.TeamHudShots = {
    Enabled    = true,
    BatchMs    = 100,   -- batch window; the HUD keeps a matching jitter buffer so the rhythm stays exact
    BurstGapMs = 700,   -- a pause longer than this starts a new burst
}

-- ███╗   ██╗██╗ ██████╗██╗  ██╗███╗   ██╗ █████╗ ███╗   ███╗███████╗███████╗
-- ████╗  ██║██║██╔════╝██║ ██╔╝████╗  ██║██╔══██╗████╗ ████║██╔════╝██╔════╝
-- ██╔██╗ ██║██║██║     █████╔╝ ██╔██╗ ██║███████║██╔████╔██║█████╗  ███████╗
-- ██║╚██╗██║██║██║     ██╔═██╗ ██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝  ╚════██║
-- ██║ ╚████║██║╚██████╗██║  ██╗██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗███████║
-- ╚═╝  ╚═══╝╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝

-- Members can pick a name they go by inside the squad. It replaces their character name on the
-- HUD, nametags, blips, chat and the roster. Ranks with the 'kick' permission can reset one.
SquadsConfig.Nicknames = {
    Enabled          = true,
    MinLength        = 2,
    MaxLength        = 20,
    CooldownSec      = 30,       -- how often one player can change it
    AllowInTemporary = true,     -- temp squads can use nicknames too
    Command          = 'squadnick', -- /squadnick <name>  (blank clears it), '' to disable
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ███████╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ╚════██║
-- ██║  ██║██║  ██║██║ ╚████║██║  ██╗███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝

-- The LAST rank is the owner and always holds every permission.
-- Squads can rename these and change permissions in-game; this is just the starting set.
SquadsConfig.MaxRanks = 6
SquadsConfig.DefaultRanks = {
    { name = 'Recruit', icon = 'fa-user',          perms = {} },
    { name = 'Member',  icon = 'fa-user-check',    perms = { invite = true, ready = true } },
    { name = 'Officer', icon = 'fa-user-shield',   perms = { invite = true, kick = true, ready = true, rally = true } },
    { name = 'Leader',  icon = 'fa-crown',         perms = { invite = true, kick = true, promote = true, edit = true, ranks = true, ready = true, rally = true, disband = true } },
}
-- Permissions a rank can hold, in the order the UI shows them.
SquadsConfig.RankPermOrder = {
    { key = 'invite',  label = 'Invite players' },
    { key = 'kick',    label = 'Remove members' },
    { key = 'promote', label = 'Change member ranks' },
    { key = 'edit',    label = 'Edit squad details' },
    { key = 'ranks',   label = 'Manage ranks' },
    { key = 'rally',   label = 'Set rally points' },
    { key = 'ready',   label = 'Start ready checks' },
    { key = 'disband', label = 'Disband the squad' },
}

SquadsConfig.RankIcons = { 'fa-user', 'fa-user-check', 'fa-user-shield', 'fa-user-tie', 'fa-crown', 'fa-star',
                     'fa-shield-halved', 'fa-gun', 'fa-kit-medical', 'fa-car-side', 'fa-headset', 'fa-skull' }

-- ███████╗██╗      ██████╗
-- ██╔════╝██║     ██╔═══██╗
-- █████╗  ██║     ██║   ██║
-- ██╔══╝  ██║     ██║   ██║
-- ███████╗███████╗╚██████╔╝
-- ╚══════╝╚══════╝ ╚═════╝

SquadsConfig.Elo = {
    Start             = 1000,
    K                 = 32,    -- how hard a result swings the rating
    MinK              = 12,    -- K floor for high-rated squads
    MarginBonus       = true,  -- a bigger kill margin moves the rating further
    EngagementTimeout = 120,   -- seconds without a kill before a fight is scored
    MinKillsToScore   = 2,     -- total kills needed before a fight counts
    AssistWindow      = 10,    -- seconds a damage hit still counts as an assist
    CountSelfDamage   = false, -- suicides and squadmate kills never count
    Floor             = 100,   -- rating can't fall below this
    Tiers = {   -- shown as a badge; lowest first
        { name = 'Bronze',   min = 0,    color = '#b4713d' },
        { name = 'Silver',   min = 900,  color = '#9aa4ab' },
        { name = 'Gold',     min = 1100, color = '#e5a50a' },
        { name = 'Platinum', min = 1300, color = '#4fd1ff' },
        { name = 'Diamond',  min = 1500, color = '#a078ff' },
        { name = 'Elite',    min = 1750, color = '#08afa2' },
    },
}

-- ██████╗ ███████╗██╗   ██╗██╗██╗   ██╗███████╗
-- ██╔══██╗██╔════╝██║   ██║██║██║   ██║██╔════╝
-- ██████╔╝█████╗  ██║   ██║██║██║   ██║█████╗
-- ██╔══██╗██╔══╝  ╚██╗ ██╔╝██║╚██╗ ██╔╝██╔══╝
-- ██║  ██║███████╗ ╚████╔╝ ██║ ╚████╔╝ ███████╗
-- ╚═╝  ╚═╝╚══════╝  ╚═══╝  ╚═╝  ╚═══╝  ╚══════╝

SquadsConfig.Revive = {
    RequireItem  = true,      -- false: squadmates can revive bare-handed
    Distance     = 2.0,
    Key          = 'G',       -- revive the nearest downed squadmate
    Hold         = true,      -- true: keep the key held down; letting go stops the revive
    -- Seconds until a downed player bleeds out, shown as a countdown on their team HUD card.
    -- Match your ambulance job (qb-ambulancejob laststand is 300 by default). 0 = count up how long they've been down.
    BleedOut     = 300,
    CancelOnMove = true,
    Cooldown     = 15,        -- seconds between revives per player
    Animation    = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
    -- Each item is offered only when the player is carrying it.
    Items = {
        { item = 'medikit',  label = 'Medkit',         icon = 'fa-suitcase-medical', time = 8000,  health = 100, remove = true },
        { item = 'bandage',  label = 'Bandage',        icon = 'fa-bandage',          time = 12000, health = 45,  remove = true },
        { item = 'syringe',  label = 'Adrenaline shot', icon = 'fa-syringe',         time = 5000,  health = 60,  remove = true },
    },
    Bare = { label = 'CPR', icon = 'fa-hand-holding-medical', time = 18000, health = 20 },
}

-- ██████╗  █████╗ ██╗     ██╗  ██╗   ██╗
-- ██╔══██╗██╔══██╗██║     ██║  ╚██╗ ██╔╝
-- ██████╔╝███████║██║     ██║   ╚████╔╝
-- ██╔══██╗██╔══██║██║     ██║    ╚██╔╝
-- ██║  ██║██║  ██║███████╗███████╗██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝

SquadsConfig.ReadyCheck = { Duration = 20 }
SquadsConfig.Rally      = { Blip = 146, BlipColor = 2, Route = true }

-- ███╗   ██╗ █████╗ ███╗   ███╗███████╗████████╗ █████╗  ██████╗ ███████╗
-- ████╗  ██║██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔════╝
-- ██╔██╗ ██║███████║██╔████╔██║█████╗     ██║   ███████║██║  ███╗███████╗
-- ██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║   ██║╚════██║
-- ██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ██║  ██║╚██████╔╝███████║
-- ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝

SquadsConfig.TagDistance       = 60.0
SquadsConfig.TagBoost          = true
SquadsConfig.TagBoostKey       = 'MOUSE_EXTRABTN1'
SquadsConfig.TagBoostMapper    = 'MOUSE_BUTTON'
SquadsConfig.TagBoostMultiplier = 2.5

-- What shows above a squadmate's head. Players can switch each of these off for themselves.
SquadsConfig.Nametag = {
    Name   = true,    -- the player's name
    Tag    = true,    -- the squad tag, shown as the crew tag beside the name
    Role   = true,    -- their rank name under the name
    Health = true,    -- health and armour bar
    Allies = true,    -- show allied squads' nametags too (needs Affiliations.ShareTags)
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

-- Which system squad notifications use.
--   'auto'    the HUD's own notifications (same as 'hud')
--   'builtin' the squad UI's own toast box (top right)
--   'none'    no squad notifications at all
--   'hud' | 'nayzeee' | 'ox_lib' | 'esx' | 'qb' | 'qbx' | 'okok' | 'mythic' | 'custom'
-- 'custom' runs the function at the bottom of bridge/client.lua — put your own call there.
-- The killfeed, fight results, ready checks and revive prompts always use the squad UI.
SquadsConfig.Notify = {
    System          = 'auto',
    Duration        = 4500,
    Position        = 'top-right',      -- ox_lib only
    NayzeeeResource = 'nayzeee-notify', -- folder name, if you renamed it
}

--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███████╗███████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║███████╗███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║╚════██║╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║███████║███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝

-- A heading strip across the top of the screen. Squadmates, allies, the rally point, your
-- waypoint and live pings show on it as markers with their distance.
-- The squads compass is replaced by the nayzeee-hud compass (config.lua / in-game /hud).
SquadsConfig.Compass = { Enabled = false }

-- ██████╗  █████╗ ██████╗ ██╗ ██████╗
-- ██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
-- ██████╔╝███████║██║  ██║██║██║   ██║
-- ██╔══██╗██╔══██║██║  ██║██║██║   ██║
-- ██║  ██║██║  ██║██████╔╝██║╚██████╔╝
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝

SquadsConfig.Voice = {
    Enabled      = true,
    ChannelBase  = 900,     -- squad radio channel = ChannelBase + squad id
    AutoJoin     = true,    -- put players on the squad channel the moment they join a squad
    PlayerCanOptOut = true, -- players can switch auto-join off in their settings
    RestoreOnLeave  = true, -- put them back on their previous channel when they leave
    TempChannelBase = 1900, -- temp squads use their own channel range so ids never collide
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝

-- Put your bot token in server.cfg (server-only, never sent to clients):
--   set nz_squads_bot_token "YOUR_BOT_TOKEN"
SquadsConfig.Discord = {
    Enabled            = true,
    GuildId            = '',
    PreferServerAvatar = true,
    CacheMinutes       = 60,
    Size               = 128,
}

-- ██████╗  ██████╗ ██╗     ███████╗███████╗
-- ██╔══██╗██╔═══██╗██║     ██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║     █████╗  ███████╗
-- ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║
-- ██║  ██║╚██████╔╝███████╗███████╗███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝

-- Gives players Discord roles for being in a squad, for their squad's tier and for their rank.
-- Uses the same bot token and GuildId as the avatars above. The bot needs Manage Roles, and its
-- own role must sit ABOVE every role listed here, or Discord refuses the change.
-- Run /squadroles after changing anything here to re-sync everyone online.
SquadsConfig.Roles = {
    Enabled       = false,
    InSquad       = '',       -- role for anyone currently in a squad
    Owner         = '',       -- role for squad owners
    RemoveOnLeave = true,     -- strip these roles once they no longer apply
    QueueDelay    = 450,      -- ms between Discord calls; raise it if you get rate limited

    -- Tier name (from SquadsConfig.Elo.Tiers) -> role id
    Tiers = {
        Bronze   = '',
        Silver   = '',
        Gold     = '',
        Platinum = '',
        Diamond  = '',
        Elite    = '',
    },

    -- Rank name -> role id. These are the DEFAULT rank names; squads that rename their ranks
    -- stop matching, so only use this when your squads keep the default names.
    Ranks = {
        -- ['Officer'] = '000000000000000000',
        -- ['Leader']  = '000000000000000000',
    },
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

SquadsConfig.Logs = {
    Enabled = false,
    Webhook = '',       -- https://discord.com/api/webhooks/...
    Name    = 'Squads',
    Color   = 561570,   -- teal
    Events  = { create = true, disband = true, join = true, leave = true, kick = true, promote = true, match = true, ally = true, admin = true },
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

SquadsConfig.Admin = {
    Command = 'squadadmin',
    Ace     = 'nz_squads.admin',   -- add_ace group.admin nz_squads.admin allow
}

-- ██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
-- ██████╔╝██║██╔██╗ ██║██║  ███╗███████╗
-- ██╔═══╝ ██║██║╚██╗██║██║   ██║╚════██║
-- ██║     ██║██║ ╚████║╚██████╔╝███████║
-- ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

SquadsConfig.Ping = {
    Key          = 'MOUSE_MIDDLE',
    Mapper       = 'MOUSE_BUTTON',
    HoldMs       = 280,
    CooldownMs   = 1000,
    TTL          = 15,
    FollowTTL    = 6,
    WaypointTTL  = 60,
    MaxDistance  = 400.0,
    Sound        = { name = 'Waypoint_Set', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    Types = {
        go      = { label = 'Go here',  icon = 'fa-location-arrow', color = { 8, 175, 162 },  blip = 1,   blipColor = 2 },
        enemy   = { label = 'Enemy',    icon = 'fa-crosshairs',     color = { 229, 72, 77 },  blip = 303, blipColor = 1 },
        danger  = { label = 'Danger',   icon = 'fa-triangle-exclamation', color = { 229, 165, 10 }, blip = 761, blipColor = 5 },
        loot    = { label = 'Loot',     icon = 'fa-box-open',       color = { 255, 255, 255 }, blip = 478, blipColor = 0 },
        defend  = { label = 'Defend',   icon = 'fa-shield-halved',  color = { 88, 166, 255 }, blip = 487, blipColor = 3 },
        vehicle = { label = 'Vehicle',  icon = 'fa-car-side',       color = { 160, 120, 255 }, blip = 225, blipColor = 27 },
        waypoint= { label = 'Waypoint', icon = 'fa-route',          color = { 8, 175, 162 },  blip = 8,   blipColor = 2 },
        downed  = { label = 'Member down', icon = 'fa-heart-crack', color = { 229, 72, 77 },  blip = 280, blipColor = 1 },
        rally   = { label = 'Rally',    icon = 'fa-flag',           color = { 8, 175, 162 },  blip = 146, blipColor = 2 },
    },
    Wheel = { 'go', 'enemy', 'danger', 'loot', 'defend', 'vehicle' },
}

-- ██████╗ ██╗     ██╗██████╗ ███████╗
-- ██╔══██╗██║     ██║██╔══██╗██╔════╝
-- ██████╔╝██║     ██║██████╔╝███████╗
-- ██╔══██╗██║     ██║██╔═══╝ ╚════██║
-- ██████╔╝███████╗██║██║     ███████║
-- ╚═════╝ ╚══════╝╚═╝╚═╝     ╚══════╝

-- Each squad picks its own colour and sprite when it's created. Players still choose whether to
-- show blips at all, and can override the colour for themselves.
SquadsConfig.SquadBlip = {
    DefaultColor  = 2,
    DefaultSprite = 1,
    Scale         = 0.85,
    AllySprite    = 1,     -- sprite used for allied squad members
    -- Sprites a squad may choose. Keep the list short so the picker stays readable.
    Sprites = {
        { id = 1,   label = 'Dot',     icon = 'fa-circle' },
        { id = 480, label = 'Skull',   icon = 'fa-skull' },
        { id = 303, label = 'Target',  icon = 'fa-crosshairs' },
        { id = 487, label = 'Shield',  icon = 'fa-shield-halved' },
        { id = 491, label = 'Star',    icon = 'fa-star' },
        { id = 310, label = 'Crown',   icon = 'fa-crown' },
        { id = 437, label = 'Flame',   icon = 'fa-fire' },
        { id = 442, label = 'Diamond', icon = 'fa-gem' },
    },
}

-- ███████╗███████╗████████╗████████╗██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗█████╗     ██║      ██║   ██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║██╔══╝     ██║      ██║   ██║██║╚██╗██║██║   ██║╚════██║
-- ███████║███████╗   ██║      ██║   ██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

-- What every player starts with. Each player can change these in the Settings tab;
-- their choices are saved on their own client and kept between sessions.
SquadsConfig.DefaultSettings = {
    -- team HUD
    hud             = true,
    hudMinimized    = false,
    hudTalking      = true,
    hudMax          = 0,            -- 0 = show all
    hudHealth       = '#ffffff',
    hudArmor        = '#58a6ff',
    hudPos          = false,
    hudKda          = false,        -- show K/D on cards
    hudAvatars      = true,         -- profile pictures on cards
    hudRank         = false,        -- rank name on cards
    hudArmorBar     = true,         -- show the armour bar at all
    hudAccent       = 'squad',      -- left edge: 'squad' | 'teal' | 'health' | 'none'
    hudStyle        = 'cards',      -- cards | slim | frost | loadout | tactical | arena | rings | heads | tiles | minimal
    hudWeapon       = true,         -- picture of the gun each squadmate is holding
    hudShots        = true,         -- cards flash in time with every shot a squadmate fires
    hudAmmo         = true,         -- clip / reserve under the gun, RELOAD and EMPTY warnings
    hudVehicle      = true,         -- what they're driving or riding in (car, truck, bike, boat, plane, heli)
    hudHits         = true,         -- cards jolt red when that squadmate takes damage
    hudScale        = 100,          -- 70-130%
    hudOpacity      = 86,           -- card background opacity
    hudShowSelf     = true,         -- your own card at the top (keeps the HUD visible when you're alone)
    animatedAvatars = true,

    -- nametags
    tags            = true,
    tagColor        = 18,
    tagName         = true,
    tagSquadTag     = true,
    tagRole         = true,
    tagHealth       = true,
    tagAllies       = true,

    -- blips
    blips           = true,
    blipUseSquad    = true,         -- use the squad's own colour instead of your own
    blipColor       = 2,
    blipAllies      = true,

    -- alerts
    chatNotify      = true,
    chatSound       = true,
    pingNotify      = true,
    pingSound       = true,
    reviveAlerts    = true,
    killfeed        = true,
    matchBanner     = true,

    -- voice
    radio           = true,         -- auto-join the squad radio channel

    -- compass
    compass         = true,
    compassStreet   = true,
    compassMarkers  = true,
}

--  ██████╗ ██████╗ ██╗      ██████╗ ██╗   ██╗██████╗ ███████╗
-- ██╔════╝██╔═══██╗██║     ██╔═══██╗██║   ██║██╔══██╗██╔════╝
-- ██║     ██║   ██║██║     ██║   ██║██║   ██║██████╔╝███████╗
-- ██║     ██║   ██║██║     ██║   ██║██║   ██║██╔══██╗╚════██║
-- ╚██████╗╚██████╔╝███████╗╚██████╔╝╚██████╔╝██║  ██║███████║
--  ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

-- Swatches offered in the Settings tab: { hex shown in the UI, GTA colour id }
SquadsConfig.BlipColors = {
    { '#08afa2', 2 }, { '#e5484d', 1 }, { '#58a6ff', 3 }, { '#e5a50a', 5 }, { '#a078ff', 27 },
    { '#ff7ad9', 8 }, { '#ffffff', 0 }, { '#8bd35a', 25 }, { '#ff9a3c', 17 }, { '#4fd1ff', 38 },
}
SquadsConfig.TagColors = {
    { '#72cc72', 18 }, { '#e5484d', 6 }, { '#58a6ff', 9 }, { '#e5a50a', 12 }, { '#a078ff', 21 },
    { '#ff7ad9', 26 }, { '#ffffff', 0 }, { '#08afa2', 28 }, { '#ff9a3c', 15 }, { '#4fd1ff', 116 },
}

-- ███████╗████████╗██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗   ██║   ██████╔╝██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║   ██║   ██╔══██╗██║██║╚██╗██║██║   ██║╚════██║
-- ███████║   ██║   ██║  ██║██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

-- Every message the squad sends. Keep the %s placeholders where they are.
SquadsConfig.Strings = {
    nick_set      = '%s now goes by %s',
    nick_cleared  = '%s cleared their nickname',
    ally_request  = '%s wants to ally with your squad',
    ally_added    = 'Allied with %s',
    ally_removed  = 'No longer allied with %s',
    ally_declined = '%s declined your alliance',
    ally_full     = 'Your squad already has the most allies allowed',
    joined        = '%s joined the squad',
    left          = '%s left the squad',
    kicked        = '%s was removed from the squad',
    new_leader    = '%s now owns the squad',
    rank_set      = '%s is now %s',
    closed        = 'Your squad was closed',
    you_kicked    = 'You were removed from the squad',
    invite_sent   = 'Invite sent to %s',
    no_waypoint   = 'Set a waypoint on your map first',
    cooldown      = 'Slow down a moment',
    no_perm       = 'Your rank cannot do that',
    revived       = '%s revived %s',
    rally_set     = '%s set a rally point',
    rally_clear   = 'Rally point cleared',
}

-- The old standalone nayzeee-squads resource running next to this one would fight over every callback and event.
-- If it's started, the built-in squads module stays off and the console says so; remove `ensure nayzeee-squads`.
do
    local me = GetCurrentResourceName()
    if SquadsConfig.Enabled and me ~= 'nayzeee-squads' then
        local state = GetResourceState('nayzeee-squads')
        local running = state == 'started' or state == 'starting'
        if running and IsDuplicityVersion() then
            -- `provide 'nayzeee-squads'` can make the name resolve to us; only a different folder is a real clash
            running = GetResourcePath('nayzeee-squads') ~= GetResourcePath(me)
            GlobalState.nhud_squadsClash = running
        elseif running then
            running = GlobalState.nhud_squadsClash == true
        end
        if running then
            SquadsConfig.Enabled = false
            print('^1[nayzeee-hud]^7 The old ^3nayzeee-squads^7 resource is running. Squads are built into nayzeee-hud now, so the'
                .. ' built-in squads are turned off. Remove ^3ensure nayzeee-squads^7 from server.cfg (and delete that folder), then restart.')
        end
    end
end
