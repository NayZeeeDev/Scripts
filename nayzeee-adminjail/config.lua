--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    NAYZEEE ADMIN JAIL - 1.0.0
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
    alertStaff  = true,  -- notify online staff (and the open admin panel) on every attempt
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
    cancelKey      = 73,    -- X — cancels the current task

    --[[
        Task types. Each one uses either:
          anim     = { dict, clip, flag }   + optional prop = { model, bone, pos, rot }
          scenario = 'WORLD_HUMAN_...'      (GTA handles the prop itself)
        ptfx (optional) = { asset, name, scale, offset } — looped particle on the player while working
        Prop offsets are tuned for freemode peds; nudge pos/rot if you use custom models.
    ]]
    tasks = {
        sweep = {
            label = 'Sweep the floor', icon = 'broom', duration = 7000,
            anim = { dict = 'amb@world_human_janitor@male@idle_a', clip = 'idle_a', flag = 1 },
            prop = { model = 'prop_tool_broom', bone = 28422, pos = vec3(-0.01, 0.04, -0.03), rot = vec3(0.0, 0.0, 0.0) },
            ptfx = { asset = 'core', name = 'ent_anim_dusty_hands', scale = 1.4, offset = vec3(0.0, 0.6, -0.95) },
        },
        mop = {
            label = 'Mop the floor', icon = 'mop', duration = 7000,
            anim = { dict = 'missfbi_s4mop', clip = 'idle_scrub', flag = 1 },
            prop = { model = 'prop_cs_mop_s', bone = 28422, pos = vec3(0.0, 0.0, 0.12), rot = vec3(0.0, 0.0, 0.0) },
        },
        scrub = {
            label = 'Scrub the surface', icon = 'sponge', duration = 6500,
            anim = { dict = 'timetable@floyd@clean_kitchen@base', clip = 'base', flag = 1 },
            prop = { model = 'prop_sponge_01', bone = 28422, pos = vec3(0.0, 0.0, -0.01), rot = vec3(90.0, 0.0, 0.0) },
        },
        trash = {
            label = 'Pick up litter', icon = 'trash', duration = 6000,
            anim = { dict = 'pickup_object', clip = 'pickup_low', flag = 1 },
        },
        repair = {
            label = 'Repair the fence', icon = 'hammer', duration = 8000,
            scenario = 'WORLD_HUMAN_HAMMERING',
        },
        wipe = {
            label = 'Wipe the windows', icon = 'sponge', duration = 6500,
            scenario = 'WORLD_HUMAN_MAID_CLEAN',
        },
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
            { coords = vec3(3060.23, -4680.54, 15.26), task = 'mop' },
            { coords = vec3(3080.08, -4717.49, 15.26), task = 'trash' },
            { coords = vec3(3053.08, -4750.20, 15.26), task = 'repair' },
            { coords = vec3(3081.39, -4759.89, 15.26), task = 'scrub' },
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
            { coords = vec3(1699.13, 2516.40, 45.56), task = 'mop' },
            { coords = vec3(1693.89, 2491.02, 45.56), task = 'trash' },
            { coords = vec3(1668.44, 2507.46, 45.56), task = 'repair' },
            { coords = vec3(1654.31, 2542.92, 45.56), task = 'scrub' },
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
            { coords = vec3(-2052.1, 3138.7, 32.8), task = 'mop' },
            { coords = vec3(-2042.8, 3142.3, 32.8), task = 'trash' },
            { coords = vec3(-2038.2, 3128.9, 32.8), task = 'repair' },
            { coords = vec3(-2055.6, 3125.4, 32.8), task = 'scrub' },
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
            { coords = vec3(465.20, -998.10, 24.91), task = 'mop' },
            { coords = vec3(458.30, -1001.70, 24.91), task = 'trash' },
            { coords = vec3(460.60, -1004.90, 24.91), task = 'repair' },
            { coords = vec3(463.70, -1006.60, 24.91), task = 'scrub' },
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

    Tables are created automatically on start.
]]

