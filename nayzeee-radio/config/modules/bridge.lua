--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - BRIDGE (framework & third-party integrations)
    Discord: discord.gg/nayzeeedev

    Everything is detected automatically. Leave a setting on 'auto' unless you
    run two scripts of the same kind and want to force one of them.

    The adapters themselves live in bridge/ (open source, not escrowed). If a
    script you use is missing or changed its exports, fix the one adapter there.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Bridge = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- WHICH SCRIPTS TO USE   ('auto' = detect what is started)
    -- ═══════════════════════════════════════════════════════════════════════

    framework = 'auto',   -- 'auto' (uses Config.Framework) | 'esx' | 'qbcore' | 'qbox' | 'standalone'

    inventory = 'auto',   -- 'ox_inventory' | 'qb-inventory' | 'qs-inventory' | 'codem-inventory' | 'origen_inventory'
                          -- 'tgiann-inventory' | 'core_inventory' | 'ps-inventory' | 'lj-inventory' | 'framework'

    target    = 'auto',   -- used for the jammers: 'ox_target' | 'qb-target' | 'qtarget' | 'interact' | 'sleepless_interact'
                          -- 'builtin' = our own [E] prompt (no target script needed)

    notify    = 'auto',   -- 'auto' = our own NUI toasts (recommended)
                          -- 'nayzeee' | 'ox_lib' | 'okok' | 'codem' | 'mythic' | 'brutal' | 't-notify' | 'qb' | 'esx' | 'native'

    -- ═══════════════════════════════════════════════════════════════════════
    -- STANDALONE (no framework)
    -- Jobs come from aces. The first job in this list the player has is theirs:
    --   add_ace identifier.license:xxxx nzr.job.police allow
    --   add_ace identifier.license:xxxx nzr.job.police.3 allow   (grade 3, optional)
    -- Job-locked channels then work exactly as on a framework server.
    -- ═══════════════════════════════════════════════════════════════════════

    standaloneJobs = {
        { name = 'police',    label = 'Police' },
        { name = 'sheriff',   label = 'Sheriff' },
        { name = 'ambulance', label = 'EMS' },
    },
    standaloneJobAce   = 'nzr.job',   -- prefix of the job aces above
    standaloneMaxGrade = 10,          -- highest nzr.job.<name>.<n> grade that is checked
    standaloneOnDuty   = true,        -- standalone jobs count as on duty

    -- ═══════════════════════════════════════════════════════════════════════
    -- ESX DUTY
    -- Older ESX servers put off-duty officers on a job called 'offpolice'.
    -- That job counts as 'police' + off duty, for the jobs listed here.
    -- New ESX (job.onDuty) works as is.
    -- ═══════════════════════════════════════════════════════════════════════

    offDutyPrefix = 'off',
    offDutyJobs   = { 'police', 'sheriff', 'ambulance' },   -- true = every job

    -- ═══════════════════════════════════════════════════════════════════════
    -- BUILT-IN TARGET (used when no target script is running, or target = 'builtin')
    -- ═══════════════════════════════════════════════════════════════════════

    builtinTarget = {
        key      = 38,     -- control id (38 = E)
        keyLabel = 'E',
        distance = 2.0,    -- default reach when an option has no distance
        scan     = 250,    -- ms between scans for things nearby
        markers  = false,  -- small dot above what you can interact with
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ITEMS
    -- ═══════════════════════════════════════════════════════════════════════

    -- Item pictures: use the inventory's own image when it exists, else ours
    -- (html/img/items/<name>.png).
    preferInventoryImages = true,

    debug = false,          -- print what was detected and every adapter error
}
