--[[
  nayzeee-garages — built-in car lock, crime tools, contracts, fake plates and impound tow.
  Shared config (loaded on server AND client): do not put secrets here.
  Design and APIs: docs/CARLOCK.md. Integration files: docs/INTEGRATIONS.md.
]]

Config.CarLock = {
  -- Master switch. When false nothing in this file is used and Config.Integrations.keys picks
  -- an external keys resource as before.
  enabled = true,

  -- 'auto' = physical keys when an inventory with item metadata is detected, else virtual keys
  -- 'physical' = plate-specific key / fob items (falls back to virtual without an inventory)
  -- 'virtual' = no items, keys live on the server (give-key and management menus)
  keyMode = 'auto',

  -- Owners, players a vehicle is shared with and job / gang fleet members always have a key.
  -- nil = true in virtual mode, false in physical mode (they need the key item).
  ownerHasKey = nil,

  -- Physical mode: give a key item on garage retrieval when the player has no valid key.
  giveKeyOnRetrieve = true,

  -- Key items are signed by the server (metadata `sig`), so keys edited or forged through an
  -- inventory never open anything. true = also accept key items without a signature (given by
  -- other scripts or inventory admin commands with just a `plate`): anyone able to write item
  -- metadata can then make keys. Prefer exports['nayzeee-garages']:GiveKeyItem(src, plate).
  trustUnsignedKeys = false,

  -- Short notification after locking / unlocking ("Vehicle locked").
  lockNotify = true,

  -- Temporary keys (hotwire, robbery, admin, other scripts, spawners) expire after this many hours.
  tempKeyHours = 24,

  -- Listen to the events other scripts use to give keys with other key resources
  -- (bridge/server/listeners.lua, bridge/client/listeners.lua). Only for key resources that
  -- are NOT running. Client-side events can only ever give a temporary key to a vehicle the
  -- player sits in or stands next to.
  compat = true,
  -- Also answer exports['qb-vehiclekeys'] / qbx_vehiclekeys / wasabi_carlock / MrNewbVehicleKeys /
  -- qs-vehiclekeys / Renewed-Vehiclekeys / vehicles_keys calls of other scripts while those
  -- resources are not running (restart the calling scripts after restarting this one).
  compatExports = true,
  -- false = other scripts' CLIENT events may only give keys to script-spawned vehicles (job /
  -- rental / mission cars), never to parked or driving NPC cars (stops a cheater from skipping
  -- lockpicking with a fake event). Server-side calls are always trusted.
  compatAmbient = false,

  -- Virtual mode: how many players an owner can give a persistent key of one vehicle.
  maxVirtualKeys = 10,

  items = {
    key = 'vehicle_key',
    fob = 'vehicle_fob',
    blank = 'key_blank',
    lockpick = 'lockpick',
    advancedLockpick = 'advancedlockpick',
    screwdriver = 'screwdriver',
    hackingDevice = 'hacking_device',
    fakePlate = 'fake_plate',
    contract = 'vehicle_contract',
    signedContract = 'signed_contract',
  },

  keys = {
    lock = 'L',            -- toggle the lock of your vehicle / the nearest vehicle you have a key for
    engine = 'G',          -- toggle the engine (driver seat)
    keyRing = 'F7',        -- open the key ring
  },

  commands = {
    lock = 'lock',
    engine = 'engine',
    keyRing = 'keys',
    giveKey = 'givekey',   -- admin: /givekey [playerId] -> key for the vehicle that player (or you) sits in
  },

  -- Groups / aces allowed to use the admin command (besides NZ.Access.isAdmin).
  adminGroups = { 'admin', 'god', 'superadmin' },

  ranges = {
    key = 5.0,             -- metres: key in pocket
    fob = 30.0,            -- metres: electronic fob (high-end profile)
    give = 3.0,            -- metres: hand a key to another player
    compat = 8.0,          -- metres: another script's client event gives keys to a vehicle this close
  },

  animation = {
    enabled = true,
    dict = 'anim@mp_player_intmenu@key_fob@',
    name = 'fob_click',
    prop = 'lr_prop_carkey_fob', -- held while clicking ('' = none; prop_cuff_keys_01 when missing)
    duration = 900,
  },

  sound = {
    enabled = true,
    lock = { name = 'Remote_Control_Close', set = 'PI_Menu_Sounds' },
    unlock = { name = 'Remote_Control_Open', set = 'PI_Menu_Sounds' },
    flashLights = true,
    hornChirp = true,
  },

  ignition = {
    requireKey = true,
    -- No key needed for these classes (13 = cycles) / models / jobs on duty in their job vehicles.
    bypassClasses = { 13 },
    bypassModels = {},
    bypassJobVehicles = true,
    -- Engine stays on when you leave the driver seat (hold the exit key briefly to turn it off).
    keepEngineRunning = true,
    -- true = a vehicle whose engine already runs can be driven without a key (a car left running).
    -- false = the engine stops for drivers without a key (rob the driver or hotwire instead).
    allowRunningEngine = false,
  },

  --[[
    Security profiles. A vehicle uses the profile of its model override, else its class, else
    'standard'. Each profile picks the key item, the access tools that open its doors, the
    hotwire method and whether it carries a tracker.
  ]]
  profiles = {
    standard = {
      label = 'Standard',
      keyItem = 'key',                 -- items.key
      remote = false,                  -- remote locking from ranges.fob
      accessTools = {
        { item = 'lockpick', difficulty = { 'easy', 'easy', 'medium' }, breakChance = 25, alarmChance = 40, alertChance = 30 },
        { item = 'screwdriver', difficulty = { 'medium', 'medium', 'medium' }, breakChance = 10, alarmChance = 60, alertChance = 40 },
        { item = 'advancedLockpick', difficulty = { 'easy', 'easy' }, breakChance = 5, alarmChance = 20, alertChance = 20 },
      },
      hotwire = { method = 'skillcheck', difficulty = { 'easy', 'medium', 'medium' }, duration = 6000, alertChance = 25 },
      tracker = false,
      alarm = 'native',                -- 'native' | 'custom' | 'none'
    },
    highend = {
      label = 'High-end',
      keyItem = 'fob',                 -- items.fob
      remote = true,
      accessTools = {
        { item = 'advancedLockpick', difficulty = { 'medium', 'hard', 'hard' }, breakChance = 15, alarmChance = 80, alertChance = 70 },
        { item = 'hackingDevice', difficulty = { 'medium', 'medium', 'hard', 'hard' }, breakChance = 0, alarmChance = 40, alertChance = 50 },
      },
      hotwire = { method = 'hack', item = 'hackingDevice', difficulty = { 'medium', 'hard', 'hard', 'hard' }, duration = 9000, alertChance = 60 },
      tracker = true,
      alarm = 'custom',
    },
  },
  -- GTA vehicle classes: 0 compacts 1 sedans 2 SUVs 3 coupes 4 muscle 5 sports classics
  -- 6 sports 7 super 8 motorcycles 9 off-road 10 industrial 11 utility 12 vans 13 cycles
  -- 14 boats 15 helicopters 16 planes 17 service 18 emergency 19 military 20 commercial 22 open wheel
  profileByClass = { [6] = 'highend', [7] = 'highend', [15] = 'highend', [16] = 'highend' },
  profileByModel = {
    -- ['sultanrs'] = 'standard',
  },

  -- No-key driver flow: search the vehicle once for a chance at money, items or a spare key.
  search = {
    enabled = true,
    duration = 7000,
    alertChance = 10,
    money = { chance = 35, min = 20, max = 250, account = 'cash' },
    spareKeyChance = 8,
    items = {
      { item = 'water', chance = 20, min = 1, max = 2 },
      { item = 'phone', chance = 3, min = 1, max = 1 },
    },
  },

  npc = {
    robbery = true,
    robTime = 3500,              -- ms aiming before they hand the key over
    maxSpeed = 8.0,              -- m/s: faster drivers ignore you
    resistChance = 20,           -- % they flee with the car or fight back
    fightChance = 35,            -- % of resisting drivers that fight instead of fleeing
    deadDriverKeys = true,       -- search the body of the original driver for the key
    alertChance = 60,
    cooldown = 60,               -- seconds between robberies per player
    -- Players with these jobs can ask NPC drivers for their vehicle (no robbery, no alert).
    assistJobs = { 'police', 'sheriff', 'state' },
  },

  locksmiths = {
    {
      name = 'Los Santos Locksmith',
      coords = vec4(170.58, -1799.68, 29.32, 320.0),
      ped = 's_m_m_autoshop_01',
      blip = { enabled = true, sprite = 134, color = 3, scale = 0.7 },
      illegal = false,
      alertChance = 0,
      services = {
        duplicate = { enabled = true, price = 250, materials = {} },
        program = { enabled = true, price = 500, materials = { { item = 'blank', count = 1 } } },
        rekey = { enabled = true, price = 1500, materials = {} },
      },
    },
    {
      name = 'Back-alley Keys',
      coords = vec4(1186.32, -3263.45, 6.03, 90.0),
      ped = 'g_m_y_mexgoon_02',
      blip = { enabled = false },
      illegal = true,              -- programs keys for any vehicle within range
      alertChance = 15,
      services = {
        duplicate = { enabled = true, price = 600, materials = {} },
        program = { enabled = true, price = 3500, materials = {} },
        rekey = { enabled = false, price = 0, materials = {} },
      },
    },
  },
  locksmithAccount = 'cash',       -- 'cash' | 'bank'

  tracker = {
    enabled = true,
    alarmSeconds = 20,             -- remote alarm length
  },

  dispatch = {
    -- 'auto' | 'wasabi_mdt' | 'ps-dispatch' | 'cd_dispatch' | 'rcore_dispatch' | 'internal' | 'none' | 'custom'
    system = 'auto',
    jobs = { 'police', 'sheriff', 'state' },
    blip = { sprite = 225, color = 1, scale = 1.0, seconds = 90 },
    codes = { theft = '10-60', robbery = '10-31', alarm = '10-66', locksmith = '10-31', fakeplate = '10-28' },
  },

  alarm = {
    seconds = 25,                  -- custom alarm length
  },
}

