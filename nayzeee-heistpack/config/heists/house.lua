--[[
    House Burglary - break in, clean the place out quietly.
    Interiors are vanilla apartments entered in a private routing bucket, so several crews can
    rob "the same" interior at once. Loot is found by scanning the interior for valuable props,
    so it also works if you swap in your own MLO / shell interiors.
]]

local C = lib.load('config.heists._common')

local interiors = {
    lowend = {
        inside = vec4(265.96, -1006.60, -101.01, 0.0), exit = vec3(265.96, -1007.46, -101.01),
        scan = vec3(262.5, -1000.0, -99.5), scanRadius = 12.0,
        spots = { vec3(266.32, -999.40, -99.50), vec3(264.37, -995.11, -99.45), vec3(259.84, -1004.32, -99.00), vec3(256.73, -995.45, -98.86) },
    },
    midend = {
        inside = vec4(346.62, -1012.60, -99.20, 0.0), exit = vec3(346.62, -1013.47, -99.20),
        scan = vec3(344.5, -1000.0, -99.2), scanRadius = 15.0,
        spots = { vec3(351.25, -993.17, -99.23), vec3(348.74, -994.88, -99.50), vec3(337.51, -995.06, -99.20), vec3(343.80, -1003.79, -99.70), vec3(352.56, -998.75, -100.0) },
    },
    highend = {
        inside = vec4(-1289.77, 450.20, 97.81, 267.59), exit = vec3(-1289.20, 450.20, 97.81),
        scan = vec3(-1287.5, 447.0, 94.0), scanRadius = 20.0,
        spots = { vec3(-1287.10, 447.17, 97.89), vec3(-1290.74, 432.44, 94.00), vec3(-1282.95, 445.88, 93.70), vec3(-1293.27, 451.50, 90.29), vec3(-1286.18, 459.04, 90.00) },
    },
}

local houses = {
    { label = 'Vespucci Canals',     door = vec4(-947.54, -928.01, 2.15, 303.16),   interior = 'lowend' },
    { label = 'Vespucci Beach',      door = vec4(-1034.92, -1227.66, 6.30, 123.0),  interior = 'midend' },
    { label = 'Mirror Park Villa',   door = vec4(965.02, -541.55, 59.72, 0.0),      interior = 'highend' },
    { label = 'Mirror Park Bungalow', door = vec4(1229.60, -725.47, 60.95, 90.0),   interior = 'midend' },
    { label = 'Grove Street House',  door = vec4(126.88, -1929.97, 21.38, 210.0),   interior = 'lowend' },
    { label = 'Forum Drive House',   door = vec4(-14.31, -1441.18, 31.10, 0.0),     interior = 'lowend' },
}

local locations = {}
for i = 1, #houses do
    local h = houses[i]
    local int = interiors[h.interior]
    locations[i] = { label = h.label, center = h.door.xyz, door = h.door, int = int }
end

-- prop model -> how it is looted. carry = true props are carried out to a vehicle trunk.
local SCAN_MODELS = {
    prop_tv_flat_01 = { label = 'Take TV', reward = 'tv', carry = { model = 'prop_tv_flat_01' } },
    prop_tv_flat_02 = { label = 'Take TV', reward = 'tv', carry = { model = 'prop_tv_flat_02' } },
    prop_tv_flat_03 = { label = 'Take TV', reward = 'tv', carry = { model = 'prop_tv_flat_03' } },
    prop_tv_03 = { label = 'Take old TV', reward = 'tv_old', carry = { model = 'prop_tv_03' } },
    prop_laptop_01a = { label = 'Take laptop', reward = 'laptop', action = 'grab', duration = 2500 },
    prop_micro_01 = { label = 'Take microwave', reward = 'appliance', carry = { model = 'prop_micro_01' } },
    prop_console_01 = { label = 'Take console', reward = 'electronics', action = 'grab', duration = 2500 },
    prop_vcr_01 = { label = 'Take VCR', reward = 'electronics', action = 'grab', duration = 2500 },
    prop_coffee_mac_02 = { label = 'Take coffee machine', reward = 'appliance', carry = { model = 'prop_coffee_mac_02' } },
    prop_monitor_w_large = { label = 'Take monitor', reward = 'electronics', carry = { model = 'prop_monitor_w_large' } },
    prop_printer_01 = { label = 'Take printer', reward = 'electronics', carry = { model = 'prop_printer_01' } },
    v_res_jewelbox = { label = 'Search jewelry box', reward = 'jewelry', action = 'search', duration = 3500 },
    prop_ld_int_safe_01 = { label = 'Crack safe', reward = 'safe', action = 'safecrack', duration = 6000 },
}

