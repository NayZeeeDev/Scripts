Config = {}

-- 'auto' | 'qbx' | 'qb' | 'esx' | 'standalone'
-- With a framework the HUD hides on character select / logout and comes back when you load in.
Config.Framework = 'auto'

-- Update intervals in ms. These are what keep resmon at ~0.00-0.01ms.
-- Lower = smoother but more CPU. Values are only sent to the UI when they change.
Config.Ticks = {
    foot = 250,         -- main loop while on foot (compass, weapon, pause state)
    vehicle = 125,      -- main loop while in a vehicle (speed, rpm, gear)
    vehicleSlow = 500,  -- fuel, engine, lights, locks, indicators
    status = 500,       -- health, armor, needs, money, voice, clock
    location = 1000,    -- street, zone, postal, weather
    slow = 2500,        -- minimap anchor, headshot, misc
}

-- Server defaults. Every player can change these in /hud and it's saved per player (client KVP).
Config.Defaults = {
    season = 'auto',        -- 'auto' picks by date | 'default' | 'winter' | 'christmas' | 'newyear' | 'valentine' | 'stpatrick' | 'spring' | 'summer' | 'independence' | 'autumn' | 'halloween'
    accent = '#b8f02a',
    units = 'mph',          -- 'mph' | 'kmh'
    statusStyle = 'ring',   -- see /hud > Player Status
    speedoStyle = 'modern', -- see /hud > Cars & Bikes
    minimap = 'vehicle',    -- 'vehicle' | 'always' | 'never'
}

Config.Watermark = {
    enabled = true,
    title = 'NAYZEEE',
    subtitle = 'ROLEPLAY',
    logo = '', -- optional image url (png/webp). Leave empty for text only.
}

Config.Minimap = {
    hideHealthBars = true, -- hides GTA's health/armour bars under the radar
}

-- Hides native GTA HUD text (vehicle name, area, street, cash).
-- 'smart'  : only hides for a few seconds when that text would appear (vehicle enter / street change). ~0.00ms
-- 'always' : hides every frame (+~0.01ms)
-- false    : leave GTA's HUD alone
Config.HideNativeHud = 'smart'

Config.Seatbelt = {
    -- true: built-in seatbelt. false: use another script (qb-smallresources' seatbelt is picked up
    -- automatically through 'seatbelt:client:ToggleSeatbelt', or call exports.SetSeatbelt).
    -- 'auto': built-in unless qb-smallresources is running.
    enabled = 'auto',
    ejectProtection = true,  -- buckled players can't fly through the windscreen
}

Config.Cruise = { enabled = true }

-- Stress (qb-hud compatible). Other scripts can keep using
-- TriggerServerEvent('hud:server:GainStress', amount) and 'hud:server:RelieveStress'.
-- qb/qbx: saved in player metadata. esx: esx_status 'stress' if it exists. standalone: kept in memory.
Config.Stress = {
    enabled = true,
    shootingChance = 0.1,      -- chance per shot to gain stress
    speedUnbuckled = 50,       -- mph; driving faster than this unbuckled adds stress
    speedBuckled = 100,        -- mph; buckled
    speedCheckMs = 10000,
    blurFrom = 50,             -- stress level where the screen starts to blur
    whitelistedJobs = { police = true, ambulance = true, leo = true, ems = true },
    noStressWeapons = { 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_STUNGUN', 'WEAPON_SNOWBALL' },
    noStressClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [18] = true, [19] = true, [20] = true, [21] = true },
    notify = true,             -- small "Feeling more stressed" text when it goes up
}

-- /cash and /bank show your balance on the HUD for a few seconds ('' to disable)
Config.MoneyCommands = { cash = 'cash', bank = 'bank' }

-- Default keys. Players can rebind them in GTA Settings > Key Bindings > FiveM.
Config.Keys = {
    seatbelt = 'B',
    cruise = 'Y',
    vehicleMenu = 'F7',
    indicatorLeft = 'LEFT',
    indicatorRight = 'RIGHT',
    hazard = '',
}

Config.Commands = {
    settings = 'hud',
    toggle = 'togglehud',
    vehicleMenu = 'vehmenu',
}

Config.ControlPanel = {
    keepInput = true, -- keep driving while the vehicle control panel is open
}

-- 'auto' detects LegacyFuel, cdn-fuel, ps-fuel, lj-fuel, ox_fuel, lc_fuel, qs-fuelstations, okokGasStation, Renewed-Fuel
-- or force one of those names, 'statebag' (Entity(veh).state.fuel) or 'native'
Config.Fuel = 'auto'

-- Weapon images for the weapon display. %s = weapon name (WEAPON_PISTOL). Set '' to disable images.
Config.WeaponImages = 'https://docs.fivem.net/weapons/%s.png'

-- Odometer per plate, saved on the player's machine.
Config.Odometer = true

-- Lock button in the vehicle control panel. Replace with your keys script if needed.
Config.ToggleLock = function(vehicle)
    local status = GetVehicleDoorLockStatus(vehicle)
    SetVehicleDoorsLocked(vehicle, status >= 2 and 1 or 2)
end

-- Return a postal code string for the street bar, or nil.
Config.GetPostal = function(coords)
    if GetResourceState('nearest-postal') == 'started' then
        local ok, postal = pcall(function() return exports['nearest-postal']:getPostal() end)
        if ok then return postal end
    end
    return nil
end
