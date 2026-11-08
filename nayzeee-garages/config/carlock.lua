--[[
  nayzeee-garages — built-in car lock, crime tools, contracts, fake plates and impound tow.
  Shared config (loaded on server AND client): do not put secrets here.
  Design and APIs: docs/CARLOCK.md. Integration files: docs/INTEGRATIONS.md.
]]

Config.CarLock = {
  -- Master switch. When false nothing in this file is used and Config.Integrations.keys picks
  -- an external keys resource as before. With Config.Integrations.keys = 'auto' the built-in
  -- car lock also stays off while another key resource runs (qbx_vehiclekeys, qb-vehiclekeys,
  -- wasabi_carlock, MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys, vehicles_keys):
  -- remove that resource, or set Config.Integrations.keys = 'nayzeee' to force this one.
  enabled = true,

  -- Key mode (docs/CARLOCK.md §1). Admins can change it in game (key settings, tab Keys).
  -- 'flexible' (default) = key / fob items. Garage retrieval reuses a key you carry or that
  --              is stored in that vehicle's glovebox / trunk, else cuts one
  --              (giveKeyOnRetrieve). Sharing gives the other player a COPY: you keep yours.
  -- 'limited'  = key / fob items, a fixed starting set per vehicle (limitedKeys, default 2).
  --              Sharing hands YOUR copy over. Retrieval gives no free copy while a copy of
  --              the current locks exists anywhere (a pocket, a stash, the ground); the set
  --              is issued again only when none is left. Locksmiths still cut paid copies.
  -- 'virtual'  = no items: the server issues access (garage hand-out, key ring). Sharing
  --              gives the other player access: you keep yours.
  -- Older values: 'physical' and 'auto' mean 'flexible'. Without an inventory that stores
  -- item metadata (or without the key items defined in it) item modes fall back to virtual.
  keyMode = 'flexible',

  -- 'limited' mode: keys in the starting set of each vehicle (1-10).
  limitedKeys = 2,

  -- Sharing (key ring "Share"). maxKeys: copies of one vehicle's current locks that may exist
  -- ('flexible': a share fails beyond it). hours: 0 = virtual shares stay until revoked,
  -- else they are temporary keys of that many hours.
  sharing = { maxKeys = 10, hours = 0 },

  -- Which car the lock key / L picks when several of yours are in range:
  -- 'nearest' | 'owned' (your own vehicles first) | 'last' (the one you used last, then nearest).
  lockPrefer = 'nearest',

  -- Key fob designs the key ring / fob HUD can draw (the UI wave adds the renders).
  fob = { defaultDesign = 'classic', designs = { 'classic', 'slim', 'card', 'sport', 'retro' } },

  -- Keyless entry / exit (fob keys only: a key item of kind 'fob', or a virtual / owner key of a
  -- vehicle whose profile uses a fob). With the fob on you a locked car unlocks as you get in
  -- (server check); walking away locks it again once you are farther than YOUR distance
  -- (player settings, clamped to minDistance-maxDistance; the server measures and locks).
  keyless = { enabled = true, minDistance = 3.0, maxDistance = 30.0, enterRange = 3.5 },

  -- Keys on the ground (dropped, thrown and missed, tossed out of a window, dropped by a robbed
  -- NPC): world props anyone can pick up. removeAfter: minutes before an untouched key is
  -- gone (0 = never). persist: keep them across a server restart (database), else only across
  -- a resource restart. marker: what players see above a key on the ground.
  ground = {
    enabled = true,
    animateDrops = true,
    persist = false,
    removeAfter = 30,
    pickupRange = 2.0,             -- metres (server ped to the key)
    throwRange = 8.0,              -- metres: throw a key to a player at most this far
    catchWindow = 1800,            -- ms the other player has to catch it (missed -> on the ground)
    props = { key = 'p_car_keys_01', fob = 'lr_prop_carkey_fob' },
    marker = { style = 'chevron', color = '#2dd4bf', size = 0.25, height = 0.35 },
    maxPerPlayer = 10,             -- keys one player may have lying around at once
  },

  -- Immobilisers (per vehicle, stored per plate): 'none' | 'standard' (no hotwiring) | 'ghost'
  -- (a four-digit PIN before the engine starts, even with the keys; no remote start). Installed
  -- with the items below (owner, standing at the vehicle) or at a locksmith (services
  -- immobiliser / ghost; items.immobiliser / items.ghostImmobiliser). The PIN is stored hashed
  -- with the key secret.
  immobiliser = {
    enabled = true,
    pinAttempts = 3,               -- wrong PINs in a row before the alarm + cooldown
    pinCooldown = 120,             -- seconds without PIN attempts after that
    pinSession = 600,              -- seconds a correct PIN stays valid for that driver and vehicle
  },

  -- Lock picking (doors). style 'skillcheck' = ox_lib skill checks of the profile's tool;
  -- 'pins' = the five-pin lock of the NUI (pins, snapChance % per overset, alarmOnSnap).
  -- The NUI minigames are only used when the player's client says it can play them; until
  -- then the server falls back to skill checks (lockpick) / the profile's method (hotwire).
  -- The fallback only changes the minigame: the signal reader / hotwire kit stays required.
  lockpicking = { style = 'skillcheck', pins = 5, snapChance = 35, alarmOnSnap = true },

  -- Hotwiring (NUI minigames, docs/CARLOCK.md §8). style 'profile' = each security profile's
  -- hotwire method (skill checks / progress / hack); 'wires' = splice three pairs of wires
  -- (kitRequired: needs items.hotwireKit), except readerClasses (only read with style 'wires'),
  -- which need items.signalReader (tune frequency / phase). Model overrides work with either
  -- style: readerModels always use the reader, wireModels always use wires.
  hotwiring = {
    style = 'profile',
    kitRequired = false,
    readerClasses = { 6, 7 },
    readerModels = {},
    wireModels = {},
  },

  -- Job vehicles: temporary keys of job spawner vehicles last this many hours (0 = tempKeyHours).
  jobVehicles = { keyHours = 0 },

  -- Per-player settings (each player changes theirs; these are the defaults).
  playerDefaults = {
    keylessUnlock = true,          -- a locked car unlocks as you get in with its fob
    keylessLock = true,            -- walking away locks it again
    keylessDistance = 10.0,        -- metres
    engineOnEnter = false,         -- start the engine as you sit down (with a key)
    keepEngineRunning = true,      -- the engine keeps running when you get out
    fobBeep = true,
    hints = true,
    fobPosition = { x = 0.86, y = 0.72, scale = 1.0 }, -- fob HUD (share of the screen)
    keyOrder = 'recent',           -- 'recent' | 'name' | 'plate' | 'distance'
    combinedKeyring = true,        -- new keys go on the one key ring
    groundPrompts = true,          -- show the pick-up prompt at keys on the ground
    units = 'metric',              -- 'metric' | 'imperial'
    alertLock = true,
    alertEngine = true,
    alertShare = true,
    shareRecall = true,            -- remind me of keys I shared
  },

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
  -- Qbox without qbx_vehiclekeys: keep compat and compatExports on; qbx_core (/car, vehicle
  -- persistence), qbx_vehicleshop and qbx_police call exports.qbx_vehiclekeys unconditionally
  -- and throw "No such export" without them.
  compat = true,
  -- Also answer exports['qb-vehiclekeys'] / qbx_vehiclekeys / wasabi_carlock / MrNewbVehicleKeys /
  -- qs-vehiclekeys / Renewed-Vehiclekeys / vehicles_keys calls of other scripts while those
  -- resources are not running (restart the calling scripts after restarting this one).
  compatExports = true,
  -- false = other scripts' CLIENT events may only give keys to script-spawned vehicles (job /
  -- rental / mission cars), never to parked or driving NPC cars (stops a cheater from skipping
  -- lockpicking with a fake event). Server-side calls are always trusted.
  compatAmbient = false,
  -- exports['nayzeee-garages']:GiveKey(vehicle) on the CLIENT (other scripts' client code asks
  -- the server for a temporary key of a vehicle the player sits in / stands next to, same
  -- rules as compat events). false = closed (with compat = false nothing client-side can ask
  -- for a key any more).
  clientGiveKeyExport = true,

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
    immobiliser = 'immobiliser',           -- installs a standard immobiliser (owner, at the vehicle)
    ghostImmobiliser = 'ghost_immobiliser', -- installs a Ghost immobiliser (PIN)
    hotwireKit = 'hotwire_kit',            -- hotwiring.kitRequired (wires)
    signalReader = 'signal_reader',        -- hotwiring readerClasses / readerModels
  },

  keys = {
    lock = 'L',            -- toggle the lock of your vehicle / the nearest vehicle you have a key for
    engine = 'G',          -- toggle the engine (driver seat)
    keyRing = 'F7',        -- open the key ring
    hotwire = 'H',         -- no-key driver: hotwire the vehicle
    search = 'Z',          -- no-key driver: search the vehicle (once)
  },

  commands = {
    lock = 'lock',
    engine = 'engine',
    keyRing = 'keys',
    giveKey = 'givekey',   -- admin: /givekey [playerId] -> key for the vehicle that player (or you) sits in
    keyAdmin = 'vehiclekeysadmin', -- admin: key manager (players' keys, custody, give / delete) and key settings
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
    -- the beep only the player who pressed the fob hears (their 'Fob beep' setting); check in game
    fob = { name = 'Remote_Control_Fob', set = 'PI_Menu_Sounds' },
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

    accessTools: items that open the locked doors (use the item standing at the vehicle and
    facing it, or the "Pick the lock" target option). item = a Config.CarLock.items entry (or
    an item name).
      difficulty   ox_lib skill checks, one entry per check: 'easy' | 'medium' | 'hard' or
                   { areaSize = 50, speedMultiplier = 1.5 }
      inputs       keys of the skill checks, e.g. { 'w', 'a', 's', 'd' } (nil = ox_lib's 'E')
      breakChance  % the tool breaks on a failed attempt
      alarmChance  % the alarm goes off on a failed attempt
      alertChance  % the police get an alert (every attempt, success or not)
    hotwire: the no-key driver flow (driver seat, no key). method:
      'skillcheck' skill checks (difficulty, inputs)
      'progress'   a progress bar of `duration` ms
      'hack'       skill checks + the `item` in the inventory (breakChance: % it breaks on a
                   failed attempt)
      alertChance / alarmChance as above. Success gives a temporary key ('hotwire').
    alarm: 'native' (GTA alarm) | 'custom' (horn + lights for alarm.seconds) | 'none'.
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
      hotwire = { method = 'skillcheck', difficulty = { 'easy', 'medium', 'medium' }, duration = 6000, alertChance = 25, alarmChance = 0 },
      tracker = false,
      alarm = 'native',                -- 'native' | 'custom' | 'none'
    },
    highend = {
      label = 'High-end',
      keyItem = 'fob',                 -- items.fob
      remote = true,
      accessTools = {
        { item = 'advancedLockpick', difficulty = { 'medium', 'hard', 'hard' }, breakChance = 15, alarmChance = 80, alertChance = 70 },
        { item = 'hackingDevice', difficulty = { 'medium', 'medium', 'hard', 'hard' }, inputs = { 'w', 'a', 's', 'd' }, breakChance = 0, alarmChance = 40, alertChance = 50 },
      },
      hotwire = { method = 'hack', item = 'hackingDevice', difficulty = { 'medium', 'hard', 'hard', 'hard' }, inputs = { 'w', 'a', 's', 'd' }, duration = 9000, alertChance = 60, alarmChance = 30, breakChance = 10 },
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

  -- No-key driver flow: search the vehicle once (per vehicle) for a chance at money, items or
  -- a spare key. Every loot entry is rolled on its own; `items` names inventory items.
  search = {
    enabled = true,
    duration = 7000,             -- ms (progress bar)
    alertChance = 10,
    cooldown = 30,               -- seconds between successful searches per player
    ambientOnly = true,          -- only traffic / parked GTA vehicles (never script- or player-spawned ones)
    money = { chance = 35, min = 20, max = 250, account = 'cash' },
    spareKeyChance = 8,
    spareKeyItem = true,         -- physical key mode: the spare key is a key item (else a temporary key)
    ownedVehicles = false,       -- also search players' vehicles (false: vehicles nobody owns only)
    items = {
      { item = 'water', chance = 20, min = 1, max = 2 },
      { item = 'phone', chance = 3, min = 1, max = 1 },
    },
  },

  -- NPC drivers: aim a weapon at a driver (stopped or slow) to rob the key; search the body
  -- of the original driver; authorized jobs ask for the vehicle.
  npc = {
    robbery = true,
    robTime = 3500,              -- ms aiming before they hand the key over
    maxSpeed = 8.0,              -- m/s: faster drivers ignore you
    range = 6.0,                 -- metres between you and the vehicle
    -- How a held-up driver reacts (weights, any numbers): hand the key over after robTime,
    -- drop the key and run (a key on the ground), fight, or drive away. Admins tune it in game.
    reactions = { handover = 60, drop = 15, fight = 10, flee = 15 },
    policeRequired = 0,          -- on-duty officers (dispatch.jobs) needed for a hold-up
    dispatchDelay = 0,           -- seconds before the police alert of a hold-up goes out
    fightWeapon = 'WEAPON_PISTOL', -- what a fighting driver pulls out ('' = fists)
    deadDriverKeys = true,       -- search the body of the original (traffic) driver for the key
    alertChance = 60,
    cooldown = 60,               -- seconds between robberies per player
    ambientOnly = true,          -- only traffic peds (never NPCs another script spawned: jobs, missions)
    ownedVehicles = false,       -- also NPCs driving a player's vehicle
    -- Players with these jobs (on duty) can ask NPC drivers for their vehicle (no robbery, no alert).
    assistJobs = { 'police', 'sheriff', 'state' },
    assistCooldown = 10,         -- seconds between requests per player
  },

  -- Locksmiths (ped + blip + target option / press-E prompt, following the interface's
  -- interaction setting). Legal shops serve owners and holders of a real key (a registered key
  -- item or a virtual key; never a temporary key, a back-alley key or garage share / job
  -- access); illegal shops program keys for any vehicle parked within `range` and may alert
  -- the police (alertChance %, NZ.Dispatch; the alert names the plate the vehicle wears).
  -- Keys from an illegal shop open the vehicle but never reach its tracker.
  -- Services: duplicate (copy a key item: physical keys only), program (a new key for a
  -- vehicle parked nearby; virtual mode: a temporary key, illegal shops only), rekey (change
  -- the locks: every other key stops working; OWNER ONLY at every shop, an illegal one included),
  -- immobiliser / ghost (install that immobiliser in the owner's vehicle parked there).
  -- materials: { item = Config.CarLock.items key or item name, count, label? }.
  -- bucket: routing bucket of the shop (default 0). Checked on the atlas map: Davis Ave (south
  -- LS shops) and the Terminal container port quay (docks); the ped is put on the ground.
  locksmiths = {
    {
      name = 'Los Santos Locksmith',
      coords = vec4(170.58, -1799.68, 29.32, 320.0),
      ped = 's_m_m_autoshop_01',
      scenario = 'WORLD_HUMAN_CLIPBOARD',   -- '' = none
      blip = { enabled = true, sprite = 134, color = 3, scale = 0.7 },
      illegal = false,
      alertChance = 0,
      range = 25.0,                         -- metres: vehicles parked this close count as nearby
      services = {
        duplicate = { enabled = true, price = 250, materials = {} },
        program = { enabled = true, price = 500, materials = { { item = 'blank', count = 1 } } },
        rekey = { enabled = true, price = 1500, materials = {} },
        immobiliser = { enabled = true, price = 2500, materials = {} },   -- standard immobiliser (owner)
        ghost = { enabled = true, price = 7500, materials = {} },         -- Ghost immobiliser + PIN (owner)
      },
    },
    {
      name = 'Back-alley Keys',
      coords = vec4(1186.32, -3263.45, 6.03, 90.0),
      ped = 'g_m_y_mexgoon_02',
      scenario = 'WORLD_HUMAN_SMOKING',
      blip = { enabled = false },
      illegal = true,                       -- programs keys for any vehicle within range
      alertChance = 15,
      range = 20.0,
      services = {
        duplicate = { enabled = true, price = 600, materials = {} },
        program = { enabled = true, price = 3500, materials = {} },
        rekey = { enabled = false, price = 0, materials = {} },
        immobiliser = { enabled = false, price = 0, materials = {} },
        ghost = { enabled = false, price = 0, materials = {} },
      },
    },
  },
  locksmithAccount = 'cash',       -- 'cash' | 'bank'

  -- Share picker of the key ring (players within ranges.give): character names of strangers
  -- are metagaming on most servers, so it lists server ids ('Player 12') unless this is true.
  sharePicker = { names = false },

  -- Tracker (security profiles with tracker = true): locate the vehicles you have a key for
  -- from the key ring (waypoint + live distance, same routing bucket) and sound their alarm.
  tracker = {
    enabled = true,
    -- A crime's key gives no tracker access: no position, distance or remote alarm of the
    -- victim's vehicle, no owner's nickname. Crime keys: temporary keys from a hotwire, a
    -- robbery, a search, a back-alley locksmith, another script (compat) or any unknown
    -- reason, and key items cut by a back-alley locksmith (or copied from such a key). Owners,
    -- garage shares / fleets, virtual keys the owner gave, key items without a crime origin and
    -- service keys (garage hand-out, job spawner, staff, contract, NPC assist) always have it.
    -- true = every key, a crime's included, has tracker access (the nickname stays private).
    tempKeys = false,
    -- Who may track a vehicle (key settings, tab Keys): 'real' = holders of a real key (above),
    -- 'any' = every key (same as tempKeys = true), 'owner' = the owner and garage shares / fleets only.
    who = 'real',
    alarmSeconds = 20,             -- remote alarm length
    alarmCooldown = 60,            -- seconds before the same vehicle's alarm can be triggered again
    locateSeconds = 120,           -- the map blip of a located vehicle follows it this long
    blip = { sprite = 225, color = 5, scale = 0.85 },
  },

  dispatch = {
    -- 'auto' | 'wasabi_mdt' | 'rcore_dispatch' | 'cd_dispatch' | 'qs-dispatch' | 'core_dispatch' |
    -- 'ps-dispatch' | 'internal' | 'none' | 'custom'. 'auto' = the first one running, else
    -- 'internal' (notification + blip for on-duty players of `jobs`).
    system = 'auto',
    jobs = { 'police', 'sheriff', 'state' },
    -- Map blip (seconds on the map, converted for every system; radius 0 = exact position).
    blip = { sprite = 225, color = 1, scale = 1.0, seconds = 90, radius = 0.0, flash = true },
    blips = {                      -- per alert kind, merged over `blip`
      robbery = { sprite = 229, color = 1 },
      alarm = { sprite = 225, color = 5, seconds = 60, radius = 60.0 },
    },
    codes = {
      theft = '10-60', lockpick = '10-60', hotwire = '10-60', search = '10-60',
      robbery = '10-31', alarm = '10-66', locksmith = '10-31', fakeplate = '10-28',
    },
    -- wasabi_mdt dispatch type per alert kind ('default' for the rest).
    wasabiTypes = { default = 'robbery', alarm = 'disturbance', locksmith = 'disturbance', fakeplate = 'disturbance' },
    cooldown = 30,                 -- seconds: one alert per player and vehicle (one incident, one call)
    sound = true,                  -- 'internal': play a sound with the alert
  },

  alarm = {
    seconds = 25,                  -- custom alarm length (native alarms: 65 s at most)
    alertChance = 40,              -- % a crime that sets the alarm off alerts the police (when the action's own roll did not)
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
  spawnDistance = { min = 80.0, max = 150.0 }, -- metres from the vehicle, on a road with a route to it, out of sight when possible
  timeout = 240,                   -- seconds for the whole tow (every attempt) before it ends
  attempts = 2,                    -- trucks sent in all: a stuck / failed truck is replaced by a new one (1-5)
  loadSeconds = 6,                 -- the driver works the bed controls while the vehicle slides onto the bed (1-20)
  speed = 14.0,                    -- m/s on the way to the vehicle and when leaving (about 50 km/h)
  drivingStyle = 786603,           -- on the way and when leaving: law-abiding (stops at lights, steers around obstacles)
  approachStyle = 786492,          -- final approach and recovering from stuck: steers around parked cars, peds and objects
                                   -- (after a recovery it also stops at red lights and drives at 8 m/s at most)
  despawnDistance = 150.0,         -- the truck (and anything left after a failure) is removed once every player is farther than this ...
  despawnSeconds = 60,             -- ... the leaving truck is followed this long at most (then left to the cleanup below)
  cleanupSeconds = 300,            -- what is left near players is faded out at the latest after this many seconds
  maxActive = 6,                   -- tow trucks at the same time (more impounds delete the vehicle at once)
  -- Too big for the bed: deleted at once (no tow). Metres, from the model dimensions.
  maxSize = { length = 6.9, width = 2.9, height = 3.4 },
  -- Never towed (GTA classes): 10 industrial, 14 boats, 15 helicopters, 16 planes,
  -- 19 military, 20 commercial, 21 trains.
  skipClasses = { 10, 14, 15, 16, 19, 20, 21 },
  -- Where the vehicle sits on the bed (metres, relative to the truck bone): `y` = centre of the
  -- bed, `rear` = its rear edge (the vehicle slides on from there), `front` = its front end at
  -- the cab (long vehicles are moved back so they never reach into the cab and hang over the
  -- rear instead). The bed height is measured on the truck when possible; `surface` is the
  -- fallback. `pitch` = degrees the vehicle tilts while it climbs onto the bed (the end that goes
  -- up first rises; 0 = level; flip the sign if it tips the wrong way in game). Tune for add-on trucks.
  bed = { bone = 'bodyshell', y = -2.35, surface = 0.55, rear = -6.0, front = 1.2, pitch = 10.0 },
  animation = { dict = 'amb@prop_human_atm@male@idle_a', clip = 'idle_b' }, -- the driver at the bed controls
  -- Blip on the tow truck for the impounding officer while it is on its way.
  blip = { enabled = true, sprite = 68, color = 17, scale = 0.8 },
}

-- Car sale contracts (docs/CARLOCK.md §12). Use a blank vehicle_contract next to one of your
-- vehicles: pick it, a buyer standing nearby, the price and the terms, then sign. The buyer
-- reads, signs and pays; ownership, keys and money move only when the server agrees.
Config.Contracts = {
  enabled = true,
  maxDistance = 10.0,              -- metres: buyer and vehicle within this range of the seller (sending and signing)
  expireSeconds = 120,             -- the buyer has this long to sign
  account = 'bank',                -- the buyer pays from, and the seller is paid into: 'bank' | 'cash'
  signedCopies = true,             -- both parties keep a signed_contract item (use it to read the contract; needs item metadata)
  maxPrice = 10000000,
  resendCooldown = 60,             -- seconds before a seller may send the same buyer another contract after a "no" (declined / expired)
}

-- Fake plates (docs/CARLOCK.md §13). Install or remove one at the rear of a vehicle (target
-- option, or use the fake_plate item next to it). Keys, locks and garages keep using the real
-- plate; everyone else, police plate checks included, sees the fake one.
Config.FakePlates = {
  enabled = true,
  requireScrewdriver = true,       -- installing and removing need the screwdriver (not consumed)
  screwdriverBreakChance = 5,      -- % the screwdriver breaks on each install / removal
  installSeconds = 6,
  removeSeconds = 5,
  returnOnStore = true,            -- storing in a garage removes the fake plate and gives the item back
  pattern = '11AAA111',            -- 1 = digit, A = letter, a space or anything else as written (8 at most, e.g. 'AAA 111'); never a registered plate
  alertChance = 0,                 -- % the police get an alert (Config.CarLock.dispatch) when one is installed
  distance = 2.0,                  -- metres from the rear of the vehicle
  animation = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
}
