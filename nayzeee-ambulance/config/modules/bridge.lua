--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - BRIDGE (framework & third-party integrations)
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

    target    = 'auto',   -- 'ox_target' | 'qb-target' | 'qtarget' | 'interact' | 'sleepless_interact'
                          -- 'builtin' = our own [E] prompt (no target script needed)

    notify    = 'auto',   -- 'auto' = our own NUI toasts (recommended)
                          -- 'nayzeee' | 'ox_lib' | 'okok' | 'codem' | 'mythic' | 'brutal' | 't-notify' | 'qb' | 'esx' | 'native'

    phone     = 'auto',   -- 'lb-phone' | 'qs-smartphone-pro' | 'qs-smartphone' | 'npwd' | 'yseries' | 'gksphone'
                          -- 'okokPhone' | 'roadphone' | 'high-phone' | 'renewed-phone' | false (no phone)

    dispatch  = 'auto',   -- external dispatch/MDT used when externalDispatch = true:
                          -- 'cd_dispatch' | 'ps-dispatch' | 'qs-dispatch' | 'rcore_dispatch' | 'core_dispatch'
                          -- 'tk_dispatch' | 'origen_police' | 'lb-tablet'

    keys      = 'auto',   -- 'qbx_vehiclekeys' | 'qb-vehiclekeys' | 'qs-vehiclekeys' | 'wasabi_carlock' | 'MrNewbVehicleKeys'
                          -- 'cd_garage' | 'Renewed-Vehiclekeys' | 't1ger_keys' | 'okokGarage' | 'jaksam' | false

    fuel      = 'auto',   -- 'ox_fuel' | 'LegacyFuel' | 'cdn-fuel' | 'ps-fuel' | 'lc_fuel' | 'okokGasStation'
                          -- 'Renewed-Fuel' | 'native'

    clothing  = 'auto',   -- 'illenium-appearance' | 'fivem-appearance' | 'qb-clothing' | 'esx_skin'
                          -- 'rcore_clothing' | 'native' | false (do not touch clothes)

    society   = 'auto',   -- where hospital money goes: 'esx_addonaccount' | 'qb-banking' | 'qb-management'
                          -- 'Renewed-Banking' | 'qbx_management' | 'okokBanking' | 'fd_banking' | false

    -- ═══════════════════════════════════════════════════════════════════════
    -- EXTERNAL DISPATCH
    -- Our own dispatch board, pager and call cards always work. Turn this on to
    -- ALSO send every EMS call to the dispatch/MDT script your server uses.
    -- ═══════════════════════════════════════════════════════════════════════

    externalDispatch = false,
    dispatchJobs     = nil,     -- jobs that receive the external alert (nil = Config.Jobs.medic)

    -- ═══════════════════════════════════════════════════════════════════════
    -- STANDALONE (no framework)
    -- Medics are players with the ace below:
    --   add_ace identifier.license:xxxx nza.medic allow
    --   add_ace identifier.license:xxxx nza.medic.3 allow   (grade 3, optional)
    --   add_ace identifier.license:xxxx nza.medic.boss allow (boss, optional)
    -- ═══════════════════════════════════════════════════════════════════════

    standaloneMedicAce  = 'nza.medic',
    standalonePoliceAce = 'nza.police',
    standaloneGrade     = 1,         -- grade of a medic without a nza.medic.<n> ace
    standaloneMaxGrade  = 10,        -- highest nza.medic.<n> grade that is checked
    standaloneOnDuty    = true,      -- standalone medics start on duty
    standaloneMoneyItem = 'money',   -- with ox_inventory, cash is this item
    standaloneFreeBills = true,      -- without any money system, bills are waived instead of failing

    -- ═══════════════════════════════════════════════════════════════════════
    -- ESX DUTY
    -- Older ESX servers put off-duty medics on a job called 'offambulance'.
    -- That job counts as 'ambulance' + off duty. New ESX (job.onDuty) works as is.
    -- ═══════════════════════════════════════════════════════════════════════

    offDutyPrefix = 'off',

    -- ═══════════════════════════════════════════════════════════════════════
    -- PHONE  - 911 / EMS messages and calls become dispatch calls
    -- ═══════════════════════════════════════════════════════════════════════

    phoneEmergency = {
        enabled   = true,
        numbers   = { '911', '112' },          -- numbers that reach EMS (npwd, lb-phone calls)
        companies = { 'ambulance', 'ems' },    -- lb-phone company / qs-smartphone job names that are EMS
        cooldown  = 60,                        -- seconds between two calls from the same player
        reply     = true,                      -- text the caller back "EMS received your call"
        -- Extra server events your phone fires when someone messages a job.
        -- Each entry: event name + which argument holds job, message and coords.
        -- Only add events you have checked in your phone's own files.
        events = {
            -- { event = 'qs-smartphone:server:sendJobAlert', net = true },
        },
    },

    phoneApp = {           -- app used for EMS notifications on each phone
        ['lb-phone']          = 'Services',
        ['qs-smartphone']     = 'business',
        ['qs-smartphone-pro'] = 'business',
        ['npwd']              = 'MESSAGES',
        ['yseries']           = 'services',
        ['okokPhone']         = 'services',
        ['gksphone']          = 'ems',
        ['roadphone']         = 'service',
        ['high-phone']        = 'services',
        ['renewed-phone']     = 'services',
    },

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
    -- VEHICLES
    -- ═══════════════════════════════════════════════════════════════════════

    keysDistance = 8.0,    -- server check: player must be this close to get keys

    -- ═══════════════════════════════════════════════════════════════════════
    -- ITEMS
    -- ═══════════════════════════════════════════════════════════════════════

    -- Inventories without item metadata (plain ESX) remember blood bag / X-ray
    -- data for us. It is stored per character in the resource KVP store.
    emulateMetadata = true,

    -- Item pictures: use the inventory's own image when it exists, else ours
    -- (html/img/items/<name>.png).
    preferInventoryImages = true,

    debug = false,          -- print what was detected and every adapter error
}
