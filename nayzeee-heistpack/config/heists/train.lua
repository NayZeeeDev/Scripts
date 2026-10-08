--[[ Freight Train Heist - a guarded freight train is stopped in the hills; burn the cargo containers open ]]

local C = lib.load('config.heists._common')

return {
    label = 'Freight Train',
    description = 'A freight train carrying cash and gold is stopped at a signal. Kill the guards and burn the cargo containers open.',
    category = 'major',
    icon = 'train',
    level = 4,
    police = 2,
    members = { min = 2, max = 8 },
    cooldown = 40,
    playerCooldown = 20,
    timeLimit = 30,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 1100, money = { 6000, 10000 } },
    requiredItems = { { name = 'thermite', count = 2, label = 'Thermite Charge x2' } },
    briefing = {
        'Go to the marked stretch of track.',
        'Kill the train guards.',
        'Burn the two cargo container locks with thermite and loot them.',
    },
    loot = {
        container = { { item = 'money', min = 7000, max = 11000 }, { item = 'gold_bar', min = 1, max = 3 } },
    },
    locations = {
        {
            label = 'Grapeseed Rail Line',
            center = vec3(2905.0, 4578.0, 48.0),
            train = vec4(2891.08, 4564.92, 47.80, 136.38),
            cars = { vec4(2916.98, 4592.43, 47.80, 316.55), vec4(2903.76, 4578.44, 47.80, 316.55) },
            containers = { vec4(2918.479, 4594.036, 48.059, 316.55), vec4(2903.812, 4578.493, 48.059, 316.55) },
            guards = {
                vec4(2904.03, 4572.19, 48.20, 159.50), vec4(2898.91, 4566.85, 48.11, 137.08), vec4(2887.71, 4564.72, 48.46, 138.25),
                vec4(2912.68, 4583.54, 48.37, 204.06), vec4(2921.50, 4590.00, 48.30, 220.00), vec4(2895.00, 4575.00, 48.20, 120.00),
            },
        },
    },
    stages = function(loc)
        local nodes = { { id = 'guards', type = 'eliminate', group = 'guards', label = 'Kill the train guards' } }
        for i = 1, #loc.containers do
            local c = loc.containers[i]
            local door = vec3(c.x, c.y, c.z + 1.2)
            nodes[#nodes + 1] = { id = 'box' .. i, type = 'prop', coords = c.xyz, heading = c.w, prop = { model = i == 1 and 'tr_prop_tr_container_01a' or 'tr_prop_tr_container_01b', heading = c.w } }
            nodes[#nodes + 1] = {
                id = 'burn' .. i, type = 'interact', action = 'thermite', label = 'Burn the container lock', icon = 'fas fa-fire',
                coords = door, radius = 3.5, burn = 8000, minigame = { type = 'memory', difficulty = 2 }, requires = { 'guards' },
                item = { name = 'thermite', label = 'Thermite', remove = true }, objective = 'Containers opened',
            }
            nodes[#nodes + 1] = {
                id = 'loot' .. i, type = 'interact', action = 'grab', label = 'Loot container', icon = 'fas fa-box-open',
                coords = door, radius = 3.5, duration = 6000, reward = 'container', requires = { 'burn' .. i },
            }
        end
        return {
            {
                id = 'train',
                task = 'Hit the stopped train',
                blip = { coords = loc.center, label = 'Freight train' },
                alert = true,
                spawn = {
                    at = loc.center, distance = 220.0,
                    guards = C.guards(loc.guards, { model = 's_m_m_security_01', weapons = { 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN' }, ground = true }),
                    vehicles = {
                        { key = 'loco', model = 'freight', coords = loc.train, freeze = true },
                        { key = 'car1', model = 'freightcar', coords = loc.cars[1], freeze = true },
                        { key = 'car2', model = 'freightcar', coords = loc.cars[2], freeze = true },
                    },
                },
                nodes = nodes,
            },
        }
    end,
}
