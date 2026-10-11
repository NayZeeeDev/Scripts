-- ██████╗  █████╗ ██████╗ ████████╗    ██╗████████╗███████╗███╗   ███╗███████╗
-- ██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝    ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██████╔╝███████║██████╔╝   ██║       ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██╔═══╝ ██╔══██║██╔══██╗   ██║       ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║     ██║  ██║██║  ██║   ██║       ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

--[[
    Parts are real inventory items. Add every item in install/ox_inventory_items.lua to your inventory.

    Mode
      'orders'  mechanics need the items in their pockets to fit parts on work orders (customers pay money)
      'all'     self-service purchases also need the items (players bring their own parts)
      'off'     no items needed
]]

Config.PartItems = {
    Mode    = 'orders',
    Consume = true,               -- remove the item when the part is fitted

    -- cart item -> inventory item (string) or several items ({ 'a', 'b' })
    Items = {
        mod_11 = 'performance_part', mod_12 = 'performance_part', mod_13 = 'clutch_replacement', mod_15 = 'suspension_parts',
        mod_16 = 'performance_part', mod_18 = 'turbocharger',
        nitrous = 'nitrous_install_kit', ecu = 'performance_part', antilag = 'performance_part', launch = 'performance_part',
        airride = { 'suspension_parts', 'suspension_parts' }, stance = 'suspension_parts', height = 'suspension_parts',
        ceramic = 'ceramic_brakes', driftKit = 'drift_tuning_kit', gearbox = 'manual_gearbox',
        wheels = 'vehicle_wheels', rearWheels = 'vehicle_wheels', customTires = 'tyre_replacement', bulletproof = 'bulletproof_tyres',
        driftTyres = 'tyre_replacement', smoke = 'tyre_smoke_kit', wheelSize = 'vehicle_wheels', wheelWidth = 'tyre_replacement',
        color1 = 'respray_kit', color2 = 'respray_kit', pearl = 'respray_kit', wheelColor = 'respray_kit', livery = 'respray_kit',
        roofLivery = 'respray_kit', interiorColor = 'respray_kit', dashboardColor = 'respray_kit',
        extras = 'extras_kit', repair = 'repair_kit', neon = 'cosmetic_part', mod_22 = 'cosmetic_part', xenonColor = 'cosmetic_part',
        sound = 'performance_part', tint = 'cosmetic_part',
    },
    -- every cosmetic mod slot without an entry above uses this
    CosmeticDefault = 'cosmetic_part',
    CosmeticSlots = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46 },

    -- tyre compounds / drivetrain conversions use their own item
    Tyres      = { semi = 'semi_slick_tyres', slick = 'slick_tyres', offroad = 'offroad_tyres', stock = 'tyre_replacement' },
    Drivetrain = { awd = 'awd_drivetrain', rwd = 'rwd_drivetrain', fwd = 'fwd_drivetrain', stock = 'awd_drivetrain' },

    -- engine swaps by family (see Config.EngineSwaps.List 'family')
    Engines = {
        i4 = 'i4_engine', v6 = 'v6_engine', v8 = 'v8_engine', v10 = 'v8_engine', v12 = 'v12_engine',
        ev = { 'ev_motor', 'ev_battery', 'ev_coolant' },
    },

    -- a major service always uses these, plus a part for every worn system below 70 %
    Service = { 'engine_oil', 'spark_plug', 'air_filter' },
    ServiceWorn = { brakes = 'brakepad_replacement', tyres = 'tyre_replacement', transmission = 'clutch_replacement', suspension = 'suspension_parts' },
}

--[[
    Supply storage: every job shop keeps its own parts stock (deliveries and supply runs fill it).

    PartSource (where parts come from on work orders, a shop can override it with partSource = '...')
      'supply'     mechanics walk to the racks in the shop and the part is taken from supply storage.
                   Nothing needed in their pockets, the storage just has to have it in stock.
      'inventory'  mechanics take the parts out of supply storage into their inventory first
                   (press E at the storage point), then fit them from their pockets.
      'both'       pockets first, anything missing comes from supply storage.
]]
Config.Storage = {
    Enabled    = true,
    PartSource = 'supply',
    TakeRank   = 'access',        -- who can take parts out of storage
    PutBack    = true,            -- employees can put parts from their pockets back into storage
    UseRadius  = 2.5,             -- metres from the storage point to take / put parts
    Max        = 500,             -- most of one part a shop can hold
}

