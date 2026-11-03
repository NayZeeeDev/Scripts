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
  keys = 'auto',    -- qbx_vehiclekeys | qb-vehiclekeys | wasabi_carlock | MrNewbVehicleKeys | qs-vehiclekeys | Renewed-Vehiclekeys | vehicles_keys | none
  fuel = 'auto',    -- ox_fuel | LegacyFuel | cdn-fuel | ps-fuel | lj-fuel | okokGasStation | qs-fuelstations | Renewed-Fuel | ti_fuel | native
  target = 'auto',  -- ox_target | qb-target | none
  housing = 'auto', -- qb-houses | ps-housing | none  (others can use the RegisterHouseGarage export)
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

-- Interaction ranges (metres).
Config.Interaction = {
  openRadius = 2.0,        -- default radius for new "open" points
  storeRadius = 4.0,       -- default radius for new "store" points
  drawMarkers = true,      -- small marker at open/store points while nearby
  markerDistance = 15.0,
}

-- First routing bucket used for garage interiors. Each live interior instance gets its own.
Config.BucketBase = 7400

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
    interaction = 'prompt',      -- 'prompt' (press E) | 'target' (ox_target / qb-target)
  },
}
