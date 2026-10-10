--[[
    ███╗   ██╗███████╗    ███╗   ███╗ ██████╗ ███╗   ██╗███████╗██╗   ██╗██╗    ██╗ █████╗ ███████╗██╗  ██╗
    ████╗  ██║╚══███╔╝    ████╗ ████║██╔═══██╗████╗  ██║██╔════╝╚██╗ ██╔╝██║    ██║██╔══██╗██╔════╝██║  ██║
    ██╔██╗ ██║  ███╔╝     ██╔████╔██║██║   ██║██╔██╗ ██║█████╗   ╚████╔╝ ██║ █╗ ██║███████║███████╗███████║
    ██║╚██╗██║ ███╔╝      ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══╝    ╚██╔╝  ██║███╗██║██╔══██║╚════██║██╔══██║
    ██║ ╚████║███████╗    ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████╗   ██║   ╚███╔███╔╝██║  ██║███████║██║  ██║
    ╚═╝  ╚═══╝╚══════╝    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

    THE WASH — shared configuration
    Frameworks: ESX · QBCore · Qbox      Inventories: ox_inventory · qb-inventory (and forks)
    Targets: ox_target · qb-target · built-in fallback
]]

Config = {}

Config.Debug = false

-- 'auto' | 'esx' | 'qb' | 'qbx'
Config.Framework = 'auto'
-- 'auto' | 'ox' | 'qb'
Config.Inventory = 'auto'
-- 'auto' | 'ox' | 'qb' | 'none'  (none = built-in [E] prompt + context menu)
Config.Target = 'auto'

-- 'nui' (NAYZEEE toasts) | 'ox' (ox_lib notify)
Config.Notify = 'nui'

-- How far (metres) props are streamed in for nearby players
Config.RenderDistance = 70.0
-- Max distance the server accepts for an interaction (anti-exploit)
Config.MaxInteractDistance = 4.5
-- Seconds a player keeps a machine "reserved" mid-interaction (door open / cutting) before others can take over
Config.SessionLock = 120
-- 3D status read-out above machines (timer, state, wear)
Config.StatusText = { enabled = true, distance = 7.0 }

-- Jobs that count as police (scan, seize, dispatch). value = minimum grade
Config.PoliceJobs = { police = 0, sheriff = 0, bcso = 0, sast = 0 }
-- Jobs that can run Treasury audits on front businesses
Config.AuditJobs = { police = 3, doj = 0, government = 0, irs = 0 }

----------------------------------------------------------------------------------------------------
-- UI (NAYZEEE UI v3 tokens — every colour on the NUI is driven from here)
----------------------------------------------------------------------------------------------------
Config.UI = {
    brand    = 'THE WASH',
    subtitle = 'Off-book operations',
    version  = 'v1.0.0',
    teal     = '#08afa2',
    tealHi   = '#0fd4c4',
    tealLo   = '#067d74',
    red      = '#e5484d',
    redLo    = '#b8262b',
    amber    = '#e5a50a',
    font     = 'Lexend',
}

----------------------------------------------------------------------------------------------------
-- PROPS (from the bzzz_money pack — keep that resource started BEFORE this one)
----------------------------------------------------------------------------------------------------
Config.Props = {
    washer        = 'bzzz_money_washing_a',          -- idle washer (door animates)
    washerRunning = 'bzzz_money_washing_d',          -- washer with tumbling money (auto-animated)
    washerBlocker = 'bzzz_money_coll_transparent_box',-- invisible collision for the open door
    washerMoney   = 'bzzz_money_washing_b',          -- cash pile inside the drum
    bagFull       = 'bzzz_money_bag_b',              -- duffel full of cash
    bagEmpty      = 'bzzz_money_bag_a',              -- emptied duffel
    printerIdle   = 'bzzz_money_machine_b',
    printerRunning= 'bzzz_money_machine_a',          -- auto-animated press
    paperRoll     = 'bzzz_money_rollpaper_a',
    cutter        = 'bzzz_money_cutter_a',
    sheets        = { 'bzzz_money_moneycut_a', 'bzzz_money_moneycut_b', 'bzzz_money_moneycut_c' },
    crates        = { 'bzzz_money_crate_a', 'bzzz_money_crate_b', 'bzzz_money_crate_c' }, -- empty · paper rolls · money stacks
    palletEmpty   = 'bzzz_money_crate_a',
    palletFull    = 'bzzz_money_crate_c',
}

