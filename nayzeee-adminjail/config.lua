--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    NAYZEEE ADMIN JAIL - 2.0.0
    Discord: discord.gg/nayzeeedev
]]

Config = {}

--[[
    ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
    ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
    █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
    ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
    ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
]]

Config.Framework = 'auto'   -- 'auto', 'qb', 'qbx', 'esx', 'standalone'
Config.Locale    = 'en'     -- file in /locales
Config.Debug     = false    -- draws zones + prints state changes

-- Who the sentence belongs to.
--   'license'   = the whole account (switching characters does NOT dodge the jail)  << recommended for admin jail
--   'character' = only the character that was jailed (citizenid / esx identifier)
Config.Scope = 'license'

--[[
     █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
    ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
    ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
    ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
    ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
    ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝
]]

Config.Permissions = {
    -- Any of these ACE permissions grants access.
    -- e.g. server.cfg:  add_ace group.admin nayzeee.adminjail allow
    aces = { 'nayzeee.adminjail' },

    -- Framework groups (QB/QBX permission, ESX group). Also checked as ACE 'group.<name>'.
    groups = { 'god', 'superadmin', 'admin', 'mod' },
}

--[[
     ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗ ███████╗
    ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝
    ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████╗
    ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║╚════██║
    ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝███████║
     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
]]

Config.Commands = {
    panel  = 'adminjail', -- /adminjail                       opens the admin panel
    jail   = 'jail',      -- /jail [id] [minutes] [reason]    works from console too
    unjail = 'unjail',    -- /unjail [id]
}

Config.HudKey = 'HOME' -- players can rebind in Settings > Key Bindings > FiveM (toggle jail HUD)

--[[
    ███████╗███████╗███╗   ██╗████████╗███████╗███╗   ██╗ ██████╗███████╗
    ██╔════╝██╔════╝████╗  ██║╚══██╔══╝██╔════╝████╗  ██║██╔════╝██╔════╝
    ███████╗█████╗  ██╔██╗ ██║   ██║   █████╗  ██╔██╗ ██║██║     █████╗
    ╚════██║██╔══╝  ██║╚██╗██║   ██║   ██╔══╝  ██║╚██╗██║██║     ██╔══╝
    ███████║███████╗██║ ╚████║   ██║   ███████╗██║ ╚████║╚██████╗███████╗
    ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝
]]

Config.Sentence = {
    maxMinutes      = 1440,                 -- hard cap per sentence (and per adjustment)
    countOffline    = false,                -- false = time only counts while the player is actually in jail
    quickDurations  = { 10, 20, 30, 60, 120 }, -- buttons in the panel
    defaultLocation = 'bolingbroke',

    -- Reason presets shown in the panel. minutes = suggested length.
    presets = {
        { label = 'RDM',            minutes = 30 },
        { label = 'VDM',            minutes = 20 },
        { label = 'FailRP',         minutes = 20 },
        { label = 'Combat logging', minutes = 60 },
        { label = 'Metagaming',     minutes = 30 },
        { label = 'Staff disrespect', minutes = 45 },
    },
}

Config.Release = {
    -- 'fixed'    = always release at the location's `release` (or the fallback below)
    -- 'previous' = put them back where they were when they got jailed (falls back to fixed)
    mode   = 'fixed',
    coords = vector4(219.11, -799.94, 30.74, 70.0),
}

--[[
    ███████╗██████╗  █████╗ ██╗    ██╗███╗   ██╗
    ██╔════╝██╔══██╗██╔══██╗██║    ██║████╗  ██║
    ███████╗██████╔╝███████║██║ █╗ ██║██╔██╗ ██║
    ╚════██║██╔═══╝ ██╔══██║██║███╗██║██║╚██╗██║
    ███████║██║     ██║  ██║╚███╔███╔╝██║ ╚████║
    ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═══╝

    Reconnects, server restarts and spawn selectors.
    A jailed player is never placed until they have *actually* spawned: the ped is visible,
    the screen is faded in, no switch/scripted camera is active and no other resource holds
    NUI focus (spawn selectors, multichar, apartments...). Then they're moved to jail.
    If they end up outside right after placement (late spawn teleports) they're pulled
    back silently, without an escape penalty.
]]

Config.Spawn = {
    settleChecks   = 3,   -- consecutive "spawned" checks (500ms apart) before placing
    settleTimeout  = 90,  -- seconds; place anyway after this (stuck camera from another script)
    pullbackWindow = 30,  -- seconds after placement where leaving the zone is not an escape
}

--[[
    ███████╗███████╗ ██████╗ █████╗ ██████╗ ███████╗
    ██╔════╝██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝
    █████╗  ███████╗██║     ███████║██████╔╝█████╗
    ██╔══╝  ╚════██║██║     ██╔══██║██╔═══╝ ██╔══╝
    ███████╗███████║╚██████╗██║  ██║██║     ███████╗
    ╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚══════╝
]]

