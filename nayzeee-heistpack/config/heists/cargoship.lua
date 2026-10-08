--[[ Cargo Ship - boat out, climb aboard, find the captain's key, lift two containers off with the Skylift ]]

local C = lib.load('config.heists._common')

local GUARDS = {
    vec4(-304.22, -4041.59, 14.30, 122.31), vec4(-307.92, -4035.26, 14.30, 27.25), vec4(-329.25, -4060.97, 9.31, 156.70),
    vec4(-339.44, -4053.75, 9.32, 340.47), vec4(-353.14, -4065.23, 9.32, 219.14), vec4(-365.55, -4075.56, 9.31, 134.27),
    vec4(-381.81, -4089.46, 9.31, 134.04), vec4(-408.02, -4111.12, 9.31, 131.62), vec4(-424.84, -4126.91, 9.31, 140.08),
    vec4(-416.02, -4146.35, 9.31, 305.63), vec4(-384.59, -4123.31, 9.32, 312.27), vec4(-365.64, -4107.42, 9.30, 311.98),
    vec4(-348.16, -4092.39, 9.32, 331.96), vec4(-399.63, -4117.11, 26.54, 328.78),
}

local CRATES = {
    vec4(-339.691, -4081.320, 8.319, 130.0), vec4(-349.900, -4069.366, 8.319, 130.0), vec4(-363.648, -4078.335, 8.319, 130.0),
    vec4(-353.726, -4090.097, 8.319, 130.0), vec4(-371.053, -4092.060, 8.319, 310.0), vec4(-389.410, -4113.167, 8.319, 310.0),
    vec4(-421.593, -4129.027, 8.320, 310.0), vec4(-409.274, -4140.384, 8.320, 40.0),
}

return {
    label = 'Cargo Ship',
    description = 'A freighter is anchored off the coast. Board it, find the captain\'s key and fly two containers to shore with the deck Skylift.',
    category = 'major',
    icon = 'ship',
    level = 5,
    police = 2,
    members = { min = 2, max = 8 },
    cooldown = 60,
    playerCooldown = 20,
    timeLimit = 45,
    simultaneous = 1,
    escape = false,
    rewards = { xp = 1600, money = { 22000, 30000 } },
    requiredItems = {},
    briefing = {
        'Take the dinghy from the port and sail to the freighter. Climb the ladder at the stern.',
        'Kill the crew and search the captain\'s cabin on the bridge for the helicopter key.',
        'Fly the Skylift: hover over a container and press E to hook it, E again to release.',
        'Drop both containers at their marked drop-offs. Loot the crates on deck for extra cash.',
    },
    loot = {
        crate = { { item = 'money', min = 1500, max = 3000 }, { item = 'electronics', min = 1, max = 3, chance = 0.5 }, { item = 'gold_bar', min = 1, max = 1, chance = 0.15 } },
        key = { { item = 'money', min = 500, max = 1000 } },
    },
    locations = {
        {
            label = 'Freighter - South Coast',
            center = vec3(-358.92, -4082.68, 9.31),
            boat = vec4(-121.20, -2727.57, 0.20, 150.0),
            cabin = vec3(-402.27, -4117.35, 26.55),
            helipad = vec4(-318.76, -4052.25, 10.50, 205.0),
            containers = { vec4(-342.734, -4061.621, 16.805, 310.0), vec4(-360.422, -4092.219, 16.805, 310.0) },
            drops = { vec3(1041.63, -3098.80, 6.0), vec3(1753.01, 3240.63, 41.0) },
        },
    },
    stages = function(loc)
        local deck = {
            { id = 'crew', type = 'eliminate', group = 'guards', label = 'Kill the ship crew' },
            {
                id = 'key', type = 'interact', action = 'search', label = 'Search the captain\'s cabin', icon = 'fas fa-key',
                coords = loc.cabin, radius = 1.5, duration = 6000, flag = 'heli_key', reward = 'key',
            },
        }
        for i = 1, #CRATES do
            local c = CRATES[i]
            deck[#deck + 1] = {
                id = 'crate' .. i, type = 'interact', action = 'search', label = 'Open crate', icon = 'fas fa-box-open',
                coords = vec3(c.x, c.y, c.z + 1.0), radius = 1.5, duration = 5000, reward = 'crate', objective = 'Deck crates',
                prop = { model = C.models.carrierCrate, coords = c.xyz, heading = c.w },
            }
        end
        return {
            {
                id = 'sail',
                task = 'Sail out to the freighter',
                blip = { coords = loc.boat.xyz, label = 'Boat' },
                spawn = { at = loc.boat.xyz, distance = 200.0, vehicles = { { key = 'boat', model = 'dinghy', coords = loc.boat } } },
                nodes = {
                    { id = 'reach', type = 'zone', coords = loc.center, radius = 120.0, label = 'Freighter', objective = 'Reach the freighter', keys = { 'boat' }, blipEntity = 'boat', entityLabel = 'Boat' },
                    { id = 'ladder_early', type = 'prop', coords = vec3(-391.28, -4133.34, 1.44), streamDistance = 250.0, prop = { model = 'prop_byard_ramp', rotation = vec3(-2.075, -30.509, 44.283) } },
                },
            },
            {
                id = 'deck',
                task = 'Take the ship and find the helicopter key',
                spawn = {
                    at = loc.center, distance = 250.0,
                    guards = C.guards(GUARDS, { model = 's_m_y_dockwork_01', weapons = { 'WEAPON_SMG', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PUMPSHOTGUN' } }),
                    vehicles = { { key = 'heli', model = 'skylift', type = 'heli', coords = loc.helipad, lockedUntil = 'heli_key' } },
                    objects = {
                        { key = 'cont1', model = C.models.bigContainer, coords = loc.containers[1], ground = false },
                        { key = 'cont2', model = C.models.bigContainer, coords = loc.containers[2], ground = false },
                    },
                },
                nodes = deck,
            },
            {
                id = 'lift',
                task = 'Fly both containers to shore',
                nodes = {
                    { id = 'drop1', type = 'deliver', entity = 'cont1', dropoff = loc.drops[1], radius = 20.0, label = 'Container drop A', entityLabel = 'Container', keys = { 'heli' }, skylift = { heli = 'heli', drop = 4.5 } },
                    { id = 'drop2', type = 'deliver', entity = 'cont2', dropoff = loc.drops[2], radius = 20.0, label = 'Container drop B', entityLabel = 'Container', keys = { 'heli' }, skylift = { heli = 'heli', drop = 4.5 } },
                },
            },
        }
    end,
}