-- Offsets relative to each machine (taken from the prop author's reference + tuned)
-- vec4 = x, y, z, heading offset
Config.Offsets = {
    washer  = { ped = vec4(-0.380, -0.832, 0.0, -85.028), bag = vec4(0.016, -0.832, 0.0, -85.028) },
    cutter  = { ped = vec4(0.0, -0.7, 0.0, 0.0), sheet = vec3(0.0, 0.062, 0.755) },
    -- the press is 4.0 x 1.9 m (pivot centred, on the floor). Ped/sheet spots are a best guess —
    -- tune with /nzmw_offsets (Debug) if they look off
    printer = { ped = vec4(0.95, -1.25, 0.0, 0.0), paper = vec4(-2.45, -0.45, 0.31, 0.0), sheets = vec4(1.10, 0.0, 0.93, 0.0) },
}

-- Ped animations (bzzz custom dicts + vanilla)
Config.Anims = {
    openDoor   = { dict = 'bzzz_money_opendoor',   clip = 'bzzz_money_opendoor',   doorAt = 2000, total = 3500 },
    throwCash  = { dict = 'bzzz_money_washmoney',  clip = 'bzzz_money_washmoney',  total = 5000 },
    closeDoor  = { dict = 'bzzz_money_closedoor',  clip = 'bzzz_money_closedoor',  doorAt = 400,  total = 1600 },
    startWash  = { dict = 'bzzz_money_startwashing', clip = 'bzzz_money_startwashing' },
    cutting    = { dict = 'bzzz_money_cutting',    clip = 'bzzz_money_cutting',    bladeAt = 2700, bladeUp = 400 },
    machine    = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    pry        = { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop' },
    fix        = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    grab       = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab' }, -- loading the duffel at the pallet
    scan       = { dict = 'weapons@first_person@aim_rng@generic@projectile@thermal_charge@', clip = 'plant_floor' },
}

Config.PropAnims = {
    washerDict = 'bzzz_money_washing', open = 'open', close = 'close',
    cutterDict = 'bzzz_money_cutter', bladeDown = 'blade_down', bladeUp = 'blade_up',
}

-- Smoke when a machine jams
Config.JamFx = { asset = 'core', name = 'ent_amb_smoke_foundry', scale = 0.6, offset = vec3(0.0, 0.0, 1.1) }

----------------------------------------------------------------------------------------------------
-- DIRTY MONEY SOURCES
-- The washer accepts any of these. The first that the player actually holds is pre-selected.
--  type 'item'    : count = value (ox_inventory black_money style)
--  type 'worth'   : each item carries metadata[worthKey] (QBCore markedbills style)
--  type 'account' : framework account (ESX black_money)
-- heat   = how traceable this cash is at birth (0-100). Serial prefix shows up on police UV scans.
----------------------------------------------------------------------------------------------------
Config.DirtySources = {
    { key = 'markedbills', type = 'worth',   name = 'markedbills', worthKey = 'worth', label = 'Marked Bills', heat = 70, serial = 'MB', dyeChance = 0.55 },
    { key = 'black_money', type = 'item',    name = 'black_money', label = 'Dirty Cash',   heat = 45, serial = 'DC', dyeChance = 0.30 },
    { key = 'esx_black',   type = 'account', name = 'black_money', label = 'Dirty Cash',   heat = 45, serial = 'DC', dyeChance = 0.30, frameworks = { esx = true } },
}

----------------------------------------------------------------------------------------------------
-- THE PIPELINE  (washer → printer → cutter → the books)
-- Disable printer/cutter for a shorter loop; the washer is always stage one.
----------------------------------------------------------------------------------------------------
Config.Stages = {
    washer = {
        enabled     = true,
        label       = 'Washer',
        outputItem  = 'nzmw_wet_cash',
        min         = 1000,
        max         = 60000,
        baseTime    = 75,     -- seconds
        perThousand = 2.0,    -- extra seconds per $1,000
        heatDrop    = 20,     -- heat removed by a wash (hot adds +10)
        wearPerRun  = 4.0,
        solventItem = 'nzmw_solvent', -- optional: neutralises dye, +quality
    },
    printer = {
        enabled     = true,
        label       = 'Re-Serial Press',
        outputItem  = 'nzmw_cash_sheets',
        paperItem   = 'nzmw_paper_roll',
        paperPer    = 20000,  -- one roll per $20k (rounded up)
        baseTime    = 60,
        perThousand = 1.2,
        heatDrop    = 45,     -- the press re-serialises bills → serial trail is broken
        wearPerRun  = 5.0,
    },
    cutter = {
        enabled     = true,
        label       = 'Guillotine',
        outputItem  = 'nzmw_cash_stacks',
        cuts        = 3,      -- matches moneycut_a → b → c
        minInterval = 2.4,    -- seconds between cuts (server enforced)
        wearPerRun  = 2.0,
    },
}

-- Washer cycle program. Ideal temp depends on how stained the bills are.
Config.Wash = {
    temps = {
        cold = { label = 'Cold', heatBonus = 0 },
        warm = { label = 'Warm', heatBonus = 5 },
        hot  = { label = 'Hot',  heatBonus = 10 },
    },
    spins = {
        low  = { label = 'Low',  time = 1.30, noise = 0.5, jam = 0.7 },
        med  = { label = 'Med',  time = 1.00, noise = 1.0, jam = 1.0 },
        high = { label = 'High', time = 0.70, noise = 1.8, jam = 1.6 },
    },
    -- dye level → ideal temp
    dyeBands = {
        { max = 24,  key = 'light',  label = 'Speckled',       ideal = 'cold' },
        { max = 59,  key = 'medium', label = 'Ink bleed',      ideal = 'warm' },
        { max = 100, key = 'heavy',  label = 'Dye-pack burst', ideal = 'hot'  },
    },
    penaltyOneOff = 0.06,  -- quality lost when temp is one step off
    penaltyTwoOff = 0.15,
    solventBonus  = 0.05,  -- quality gained when solvent is used (also halves dye)
}

-- Quality modifiers from the cutter minigame
Config.Cut = { perfect = 0.025, good = 0.0, miss = -0.06 }

-- Quality clamp (1.0 = face value before market rate)
Config.Quality = { min = 0.40, max = 1.12 }

----------------------------------------------------------------------------------------------------
-- MACHINE WEAR & JAMS
----------------------------------------------------------------------------------------------------
Config.Wear = {
    jamBase     = 0.06,   -- jam chance per cycle at 0% wear
    jamPerWear  = 0.0045, -- + per 1% wear  (100% wear ≈ 51% jam chance)
    failPenalty = 0.05,   -- quality lost per failed unjam attempt
    repairItem  = 'nzmw_repair_kit',
    repairTo    = 0,      -- wear after a repair
    kitEasier   = true,   -- unjam skill-check is easier with a repair kit
}

----------------------------------------------------------------------------------------------------
-- HEAT, TRACE & POLICE
----------------------------------------------------------------------------------------------------
Config.Heat = {
    payoutPenaltyMax = 0.25, -- at 100 heat you lose 25% at the books
    scannerItem      = 'nzmw_uv_scanner', -- police tool (target a player / a machine)
    alertBase        = 0.05, -- chance a running cycle draws a 911 call
    alertPerHeat     = 0.004,
    minPolice        = 0,    -- required police on duty to start any machine
}

-- Thieves can pry open someone else's running / finished machine
Config.Theft = {
    enabled      = true,
    items        = { 'weapon_crowbar', 'WEAPON_CROWBAR', 'crowbar' }, -- any one of these works (ox uses upper-case weapon names)
    duration     = 9000,
    runningPenalty = 0.20, -- quality lost when ripped out mid-cycle (and no heat drop)
    alertChance  = 0.65,
    notifyOwner  = true,
}

----------------------------------------------------------------------------------------------------
-- MONEY PALLET
-- A finished load nobody comes back for gets moved onto the operation's pallet, so the machine
-- frees up. The pallet shows stacks of money while it holds anything; load it into a duffel to take it.
----------------------------------------------------------------------------------------------------
Config.Pallet = {
    enabled      = true,
    label        = 'Money Pallet',
    moveAfter    = 180,   -- seconds a finished load waits in the machine…
    ownerRadius  = 15.0,  -- …and only moves if its owner isn't this close
    capacity     = 10,    -- loads per pallet
    loadTime     = 6000,  -- ms to fill the duffel
    theft        = true,  -- people without access can grab one load
    theftTime    = 12000,
    theftAlert   = 0.5,   -- chance a grab calls the police
}

----------------------------------------------------------------------------------------------------
-- CREW LINE BONUS
-- Different people running consecutive stations within the window = assembly-line bonus.
----------------------------------------------------------------------------------------------------
Config.Crew = { enabled = true, perMember = 0.05, cap = 0.15, windowMinutes = 45 }

----------------------------------------------------------------------------------------------------
-- DYNAMIC WASH MARKET (city-wide rate, reacts to how much is being laundered)
----------------------------------------------------------------------------------------------------
Config.Market = {
    base          = 0.78,
    min           = 0.50,
    max           = 0.92,
    saturationAt  = 400000, -- $ laundered in the window that applies the full saturation drop
    saturationMax = 0.18,
    windowMinutes = 60,
    historyEvery  = 5,      -- minutes between chart points
    historyPoints = 24,
    eventEvery    = 30,     -- minutes between event rolls
    eventChance   = 0.45,
    events = {
        { label = 'Treasury crackdown',   mod = -0.10, minutes = 30, note = 'Banks are filing SARs on everything.' },
        { label = 'Casino weekend',       mod =  0.06, minutes = 40, note = 'Chips and cash everywhere — easy cover.' },
        { label = 'Crypto rush',          mod =  0.04, minutes = 25, note = 'Everyone is moving money, nobody looks twice.' },
        { label = 'Federal task force',   mod = -0.14, minutes = 20, note = 'FIB auditors are in town.' },
        { label = 'Tax season',           mod = -0.05, minutes = 45, note = 'Accountants are paying attention.' },
        { label = 'Cash-heavy festival',  mod =  0.08, minutes = 30, note = 'Vendors are banking stacks of small bills.' },
    },
}

----------------------------------------------------------------------------------------------------
-- COOK THE BOOKS + CLEARING HOUSE + TREASURY AUDITS
----------------------------------------------------------------------------------------------------
Config.Books = {
    instantFee     = 0.12,  -- "Cash out now" fee (vs clearing)
    instantAccount = 'cash',
    clearingAccount= 'bank',
    clearingMinutes= 20,    -- clean money lands after this delay
    clearingTick   = 30,    -- seconds between clearing payouts
    -- suspicion weights
    wDeviation     = 0.60,
    wOverCap       = 1.20,
    wHeat          = 0.35,
    wRecentFlags   = 0.10,  -- per flagged entry on this front in the last 24h
}

Config.Audit = {
    base         = 0.02,
    scale        = 0.55,    -- audit chance = base + suspicion * scale
    durationMin  = 25,      -- front stays under audit (books closed) for this long
    seizePct     = 0.40,    -- pending clearings on an audited front lose this share
    flagAt       = 0.45,    -- suspicion above this flags the ledger entry
    notifyJobs   = true,
}

----------------------------------------------------------------------------------------------------
-- PLAYER-PLACED EQUIPMENT
----------------------------------------------------------------------------------------------------
Config.Placement = {
    enabled      = true,
    kits         = { washer = 'nzmw_washer_kit', printer = 'nzmw_printer_kit', cutter = 'nzmw_cutter_kit', counter = 'nzmw_counter_kit' },
    -- 'unit'  : kits only work inside a wash unit (recommended — see Config.Facility)
    -- 'world' : kits work anywhere indoors (old behaviour)
    -- 'both'  : either
    mode         = 'unit',
    maxPerPlayer = 6,
    interiorOnly = true,     -- must be inside an interior (MLO / shell)
    minSpacing   = 1.4,      -- metres from other machines
    maxDistance  = 6.0,
    share        = 'gang',   -- 'gang' | 'job' | 'none' → who besides the owner can use placed machines
    blacklist    = {         -- no-build zones (centre, radius)
        { coords = vec3(441.0, -982.0, 30.7), radius = 80.0 },   -- MRPD
        { coords = vec3(298.0, -584.0, 43.3), radius = 60.0 },   -- Pillbox
    },
}

-- Item labels used by the NUI (the actual items are defined in your inventory, see README)
Config.ItemLabels = {
    nzmw_wet_cash    = 'Wet Cash',
    nzmw_cash_sheets = 'Uncut Sheets',
    nzmw_cash_stacks = 'Clean Stacks',
    nzmw_paper_roll  = 'Press Paper Roll',
    nzmw_solvent     = 'Dye Solvent',
    nzmw_repair_kit  = 'Machine Repair Kit',
    nzmw_uv_scanner  = 'UV Serial Scanner',
    nzmw_washer_kit  = 'Industrial Washer (crate)',
    nzmw_printer_kit = 'Print Press (crate)',
    nzmw_cutter_kit  = 'Guillotine (crate)',
    nzmw_counter_kit = 'Money Counter (crate)',
}

----------------------------------------------------------------------------------------------------
-- MONEY COUNTER
-- A counting machine on a small table with a live digital screen (DUI) everyone nearby can read.
--  · Count stacks: banded Clean Stacks come out strapped & counted → worth more at the books
--  · Count cash  : shows your clean cash and dirty money on the screen (roleplay)
----------------------------------------------------------------------------------------------------
Config.Counter = {
    label       = 'Money Counter',
    model       = 'bkr_prop_money_counter',   -- GTA biker DLC counting machine
    table       = 'prop_table_03',            -- set false if the counter sits on an existing desk (coords = desk top)
    bonus       = 0.03,                       -- counted stacks are worth +3% at the books
    baseTime    = 4,                          -- seconds
    perSecond   = 25000,                      -- $ counted per second on top of the base
    maxTime     = 20,
    resultTime  = 10,                         -- seconds the total stays on the screen
    screen      = { width = 0.34, height = 0.17, lift = 0.12 }, -- metres; floats just above the front edge
    drawDistance= 8.0,
    sounds      = {
        tick   = { name = 'LOCAL_PLYR_CASH_COUNTER_INCREASE', set = 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', every = 110 },
        finish = { name = 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', set = 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS' },
    },
    -- operator animation (biker cash factory counting). Falls back to Config.Anims.machine if missing.
    anim        = { dict = 'anim@amb@business@cfm@cfm_counting_notes@', clip = 'note_counting_v2_counter' },
    -- banknote flicks out of the machine while it runs (set false to disable)
    fx          = { asset = 'core', name = 'ent_brk_banknotes', scale = 0.35, every = 650 },
}

----------------------------------------------------------------------------------------------------
-- WASH UNITS (private floors)
-- GTA's counterfeit cash factory interior with every piece of its own equipment switched off.
-- Each unit is its own routing bucket: crews only ever see their own floor and machines.
----------------------------------------------------------------------------------------------------
Config.Facility = {
    enabled     = true,
    price       = 250000,         -- one-off lease, paid from the bank
    maxOwned    = 1,
    bucketBase  = 7100,           -- unit #12 lives in routing bucket 7112
    baseSlots   = 6,              -- machines a unit can hold before expanding
    -- door players use to reach their unit (the laundromat's back room by default)
    entrance    = vec4(887.65, -1037.26, 34.25, 90.0),
    interior    = {
        ipl    = 'bkr_biker_interior_placement_interior_5_biker_dlc_int_ware04_milo',
        coords = vec3(1121.897, -3195.338, -40.4025),
        inside = vec4(1138.09, -3198.97, -39.67, 90.0), -- where you appear / the exit + terminal
        -- everything GTA puts in the factory; all switched off so crews build their own floor
        sets   = {
            'counterfeit_low_security', 'counterfeit_security', 'counterfeit_setup',
            'counterfeit_standard_equip', 'counterfeit_standard_equip_no_prod',
            'counterfeit_upgrade_equip', 'counterfeit_upgrade_equip_no_prod',
            'dryera_off', 'dryera_on', 'dryera_open', 'dryerb_off', 'dryerb_on', 'dryerb_open',
            'dryerc_off', 'dryerc_on', 'dryerc_open', 'dryerd_off', 'dryerd_on', 'dryerd_open',
            'money_cutter', 'special_chairs',
        },
        cashPiles = true,         -- also switch off counterfeit_cashpile10a … 100d
    },
    upgrades = {
        soundproof = { label = 'Soundproofing', desc = 'Foam walls and rubber mounts. Each level cuts 911 calls from machines by 35%.', max = 2, price = { 60000, 120000 } },
        expansion  = { label = 'Floor expansion', desc = 'Clear the back of the warehouse. Each level adds 2 machine slots.', max = 2, price = { 80000, 160000 } },
        alarm      = { label = 'Door alarm', desc = 'Silent alarm on the door. The whole crew is warned the moment police breach.', max = 1, price = { 45000 } },
    },
    -- supplies the terminal can order (paid from the bank, delivered to your pockets)
    shop = {
        { key = 'paper',   item = 'nzmw_paper_roll',  amount = 5, price = 2500,   label = 'Paper rolls ×5',      desc = 'Feeds the re-serial press.' },
        { key = 'solvent', item = 'nzmw_solvent',     amount = 3, price = 4500,   label = 'Dye solvent ×3',      desc = 'Lifts dye-pack ink in the wash.' },
        { key = 'repair',  item = 'nzmw_repair_kit',  amount = 1, price = 6000,   label = 'Repair kit',          desc = 'Resets a machine\'s wear.' },
        { key = 'washer',  item = 'nzmw_washer_kit',  amount = 1, price = 35000,  label = 'Industrial washer',   desc = 'Crate. Use it inside the unit to set it up.' },
        { key = 'printer', item = 'nzmw_printer_kit', amount = 1, price = 60000,  label = 'Re-serial press',     desc = 'Crate. Use it inside the unit to set it up.' },
        { key = 'cutter',  item = 'nzmw_cutter_kit',  amount = 1, price = 25000,  label = 'Guillotine',          desc = 'Crate. Use it inside the unit to set it up.' },
        { key = 'counter', item = 'nzmw_counter_kit', amount = 1, price = 18000,  label = 'Money counter',       desc = 'Crate. Straps your stacks for a better rate.' },
    },
    breachTime  = 10000,          -- ms police spend forcing the door
    flagMinutes = 30,             -- how long a 911 call keeps a unit on the police list
}
