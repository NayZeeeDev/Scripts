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

    Squads · v3.0.0
    Discord: discord.gg/nayzeeedev
]]

Config = {}


--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Version   = '3.0.0'
Config.Framework = 'auto'           -- 'auto' | 'esx' | 'qbcore' | 'qbx' | 'standalone'
Config.Debug     = false            -- extra detail in the server console

Config.Command          = 'squads'  -- opens the menu
Config.OpenKey          = ''        -- optional keybind (e.g. 'F6'), '' = none
Config.MaxMembers       = 8         -- hard ceiling for squad size
Config.MinMembers       = 2
Config.UseCharacterName = true      -- framework character name instead of the FiveM name

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

-- Every message goes through ox_lib's lib.notify. There are no built-in toasts.
Config.Notify = {
    Title    = 'Squads',
    Position = 'top-right',   -- any lib.notify position
    Duration = 4500,
    Icon     = 'users',       -- Font Awesome name shown on every squad notification
    -- Icons used for specific events; leave one out to fall back to Icon above.
    Icons = {
        invite = 'envelope', chat = 'message', ping = 'location-dot', downed = 'heart-crack',
        revive = 'kit-medical', ally = 'handshake', rally = 'flag', request = 'user-plus',
    },
}

-- ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗     ████████╗██╗   ██╗██████╗ ███████╗███████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗    ╚══██╔══╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔════╝
-- ███████╗██║   ██║██║   ██║███████║██║  ██║       ██║    ╚████╔╝ ██████╔╝█████╗  ███████╗
-- ╚════██║██║▄▄ ██║██║   ██║██╔══██║██║  ██║       ██║     ╚██╔╝  ██╔═══╝ ██╔══╝  ╚════██║
-- ███████║╚██████╔╝╚██████╔╝██║  ██║██████╔╝       ██║      ██║   ██║     ███████╗███████║
-- ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝        ╚═╝      ╚═╝   ╚═╝     ╚══════╝╚══════╝

--   temporary : a quick group for one session. Never saved, never rated, no ELO or K/D/A.
--   permanent : a real crew. Saved to the database, keeps its roster, ranks, ELO and K/D/A.
Config.SquadTypes = {
    AllowTemporary = true,
    AllowPermanent = true,     -- forced off when Config.Persistence is false
    Default        = 'permanent',
    TempMaxHours   = 0,        -- auto-close a temp squad after this many hours (0 = never)
}

-- ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ███████╗███████╗
-- ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
-- ██║  ██║███████║   ██║   ███████║██████╔╝███████║███████╗█████╗
-- ██║  ██║██╔══██║   ██║   ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝
-- ██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝██║  ██║███████║███████╗
-- ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

Config.Persistence        = true   -- false: every squad is temporary and no stats are kept
Config.DisbandOnEmpty     = false  -- true: delete a saved squad once the last member leaves for good
Config.InactiveDays       = 30     -- delete saved squads untouched for this long (0 = never)
Config.MaxSquadsPerPlayer = 1      -- saved squads a player can own
Config.LogRetentionDays   = 14     -- activity log entries older than this are pruned on start

-- ██╗   ██╗ █████╗ ██╗     ██╗██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██║   ██║██╔══██╗██║     ██║██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║   ██║███████║██║     ██║██║  ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ╚██╗ ██╔╝██╔══██║██║     ██║██║  ██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
--  ╚████╔╝ ██║  ██║███████╗██║██████╔╝██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
--   ╚═══╝  ╚═╝  ╚═╝╚══════╝╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.NameMin        = 3
Config.NameMax        = 24
Config.TagMin         = 2
Config.TagMax         = 4
Config.DescriptionMax = 120    -- short blurb shown in the browser
Config.MotdMax        = 200    -- message of the day shown to members
Config.BlockedWords   = { 'admin', 'staff', 'nigger', 'faggot' }
Config.ImageHosts     = { 'i.imgur.com', 'cdn.discordapp.com', 'media.discordapp.net', 'r2.fivemanage.com' } -- {} = allow any https image
Config.ChatMaxLength  = 180
Config.ChatHistory    = 60
Config.ChatCooldownMs = 600
Config.InviteExpireSec = 60

-- ██████╗ ███████╗ ██████╗ ██╗   ██╗███████╗███████╗████████╗███████╗
-- ██╔══██╗██╔════╝██╔═══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝█████╗  ██║   ██║██║   ██║█████╗  ███████╗   ██║   ███████╗
-- ██╔══██╗██╔══╝  ██║▄▄ ██║██║   ██║██╔══╝  ╚════██║   ██║   ╚════██║
-- ██║  ██║███████╗╚██████╔╝╚██████╔╝███████╗███████║   ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝   ╚══════╝

-- Players can ask to join a locked or invite-only squad. Anyone with the 'invite' permission
-- sees the request in the menu and can accept or decline it.
Config.JoinRequests = {
    Enabled    = true,
    ExpireSec  = 300,    -- how long a request stays open
    MessageMax = 80,     -- optional note the player can attach
    MaxOpen    = 3,      -- requests one player may have open at once
}

--  █████╗ ███████╗███████╗██╗██╗     ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██║██║     ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
-- ███████║█████╗  █████╗  ██║██║     ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
-- ██╔══██║██╔══╝  ██╔══╝  ██║██║     ██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║██║     ██║     ██║███████╗██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝╚══════╝╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Allied squads see each other, optionally can't hurt each other, and never trade ELO.
Config.Affiliations = {
    MaxPerSquad   = 2,      -- 0 turns the system off
    RequireBoth   = true,   -- both sides must accept
    Friendly      = true,   -- allies can't damage each other
    ShareBlips    = true,
    ShareTags     = true,
    IgnoreInElo   = true,   -- kills between allies never score a fight
    RequestExpiry = 120,    -- seconds an ally request stays open
    MinRankPerm   = 'edit', -- rank permission needed to manage alliances
}

-- ███████╗███████╗ █████╗ ████████╗██╗   ██╗██████╗ ███████╗███████╗
-- ██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║   ██║██╔══██╗██╔════╝██╔════╝
-- █████╗  █████╗  ███████║   ██║   ██║   ██║██████╔╝█████╗  ███████╗
-- ██╔══╝  ██╔══╝  ██╔══██║   ██║   ██║   ██║██╔══██╗██╔══╝  ╚════██║
-- ██║     ███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║███████╗███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

Config.Features = {
    Relations    = true,   -- squad members can't damage each other
    Blips        = true,
    Tags         = true,   -- nametags
    Hud          = true,
    Pings        = true,
    Waypoint     = true,
    Combat       = true,   -- kills / deaths / assists + ELO (needs Persistence)
    Revive       = true,
    ReadyCheck   = true,
    Rally        = true,
    DownedAlert  = true,   -- auto-ping a squadmate's position when they go down
    TargetInvite = true,   -- invite with ox_target by looking at a player
    Leaderboard  = true,
    Affiliations = true,
    SquadBlips   = true,   -- each squad picks its own blip colour and sprite
    AutoRadio    = true,   -- join the squad radio channel automatically (needs pma-voice)
    ActivityLog  = true,   -- joins, kicks, promotions and fights kept per squad
    Killfeed     = true,   -- on-screen feed for kills against other squads
    MatchBanner  = true,   -- on-screen result when a fight is scored
    Compass      = true,
}

Config.VitalsIntervalMs = 750     -- server HUD sync rate (only sends changes)
Config.CoordsEveryTicks = 2       -- include coords for off-scope blips every N vitals ticks

-- ███████╗███╗   ███╗ ██████╗ ████████╗███████╗███╗   ███╗ ██████╗ ███╗   ██╗███████╗
-- ██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝████╗ ████║██╔═══██╗████╗  ██║██╔════╝
-- █████╗  ██╔████╔██║██║   ██║   ██║   █████╗  ██╔████╔██║██║   ██║██╔██╗ ██║███████╗
-- ██╔══╝  ██║╚██╔╝██║██║   ██║   ██║   ██╔══╝  ██║╚██╔╝██║██║   ██║██║╚██╗██║╚════██║
-- ███████╗██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████║
-- ╚══════╝╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Quick keys for the on-screen prompts (invites and ready checks). Rebindable by players.
Config.Prompts = {
    AcceptKey  = 'Y',
    DeclineKey = 'U',
}

-- ███╗   ██╗██╗ ██████╗██╗  ██╗███╗   ██╗ █████╗ ███╗   ███╗███████╗███████╗
-- ████╗  ██║██║██╔════╝██║ ██╔╝████╗  ██║██╔══██╗████╗ ████║██╔════╝██╔════╝
-- ██╔██╗ ██║██║██║     █████╔╝ ██╔██╗ ██║███████║██╔████╔██║█████╗  ███████╗
-- ██║╚██╗██║██║██║     ██╔═██╗ ██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝  ╚════██║
-- ██║ ╚████║██║╚██████╗██║  ██╗██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗███████║
-- ╚═╝  ╚═══╝╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝

Config.Nicknames = {
    Enabled          = true,
    MinLength        = 2,
    MaxLength        = 20,
    CooldownSec      = 30,
    AllowInTemporary = true,
    Command          = 'squadnick', -- /squadnick <name> (blank clears it), '' to disable
}

--  ██████╗██╗  ██╗ █████╗ ████████╗
-- ██╔════╝██║  ██║██╔══██╗╚══██╔══╝
-- ██║     ███████║███████║   ██║
-- ██║     ██╔══██║██╔══██║   ██║
-- ╚██████╗██║  ██║██║  ██║   ██║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝

-- Chat commands so nobody has to open the menu mid-fight. Set any to '' to disable it.
Config.Commands = {
    Chat   = 'sq',        -- /sq <message>   squad chat
    Invite = 'sqinvite',  -- /sqinvite <id>  invite by server id
    Leave  = 'sqleave',   -- /sqleave        leave (stays on the roster of a saved squad)
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ███████╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ╚════██║
-- ██║  ██║██║  ██║██║ ╚████║██║  ██╗███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝

-- The LAST rank is the owner and always holds every permission.
Config.MaxRanks = 6
Config.DefaultRanks = {
    { name = 'Recruit', icon = 'fa-user',        perms = {} },
    { name = 'Member',  icon = 'fa-user-check',  perms = { invite = true, ready = true } },
    { name = 'Officer', icon = 'fa-user-shield', perms = { invite = true, kick = true, ready = true, rally = true, motd = true } },
    { name = 'Leader',  icon = 'fa-crown',       perms = { invite = true, kick = true, promote = true, edit = true, ranks = true, ready = true, rally = true, motd = true, disband = true } },
}
Config.RankPermOrder = {
    { key = 'invite',  label = 'Invite players and answer join requests' },
    { key = 'kick',    label = 'Remove members' },
    { key = 'promote', label = 'Change member ranks' },
    { key = 'edit',    label = 'Edit squad details' },
    { key = 'motd',    label = 'Set the message of the day' },
    { key = 'ranks',   label = 'Manage ranks' },
    { key = 'rally',   label = 'Set rally points' },
    { key = 'ready',   label = 'Start ready checks' },
    { key = 'disband', label = 'Disband the squad' },
}
Config.RankIcons = { 'fa-user', 'fa-user-check', 'fa-user-shield', 'fa-user-tie', 'fa-crown', 'fa-star',
                     'fa-shield-halved', 'fa-gun', 'fa-kit-medical', 'fa-car-side', 'fa-headset', 'fa-skull' }

-- ███████╗██╗      ██████╗
-- ██╔════╝██║     ██╔═══██╗
-- █████╗  ██║     ██║   ██║
-- ██╔══╝  ██║     ██║   ██║
-- ███████╗███████╗╚██████╔╝
-- ╚══════╝╚══════╝ ╚═════╝

Config.Elo = {
    Start             = 1000,
    K                 = 32,
    MinK              = 12,
    MarginBonus       = true,
    EngagementTimeout = 120,   -- seconds without a kill before a fight is scored
    MinKillsToScore   = 2,
    AssistWindow      = 10,
    Floor             = 100,
    StreakFrom        = 3,     -- kill streaks of this size show in the killfeed
    Tiers = {
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

Config.Revive = {
    RequireItem  = true,
    Distance     = 2.0,
    Key          = 'G',
    CancelOnMove = true,
    Cooldown     = 15,
    Animation    = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
    Items = {
        { item = 'medikit', label = 'Medkit',          icon = 'suitcase-medical', time = 8000,  health = 100, remove = true },
        { item = 'bandage', label = 'Bandage',         icon = 'bandage',          time = 12000, health = 45,  remove = true },
        { item = 'syringe', label = 'Adrenaline shot', icon = 'syringe',          time = 5000,  health = 60,  remove = true },
    },
    Bare = { label = 'CPR', icon = 'hand-holding-medical', time = 18000, health = 20 },
}

Config.ReadyCheck = { Duration = 20 }
Config.Rally      = { Blip = 146, BlipColor = 2, Route = true }

-- ███╗   ██╗ █████╗ ███╗   ███╗███████╗████████╗ █████╗  ██████╗ ███████╗
-- ████╗  ██║██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔════╝
-- ██╔██╗ ██║███████║██╔████╔██║█████╗     ██║   ███████║██║  ███╗███████╗
-- ██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║   ██║╚════██║
-- ██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ██║  ██║╚██████╔╝███████║
-- ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝

Config.TagDistance        = 60.0
Config.TagBoost           = true
Config.TagBoostKey        = 'MOUSE_EXTRABTN1'
Config.TagBoostMapper     = 'MOUSE_BUTTON'
Config.TagBoostMultiplier = 2.5

Config.Nametag = {
    Name   = true,
    Tag    = true,
    Role   = true,
    Health = true,
    Allies = true,
}

--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███████╗███████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║███████╗███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║╚════██║╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║███████║███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝

Config.Compass = {
    OnlyInSquad   = false,
    HideInVehicle = false,
    ShowStreet    = true,
    ShowSquad     = true,
    ShowAllies    = true,
    ShowRally     = true,
    ShowWaypoint  = true,
    ShowPings     = true,
    MarkerRange   = 1500.0,
    UpdateMs      = 40,
}

-- ██████╗  █████╗ ██████╗ ██╗ ██████╗
-- ██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
-- ██████╔╝███████║██║  ██║██║██║   ██║
-- ██╔══██╗██╔══██║██║  ██║██║██║   ██║
-- ██║  ██║██║  ██║██████╔╝██║╚██████╔╝
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝

Config.Voice = {
    Enabled         = true,
    ChannelBase     = 900,
    AutoJoin        = true,
    PlayerCanOptOut = true,
    RestoreOnLeave  = true,
    TempChannelBase = 1900,
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝

-- Bot token goes in server.cfg (server-only):  set nz_squads_bot_token "YOUR_BOT_TOKEN"
Config.Discord = {
    Enabled            = true,
    GuildId            = '',
    PreferServerAvatar = true,
    CacheMinutes       = 60,
    Size               = 128,
}

Config.Roles = {
    Enabled       = false,
    InSquad       = '',
    Owner         = '',
    RemoveOnLeave = true,
    QueueDelay    = 450,
    Tiers = { Bronze = '', Silver = '', Gold = '', Platinum = '', Diamond = '', Elite = '' },
    Ranks = {
        -- ['Officer'] = '000000000000000000',
    },
}

Config.Logs = {
    Enabled = false,
    Webhook = '',
    Name    = 'Squads',
    Color   = 561570,
    Events  = { create = true, disband = true, join = true, leave = true, kick = true, promote = true, match = true, ally = true, admin = true, request = false },
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

Config.Admin = {
    Command = 'squadadmin',
    Ace     = 'nz_squads.admin',   -- add_ace group.admin nz_squads.admin allow
}

-- ██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
-- ██████╔╝██║██╔██╗ ██║██║  ███╗███████╗
-- ██╔═══╝ ██║██║╚██╗██║██║   ██║╚════██║
-- ██║     ██║██║ ╚████║╚██████╔╝███████║
-- ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

Config.Ping = {
    Key         = 'MOUSE_MIDDLE',
    Mapper      = 'MOUSE_BUTTON',
    HoldMs      = 280,
    CooldownMs  = 1000,
    TTL         = 15,
    FollowTTL   = 6,
    WaypointTTL = 60,
    MaxDistance = 400.0,
    Sound       = { name = 'Waypoint_Set', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    Types = {
        go       = { label = 'Go here',     icon = 'fa-location-arrow',       color = { 8, 175, 162 },   blip = 1,   blipColor = 2 },
        enemy    = { label = 'Enemy',       icon = 'fa-crosshairs',           color = { 229, 72, 77 },   blip = 303, blipColor = 1 },
        danger   = { label = 'Danger',      icon = 'fa-triangle-exclamation', color = { 229, 165, 10 },  blip = 761, blipColor = 5 },
        loot     = { label = 'Loot',        icon = 'fa-box-open',             color = { 255, 255, 255 }, blip = 478, blipColor = 0 },
        defend   = { label = 'Defend',      icon = 'fa-shield-halved',        color = { 88, 166, 255 },  blip = 487, blipColor = 3 },
        vehicle  = { label = 'Vehicle',     icon = 'fa-car-side',             color = { 160, 120, 255 }, blip = 225, blipColor = 27 },
        waypoint = { label = 'Waypoint',    icon = 'fa-route',                color = { 8, 175, 162 },   blip = 8,   blipColor = 2 },
        downed   = { label = 'Member down', icon = 'fa-heart-crack',          color = { 229, 72, 77 },   blip = 280, blipColor = 1 },
        rally    = { label = 'Rally',       icon = 'fa-flag',                 color = { 8, 175, 162 },   blip = 146, blipColor = 2 },
    },
    Wheel = { 'go', 'enemy', 'danger', 'loot', 'defend', 'vehicle' },
}

-- ██████╗ ██╗     ██╗██████╗ ███████╗
-- ██╔══██╗██║     ██║██╔══██╗██╔════╝
-- ██████╔╝██║     ██║██████╔╝███████╗
-- ██╔══██╗██║     ██║██╔═══╝ ╚════██║
-- ██████╔╝███████╗██║██║     ███████║
-- ╚═════╝ ╚══════╝╚═╝╚═╝     ╚══════╝

Config.SquadBlip = {
    DefaultColor  = 2,
    DefaultSprite = 1,
    Scale         = 0.85,
    AllySprite    = 1,
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

-- GTA blip colour id -> hex, used by the UI and the compass. Add any id you let squads pick.
Config.BlipHex = {
    [0] = '#ffffff', [1] = '#e5484d', [2] = '#4cd964', [3] = '#2f95dc', [5] = '#e5a50a', [8] = '#ff7ad9',
    [17] = '#ff9a3c', [25] = '#8bd35a', [27] = '#a078ff', [38] = '#4fd1ff', [40] = '#9aa4ab', [48] = '#08afa2',
}
-- Colours a squad may pick for its blip, in the order the picker shows them.
Config.SquadBlipColors = { 2, 3, 1, 5, 27, 38, 0, 8, 17, 25, 48, 40 }

-- ███████╗███████╗████████╗████████╗██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗█████╗     ██║      ██║   ██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║██╔══╝     ██║      ██║   ██║██║╚██╗██║██║   ██║╚════██║
-- ███████║███████╗   ██║      ██║   ██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

-- What every player starts with. Changed in the Settings tab, saved on their own client.
Config.DefaultSettings = {
    -- team HUD
    hud             = true,
    hudMinimized    = false,
    hudTalking      = true,
    hudMax          = 0,
    hudHealth       = '#ffffff',
    hudArmor        = '#58a6ff',
    hudPos          = false,
    hudKda          = false,
    hudAvatars      = true,
    hudRank         = false,
    hudArmorBar     = true,
    hudAccent       = 'squad',      -- 'squad' | 'teal' | 'health' | 'none'
    hudStyle        = 'cards',      -- 'cards' | 'bars'
    hudScale        = 100,
    hudOpacity      = 86,
    hudShowSelf     = true,
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
    blipUseSquad    = true,
    blipColor       = 2,
    blipAllies      = true,

    -- alerts (all go through lib.notify)
    quiet           = false,        -- mute every squad notification except invites and downed alerts
    chatNotify      = true,
    chatSound       = true,
    pingNotify      = true,
    pingSound       = true,
    reviveAlerts    = true,
    killfeed        = true,
    matchBanner     = true,
    requestNotify   = true,         -- tell officers when someone asks to join

    -- voice
    radio           = true,

    -- compass
    compass         = true,
    compassStreet   = true,
    compassMarkers  = true,
}

Config.TagColors = {
    { '#72cc72', 18 }, { '#e5484d', 6 }, { '#58a6ff', 9 }, { '#e5a50a', 12 }, { '#a078ff', 21 },
    { '#ff7ad9', 26 }, { '#ffffff', 0 }, { '#08afa2', 28 }, { '#ff9a3c', 15 }, { '#4fd1ff', 116 },
}

-- ███████╗████████╗██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗   ██║   ██████╔╝██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║   ██║   ██╔══██╗██║██║╚██╗██║██║   ██║╚════██║
-- ███████║   ██║   ██║  ██║██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

Config.Strings = {
    joined           = '%s joined the squad',
    left             = '%s left the squad',
    kicked           = '%s was removed from the squad',
    new_leader       = '%s now owns the squad',
    rank_set         = '%s is now %s',
    closed           = 'Your squad was closed',
    you_kicked       = 'You were removed from the squad',
    invite_sent      = 'Invite sent to %s',
    invite_received  = '%s invited you to %s',
    no_waypoint      = 'Set a waypoint on your map first',
    cooldown         = 'Slow down a moment',
    no_perm          = 'Your rank cannot do that',
    revived          = '%s revived %s',
    rally_set        = '%s set a rally point',
    rally_clear      = 'Rally point cleared',
    nick_set         = '%s now goes by %s',
    nick_cleared     = '%s cleared their nickname',
    ally_request     = '%s wants to ally with your squad',
    ally_added       = 'Allied with %s',
    ally_removed     = 'No longer allied with %s',
    ally_declined    = '%s declined your alliance',
    ally_full        = 'Your squad already has the most allies allowed',
    motd_set         = '%s updated the message of the day',
    request_sent     = 'Request sent to %s',
    request_received = '%s asked to join the squad',
    request_accepted = 'Your request to join %s was accepted',
    request_declined = '%s declined your request',
    request_cancel   = 'Request withdrawn',
}