Config.Escape = {
    enabled     = true,
    penalty     = 5,     -- minutes added on the first attempt
    escalation  = 5,     -- extra minutes added per previous attempt (5, 10, 15 ...)
    maxPenalty  = 30,    -- cap per attempt
    grace       = 10,    -- seconds of immunity after placement / an attempt
    broadcast   = false, -- notify the whole server
    serverCheck = true,  -- OneSync position check on the server (catches noclip / menus)
    serverInterval = 3000,
}

--[[
    ██████╗ ███████╗███████╗████████╗██████╗ ██╗ ██████╗████████╗
    ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔══██╗██║██╔════╝╚══██╔══╝
    ██████╔╝█████╗  ███████╗   ██║   ██████╔╝██║██║        ██║
    ██╔══██╗██╔══╝  ╚════██║   ██║   ██╔══██╗██║██║        ██║
    ██║  ██║███████╗███████║   ██║   ██║  ██║██║╚██████╗   ██║
    ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝ ╚═════╝   ╚═╝
]]

Config.Restrictions = {
    godmode        = true,  -- can't die / be killed while jailed
    disarm         = true,  -- forced unarmed
    noMelee        = true,  -- no punching (ped config flag, zero per-frame cost)
    noVehicles     = true,  -- kicked out of vehicles
    blockInventory = true,  -- sets ox_inventory `invBusy` + qb `inv_busy` state bags
}

--[[
    ██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
    ██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
    ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
    ██║███╗██║██║   ██║██╔══██╗██╔═██╗
    ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
     ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

    Every step is verified by the server (position + duration), so the work program
    can't be triggered remotely to wipe a sentence.
]]