-- Impound: an NPC flatbed tow truck collects vehicles impounded with the impound form
-- (/impound or the target option). The database impound happens at once; the tow is only
-- visual. When anything goes wrong (no road nearby, stuck, nobody left to run it, timeout)
-- the vehicle is deleted instead, as without the tow truck. Vehicles somebody sits in,
-- boats, aircraft and vehicles too big for the bed are deleted at once (no tow).
Config.Tow = {
  enabled = true,
  truck = 'flatbed',
  driver = 's_m_m_trucker_01',
  plate = 'IMPOUND',               -- plate text of the tow truck (8 characters at most, '' = random)
  spawnDistance = { min = 80.0, max = 150.0 }, -- metres from the vehicle, on a road, out of sight when possible
  timeout = 150,                   -- seconds before falling back to deleting the vehicle
  loadSeconds = 6,                 -- the driver works the bed controls while the vehicle is pulled on
  speed = 14.0,                    -- m/s on the way to the vehicle and when leaving (about 50 km/h)
  drivingStyle = 786603,           -- law-abiding (786469 = goes around traffic and ignores lights)
  despawnDistance = 150.0,         -- after loading: removed once every player is farther than this ...
  despawnSeconds = 60,             -- ... or after this many seconds
  maxActive = 6,                   -- tow trucks at the same time (more impounds delete the vehicle at once)
  -- Too big for the bed: deleted at once (no tow). Metres, from the model dimensions.
  maxSize = { length = 6.9, width = 2.9, height = 3.4 },
  -- Never towed (GTA classes): 10 industrial, 14 boats, 15 helicopters, 16 planes,
  -- 19 military, 20 commercial, 21 trains.
  skipClasses = { 10, 14, 15, 16, 19, 20, 21 },
  -- Where the vehicle sits on the bed (metres, relative to the truck bone): `y` = centre of the
  -- bed, `rear` = its rear edge (the vehicle is pulled on from there). The bed height is
  -- measured on the truck when possible; `surface` is the fallback. Tune for add-on trucks.
  bed = { bone = 'bodyshell', y = -2.35, surface = 0.55, rear = -6.0 },
  animation = { dict = 'amb@prop_human_atm@male@idle_a', clip = 'idle_b' }, -- the driver at the bed controls
  -- Blip on the tow truck for the impounding officer while it is on its way.
  blip = { enabled = true, sprite = 68, color = 17, scale = 0.8 },
}

-- Car sale contracts.
Config.Contracts = {
  enabled = true,
  maxDistance = 10.0,              -- buyer and vehicle within this range of the seller
  expireSeconds = 120,
  account = 'bank',                -- buyer pays from 'bank' | 'cash'
  signedCopies = true,             -- both parties keep a signed_contract item
  maxPrice = 10000000,
}

-- Fake plates.
Config.FakePlates = {
  enabled = true,
  requireScrewdriver = true,
  screwdriverBreakChance = 5,
  installSeconds = 6,
  removeSeconds = 5,
  returnOnStore = true,            -- storing in a garage removes the fake plate and returns the item
  pattern = '11AAA111',            -- 1 = digit, A = letter
  alertChance = 0,
}
