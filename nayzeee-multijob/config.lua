--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
███╗   ███╗██╗   ██╗██╗  ████████╗██╗     ██╗ ██████╗ ██████╗
████╗ ████║██║   ██║██║  ╚══██╔══╝██║     ██║██╔═══██╗██╔══██╗
██╔████╔██║██║   ██║██║     ██║   ██║     ██║██║   ██║██████╔╝
██║╚██╔╝██║██║   ██║██║     ██║   ██║██   ██║██║   ██║██╔══██╗
██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║╚█████╔╝╚██████╔╝██████╔╝
╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚════╝  ╚═════╝ ╚═════╝

    MULTIJOB SCRIPT - 1.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

-- ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
-- ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
-- █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
-- ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
-- ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
-- Framework detection and debug output

Config.Framework = 'auto' -- 'esx', 'qbcore', 'qbox', 'auto' (auto-detect)
Config.Debug = false

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝
-- Job limits, commands and the default job

Config.MaxJobs = 4 -- Maximum secondary jobs a player can have (does NOT count unemployed)
Config.Command = 'jobs' -- Command to open the job menu
Config.AdminCommand = 'jobadmin' -- Command to open admin panel
Config.Keybind = false -- Keybind to open job menu (set to false to disable)

-- The job players fall back to when they quit. Everyone always has it, it
-- never counts towards MaxJobs and it is clocked in automatically.
Config.DefaultJob = {
    name = 'unemployed',
    grade = 0
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝
-- Who can open the admin panel and what they can do

-- Checked on the SERVER. ESX: xPlayer.getGroup(). QBCore / QBox: the
-- 'group.<name>' ACE or QBCore permission of the same name.
-- Anyone with the ACE 'nayzeee-multijob.admin' is always allowed:
--   add_ace group.admin nayzeee-multijob.admin allow
Config.AdminGroups = { 'mod', 'admin', 'superadmin', 'god', 'management', 'developer', 'owner' }

-- Set any of these to false to hide that tab and block the action server-side
Config.AdminPermissions = {
    viewPlayers = true,     -- Players tab, including the offline character search
    editJobs = true,        -- add / remove jobs from a single player
    bulkOperations = true,  -- Bulk actions tab
    viewLogs = true,        -- Logs tab
    viewAnalytics = true,   -- Analytics tab
}

-- ██████╗  ██████╗ ███████╗███████╗
-- ██╔══██╗██╔═══██╗██╔════╝██╔════╝
-- ██████╔╝██║   ██║███████╗███████╗
-- ██╔══██╗██║   ██║╚════██║╚════██║
-- ██████╔╝╚██████╔╝███████║███████║
-- ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
-- Team tab for job bosses: hire, promote and let people go

Config.Boss = {
    enabled = true,

    -- Who counts as a boss of a job:
    --   QBCore / QBox -> grades with isboss = true
    --   ESX           -> the grade named 'boss' (same rule as esx_society)
    --   any job       -> its highest grade, when no grade is marked as boss
    -- Override per job with the lowest grade that is a boss, e.g. police = 3
    minGrade = {},

    -- Bosses can set grades up to one below their own. true = up to their own grade.
    promoteToOwnGrade = false,

    -- How close a new hire must be standing, in metres. 0 = anyone online.
    -- (Needs OneSync, which ESX Legacy and QBCore already require.)
    hireDistance = 5.0,

    -- New hires get a pop-up to accept or decline the offer
    requireAccept = true,
    offerTimeout = 60, -- seconds before an unanswered offer expires

    -- Turn single actions off for every boss
    permissions = {
        hire = true,
        fire = true,
        promote = true, -- promote and demote
    },
}

--  ██████╗ █████╗ ████████╗███████╗ ██████╗  ██████╗ ██████╗ ██╗███████╗███████╗
-- ██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝██╔════╝
-- ██║     ███████║   ██║   █████╗  ██║  ███╗██║   ██║██████╔╝██║█████╗  ███████╗
-- ██║     ██╔══██║   ██║   ██╔══╝  ██║   ██║██║   ██║██╔══██╗██║██╔══╝  ╚════██║
-- ╚██████╗██║  ██║   ██║   ███████╗╚██████╔╝╚██████╔╝██║  ██║██║███████╗███████║
--  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝
-- How jobs are grouped and filtered in the menu

Config.Categories = {
    emergency = {
        label = 'Emergency Services',
        icon = 'fa-solid fa-truck-medical',
        color = '#ef4444',
        jobs = { 'police', 'ambulance', 'firefighter' }
    },
    government = {
        label = 'Government',
        icon = 'fa-solid fa-landmark',
        color = '#3b82f6',
        jobs = { 'judge', 'lawyer', 'mayor', 'reporter' }
    },
    business = {
        label = 'Business',
        icon = 'fa-solid fa-briefcase',
        color = '#22c55e',
        jobs = { 'realestate', 'banker', 'cardealer' }
    },
    service = {
        label = 'Service Industry',
        icon = 'fa-solid fa-utensils',
        color = '#f59e0b',
        jobs = { 'mechanic', 'taxi', 'trucker', 'garbage', 'tow' }
    },
    criminal = {
        label = 'Underground',
        icon = 'fa-solid fa-skull',
        color = '#a855f7',
        jobs = { 'gang', 'mafia' }
    },
    civilian = {
        label = 'Civilian',
        icon = 'fa-solid fa-user',
        color = '#6b7280',
        jobs = { 'unemployed', 'offduty' }
    }
}

-- ██████╗ ██╗   ██╗████████╗██╗   ██╗
-- ██╔══██╗██║   ██║╚══██╔══╝╚██╗ ██╔╝
-- ██║  ██║██║   ██║   ██║    ╚████╔╝
-- ██║  ██║██║   ██║   ██║     ╚██╔╝
-- ██████╔╝╚██████╔╝   ██║      ██║
-- ╚═════╝  ╚═════╝    ╚═╝      ╚═╝
-- Clock in / clock out behaviour and shift tracking

Config.DutyTracking = {
    enabled = true,
    saveInterval = 60, -- seconds between saving open shifts (survives a crash)

    -- Players who stop moving get clocked out. The default job is paused
    -- instead and clocks back in by itself the moment they move again.
    autoClockOut = {
        enabled = true,
        inactivityMinutes = 30,
        warningMinutes = 25,
    },

    -- QBCore / QBox only. Clocking in here also sets the framework's own
    -- on-duty flag (which is what QBCore paychecks check) and the other way
    -- round, so job scripts with their own duty toggle stay in sync.
    syncFrameworkDuty = true,
}

-- How shift earnings are recorded for stats, shift history and rankings
Config.Earnings = {
    -- 'paycheck' = only real paychecks reported by install/REPLACE_paycheck.lua
    --              or exports['nayzeee-multijob']:TrackPaycheck(src, amount)
    -- 'estimate' = salary x shift length / paycheckMinutes (no paycheck hook needed)
    -- 'auto'     = 'paycheck' on ESX, 'estimate' on QBCore / QBox
    mode = 'auto',

    -- Minutes between framework paychecks. nil = framework default
    -- (ESX 7, QBCore 10). Only used by 'estimate'.
    paycheckMinutes = nil,
}

-- ██████╗  ██████╗ ██╗███╗   ██╗████████╗███████╗
-- ██╔══██╗██╔═══██╗██║████╗  ██║╚══██╔══╝██╔════╝
-- ██████╔╝██║   ██║██║██╔██╗ ██║   ██║   ███████╗
-- ██╔═══╝ ██║   ██║██║██║╚██╗██║   ██║   ╚════██║
-- ██║     ╚██████╔╝██║██║ ╚████║   ██║   ███████║
-- ╚═╝      ╚═════╝ ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝
-- Clock-in points: where a job has to be to clock in

Config.DutyPoints = {
    enabled = false,

    -- How players clock in at a point:
    --   'textui' = walk in and press the key (ox_lib text UI, nothing extra needed)
    --   'target' = an ox_target option on the point
    --   false    = no prompt, use the menu while standing in the point
    interact = 'textui',
    key = 38, -- E. Control index used by 'textui'.

    blips = true,
    clockOutAtPoint = false, -- true = players have to be at a point to clock out as well
    waypoint = true,         -- clocking in away from a point marks the nearest one on the map

    -- A job with points listed here can only clock in at one of them.
    -- Jobs with no points keep clocking in from anywhere, like before.
    -- blip: false hides that point's blip. Sprites: 60 police, 61 hospital, 446 mechanic.
    points = {
        { job = 'police', label = 'Mission Row PD', coords = vec3(441.1, -981.9, 30.7), radius = 3.0,
          blip = { sprite = 60, colour = 29, scale = 0.7 } },
        { job = 'ambulance', label = 'Pillbox Medical', coords = vec3(311.2, -593.8, 43.3), radius = 3.0,
          blip = { sprite = 61, colour = 1, scale = 0.7 } },
        { job = 'mechanic', label = 'Bennys Motorworks', coords = vec3(-205.9, -1310.9, 31.3), radius = 4.0,
          blip = { sprite = 446, colour = 5, scale = 0.7 } },
    },
}

--  ██████╗ ██████╗  ██████╗ ██╗     ██████╗  ██████╗ ██╗    ██╗███╗   ██╗███████╗
-- ██╔════╝██╔═══██╗██╔═══██╗██║     ██╔══██╗██╔═══██╗██║    ██║████╗  ██║██╔════╝
-- ██║     ██║   ██║██║   ██║██║     ██║  ██║██║   ██║██║ █╗ ██║██╔██╗ ██║███████╗
-- ██║     ██║   ██║██║   ██║██║     ██║  ██║██║   ██║██║███╗██║██║╚██╗██║╚════██║
-- ╚██████╗╚██████╔╝╚██████╔╝███████╗██████╔╝╚██████╔╝╚███╔███╔╝██║ ╚████║███████║
--  ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═══╝╚══════╝
-- Time limits between job switches and quits

Config.Cooldowns = {
    enabled = false,
    globalCooldown = 300,
    
    jobCooldowns = {
        police = 600,
        ambulance = 600,
    },
    
    exempt = { 'unemployed', 'offduty' }
}

-- ███████╗ ██████╗██╗  ██╗███████╗██████╗ ██╗   ██╗██╗     ███████╗
-- ██╔════╝██╔════╝██║  ██║██╔════╝██╔══██╗██║   ██║██║     ██╔════╝
-- ███████╗██║     ███████║█████╗  ██║  ██║██║   ██║██║     █████╗
-- ╚════██║██║     ██╔══██║██╔══╝  ██║  ██║██║   ██║██║     ██╔══╝
-- ███████║╚██████╗██║  ██║███████╗██████╔╝╚██████╔╝███████╗███████╗
-- ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝
-- Automatic job switching at a set time

-- Times use the SERVER clock (os.date), not the player's.
Config.Schedule = {
    enabled = true,
    maxSchedules = 5,       -- per player
    playerCanCreate = true, -- false = players can only view / delete
    notifyBefore = 5,       -- minutes of warning before a switch
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝ ██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗███████╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║╚════██║
-- ██║  ██║██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝
-- Server-wide leaderboards shown in the menu

Config.Leaderboards = {
    enabled = true,
    refreshInterval = 300, -- seconds the rankings are cached for
    maxEntries = 10,

    -- Hours / earnings in these jobs don't count (stops AFK welfare farming the board)
    excludeJobs = { 'unemployed' },
    
    categories = {
        { id = 'total_hours', label = 'Total Hours Worked', icon = 'fa-solid fa-clock' },
        { id = 'total_earnings', label = 'Total Earnings', icon = 'fa-solid fa-dollar-sign' },
        { id = 'jobs_held', label = 'Jobs Mastered', icon = 'fa-solid fa-briefcase' },
    }
}

-- ██╗   ██╗██╗
-- ██║   ██║██║
-- ██║   ██║██║
-- ██║   ██║██║
-- ╚██████╔╝██║
--  ╚═════╝ ╚═╝
-- Colours, fonts and window text - change these freely

Config.UI = {

    -- Main accent. Every teal element in the menu follows this one value:
    -- nav highlight, buttons, tags, meters, the brand mark and the glow.
    accent = '#08afa2',

    -- Leave these nil and they are derived from accent automatically.
    -- Set them if you want exact control over the gradient.
    accentHi = nil, -- top of button gradients / mark highlight
    accentLo = nil, -- bottom of button gradients

    -- Destructive actions: Close pill, delete buttons, warnings.
    danger   = '#e5484d',
    dangerLo = nil,

    -- Window background. Surfaces are stepped up from this automatically,
    -- so a dark colour works best. '#000000' is the default look.
    background = '#000000',

    -- Font family loaded in html/index.html. Swap the Google Fonts link
    -- there too if you change this to something that isn't Lexend.
    font = 'Lexend',

    -- Window title and the small line under it
    title = 'Job Center',
    subtitle = 'Employment Services',

    -- Window size in pixels. This is a compact in-game panel by default -
    -- it is not meant to fill the screen. Raise these if you want it bigger.
    width   = 860, -- total window width
    height  = 470, -- height of the content area (title bar and status bar sit outside it)
    sidebar = 190, -- width of the left navigation rail

    -- Visual extras
    grain = true,     -- subtle film grain over the window
    watermark = true, -- large faded shape in the bottom-right of the content
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝
-- Phones and on-screen notify resources

Config.Notifications = {

    -- ─────────────────────────────────────────────────────────────────────
    -- WHERE NOTIFICATIONS ARE SHOWN
    -- ─────────────────────────────────────────────────────────────────────
    -- This is the only switch that decides what the player sees.
    --
    --   'notify' = on-screen notification only   (no phone)
    --   'phone'  = phone notification only       (no on-screen popup)
    --   'both'   = optional - show both at once
    --
    -- If 'phone' is set but no supported phone is running, messages fall
    -- back to the on-screen notify so nothing is silently lost.
    output = 'notify',

    -- ─────────────────────────────────────────────────────────────────────
    -- ON-SCREEN NOTIFY RESOURCE  (used by 'notify' and 'both')
    -- ─────────────────────────────────────────────────────────────────────
    -- 'auto'    = detect the first started resource from NayNotify.SystemPriority
    -- 'nayzeee' = nayzeee-notify
    -- 'ox_lib' | 'okok' | 'codem' | 'mythic' | 'brutal' | 't-notify'
    -- 'qb' | 'esx' | 'esx_advanced' | 'chat' | 'native'
    --
    -- Add your own in notify/adapters.lua -> NayNotify.Systems['name']
    system = 'auto',

    duration = 5000,
    position = 'top-right', -- ox_lib only

    -- ─────────────────────────────────────────────────────────────────────
    -- PHONE RESOURCE  (used by 'phone' and 'both')
    -- ─────────────────────────────────────────────────────────────────────
    phone = {

        -- 'auto' = detect the first started phone from NayNotify.PhonePriority
        -- 'lb-phone' | 'qs-smartphone' | 'qs-smartphone-pro' | 'gksphone'
        -- 'roadphone' | 'yflip-phone' | 'high-phone' | 'npwd' | 'qb-phone'
        --
        -- Add your own in notify/adapters.lua -> NayNotify.Phones['name']
        resource = 'auto',

        -- App the notification is posted under (banking/wallet app name)
        app = 'Wallet',
    },
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝
-- Optional Discord logging

-- Discord logging lives in config_server.lua so the webhook URL is never
-- sent to players (this file is downloaded by every client).

-- ██████╗ ██╗      █████╗  ██████╗██╗  ██╗██╗     ██╗███████╗████████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝██║     ██║██╔════╝╚══██╔══╝
-- ██████╔╝██║     ███████║██║     █████╔╝ ██║     ██║███████╗   ██║
-- ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ ██║     ██║╚════██║   ██║
-- ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗███████╗██║███████║   ██║
-- ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝╚══════╝   ╚═╝
-- Jobs players can never take or remove

Config.BlacklistedJobs = { 'prisoner' } -- never added to a player's list, can't be switched to
Config.NonRemovableJobs = { 'unemployed' } -- players can't remove or quit these themselves

-- ██╗      ██████╗  ██████╗ █████╗ ██╗     ███████╗
-- ██║     ██╔═══██╗██╔════╝██╔══██╗██║     ██╔════╝
-- ██║     ██║   ██║██║     ███████║██║     █████╗
-- ██║     ██║   ██║██║     ██╔══██║██║     ██╔══╝
-- ███████╗╚██████╔╝╚██████╗██║  ██║███████╗███████╗
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝
-- Every string the player sees

Config.Locale = {
    ['job_menu'] = 'Job Menu',
    ['admin_panel'] = 'Admin Panel',
    ['close'] = 'Close',
    ['search'] = 'Search jobs...',
    ['no_results'] = 'No jobs found',
    ['switch_job'] = 'Switch to this job',
    ['favorite'] = 'Add to Favorites',
    ['unfavorite'] = 'Remove from Favorites',
    ['remove_job'] = 'Remove Job',
    ['clock_in'] = 'Clock In',
    ['clock_out'] = 'Clock Out',
    ['on_duty'] = 'On Duty',
    ['off_duty'] = 'Off Duty',
    ['current_job'] = 'Current Job',
    ['shift_time'] = 'Shift Time',
    ['job_switched'] = 'You are now working as %s',
    ['job_added'] = 'Job added to your list',
    ['job_removed'] = 'Job removed from your list',
    ['cooldown_active'] = 'You must wait %s before switching jobs',
    ['max_jobs_reached'] = 'You have reached the maximum number of jobs',
    ['clocked_in'] = 'You have clocked in',
    ['clocked_out'] = 'You have clocked out after %s',
    ['inactivity_warning'] = 'You will be clocked out in %s minutes due to inactivity',
    ['auto_clock_out'] = 'You have been automatically clocked out due to inactivity',
    ['schedule_reminder'] = 'Scheduled job switch to %s in %s minutes',
    ['admin_no_permission'] = 'You do not have permission to access this',
    ['player_not_found'] = 'Player not found',
    ['action_logged'] = 'Action logged successfully',
    ['job_quit'] = 'You quit your job as %s',
    ['job_not_found'] = 'That job does not exist',
    ['job_not_owned'] = 'You do not have this job',
    ['job_blacklisted'] = 'You cannot take this job',
    ['job_not_removable'] = 'This job cannot be removed',
    ['job_is_active'] = 'Quit this job instead - it is your active job',
    ['job_switch_failed'] = 'Could not switch job, try again',
    ['already_on_duty'] = 'You are already clocked in',
    ['not_on_duty'] = 'You are not clocked in',
    ['default_always_on'] = 'You are always on duty while %s',
    ['default_no_clockout'] = 'You cannot clock out while %s',
    ['afk_resumed'] = 'Welcome back, you are clocked in again',
    ['schedule_saved'] = 'Schedule saved',
    ['schedule_deleted'] = 'Schedule deleted',
    ['schedule_limit'] = 'You can only have %s schedules',
    ['schedule_disabled'] = 'Schedules are managed by staff on this server',
    ['schedule_invalid'] = 'That schedule is not valid',
    ['admin_done'] = 'Done - %s',
    ['admin_bulk_done'] = '%s of %s players updated',

    -- clock-in points
    ['duty_point_needed'] = 'Clock in at %s',
    ['duty_point_needed_out'] = 'Clock out at %s',
    ['duty_point_waypoint'] = 'Clock in at %s - it is marked on your map',
    ['duty_point_prompt_in'] = '[E] Clock in · %s',
    ['duty_point_prompt_out'] = '[E] Clock out · %s',

    -- boss / team
    ['boss_not_boss'] = 'You are not a boss of this job',
    ['boss_no_permission'] = 'Bosses cannot do that on this server',
    ['boss_offer_sent'] = 'Job offer sent to %s',
    ['boss_offer_title'] = 'Job offer',
    ['boss_offer_text'] = '%s is offering you a job as %s (%s). Do you accept?',
    ['boss_offer_accept'] = 'Accept',
    ['boss_offer_decline'] = 'Decline',
    ['boss_offer_accepted'] = '%s accepted your job offer',
    ['boss_offer_declined'] = '%s turned down your job offer',
    ['boss_offer_expired'] = 'That job offer has expired',
    ['boss_offer_pending'] = '%s already has a job offer waiting',
    ['boss_hired'] = 'You were hired as %s - switch to it from /jobs',
    ['boss_already_employed'] = '%s already works here',
    ['boss_too_far'] = 'Stand closer to the person you are hiring',
    ['boss_target_full'] = '%s has no free job slots',
    ['boss_fired'] = '%s was let go',
    ['boss_you_fired'] = 'You were let go from %s',
    ['boss_rank_too_high'] = 'You can only manage staff below your own grade',
    ['boss_grade_too_high'] = 'You cannot give out a grade that high',
    ['boss_grade_set'] = '%s is now %s',
    ['boss_your_grade'] = 'You are now %s at %s',
}
