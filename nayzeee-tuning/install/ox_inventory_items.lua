-- Add to ox_inventory/data/items.lua
-- Usable items are registered by nayzeee-tuning through your framework (ESX / QBCore / Qbox), no client events needed.
-- Item images: put PNGs with the same names in ox_inventory/web/images/

['mechanic_tablet'] = {
    label = 'Mechanic Tablet',
    weight = 900,
    stack = false,
    close = true,
    description = "Rugged workshop tablet. Orders, diagnostics, ECU tuning and your own settings.",
},

['engine_oil'] = {
    label = 'Engine Oil',
    weight = 1000,
    stack = true,
    close = false,
    description = "5W-30 synthetic. Used in every major service.",
},

['spark_plug'] = {
    label = 'Spark Plug',
    weight = 100,
    stack = true,
    close = false,
    description = "Iridium spark plug. Used in every major service.",
},

['air_filter'] = {
    label = 'Air Filter',
    weight = 300,
    stack = true,
    close = false,
    description = "Performance air filter element.",
},

['brakepad_replacement'] = {
    label = 'Brake Pads',
    weight = 1200,
    stack = true,
    close = false,
    description = "Replacement brake pads for worn brakes.",
},

['tyre_replacement'] = {
    label = 'Tyre Replacement',
    weight = 4000,
    stack = true,
    close = false,
    description = "A set of road tyres.",
},

['clutch_replacement'] = {
    label = 'Clutch Replacement',
    weight = 5000,
    stack = true,
    close = false,
    description = "Clutch kit for transmission work.",
},

['suspension_parts'] = {
    label = 'Suspension Parts',
    weight = 4500,
    stack = true,
    close = false,
    description = "Coilovers, bushes and arms.",
},

['i4_engine'] = {
    label = 'I4 Engine',
    weight = 60000,
    stack = false,
    close = false,
    description = "Inline-four crate engine for swaps.",
},

['v6_engine'] = {
    label = 'V6 Engine',
    weight = 80000,
    stack = false,
    close = false,
    description = "V6 crate engine for swaps.",
},

['v8_engine'] = {
    label = 'V8 Engine',
    weight = 100000,
    stack = false,
    close = false,
    description = "V8 crate engine for swaps.",
},

['v12_engine'] = {
    label = 'V12 Engine',
    weight = 130000,
    stack = false,
    close = false,
    description = "V12 crate engine for swaps.",
},

['turbocharger'] = {
    label = 'Turbocharger',
    weight = 9000,
    stack = true,
    close = false,
    description = "Bolt-on turbo kit.",
},

['ev_motor'] = {
    label = 'EV Motor',
    weight = 45000,
    stack = false,
    close = false,
    description = "Electric drive unit for EV conversions.",
},

['ev_battery'] = {
    label = 'EV Battery',
    weight = 90000,
    stack = false,
    close = false,
    description = "High-voltage battery pack for EV conversions.",
},

['ev_coolant'] = {
    label = 'EV Coolant',
    weight = 1000,
    stack = true,
    close = false,
    description = "Battery coolant for EV conversions.",
},

['awd_drivetrain'] = {
    label = 'AWD Drivetrain',
    weight = 40000,
    stack = false,
    close = false,
    description = "All-wheel-drive conversion kit.",
},

['rwd_drivetrain'] = {
    label = 'RWD Drivetrain',
    weight = 35000,
    stack = false,
    close = false,
    description = "Rear-wheel-drive conversion kit.",
},

['fwd_drivetrain'] = {
    label = 'FWD Drivetrain',
    weight = 30000,
    stack = false,
    close = false,
    description = "Front-wheel-drive conversion kit.",
},

['slick_tyres'] = {
    label = 'Slick Tyres',
    weight = 8000,
    stack = true,
    close = false,
    description = "Track slicks. Maximum grip, useless off road.",
},

['semi_slick_tyres'] = {
    label = 'Semi Slick Tyres',
    weight = 7000,
    stack = true,
    close = false,
    description = "Road-legal semi slicks.",
},

