-- ██████╗  █████╗ ██████╗ ████████╗███████╗
-- ██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝███████║██████╔╝   ██║   ███████╗
-- ██╔═══╝ ██╔══██║██╔══██╗   ██║   ╚════██║
-- ██║     ██║  ██║██║  ██║   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝

--[[
    Every purchasable thing is an item. Prices are worked out on the server.

    mult     multiplier of the vehicle price (see Config.VehiclePrices). A table = price per level.
    price    flat price (used instead of mult)
    min/max  clamp the final price
    cam      camera preset while browsing ('full','front','rear','side','wheel','engine','interior','top','plate','exhaust')
    doors    door indexes opened while browsing (4 = hood, 5 = trunk)
    pile     stockpile the mechanic fetches the part from ('body','engine','wheels','paint','interior','electronics')
    spot     where on the car it is fitted (Config.InstallSpots key, 'wheels' = all four corners)
]]

Config.Parts = {
    ------------------------------------------------------------------ performance
    mod_11 = { label = 'Engine',        icon = 'fa-gears',              kind = 'mod', slot = 11, mult = { 0.03, 0.05, 0.07, 0.09, 0.11, 0.13 }, min = 2500,  cam = 'engine', doors = { 4 }, pile = 'engine', spot = 'engine' },
    mod_12 = { label = 'Brakes',        icon = 'fa-circle-stop',        kind = 'mod', slot = 12, mult = { 0.02, 0.035, 0.05, 0.065, 0.08 },       min = 1500,  cam = 'wheel',  pile = 'wheels', spot = 'wheels' },
    mod_13 = { label = 'Transmission',  icon = 'fa-code-branch',        kind = 'mod', slot = 13, mult = { 0.025, 0.045, 0.065, 0.085, 0.105 },       min = 2000,  cam = 'side',   pile = 'engine', spot = 'engine' },
    mod_15 = { label = 'Suspension',    icon = 'fa-arrows-up-down',     kind = 'mod', slot = 15, mult = { 0.02, 0.04, 0.06, 0.08, 0.10, 0.12 }, min = 1200,  cam = 'wheel',  pile = 'wheels', spot = 'wheels' },
    mod_16 = { label = 'Armor',         icon = 'fa-shield-halved',      kind = 'mod', slot = 16, mult = { 0.03, 0.06, 0.09, 0.12, 0.15, 0.18 }, min = 2500,  cam = 'side',   pile = 'body',   spot = 'left' },
    mod_18 = { label = 'Turbo',         icon = 'fa-fan',                kind = 'toggle', slot = 18, mult = 0.10, min = 6000, cam = 'engine', doors = { 4 }, pile = 'engine', spot = 'engine' },
    nitrous    = { label = 'Nitrous',        icon = 'fa-fire-flame-simple', kind = 'nitrous',    cam = 'rear',   doors = { 5 }, pile = 'engine', spot = 'rear' },
    ecu        = { label = 'ECU Tune',       icon = 'fa-microchip',         kind = 'ecu',        price = 18000,  cam = 'interior', pile = 'electronics', spot = 'interior' },
    engineSwap = { label = 'Engine Swap',    icon = 'fa-car-battery',       kind = 'swap',       cam = 'engine', doors = { 4 }, pile = 'engine', spot = 'engine' },
    antilag    = { label = 'Anti-Lag',       icon = 'fa-burst',             kind = 'antilag',    price = 22000,  cam = 'exhaust', pile = 'electronics', spot = 'engine' },
    launch     = { label = 'Launch Control', icon = 'fa-flag-checkered',    kind = 'launch',     price = 16000,  cam = 'interior', pile = 'electronics', spot = 'interior' },
    tyres      = { label = 'Tyre Compound',  icon = 'fa-life-ring',          kind = 'tyres',      cam = 'wheel',  pile = 'wheels', spot = 'wheels' },
    drivetrain = { label = 'Drivetrain',     icon = 'fa-gear',               kind = 'drivetrain', cam = 'side',   pile = 'jacks',  spot = 'wheels' },
    ceramic    = { label = 'Ceramic Brakes', icon = 'fa-compact-disc',       kind = 'ceramic',    cam = 'wheel',  pile = 'jacks',  spot = 'wheels' },
    driftKit   = { label = 'Drift Kit',      icon = 'fa-arrows-spin',        kind = 'driftKit',   cam = 'wheel',  pile = 'jacks',  spot = 'wheels' },
    gearbox    = { label = 'Gearbox',        icon = 'fa-arrow-down-up-across-line', kind = 'gearbox', cam = 'side', pile = 'jacks', spot = 'wheels' },
    sound      = { label = 'Engine Note',    icon = 'fa-volume-high',        kind = 'sound',      cam = 'exhaust', pile = 'exhaust', spot = 'rear' },
    airride    = { label = 'Air Suspension', icon = 'fa-wind',              kind = 'airride',    price = 45000,  cam = 'wheel',  pile = 'wheels', spot = 'wheels' },

    ------------------------------------------------------------------ body
    mod_0  = { label = 'Spoiler',        icon = 'fa-plane-up',          kind = 'mod', slot = 0,  mult = 0.035, min = 800, cam = 'rear',    pile = 'body', spot = 'rear' },
    mod_1  = { label = 'Front Bumper',   icon = 'fa-car-rear',          kind = 'mod', slot = 1,  mult = 0.030, min = 800, cam = 'front',   pile = 'body', spot = 'front' },
    mod_2  = { label = 'Rear Bumper',    icon = 'fa-car-rear',          kind = 'mod', slot = 2,  mult = 0.030, min = 800, cam = 'rear',    pile = 'body', spot = 'rear' },
    mod_3  = { label = 'Side Skirts',    icon = 'fa-ruler-horizontal',  kind = 'mod', slot = 3,  mult = 0.025, min = 700, cam = 'side',    pile = 'body', spot = 'left' },
    mod_4  = { label = 'Exhaust',        icon = 'fa-wind',              kind = 'mod', slot = 4,  mult = 0.028, min = 700, cam = 'exhaust', pile = 'body', spot = 'exhaust' },
    mod_5  = { label = 'Roll Cage',      icon = 'fa-border-all',        kind = 'mod', slot = 5,  mult = 0.030, min = 900, cam = 'interior',pile = 'interior', spot = 'interior' },
    mod_6  = { label = 'Grille',         icon = 'fa-grip-lines',        kind = 'mod', slot = 6,  mult = 0.018, min = 500, cam = 'front',   pile = 'body', spot = 'front' },
    mod_7  = { label = 'Hood',           icon = 'fa-car',               kind = 'mod', slot = 7,  mult = 0.028, min = 800, cam = 'front',   pile = 'body', spot = 'front' },
    mod_8  = { label = 'Left Fender',    icon = 'fa-car-side',          kind = 'mod', slot = 8,  mult = 0.020, min = 500, cam = 'side',    pile = 'body', spot = 'left' },
    mod_9  = { label = 'Right Fender',   icon = 'fa-car-side',          kind = 'mod', slot = 9,  mult = 0.020, min = 500, cam = 'side',    pile = 'body', spot = 'right' },
    mod_10 = { label = 'Roof',           icon = 'fa-car-tunnel',        kind = 'mod', slot = 10, mult = 0.024, min = 700, cam = 'top',     pile = 'body', spot = 'roof' },
    mod_27 = { label = 'Trim',           icon = 'fa-pen-ruler',         kind = 'mod', slot = 27, mult = 0.012, min = 400, cam = 'side',    pile = 'body', spot = 'left' },
    mod_35 = { label = 'Plaques',        icon = 'fa-certificate',       kind = 'mod', slot = 35, mult = 0.010, min = 300, cam = 'interior',pile = 'interior', spot = 'interior' },
    mod_36 = { label = 'Speakers',       icon = 'fa-volume-high',       kind = 'mod', slot = 36, mult = 0.014, min = 500, cam = 'rear',    doors = { 5 }, pile = 'electronics', spot = 'rear' },
    mod_37 = { label = 'Trunk',          icon = 'fa-box-open',          kind = 'mod', slot = 37, mult = 0.014, min = 500, cam = 'rear',    doors = { 5 }, pile = 'body', spot = 'rear' },
    mod_38 = { label = 'Hydraulics',     icon = 'fa-arrows-up-down-left-right', kind = 'mod', slot = 38, mult = 0.030, min = 1500, cam = 'side', pile = 'wheels', spot = 'wheels' },
    mod_39 = { label = 'Engine Block',   icon = 'fa-cubes',             kind = 'mod', slot = 39, mult = 0.015, min = 600, cam = 'engine',  doors = { 4 }, pile = 'engine', spot = 'engine' },
    mod_40 = { label = 'Air Filter',     icon = 'fa-filter',            kind = 'mod', slot = 40, mult = 0.012, min = 500, cam = 'engine',  doors = { 4 }, pile = 'engine', spot = 'engine' },
    mod_41 = { label = 'Strut Braces',   icon = 'fa-grip-lines-vertical', kind = 'mod', slot = 41, mult = 0.012, min = 500, cam = 'engine', doors = { 4 }, pile = 'engine', spot = 'engine' },
    mod_42 = { label = 'Arch Covers',    icon = 'fa-circle-half-stroke',kind = 'mod', slot = 42, mult = 0.012, min = 500, cam = 'side',    pile = 'body', spot = 'left' },
    mod_43 = { label = 'Aerials',        icon = 'fa-tower-broadcast',   kind = 'mod', slot = 43, mult = 0.008, min = 300, cam = 'rear',    pile = 'body', spot = 'rear' },
    mod_44 = { label = 'Exterior Trim',  icon = 'fa-pen-ruler',         kind = 'mod', slot = 44, mult = 0.012, min = 400, cam = 'side',    pile = 'body', spot = 'right' },
    mod_45 = { label = 'Fuel Tank',      icon = 'fa-gas-pump',          kind = 'mod', slot = 45, mult = 0.010, min = 400, cam = 'rear',    pile = 'body', spot = 'rear' },
    mod_46 = { label = 'Windows',        icon = 'fa-window-maximize',   kind = 'mod', slot = 46, mult = 0.010, min = 400, cam = 'side',    pile = 'body', spot = 'left' },

    ------------------------------------------------------------------ interior
    mod_28 = { label = 'Ornaments',      icon = 'fa-star',              kind = 'mod', slot = 28, mult = 0.008, min = 300, cam = 'interior', pile = 'interior', spot = 'interior' },
    mod_29 = { label = 'Dashboard',      icon = 'fa-gauge',             kind = 'mod', slot = 29, mult = 0.014, min = 500, cam = 'interior', pile = 'interior', spot = 'interior' },
    mod_30 = { label = 'Dials',          icon = 'fa-gauge-simple',      kind = 'mod', slot = 30, mult = 0.010, min = 400, cam = 'interior', pile = 'interior', spot = 'interior' },
    mod_31 = { label = 'Door Speakers',  icon = 'fa-volume-low',        kind = 'mod', slot = 31, mult = 0.010, min = 400, cam = 'interior', doors = { 0 }, pile = 'electronics', spot = 'left' },
    mod_32 = { label = 'Seats',          icon = 'fa-chair',             kind = 'mod', slot = 32, mult = 0.016, min = 500, cam = 'interior', pile = 'interior', spot = 'interior' },
    mod_33 = { label = 'Steering Wheel', icon = 'fa-dharmachakra',      kind = 'mod', slot = 33, mult = 0.010, min = 400, cam = 'interior', pile = 'interior', spot = 'interior' },
    mod_34 = { label = 'Shifter',        icon = 'fa-arrow-down-up-across-line', kind = 'mod', slot = 34, mult = 0.008, min = 300, cam = 'interior', pile = 'interior', spot = 'interior' },

    ------------------------------------------------------------------ paint
    color1         = { label = 'Primary Paint',   icon = 'fa-fill-drip',  kind = 'color', target = 'primary',   mult = 0.030, min = 1200, max = 18000, rgbExtra = 0.25, cam = 'full', pile = 'paint', spot = 'paint' },
    color2         = { label = 'Secondary Paint', icon = 'fa-fill',       kind = 'color', target = 'secondary', mult = 0.020, min = 900,  max = 12000, rgbExtra = 0.25, cam = 'full', pile = 'paint', spot = 'paint' },
    pearl          = { label = 'Pearlescent',     icon = 'fa-droplet',    kind = 'color', target = 'pearl',     mult = 0.012, min = 700,  cam = 'full', pile = 'paint', spot = 'paint' },
    interiorColor  = { label = 'Interior Trim',   icon = 'fa-couch',      kind = 'color', target = 'interior',  mult = 0.008, min = 400,  cam = 'interior', pile = 'interior', spot = 'interior' },
    dashboardColor = { label = 'Dashboard Color', icon = 'fa-gauge',      kind = 'color', target = 'dashboard', mult = 0.008, min = 400,  cam = 'interior', pile = 'interior', spot = 'interior' },
    livery         = { label = 'Livery',          icon = 'fa-paint-roller', kind = 'livery',   mult = 0.030, min = 1500, cam = 'full', pile = 'paint', spot = 'paint' },
    roofLivery     = { label = 'Roof Livery',     icon = 'fa-paint-roller', kind = 'roofLivery', mult = 0.015, min = 800, cam = 'top',  pile = 'paint', spot = 'paint' },

    ------------------------------------------------------------------ wheels
    wheels       = { label = 'Rims',            icon = 'fa-circle-dot',        kind = 'wheels',      mult = 0.030, min = 1500, max = 30000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    rearWheels   = { label = 'Rear Rim',        icon = 'fa-circle-dot',        kind = 'rearWheels',  mult = 0.020, min = 1000, cam = 'wheel', pile = 'wheels', spot = 'wheel_lr' },
    customTires  = { label = 'Custom Tyres',    icon = 'fa-life-ring',         kind = 'customTires', price = 3500, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    wheelColor   = { label = 'Rim Color',       icon = 'fa-palette',           kind = 'color', target = 'wheel', mult = 0.010, min = 600, cam = 'wheel', pile = 'paint', spot = 'wheels' },
    smoke        = { label = 'Tyre Smoke',      icon = 'fa-smog',              kind = 'smoke',       price = 4500, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    driftTyres   = { label = 'Drift Tyres',     icon = 'fa-rotate',            kind = 'drift',       mult = 0.020, min = 5000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    bulletproof  = { label = 'Run-Flat Tyres',  icon = 'fa-shield',            kind = 'bulletproof', mult = 0.040, min = 12000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    wheelSize    = { label = 'Rim Diameter',    icon = 'fa-up-right-and-down-left-from-center', kind = 'wheelSize',  price = 12000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    wheelWidth   = { label = 'Tyre Width',      icon = 'fa-left-right',        kind = 'wheelWidth',  price = 12000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },

    ------------------------------------------------------------------ stance
    stance       = { label = 'Fitment',         icon = 'fa-arrows-left-right-to-line', kind = 'stance', price = 20000, cam = 'wheel', pile = 'wheels', spot = 'wheels' },
    height       = { label = 'Ride Height',     icon = 'fa-arrows-up-to-line', kind = 'height',      price = 9000,  cam = 'side',  pile = 'wheels', spot = 'wheels' },

    ------------------------------------------------------------------ lights
    mod_22       = { label = 'Xenon Headlights',icon = 'fa-lightbulb',         kind = 'toggle', slot = 22, mult = 0.012, min = 1500, cam = 'front', pile = 'electronics', spot = 'front' },
    xenonColor   = { label = 'Headlight Color', icon = 'fa-sun',               kind = 'xenonColor',  price = 3000, rgbExtra = 0.5, cam = 'front', pile = 'electronics', spot = 'front' },
    neon         = { label = 'Underglow',       icon = 'fa-lightbulb',         kind = 'neon',        price = 9000, cam = 'side',  pile = 'electronics', spot = 'left' },
    neonPattern  = { label = 'Underglow Mode',  icon = 'fa-wave-square',       kind = 'neonPattern', price = 6500, cam = 'side',  pile = 'electronics', spot = 'interior' },

    ------------------------------------------------------------------ plate
    plateText    = { label = 'Custom Plate',    icon = 'fa-id-card',           kind = 'plateText',   price = 85000, cam = 'plate', pile = 'body', spot = 'plate' },
    plateIndex   = { label = 'Plate Style',     icon = 'fa-rectangle-list',    kind = 'plateIndex',  price = 1500,  cam = 'plate', pile = 'body', spot = 'plate' },
    mod_25       = { label = 'Plate Holder',    icon = 'fa-border-top-left',   kind = 'mod', slot = 25, mult = 0.008, min = 300, cam = 'plate', pile = 'body', spot = 'plate' },
    mod_26       = { label = 'Vanity Plate',    icon = 'fa-signature',         kind = 'mod', slot = 26, mult = 0.008, min = 300, cam = 'front', pile = 'body', spot = 'front' },

    ------------------------------------------------------------------ extras
    tint         = { label = 'Window Tint',     icon = 'fa-circle-half-stroke',kind = 'tint',        mult = 0.010, min = 800, cam = 'side', pile = 'interior', spot = 'left' },
    mod_14       = { label = 'Horn',            icon = 'fa-bullhorn',          kind = 'mod', slot = 14, mult = 0.006, min = 300, cam = 'front', pile = 'electronics', spot = 'front' },
    extras       = { label = 'Vehicle Extras',  icon = 'fa-puzzle-piece',      kind = 'extras',      price = 1500, cam = 'full', pile = 'body', spot = 'left' },
    locator      = { label = 'GPS Tracker',     icon = 'fa-location-crosshairs', kind = 'locator',   price = 12000, cam = 'interior', pile = 'electronics', spot = 'interior' },

    ------------------------------------------------------------------ service
    repair       = { label = 'Full Repair',     icon = 'fa-screwdriver-wrench',kind = 'repair',      price = 1800, cam = 'full', pile = 'engine', spot = 'engine' },
    clean        = { label = 'Wash & Detail',   icon = 'fa-soap',              kind = 'clean',       price = 350,  cam = 'full', pile = 'paint', spot = 'left' },
    service      = { label = 'Major Service',   icon = 'fa-oil-can',           kind = 'service',     price = 2500, cam = 'engine', doors = { 4 }, pile = 'engine', spot = 'engine' },
}

-- Menu layout. Items the vehicle can't take (no mod slots, bikes etc.) are hidden automatically.
Config.Categories = {
    { id = 'performance', label = 'Performance', icon = 'fa-gauge-high',   items = { 'mod_11', 'mod_12', 'mod_13', 'mod_15', 'mod_18', 'mod_16', 'nitrous', 'ecu', 'engineSwap', 'sound', 'antilag', 'launch' } },
    { id = 'body',        label = 'Body',        icon = 'fa-car-side',     items = { 'mod_0', 'mod_1', 'mod_2', 'mod_3', 'mod_4', 'mod_6', 'mod_7', 'mod_8', 'mod_9', 'mod_10', 'mod_27', 'mod_44', 'mod_42', 'mod_43', 'mod_45', 'mod_46', 'mod_37', 'mod_36', 'mod_38', 'mod_39', 'mod_40', 'mod_41', 'mod_5', 'mod_35' } },
    { id = 'paint',       label = 'Paint',       icon = 'fa-spray-can',    items = { 'color1', 'color2', 'pearl', 'livery', 'roofLivery', 'interiorColor', 'dashboardColor' } },
    { id = 'wheels',      label = 'Wheels',      icon = 'fa-circle-dot',   items = { 'wheels', 'rearWheels', 'customTires', 'wheelColor', 'smoke', 'driftTyres', 'bulletproof', 'wheelSize', 'wheelWidth' } },
    { id = 'chassis',     label = 'Chassis',     icon = 'fa-car-burst',    items = { 'drivetrain', 'gearbox', 'ceramic', 'driftKit', 'airride', 'tyres' } },
    { id = 'stance',      label = 'Stance',      icon = 'fa-arrows-left-right-to-line', items = { 'stance', 'height' } },
    { id = 'interior',    label = 'Interior',    icon = 'fa-chair',        items = { 'mod_32', 'mod_33', 'mod_29', 'mod_30', 'mod_34', 'mod_28', 'mod_31' } },
    { id = 'lights',      label = 'Lights',      icon = 'fa-lightbulb',    items = { 'mod_22', 'xenonColor', 'neon', 'neonPattern' } },
    { id = 'plate',       label = 'Plate',       icon = 'fa-id-card',      items = { 'plateText', 'plateIndex', 'mod_25', 'mod_26' } },
    { id = 'extras',      label = 'Extras',      icon = 'fa-puzzle-piece', items = { 'tint', 'mod_14', 'extras', 'locator' } },
    { id = 'service',     label = 'Service',     icon = 'fa-screwdriver-wrench', items = { 'repair', 'service', 'clean' } },
}

-- Armed / weaponised body kits are hidden when their name contains one of these
Config.HideArmedMods = true
Config.ArmedModKeywords = { 'GUN', 'MISSILE', 'ROCKET', 'TORPEDO', 'MG_', 'ARMOR_PLATE', 'PROX', 'RAM' }

-- Per-model caps on performance levels (0 = level 1). Stops GTA+ / HSW cars getting stages they shouldn't.
Config.MaxLevels = {
    -- buffalo5 = { [11] = 3, [12] = 2, [13] = 2, [15] = 3 },
}

-- Rename mod options that come through as NULL or ugly labels: [model] = { [slot] = { [index] = 'Label' } }
Config.ModNames = {
    -- sultanrs = { [0] = { [0] = 'GT Wing' } },
}

-- Horns: labels for horn indexes (mod 14). Unlisted indexes show 'Horn #'.
Config.HornNames = {
    [0] = 'Truck Horn', [1] = 'Police Horn', [2] = 'Clown Horn', [3] = 'Musical Horn 1', [4] = 'Musical Horn 2',
    [5] = 'Musical Horn 3', [6] = 'Musical Horn 4', [7] = 'Musical Horn 5', [8] = 'Sad Trombone', [9] = 'Classical Horn 1',
    [10] = 'Classical Horn 2', [11] = 'Classical Horn 3', [12] = 'Classical Horn 4', [13] = 'Classical Horn 5',
    [14] = 'Classical Horn 6', [15] = 'Classical Horn 7', [16] = 'Scale Do', [17] = 'Scale Re', [18] = 'Scale Mi',
    [19] = 'Scale Fa', [20] = 'Scale Sol', [21] = 'Scale La', [22] = 'Scale Ti', [23] = 'Scale Do (High)',
    [24] = 'Jazz Horn 1', [25] = 'Jazz Horn 2', [26] = 'Jazz Horn 3', [27] = 'Jazz Horn Loop', [28] = 'Star Spangled 1',
    [29] = 'Star Spangled 2', [30] = 'Star Spangled 3', [31] = 'Star Spangled 4', [32] = 'Classical Loop 1',
    [33] = 'Classical Horn 8', [34] = 'Classical Loop 2', [35] = 'Liberty City Loop', [36] = 'San Andreas Loop',
    [37] = 'Halloween Loop 1', [38] = 'Halloween Loop 2', [39] = 'Festive Loop 1', [40] = 'Festive Loop 2',
    [41] = 'Festive Loop 3', [42] = 'Air Horn 1', [43] = 'Air Horn 2', [44] = 'Air Horn 3',
}
