--[[ Vangelico Jewel Heist - gas the store from the rooftops with the drone, breach, smash and grab ]]

local CASES = {
    vec3(-626.32, -239.05, 38.05), vec3(-625.28, -238.29, 38.05), vec3(-619.85, -234.91, 38.05), vec3(-618.80, -234.15, 38.05),
    vec3(-617.09, -230.16, 38.05), vec3(-617.85, -229.11, 38.05), vec3(-619.20, -227.25, 38.05), vec3(-619.97, -226.20, 38.05),
    vec3(-624.28, -226.61, 38.05), vec3(-625.33, -227.37, 38.05), vec3(-626.54, -233.60, 38.05), vec3(-627.59, -234.37, 38.05),
    vec3(-627.21, -234.89, 38.05), vec3(-626.16, -234.13, 38.05), vec3(-622.62, -232.56, 38.05), vec3(-620.52, -232.88, 38.05),
    vec3(-620.18, -230.79, 38.05), vec3(-621.52, -228.95, 38.05), vec3(-623.61, -228.62, 38.05), vec3(-623.96, -230.73, 38.05),
}

return {
    label = 'Vangelico Jewel Heist',
    description = 'Drop knockout gas into the vents with a drone, blow the locked doors and clean out the cases, art and back-office safe.',
    category = 'major',
    icon = 'diamond',
    level = 4,
    police = 3,
    members = { min = 2, max = 6 },
    cooldown = 45,
    playerCooldown = 20,
    timeLimit = 30,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 1200, money = { 6000, 10000 } },
    requiredItems = {
        { name = 'heist_drone', count = 1, label = 'Recon Drone' },
        { name = 'c4_charge', count = 1, label = 'C4 Charge' },
    },
    alertTitle = 'Vangelico Alarm',
    briefing = {
        'Go to the marked rooftop and launch your drone (use the item).',
        'Fly over the three marked vents and press G to drop the gas canisters.',
        'Wear a gas mask inside - the gas hurts anyone without one.',
        'Blow the locked front doors with C4, smash the cases (weapon in hand), take the paintings and drill the safe.',
        'Get 250m away.',
    },
    loot = {
        case = {
            { item = 'rolex', min = 1, max = 3, chance = 0.7 },
            { item = 'diamond_ring', min = 1, max = 2, chance = 0.5 },
            { item = 'necklace', min = 1, max = 2, chance = 0.6 },
            { item = 'diamond', min = 1, max = 1, chance = 0.15 },
        },
        painting = { { item = 'painting', min = 1, max = 1 } },
        safe = { { item = 'money', min = 6000, max = 9000 }, { item = 'diamond', min = 2, max = 4 } },
    },
    locations = {
        {
            label = 'Vangelico Rockford Hills',
            center = vec3(-622.30, -231.00, 38.05),
            launch = vec3(-766.55, -188.71, 48.62),
            vents = { vec3(-622.45, -233.63, 58.1), vec3(-626.98, -216.57, 58.49), vec3(-598.59, -265.39, 56.42) },
            doors = {
                front_l = { model = 'p_jewel_door_l', coords = vec3(-631.96, -236.33, 38.21), radius = 2.0, kind = 'gate' },
                front_r = { model = 'p_jewel_door_r1', coords = vec3(-630.43, -238.44, 38.21), radius = 2.0, kind = 'gate' },
            },
        },
    },
    stages = function(loc)
        local gas = {}
        for i = 1, #loc.vents do
            gas[i] = {
                id = 'vent' .. i, type = 'dronedrop', coords = loc.vents[i], radius = 3.0, label = 'Ventilation shaft', objective = 'Gas the vents',
                effect = { asset = 'core', name = 'exp_grd_bzgas_smoke' }, dropMessage = 'Gas canister dropped',
            }
        end
        gas[#gas + 1] = { id = 'launch', type = 'zone', coords = loc.launch, radius = 8.0, label = 'Drone launch point', required = false, blip = { label = 'Drone launch point', sprite = 627 } }

        local store = {
            { id = 'gas', type = 'hazard', coords = loc.center, radius = 14.0, damage = 4, label = 'Knockout gas', requiresFlag = 'gassed' },
        }
        for i = 1, #CASES do
            store[#store + 1] = { id = 'case' .. i, type = 'smash', label = 'Smash case', coords = CASES[i], radius = 0.8, reward = 'case', objective = 'Cases', requires = { 'doors' } }
        end
        store[#store + 1] = {
            id = 'painting1', type = 'carry', label = 'Take painting', icon = 'fas fa-image', coords = vec3(-627.22, -228.32, 38.2), radius = 1.0,
            reward = 'painting', carry = { model = 'ch_prop_vault_painting_01a', pos = vec3(0.0, -0.05, -0.3) }, requires = { 'doors' },
        }
        store[#store + 1] = {
            id = 'painting2', type = 'carry', label = 'Take painting', icon = 'fas fa-image', coords = vec3(-617.00, -233.22, 38.2), radius = 1.0,
            reward = 'painting', carry = { model = 'ch_prop_vault_painting_01a', pos = vec3(0.0, -0.05, -0.3) }, requires = { 'doors' },
        }
        store[#store + 1] = {
            id = 'safe', type = 'interact', action = 'drill', label = 'Drill the office safe', icon = 'fas fa-vault', coords = vec3(-630.56, -228.28, 37.81),
            radius = 1.0, minigame = { type = 'drill', difficulty = 3 }, reward = 'safe', item = { name = 'heist_drill', label = 'Heavy Drill' }, requires = { 'doors' },
        }
        store[#store + 1] = {
            id = 'doors', type = 'interact', action = 'c4', label = 'Plant C4 on the doors', icon = 'fas fa-bomb', coords = vec3(-631.20, -237.40, 38.21),
            radius = 1.5, fuse = 6000, unlocks = { 'front_l', 'front_r' }, item = { name = 'c4_charge', label = 'C4 Charge', remove = true }, alert = 1.0,
        }

        return {
            {
                id = 'gas',
                task = 'Gas the store from the rooftops',
                blip = { coords = loc.launch, label = 'Drone launch point', sprite = 627 },
                nodes = gas,
                onComplete = { flag = 'gassed' },
            },
            {
                id = 'breach',
                task = 'Blow the front doors',
                blip = { coords = loc.center, label = 'Vangelico' },
                nodes = store,
            },
        }
    end,
}