['offroad_tyres'] = {
    label = 'Offroad Tyres',
    weight = 9000,
    stack = true,
    close = false,
    description = "All-terrain tyres.",
},

['drift_tuning_kit'] = {
    label = 'Drift Tuning Kit',
    weight = 12000,
    stack = true,
    close = false,
    description = "Steering lock, knuckles and a loose rear end.",
},

['ceramic_brakes'] = {
    label = 'Ceramic Brakes',
    weight = 9000,
    stack = true,
    close = false,
    description = "Carbon-ceramic brake kit.",
},

['lighting_controller'] = {
    label = 'Lighting Controller',
    weight = 300,
    stack = false,
    close = true,
    description = "Remote for your underglow. Use it in the driver seat.",
},

['stancing_kit'] = {
    label = 'Stancer Kit',
    weight = 2500,
    stack = false,
    close = true,
    description = "Adjust track width, camber and ride height on the fly.",
},

['cosmetic_part'] = {
    label = 'Cosmetic Parts',
    weight = 2000,
    stack = true,
    close = false,
    description = "Body kit panels, trims and fittings.",
},

['respray_kit'] = {
    label = 'Respray Kit',
    weight = 1500,
    stack = true,
    close = false,
    description = "Paint, primer and clear coat.",
},

['vehicle_wheels'] = {
    label = 'Wheels Set',
    weight = 12000,
    stack = true,
    close = false,
    description = "A set of aftermarket rims.",
},

['tyre_smoke_kit'] = {
    label = 'Tyre Smoke Kit',
    weight = 500,
    stack = true,
    close = false,
    description = "Coloured tyre smoke compound.",
},

['bulletproof_tyres'] = {
    label = 'Bulletproof Tyres',
    weight = 14000,
    stack = true,
    close = false,
    description = "Run-flat tyres.",
},

['extras_kit'] = {
    label = 'Extras Kit',
    weight = 800,
    stack = true,
    close = false,
    description = "Factory extras and accessories.",
},

['nitrous_bottle'] = {
    label = 'Nitrous Bottle',
    weight = 3000,
    stack = true,
    close = true,
    description = "Refills a fitted nitrous kit. Use it next to the car.",
},

['empty_nitrous_bottle'] = {
    label = 'Empty Nitrous Bottle',
    weight = 1500,
    stack = true,
    close = false,
    description = "Return it to a workshop for a refill.",
},

['nitrous_install_kit'] = {
    label = 'Nitrous Install Kit',
    weight = 6000,
    stack = true,
    close = false,
    description = "Solenoids, lines and a bottle bracket.",
},

['cleaning_kit'] = {
    label = 'Cleaning Kit',
    weight = 600,
    stack = true,
    close = true,
    description = "Sponge and snow foam. Use it next to a dirty car.",
},

['repair_kit'] = {
    label = 'Repair Kit',
    weight = 2500,
    stack = true,
    close = true,
    description = "Fixes body and engine damage on the spot.",
},

['duct_tape'] = {
    label = 'Duct Tape',
    weight = 100,
    stack = true,
    close = true,
    description = "Holds a dead engine together long enough to limp home.",
},

['performance_part'] = {
    label = 'Performance Parts',
    weight = 3000,
    stack = true,
    close = false,
    description = "Engine internals, ECU hardware and upgrades.",
},

['manual_gearbox'] = {
    label = 'Manual Gearbox',
    weight = 25000,
    stack = false,
    close = false,
    description = "H-pattern manual conversion.",
},

['tuning_component'] = {
    label = 'Tuning Component',
    weight = 250,
    stack = true,
    close = false,
    description = "Salvaged parts a workshop can use as payment.",
},

['obd_scanner'] = {
    label = 'OBD Scanner',
    weight = 600,
    stack = false,
    close = true,
    description = "Reads fault codes and part condition from a vehicle.",
},
