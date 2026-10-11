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
    accent = '#08afa2',     -- NayZeee teal
    units = 'mph',          -- 'mph' | 'kmh'
    statusStyle = 'ring',   -- see /hud > Player Status
    speedoStyle = 'modern', -- see /hud > Cars & Bikes
    minimap = 'vehicle',    -- 'vehicle' | 'always' | 'never'
    notifyStyle = 'card',   -- 'card' | 'glass' | 'pill' | 'stripe' | 'minimal'
    notifyPosition = 'right', -- 'right' | 'left' | 'top' | 'bottom'
    progressStyle = 'bar',  -- 'bar' | 'ring' | 'line' | 'pill'
    textStyle = 'key',      -- interaction prompt: 'key' | 'card' | 'minimal'
    crosshairStyle = 'crossdot', -- 'dot' | 'cross' | 'crossdot' | 'tee' | 'plus' | 'circle' | 'circledot' | 'chevron'
    voiceStyle = 'pill',    -- 'pill' | 'bars' | 'card' | 'minimal'
}

-- Notifications, progress bars and interaction prompts (exports Notify / Progress / ShowTextUI / HideTextUI).
-- See README > Notifications for how to send qb-core, ESX and ox_lib notifications here too.
Config.UI = {
    Notify = { Duration = 5000 },
    Progress = {
        CancelKey = 73,        -- X (control index)
        CancelLabel = 'X',     -- shown on the bar
    },
    TextUI = {
        QBEvents = true,       -- also listen to qb-core:client:DrawText / HideText / ChangeText / KeyPressed
    },
    TestCommand = true,        -- /hudtest notify | progress | text
}

-- Custom crosshair while aiming. false: never touch GTA's own reticle (the Crosshair tab disappears).
Config.Crosshair = { enabled = true }

Config.Watermark = {
    enabled = true,
    title = 'NAYZEEE',
    subtitle = 'ROLEPLAY',
    -- Server logo. Drop your image into nayzeee-hud/html/logo/ and restart the resource.
    --   'auto'        uses logo.png, logo.webp, logo.gif or logo.svg from that folder (the first one found)
    --   'mylogo.png'  a specific file from that folder
    --   'https://...' an image link still works too
    --   ''            no logo, text only
    logo = 'auto',
    showText = true, -- false: logo only by default (players can still pick Logo & text / Logo only / Text only in /hud)
}

Config.Minimap = {
    hideHealthBars = true,   -- hides GTA's health/armour bars under the radar
    raiseForStatus = 0.065,  -- how far the radar moves up when player status sits under it (screen height, 0-1)
    -- 'default' | 'square' | 'circle' (players pick in /hud). Square and circle need squaremap.ytd /
    -- circlemap.ytd in a stream/ folder in this resource; without them the default shape is used.
    shape = 'default',
    -- Nudge the minimap frame for everyone, in 1080p pixels (players can fine-tune on top in /hud > Map & Compass > Frame fit).
    -- x: + right, y: + down, w / h: + bigger.
    frameFit = { x = 0, y = 0, w = 0, h = 0 },
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
    blockExit = true,        -- buckled players can't get out until they unbuckle
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
    maxRelief = 50,            -- most stress one hud:server:RelieveStress call can remove (limited to once a second)
    blurFrom = 50,             -- stress level where the screen starts to blur
    whitelistedJobs = { police = true, ambulance = true, leo = true, ems = true },
    noStressWeapons = { 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_STUNGUN', 'WEAPON_SNOWBALL' },
    noStressClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [18] = true, [19] = true, [20] = true, [21] = true },
    notify = true,             -- small "Feeling more stressed" text when it goes up
}

-- Discord profile pictures (static + animated) for the player info widget.
-- Needs a bot token in server.cfg (never here, this file is sent to clients):
--   set nhud_discord_token "YOUR_BOT_TOKEN"     (the squads token nz_squads_bot_token also works)
-- guildId: your Discord server id, so server-specific avatars are used. The bot must be in that server.
Config.Discord = {
    enabled = true,
    guildId = '',
    preferServerAvatar = true,
    size = 128,
    cacheMinutes = 60,
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
