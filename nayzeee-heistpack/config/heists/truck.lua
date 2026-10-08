--[[ Container Heist - steal a rig, clear the container yard, load a container with the handler, deliver it ]]

local C = lib.load('config.heists._common')

return {
    label = 'Container Heist',
    description = 'Steal a rig and flatbed, clear the guarded container yard, lift the container onto the trailer with the handler and haul it out.',
    category = 'major',
    icon = 'container',
    level = 4,
    police = 2,
    members = { min = 2, max = 6 },
    cooldown = 40,
    playerCooldown = 20,
    timeLimit = 40,
    simultaneous = 1,
    escape = false,
    rewards = { xp = 1300, money = { 18000, 26000 } },
    requiredItems = {},
    briefing = {
        'Steal the rig and flatbed trailer in Cypress Flats.',
        'Drive to the container yard and kill the guards.',
        'Use the handler (container forklift) to lift the container - press E above it - then E again next to the trailer to load it.',
        'Drive the rig and the loaded trailer to the drop-off.',
    },
    loot = {},
    locations = {
        {
            label = 'Port of Los Santos - Container Yard',
            center = vec3(75.0, -2488.0, 6.0),
            truck = vec4(988.51, -2532.91, 28.38, 356.68),
            trailer = vec4(987.64, -2544.51, 30.24, 356.68),
            handler = vec4(85.61, -2490.03, 6.20, 60.47),
            container = vec4(68.10, -2491.38, 5.01, 54.30),
            dropoff = vec3(-459.08, -1714.87, 18.64),
            guards = {
                vec4(65.15, -2483.75, 6.01, 47.85), vec4(70.93, -2474.47, 6.01, 97.58), vec4(93.37, -2487.91, 6.00, 70.27),
                vec4(87.29, -2497.17, 6.00, 45.92), vec4(73.50, -2480.00, 6.01, 60.00), vec4(80.20, -2478.50, 6.01, 85.00),
                vec4(90.00, -2485.00, 6.01, 75.00),
            },
        },
    },
    stages = function(loc)
        return {
            {
                id = 'rig',
                task = 'Steal the rig and trailer',
                blip = { coords = loc.truck.xyz, label = 'Rig' },
                spawn = {
                    at = loc.truck.xyz, distance = 200.0,
                    vehicles = {
                        { key = 'truck', model = 'phantom', coords = loc.truck },
                        { key = 'trailer', model = 'trflat', coords = loc.trailer, attachTo = 'truck' },
                    },
                },
                nodes = {
                    { id = 'getrig', type = 'zone', coords = loc.truck.xyz, radius = 6.0, label = 'Rig', objective = 'Get to the rig', keys = { 'truck' } },
                },
            },
            {
                id = 'yard',
                task = 'Clear the container yard',
                blip = { coords = loc.center, label = 'Container yard' },
                spawn = {
                    at = loc.center, distance = 220.0,
                    guards = C.guards(loc.guards, { model = 's_m_y_dockwork_01', weapons = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_PISTOL', 'WEAPON_MICROSMG' } }),
                    vehicles = { { key = 'handler', model = 'handler', coords = loc.handler } },
                    objects = { { key = 'container', model = C.models.handlerBox, coords = loc.container, ground = false } },
                },
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Kill the yard guards', keys = { 'truck', 'handler' } },
                },
            },
            {
                id = 'haul',
                task = 'Load the container and deliver it',
                nodes = {
                    {
                        id = 'deliver', type = 'deliver', entity = 'container', dropoff = loc.dropoff, radius = 15.0, label = 'Drop-off',
                        entityLabel = 'Container', keys = { 'truck', 'handler' }, handler = { handler = 'handler', trailer = 'trailer', offset = vec3(0.0, -0.6, 1.1) },
                    },
                },
            },
        }
    end,
}