return {
    label = 'House Burglary',
    description = 'Break into a home and clean it out. Stay quiet - sprinting, jumping and gunfire fill the noise meter.',
    category = 'small',
    icon = 'house',
    level = 1,
    police = 0,
    members = { min = 1, max = 4 },
    cooldown = 0,
    locationCooldown = 30,
    playerCooldown = 10,
    timeLimit = 20,
    simultaneous = 4,
    escape = 120.0,
    rewards = { xp = 260, money = { 400, 900 } },
    requiredItems = { { name = 'lockpick', count = 1, label = 'Lockpick' } },
    briefing = {
        'Head to the marked house and pick the front door lock.',
        'Search drawers and cabinets; carry TVs and appliances out to a vehicle trunk.',
        'Keep the noise meter low - if it maxes out the neighbours call the police.',
        'Leave the house and get clear of the area.',
    },
    loot = {
        spot = {
            { item = 'money', min = 80, max = 350, chance = 0.7 },
            { item = 'gold_chain', min = 1, max = 1, chance = 0.25 },
            { item = 'necklace', min = 1, max = 1, chance = 0.15 },
            { item = 'electronics', min = 1, max = 2, chance = 0.3 },
        },
        tv = { { item = 'electronics', min = 3, max = 5 } },
        tv_old = { { item = 'electronics', min = 1, max = 2 } },
        laptop = { { item = 'laptop', min = 1, max = 1 } },
        appliance = { { item = 'electronics', min = 1, max = 3 } },
        electronics = { { item = 'electronics', min = 1, max = 2 } },
        jewelry = {
            { item = 'rolex', min = 1, max = 1, chance = 0.4 },
            { item = 'diamond_ring', min = 1, max = 1, chance = 0.3 },
            { item = 'necklace', min = 1, max = 2, chance = 0.6 },
        },
        safe = { { item = 'money', min = 1500, max = 3500 }, { item = 'diamond', min = 1, max = 2, chance = 0.2 } },
    },
    locations = locations,
    stages = function(loc)
        local int = loc.int
        local nodes = {
            { id = 'enter', type = 'portal', label = 'Enter house', icon = 'fas fa-door-open', coords = loc.door.xyz, radius = 1.2, target = int.inside, bucket = 'enter', requires = { 'lockpick' } },
            { id = 'exit', type = 'portal', label = 'Leave house', icon = 'fas fa-door-closed', coords = int.exit, radius = 1.2, target = loc.door, bucket = 'exit' },
            { id = 'scan', type = 'scan', coords = int.scan, radius = int.scanRadius, models = SCAN_MODELS, max = 8 },
        }
        for i = 1, #int.spots do
            nodes[#nodes + 1] = C.search('spot' .. i, int.spots[i], 'spot', { label = 'Search', duration = 4500 })
        end
        return {
            {
                id = 'breakin',
                task = 'Pick the front door lock',
                blip = { coords = loc.door.xyz, label = loc.label },
                nodes = {
                    {
                        id = 'lockpick', type = 'interact', action = 'lockpick', label = 'Pick the lock', icon = 'fas fa-key',
                        coords = loc.door.xyz, radius = 1.2, minigame = { type = 'lockpick', difficulty = 2 },
                        item = { name = 'lockpick', label = 'Lockpick', remove = 0.2, removeOnFail = true }, alert = 0.1,
                    },
                },
            },
            {
                id = 'loot',
                task = 'Clean the house out quietly',
                noise = true,
                nodes = nodes,
            },
        }
    end,
}