-- Parts supplier inside the tablet. Employees buy stock with the workshop account.
Config.Supplier = {
    Enabled = true,
    MinRank = 'access',           -- 'access' | 'manager' | 'boss'
    MaxPerOrder = 20,
    DeliveryMinutes = 6,          -- "Deliver now" orders arrive in supply storage after this long (0 = instantly)
    Items = {
        { item = 'engine_oil',          label = 'Engine Oil',          price = 120,   cat = 'Servicing' },
        { item = 'spark_plug',          label = 'Spark Plug',          price = 60,    cat = 'Servicing' },
        { item = 'air_filter',          label = 'Air Filter',          price = 80,    cat = 'Servicing' },
        { item = 'brakepad_replacement',label = 'Brake Pads',          price = 260,   cat = 'Servicing' },
        { item = 'tyre_replacement',    label = 'Tyre Replacement',    price = 340,   cat = 'Servicing' },
        { item = 'clutch_replacement',  label = 'Clutch Replacement',  price = 900,   cat = 'Servicing' },
        { item = 'suspension_parts',    label = 'Suspension Parts',    price = 700,   cat = 'Servicing' },
        { item = 'repair_kit',          label = 'Repair Kit',          price = 450,   cat = 'Servicing' },
        { item = 'cleaning_kit',        label = 'Cleaning Kit',        price = 90,    cat = 'Servicing' },
        { item = 'duct_tape',           label = 'Duct Tape',           price = 40,    cat = 'Servicing' },
        { item = 'performance_part',    label = 'Performance Parts',   price = 1800,  cat = 'Performance' },
        { item = 'turbocharger',        label = 'Turbocharger',        price = 6500,  cat = 'Performance' },
        { item = 'ceramic_brakes',      label = 'Ceramic Brakes',      price = 5200,  cat = 'Performance' },
        { item = 'drift_tuning_kit',    label = 'Drift Tuning Kit',    price = 4800,  cat = 'Performance' },
        { item = 'manual_gearbox',      label = 'Manual Gearbox',      price = 7200,  cat = 'Performance' },
        { item = 'nitrous_install_kit', label = 'Nitrous Install Kit', price = 5600,  cat = 'Performance' },
        { item = 'nitrous_bottle',      label = 'Nitrous Bottle',      price = 900,   cat = 'Performance' },
        { item = 'i4_engine',           label = 'I4 Engine',           price = 9000,  cat = 'Engines' },
        { item = 'v6_engine',           label = 'V6 Engine',           price = 16000, cat = 'Engines' },
        { item = 'v8_engine',           label = 'V8 Engine',           price = 26000, cat = 'Engines' },
        { item = 'v12_engine',          label = 'V12 Engine',          price = 42000, cat = 'Engines' },
        { item = 'ev_motor',            label = 'EV Motor',            price = 18000, cat = 'Engines' },
        { item = 'ev_battery',          label = 'EV Battery',          price = 15000, cat = 'Engines' },
        { item = 'ev_coolant',          label = 'EV Coolant',          price = 600,   cat = 'Engines' },
        { item = 'awd_drivetrain',      label = 'AWD Drivetrain',      price = 14000, cat = 'Drivetrain' },
        { item = 'rwd_drivetrain',      label = 'RWD Drivetrain',      price = 11000, cat = 'Drivetrain' },
        { item = 'fwd_drivetrain',      label = 'FWD Drivetrain',      price = 9000,  cat = 'Drivetrain' },
        { item = 'slick_tyres',         label = 'Slick Tyres',         price = 2400,  cat = 'Wheels' },
        { item = 'semi_slick_tyres',    label = 'Semi Slick Tyres',    price = 1600,  cat = 'Wheels' },
        { item = 'offroad_tyres',       label = 'Offroad Tyres',       price = 1400,  cat = 'Wheels' },
        { item = 'bulletproof_tyres',   label = 'Bulletproof Tyres',   price = 6000,  cat = 'Wheels' },
        { item = 'vehicle_wheels',      label = 'Wheels Set',          price = 2200,  cat = 'Wheels' },
        { item = 'tyre_smoke_kit',      label = 'Tyre Smoke Kit',      price = 700,   cat = 'Wheels' },
        { item = 'cosmetic_part',       label = 'Cosmetic Parts',      price = 400,   cat = 'Cosmetic' },
        { item = 'respray_kit',         label = 'Respray Kit',         price = 650,   cat = 'Cosmetic' },
        { item = 'extras_kit',          label = 'Extras Kit',          price = 350,   cat = 'Cosmetic' },
        { item = 'lighting_controller', label = 'Lighting Controller', price = 1200,  cat = 'Tools' },
        { item = 'stancing_kit',        label = 'Stancer Kit',         price = 2500,  cat = 'Tools' },
        { item = 'mechanic_tablet',     label = 'Mechanic Tablet',     price = 1500,  cat = 'Tools' },
        { item = 'obd_scanner',         label = 'OBD Scanner',         price = 800,   cat = 'Tools' },
    },
}

-- Usable items
Config.UsableItems = {
    Tablet             = 'mechanic_tablet',
    LightingController = 'lighting_controller',   -- underglow / headlight remote for the car you're in
    StancerKit         = 'stancing_kit',          -- adjust fitment on the fly (car needs Fitment fitted)
    StancerNeedsFitment= true,
    RepairKit          = { item = 'repair_kit', engine = 700.0, body = 650.0, time = 12000, mechanicsOnly = false },
    DuctTape           = { item = 'duct_tape', minEngine = 320.0, maxUses = 2, time = 6000 },
    CleaningKit        = { item = 'cleaning_kit', time = 8000 },
    EmptyNitrous       = 'empty_nitrous_bottle',  -- handed back after a refill (false = none)
}
