--[[ Ammu-Nation Shipment - one of four marked dock yards holds the real shipment ]]

local C = lib.load('config.heists._common')

local yards = {
    {
        label = 'Elysian Island Yard A', center = vec3(1139.23, -3193.17, 5.90),
        containers = { vec4(1132.873, -3181.619, 4.901, 0.0), vec4(1136.239, -3181.571, 4.901, 0.0), vec4(1140.260, -3181.627, 4.901, 0.0), vec4(1144.235, -3181.610, 4.901, 0.0),
                       vec4(1132.154, -3190.396, 4.901, 180.0), vec4(1136.204, -3190.360, 4.901, 180.0) },
        guards = { vec4(1144.15, -3194.87, 5.90, 186.96), vec4(1131.14, -3193.28, 5.90, 190.36), vec4(1131.55, -3178.89, 5.90, 352.56), vec4(1146.07, -3178.78, 5.90, 315.33) },
    },
    {
        label = 'Elysian Island Yard B', center = vec3(1108.26, -3080.95, 5.85),
        containers = { vec4(1092.305, -3089.684, 4.890, 90.0), vec4(1092.393, -3086.037, 4.889, 90.0), vec4(1092.362, -3082.694, 4.889, 90.0),
                       vec4(1099.923, -3078.022, 4.877, 270.0), vec4(1099.975, -3081.758, 4.872, 270.0), vec4(1099.965, -3085.479, 4.873, 270.0) },
        guards = { vec4(1103.34, -3076.24, 5.88, 248.45), vec4(1103.06, -3090.12, 5.87, 327.22), vec4(1087.97, -3091.63, 5.90, 87.44), vec4(1088.08, -3078.17, 5.90, 151.81) },
    },
    {
        label = 'Terminal Yard', center = vec3(1280.73, -3304.15, 5.90),
        containers = { vec4(1283.748, -3306.488, 4.918, 270.0), vec4(1283.816, -3309.939, 4.918, 270.0), vec4(1283.905, -3313.388, 4.903, 270.0),
                       vec4(1275.467, -3317.947, 4.902, 90.0), vec4(1275.323, -3314.343, 4.902, 90.0), vec4(1275.298, -3310.718, 4.902, 90.0) },
        guards = { vec4(1284.10, -3295.26, 5.90, 39.69), vec4(1283.01, -3295.59, 5.90, 103.70), vec4(1279.43, -3296.21, 5.90, 98.90), vec4(1281.01, -3293.91, 5.90, 295.24) },
    },
    {
        label = 'Port Warehouse Row', center = vec3(847.45, -3137.83, 5.90),
        containers = { vec4(851.277, -3129.968, 4.901, 0.0), vec4(846.507, -3130.134, 4.901, 0.0), vec4(842.801, -3130.106, 4.901, 0.0),
                       vec4(838.674, -3129.948, 4.901, 0.0), vec4(834.592, -3130.084, 4.901, 0.0), vec4(830.361, -3130.236, 4.901, 0.0) },
        guards = { vec4(823.15, -3134.15, 5.90, 171.59), vec4(832.60, -3133.72, 5.90, 197.27), vec4(843.76, -3133.96, 5.90, 176.98), vec4(851.89, -3134.15, 5.90, 202.05) },
    },
}

local CONTAINER_MODELS = { 'tr_prop_tr_container_01a', 'tr_prop_tr_container_01b', 'tr_prop_tr_container_01c', 'tr_prop_tr_container_01d' }

return {
    label = 'Ammu-Nation Shipment',
    description = 'An Ammu-Nation weapons shipment sits in one of four dock yards. Find the right one, kill the guards and cut the containers open.',
    category = 'medium',
    icon = 'gun',
    level = 3,
    police = 2,
    members = { min = 2, max = 6 },
    cooldown = 40,
    playerCooldown = 15,
    timeLimit = 30,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 700, money = { 4000, 7000 } },
    requiredItems = { { name = 'angle_grinder', count = 1, label = 'Angle Grinder' } },
    briefing = {
        'Four yards are marked - only one holds the shipment. Check them.',
        'Take out the guards at the real yard.',
        'Cut the containers open with an Angle Grinder and grab the weapon parts.',
    },
    loot = {
        container = {
            { item = 'weapon_parts', min = 2, max = 5 },
            { item = 'money', min = 800, max = 1600, chance = 0.5 },
        },
    },
    locations = yards,
    stages = function(loc)
        local search = {}
        for i = 1, #yards do
            local y = yards[i]
            local real = y.center == loc.center
            search[i] = {
                id = real and 'real' or ('decoy' .. i), type = 'zone', coords = y.center, radius = 25.0, label = 'Possible shipment',
                decoy = not real, required = real, objective = 'Find the shipment', blip = { label = 'Possible shipment', sprite = 478 },
            }
        end
        local containers = {}
        for i = 1, #loc.containers do
            local c = loc.containers[i]
            containers[#containers + 1] = { id = 'box' .. i, type = 'prop', coords = c.xyz, heading = c.w, prop = { model = CONTAINER_MODELS[(i - 1) % #CONTAINER_MODELS + 1], heading = c.w } }
            containers[#containers + 1] = {
                id = 'cut' .. i, type = 'interact', action = 'cut', label = 'Cut container open', icon = 'fas fa-scissors',
                coords = vec3(c.x, c.y, c.z + 1.0), radius = 3.2, duration = 7000, reward = 'container',
                item = { name = 'angle_grinder', label = 'Angle Grinder' }, requires = { 'guards' }, objective = 'Containers',
            }
        end
        containers[#containers + 1] = { id = 'guards', type = 'eliminate', group = 'guards', label = 'Take out the guards' }
        return {
            { id = 'find', task = 'Find the real shipment', nodes = search, complete = 1 },
            {
                id = 'raid',
                task = 'Take out the guards',
                blip = { coords = loc.center, label = loc.label },
                spawn = { at = loc.center, distance = 200.0, guards = C.guards(loc.guards, { model = 's_m_y_blackops_01', weapon = 'WEAPON_CARBINERIFLE' }) },
                nodes = containers,
            },
        }
    end,
}