Config.Work = {
    enabled        = true,
    pointsPerCycle = 5,     -- tasks per cycle (picked at random from the location's points)
    reduction      = 2,     -- minutes removed per finished cycle
    maxPerHour     = 10,    -- max minutes removable per real hour (persists through reconnects)
    viewDistance   = 40.0,  -- marker draw distance
    interactDistance = 1.6,
    blip           = true,

    -- Task types. Use a GTA scenario (handles the prop for you) or anim + prop.
    tasks = {
        sweep = { label = 'Sweep the floor',   duration = 6000, scenario = 'WORLD_HUMAN_JANITOR' },
        scrub = { label = 'Scrub the surface', duration = 6000, scenario = 'WORLD_HUMAN_MAID_CLEAN' },
        trash = { label = 'Pick up trash',     duration = 5000, scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
        --[[ anim example:
        mop = {
            label = 'Mop', duration = 6000,
            anim = { dict = 'move_mop', clip = 'idle_scrub_small_player', flag = 49 },
            prop = { model = 'prop_cs_mop_s', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
        },
        ]]
    },
}

--[[
    ██╗      ██████╗  ██████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
    ██║     ██╔═══██╗██╔════╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
    ██║     ██║   ██║██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
    ██║     ██║   ██║██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
    ███████╗╚██████╔╝╚██████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
    ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

    zone: polygon `points` + `thickness` (centered on the points' z) or `minZ`/`maxZ`,
          or a sphere: { center = vec3(...), radius = 50.0 }
    work: { coords, task } - task is a key of Config.Work.tasks
    release (optional): where this location releases to (Config.Release.mode = 'fixed')
]]

Config.Locations = {
    {
        id = 'aircraft_carrier',
        name = 'USS Luxington',
        description = 'Maximum security floating prison',
        image = 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/aircraft.png',
        spawn = vector4(3066.8, -4738.24, 15.26, 0.0),
        zone = {
            points = {
                vec3(3057.8, -4826.37, 15.0),
                vec3(2991.62, -4605.99, 15.0),
                vec3(2999.78, -4513.56, 15.0),
                vec3(3020.38, -4508.06, 15.0),
                vec3(3049.91, -4586.47, 15.0),
                vec3(3073.2, -4592.7, 15.0),
                vec3(3130.08, -4800.5, 15.0),
            },
            thickness = 40.0,
        },
        work = {
            { coords = vec3(3046.41, -4715.99, 15.26), task = 'sweep' },
            { coords = vec3(3060.23, -4680.54, 15.26), task = 'scrub' },
            { coords = vec3(3080.08, -4717.49, 15.26), task = 'sweep' },
            { coords = vec3(3053.08, -4750.20, 15.26), task = 'trash' },
            { coords = vec3(3081.39, -4759.89, 15.26), task = 'sweep' },
        },
    },
    {
        id = 'bolingbroke',
        name = 'Bolingbroke Penitentiary',
        description = 'Maximum security prison',
        image = 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/prison.png',
        spawn = vector4(1680.51, 2512.66, 45.56, 204.54),
        release = vector4(1846.38, 2585.86, 45.67, 270.0),
        zone = {
            points = {
                vec3(1700.17, 2474.98, 45.0),
                vec3(1718.68, 2524.92, 45.0),
                vec3(1657.65, 2549.12, 45.0),
                vec3(1630.09, 2525.54, 45.0),
            },
            thickness = 30.0,
        },
        work = {
            { coords = vec3(1656.47, 2522.59, 45.56), task = 'sweep' },
            { coords = vec3(1699.13, 2516.40, 45.56), task = 'trash' },
            { coords = vec3(1693.89, 2491.02, 45.56), task = 'sweep' },
            { coords = vec3(1668.44, 2507.46, 45.56), task = 'scrub' },
            { coords = vec3(1654.31, 2542.92, 45.56), task = 'sweep' },
        },
    },
    {
        id = 'military_base',
        name = 'Fort Zancudo Detention',
        description = 'Military detention facility',
        image = 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/militery.png',
        spawn = vector4(-2047.4, 3132.1, 32.8, 240.0),
        zone = {
            points = {
                vec3(-2100.0, 3100.0, 32.0),
                vec3(-2000.0, 3100.0, 32.0),
                vec3(-2000.0, 3200.0, 32.0),
                vec3(-2100.0, 3200.0, 32.0),
            },
            thickness = 30.0,
        },
        work = {
            { coords = vec3(-2047.4, 3132.1, 32.8), task = 'sweep' },
            { coords = vec3(-2052.1, 3138.7, 32.8), task = 'trash' },
            { coords = vec3(-2042.8, 3142.3, 32.8), task = 'sweep' },
            { coords = vec3(-2038.2, 3128.9, 32.8), task = 'scrub' },
            { coords = vec3(-2055.6, 3125.4, 32.8), task = 'sweep' },
        },
    },
    {
        id = 'police_station',
        name = 'Mission Row Holding',
        description = 'Police station detention',
        image = 'https://r2.fivemanage.com/4iPDn6qcQHpV9zEdQQSZO/police.png',
        spawn = vector4(461.65, -994.49, 24.91, 180.0),
        zone = {
            points = {
                vec3(459.56, -990.78, 24.0),
                vec3(465.29, -990.83, 24.0),
                vec3(465.61, -1008.32, 24.0),
                vec3(454.91, -1008.95, 24.0),
            },
            thickness = 15.0,
        },
        work = {
            { coords = vec3(461.60, -994.50, 24.91), task = 'sweep' },
            { coords = vec3(465.20, -998.10, 24.91), task = 'scrub' },
            { coords = vec3(458.30, -1001.70, 24.91), task = 'sweep' },
            { coords = vec3(460.60, -1004.90, 24.91), task = 'trash' },
            { coords = vec3(463.70, -1006.60, 24.91), task = 'sweep' },
        },
    },
}

--[[
    ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ███████╗███████╗
    ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
    ██║  ██║███████║   ██║   ███████║██████╔╝███████║███████╗█████╗
    ██║  ██║██╔══██║   ██║   ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝
    ██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝██║  ██║███████║███████╗
    ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

    Tables are created automatically. Sentences from v1 (`nayzeee_adminjail` /
    `nayzeee_adminjail_history`) are imported once on first start when legacyImport = true.
]]

Config.Database = {
    active        = 'nayzeee_adminjail_active',
    history       = 'nayzeee_adminjail_log',
    legacyImport  = true,
    flushInterval = 30, -- seconds between saves of running sentences (crash safety)
}

--[[
    ██╗    ██╗███████╗██████╗ ██╗  ██╗ ██████╗  ██████╗ ██╗  ██╗
    ██║    ██║██╔════╝██╔══██╗██║  ██║██╔═══██╗██╔═══██╗██║ ██╔╝
    ██║ █╗ ██║█████╗  ██████╔╝███████║██║   ██║██║   ██║█████╔╝
    ██║███╗██║██╔══╝  ██╔══██╗██╔══██║██║   ██║██║   ██║██╔═██╗
    ╚███╔███╔╝███████╗██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║  ██╗
     ╚══╝╚══╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝
]]

Config.Webhook = {
    enabled   = false,
    url       = '',
    botName   = 'NAYZEEE Admin Jail',
    avatarUrl = '',
    colors = {
        jail     = 0x08afa2,
        release  = 0x3fb950,
        escape   = 0xe5484d,
        adjust   = 0xe5a50a,
        transfer = 0x9ea5aa,
    },
}

--[[
    ██████╗ ██╗   ██╗██╗     ███████╗███████╗
    ██╔══██╗██║   ██║██║     ██╔════╝██╔════╝
    ██████╔╝██║   ██║██║     █████╗  ███████╗
    ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║
    ██║  ██║╚██████╔╝███████╗███████╗███████║
    ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝

    Shown on the jailed player's HUD. Supports:
      <span class="red">text</span>   <span class="teal">text</span>   <span class="amber">text</span>
]]

Config.Rules = {
    'Escape attempts add <span class="red">extra time</span> - and it stacks',
    'Finish work cycles to <span class="teal">reduce your sentence</span>',
    'Work reduction has an <span class="amber">hourly limit</span>',
    'Your timer pauses while you are offline - leaving does not help',
    'Respect all staff decisions',
}

--[[
    ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
    ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
    ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
    ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
    ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
    ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝
]]

Config.Notify = 'ox' -- 'ox', 'qb', 'esx', 'nayzeee'
Config.Progress = 'circle' -- 'circle' or 'bar' (ox_lib)