Config.Database = {
    active        = 'nayzeee_adminjail_active',
    history       = 'nayzeee_adminjail_log',
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
     ██████╗██╗███╗   ██╗███████╗███╗   ███╗ █████╗ ████████╗██╗ ██████╗
    ██╔════╝██║████╗  ██║██╔════╝████╗ ████║██╔══██╗╚══██╔══╝██║██╔════╝
    ██║     ██║██╔██╗ ██║█████╗  ██╔████╔██║███████║   ██║   ██║██║
    ██║     ██║██║╚██╗██║██╔══╝  ██║╚██╔╝██║██╔══██║   ██║   ██║██║
    ╚██████╗██║██║ ╚████║███████╗██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╗
     ╚═════╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝

    Sentencing:  sky camera out -> jumpsuit on -> sky camera in -> mugshot booking
                 (player holds a printed booking board, two camera flashes, front + side)
                 with a booking card showing their real in-game headshot.
    Reconnect:   quick fade + "sentence resumed" card.
    Escape:      alarm, red screen pulse, camera shake, then dragged back.
    Release:     summary card (time served, escapes, work), sky camera to the release point.
]]

Config.Cinematic = {
    enabled  = true,
    skyCam   = true,          -- GTA character-switch camera for sentencing, transfers and release
    mugshot  = true,          -- booking board + camera flashes after a fresh sentence
    board    = 'ADMIN JAIL',  -- top line printed on the booking board
    sounds   = true,
    effects  = true,          -- screen effects / camera shake
}

--[[
     ██████╗ ██╗   ██╗████████╗███████╗██╗████████╗
    ██╔═══██╗██║   ██║╚══██╔══╝██╔════╝██║╚══██╔══╝
    ██║   ██║██║   ██║   ██║   █████╗  ██║   ██║
    ██║   ██║██║   ██║   ██║   ██╔══╝  ██║   ██║
    ╚██████╔╝╚██████╔╝   ██║   ██║     ██║   ██║
     ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝   ╚═╝

    Prison jumpsuit while jailed. The real outfit is saved on the player's PC (resource KVP),
    so it comes back on release even after a server restart or a reconnect.
    Only applied to freemode peds. [component] = { drawable, texture }
    Defaults are the classic orange jumpsuit - change them to match your clothing packs.
]]

Config.Outfit = {
    enabled = true,
    clearProps = true, -- remove hats, glasses, watches...
    male = {
        [3]  = { 0, 0 },   -- arms
        [4]  = { 3, 7 },   -- pants
        [6]  = { 1, 0 },   -- shoes
        [7]  = { 0, 0 },   -- accessories
        [8]  = { 15, 0 },  -- undershirt
        [11] = { 146, 0 }, -- top (jumpsuit)
    },
    female = {
        [3]  = { 0, 0 },
        [4]  = { 3, 15 },
        [6]  = { 1, 0 },
        [7]  = { 0, 0 },
        [8]  = { 14, 0 },
        [11] = { 141, 0 },
    },
}

--[[
     ██████╗ ██╗   ██╗███████╗██████╗ ██╗  ██╗███████╗ █████╗ ██████╗
    ██╔═══██╗██║   ██║██╔════╝██╔══██╗██║  ██║██╔════╝██╔══██╗██╔══██╗
    ██║   ██║██║   ██║█████╗  ██████╔╝███████║█████╗  ███████║██║  ██║
    ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██╔══██║██╔══╝  ██╔══██║██║  ██║
    ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║██║  ██║███████╗██║  ██║██████╔╝
     ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

    Floating tag above inmates for other players nearby. Costs nothing while
    nobody on the server is jailed (driven by state bags, no polling).
]]

Config.Overhead = {
    enabled  = true,
    distance = 15.0,
    label    = 'ADMIN JAIL',
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
Config.Progress = 'nayzeee' -- 'nayzeee' (built-in, matches the UI), 'circle' or 'bar' (ox_lib)
