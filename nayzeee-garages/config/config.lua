--[[
  nayzeee-garages — static configuration (shared: loaded on server AND client).

  Almost everything about garages, impounds, interiors and gameplay rules is edited
  in-game through the admin panel (/garageadmin) and stored in the database.
  This file only holds things that must exist before the database is reachable, and the
  default values used the first time the resource starts.

  Do NOT put secrets here (clients can read shared files). Webhooks go in config/server.lua.
]]

Config = {}

-- 'auto' detects qbx_core, qb-core, then es_extended. Force with 'qbx' | 'qb' | 'esx'.
Config.Framework = 'auto'

-- Language used by Lua and the interface. Translation tables live in locales/<lang>.lua
Config.Locale = 'en'

-- Print debug information to the server/client console.
Config.Debug = false

-- Integrations: 'auto' picks the first running resource it knows. See bridge/client/*.lua
Config.Integrations = {
  -- Keys: 'auto' = the built-in car lock (config/carlock.lua) when Config.CarLock.enabled and none
  -- of these runs, else the first running one: qbx_vehiclekeys | qb-vehiclekeys | wasabi_carlock |
  -- MrNewbVehicleKeys | qs-vehiclekeys | Renewed-Vehiclekeys | vehicles_keys (one that starts while
  -- the server boots also takes over). 'nayzeee' forces the built-in car lock; or force one of
  -- those, or 'none'.
  keys = 'auto',
  -- Inventory (car lock key items, tools, contracts, fake plates): 'auto' = first started of
  -- ox_inventory | qs-inventory-pro | qs-inventory | codem-inventory | tgiann-inventory |
  -- origen_inventory | core_inventory | ps-inventory | lj-inventory | qb-inventory, else framework
  -- items; or force one of those, framework (items without metadata), custom, none
  inventory = 'auto',
  fuel = 'auto',    -- ox_fuel | LegacyFuel | cdn-fuel | ps-fuel | lj-fuel | okokGasStation | qs-fuelstations | Renewed-Fuel | ti_fuel | native
  target = 'auto',  -- ox_target | qb-target | none
  -- House garages: 'auto' (every supported housing script that is started) | 'none' | one name |
  -- a list, e.g. { 'ps-housing', 'loaf_housing' }. Names (resource or house id prefix): qb-houses (qb),
  -- ps-housing (ps), qs-housing (qs), esx_property (esx), loaf_housing (loaf), vms_housing (vms),
  -- bcs_housing (bcs), tk_housing (tk), rtx_housing (rtx), RxHousing (rx), nolag_properties (nolag).
  -- Some need a small file copied into the housing script: see install/housing/README.md.
  -- Any other script can use the RegisterHouseGarage / SetHouseAccess exports.
  housing = 'auto',
  -- Notifications: ox_lib | auto (first running okokNotify / wasabi_notify / brutal_notify / lation_ui /
  -- t-notify / mythic_notify / pNotify, else ox_lib) | framework (qb / qbx / esx built-in) | qb | qbx |
  -- esx (esx_notify, ESX Legacy 1.9+) | okokNotify | mythic_notify | pNotify | wasabi_notify |
  -- brutal_notify | lation_ui | t-notify | custom ('custom': edit NZ.Notify.custom in
  -- bridge/client/notify.lua). ox_lib is used whenever the configured resource is not started.
  notify = 'ox_lib',
}

-- Notification look (used by every notify integration that supports it).
Config.Notify = {
  title = 'Garage',          -- title shown by integrations that have one ('' = none)
  position = nil,            -- nil = each player's own ox_lib setting; or 'top' | 'top-right' | 'top-left' |
                             -- 'bottom' | 'bottom-right' | 'bottom-left' | 'center-right' | 'center-left'
  duration = 5000,           -- milliseconds
  -- While a garage window has mouse focus FiveM draws it above every other resource's interface,
  -- so a notification from the integration above would be hidden behind it. true = show it inside
  -- the open window instead; false = always use Config.Integrations.notify.
  inInterface = true,
}

Config.Commands = {
  admin = 'garageadmin',   -- opens the admin panel (ace: nayzeee-garages.admin or ServerConfig.AdminGroups)
  impound = 'impound',     -- opens the impound form for the closest vehicle (impound jobs only)
}

-- Default key bindings (players can rebind them in GTA settings > Key Bindings > FiveM).
Config.Keys = {
  interact = 'E',          -- open garage / store vehicle (prompt mode)
  interiorPanel = 'F6',    -- interior control panel
  creatorFocus = 'E',      -- return to the interior creator panel while walking around
}

-- NPCs at garages (target interaction). The model and scenario are chosen per location in the
-- admin panel; these are the defaults offered there.
Config.Peds = {
  defaultModel = 's_m_y_valet_01',
  defaultScenario = 'WORLD_HUMAN_CLIPBOARD',
  spawnDistance = 60.0,     -- metres: peds exist only while a player is this close
}

-- Interaction ranges (metres).
Config.Interaction = {
  openRadius = 2.0,        -- default radius for new "open" points
  storeRadius = 4.0,       -- default radius for new "store" points
  drawMarkers = true,      -- small marker at open/store points while nearby
  markerDistance = 15.0,
}

-- On the very first start, when no garage exists yet, import the locations of an installed
-- qbx_garages / qb-garages config (the resource may be stopped). Runs once.
Config.AutoImportOnFirstStart = true

-- First routing bucket used for garage interiors. Each live interior instance gets its own.
Config.BucketBase = 7400

-- Phone garage apps (install/phone/README.md). These are the defaults server/phone.lua uses
-- when a value is missing.
Config.Phone = {
  valet = true,                 -- allow phone valet ("bring my car") claims
  valetTypes = { car = true },  -- categories a valet may deliver: car | sea | air
  claimTimeout = 60,            -- seconds (15-300) to deliver before the vehicle goes back to its garage
  applyData = true,             -- re-apply saved damage / fuel / mileage to the delivered vehicle
  maxPending = 2,               -- undelivered valet claims per player
  listShared = true,            -- phone lists include vehicles shared with the player
  hints = true,                 -- console hint at start for an installed phone with no adapter
}

-- Vehicles you never want stored (spawn names). Job spawner vehicles are handled separately.
Config.BlacklistedModels = {}

-- Optional per-model overrides for images/labels shown in the interface.
-- ['mycustomcar'] = { label = 'Pegassi Custom', image = 'https://example.com/mycustomcar.png' }
Config.VehicleOverrides = {}

--[[
  Defaults for the in-game Settings page (admin panel > Settings).
  The first boot writes these to the `nz_settings` table; after that the admin panel is
  the source of truth. Keep this shape in sync with the `Settings` type in
  web/src/lib/types.ts.
]]
Config.DefaultSettings = {
  vehicles = {
    spawnOutside = false,        -- spawn next to the vehicle instead of inside it
    saveMods = true,             -- save vehicle modifications when storing
    checkModel = true,           -- verify the stored model before accepting a vehicle
    serverSpawn = false,         -- create vehicles on the server (test with your vehicle scripts first)
    saveDamage = true,           -- engine/body/tank health, doors, windows, tyres
    saveDeformation = true,      -- body deformation (requires saveDamage)
    trailers = true,             -- store attached trailers together with the vehicle
    giveKeys = true,             -- give keys through the detected keys resource
    needsServiceBelow = 60,      -- engine % under which the "needs service" badge shows
  },
  garages = {
    retrieveMode = 'last',       -- 'last': drive only from the garage it is parked in | 'anywhere'
    showBlips = true,
    suggestWhenFull = true,      -- offer directions to the nearest garage with free space
    outOnRestart = 'garage',     -- 'garage' | 'impound' | 'keep'  (vehicles left out at server start)
    restartImpound = nil,        -- impound location id used when outOnRestart = 'impound'
    recoverFee = 250,            -- fee to recover a vehicle that is out but no longer exists
    storeOnlyOwned = true,       -- only owned / shared / job vehicles can be stored
    maxDistance = 25.0,          -- max distance from a garage point for any garage action
  },
  transfers = {
    garageEnabled = true,
    garageFee = 2500,
    playerEnabled = true,
    playerFee = 0,
    sellEnabled = true,
    shareEnabled = true,
    maxShares = 5,
  },
  impound = {
    defaultFee = 500,
    defaultHours = 0,
    staffBypassFee = true,       -- impound staff can take vehicles out without paying
  },
  economy = {
    account = 'bank',            -- 'bank' | 'cash' | 'both' (cash first, then bank)
  },
  interface = {
    defaultView = 'grid',        -- 'grid' | 'list'
    distanceUnit = 'mi',         -- 'mi' | 'km'
    currency = '$',
    imageUrl = 'https://docs.fivem.net/vehicles/{model}.webp',
    showImages = true,
    accent = '#08afa2',
    interaction = 'prompt',      -- 'prompt' (press E) | 'target' (ox_target / qb-target) | 'both'
  },
}
