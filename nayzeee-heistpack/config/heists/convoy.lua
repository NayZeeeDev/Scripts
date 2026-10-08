--[[ Military Convoy (new) - ambush a weapons convoy on Route 68 ]]

return {
    label = 'Military Convoy',
    description = 'A Merryweather convoy is moving weapons to Fort Zancudo along Route 68. Ambush it, kill the escort and cut open the cargo truck.',
    category = 'major',
    icon = 'convoy',
    level = 6,
    police = 3,
    members = { min = 3, max = 8 },
    cooldown = 60,
    playerCooldown = 25,
    timeLimit = 30,
    simultaneous = 1,
    escape = 300.0,
    rewards = { xp = 1700, money = { 10000, 16000 } },
    requiredItems = { { name = 'angle_grinder', count = 1, label = 'Angle Grinder' } },
    alertTitle = 'Convoy under attack',
    briefing = {
        'The convoy starts near Harmony and drives west towards Fort Zancudo.',
        'Stop it and kill every escort.',
        'Cut open the cargo truck with an Angle Grinder and grab the weapon crates.',
    },
    loot = {
        crate = { { item = 'weapon_parts', min = 3, max = 6 }, { item = 'money', min = 2500, max = 4000 } },
    },
    locations = {
        {
            label = 'Route 68 - Harmony',
            center = vec3(1130.0, 2690.0, 38.6),
            truck = vec4(1130.0, 2690.0, 38.6, 90.0),
            escort1 = vec4(1145.0, 2690.5, 38.6, 90.0),
            escort2 = vec4(1115.0, 2689.5, 38.6, 90.0),
            route = vec3(-1570.0, 2780.0, 17.0),
        },
    },
    stages = function(loc)
        local merc = { model = 's_m_y_blackops_01', weapon = 'WEAPON_CARBINERIFLE', group = 'convoy' }
        local merc2 = { model = 's_m_y_blackops_02', weapon = 'WEAPON_SPECIALCARBINE' }
        return {
            {
                id = 'ambush',
                task = 'Ambush the convoy',
                blip = { coords = loc.center, label = 'Convoy' },
                alert = true,
                spawn = {
                    at = loc.center, distance = 350.0,
                    vehicles = {
                        { key = 'truck', model = 'barracks', coords = loc.truck, route = loc.route, speed = 16.0, locked = true, driver = merc, passengers = { merc2 } },
                        { key = 'escort1', model = 'mesa3', coords = loc.escort1, route = loc.route, speed = 16.0, driver = merc, passengers = { merc2, merc2 } },
                        { key = 'escort2', model = 'mesa3', coords = loc.escort2, route = loc.route, speed = 16.0, driver = merc, passengers = { merc2, merc2 } },
                    },
                },
                nodes = {
                    { id = 'convoy', type = 'eliminate', group = 'convoy', label = 'Kill the escort', blipEntity = 'truck', entityLabel = 'Cargo truck' },
                },
            },
            {
                id = 'cargo',
                task = 'Cut open the cargo truck',
                nodes = {
                    {
                        id = 'cut', type = 'interact', action = 'cut', label = 'Cut the cargo lock', icon = 'fas fa-scissors',
                        attach = { entity = 'truck', offset = vec3(0.0, -5.0, 0.0) }, radius = 1.8, duration = 10000, flag = 'open',
                        item = { name = 'angle_grinder', label = 'Angle Grinder' },
                    },
                    {
                        id = 'crates', type = 'interact', action = 'grab', label = 'Grab weapon crate', icon = 'fas fa-box',
                        attach = { entity = 'truck', offset = vec3(0.0, -5.0, 0.0) }, radius = 1.8, uses = 4, duration = 5000,
                        reward = 'crate', requiresFlag = 'open', objective = 'Weapon crates',
                    },
                },
            },
        }
    end,
}
