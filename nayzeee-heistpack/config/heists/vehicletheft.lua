--[[ Vehicle Theft - grab a car hauler, hit a guarded lot, deliver three high-end cars ]]

local C = lib.load('config.heists._common')

local CARS = { 'sultanrs', 'jester', 'banshee2', 'feltzer2', 'massacro', 'specter', 'comet5', 'elegy' }

return {
    label = 'Vehicle Theft',
    description = 'Collect a car hauler, raid a guarded lot near Grapeseed and deliver three high-end cars to the airfield.',
    category = 'medium',
    icon = 'car',
    level = 3,
    police = 2,
    members = { min = 2, max = 4 },
    cooldown = 25,
    playerCooldown = 15,
    timeLimit = 35,
    simultaneous = 1,
    escape = false,
    rewards = { xp = 800, money = { 15000, 22000 } },
    requiredItems = {},
    briefing = {
        'Pick up the car hauler in Sandy Shores.',
        'Hit the lot near the Grapeseed airstrip and take out the guards.',
        'Load the cars onto the hauler (or drive them) and deliver all three to the Sandy Shores airfield.',
    },
    loot = {},
    locations = {
        {
            label = 'Grapeseed Lot',
            center = vec3(2137.54, 4780.03, 40.33),
            truck = vec4(914.41, 3590.26, 33.31, 270.82),
            trailer = vec4(904.75, 3590.16, 33.35, 270.55),
            cars = { vec4(2141.99, 4782.83, 40.33, 48.50), vec4(2137.54, 4780.03, 40.33, 37.47), vec4(2135.17, 4775.70, 40.33, 7.20) },
            guards = { vec4(2131.41, 4785.00, 40.97, 13.43), vec4(2130.62, 4779.67, 40.97, 8.0), vec4(2138.62, 4784.83, 40.97, 50.0), vec4(2135.59, 4787.72, 40.97, 45.35), vec4(2129.40, 4787.81, 40.97, 6.22) },
            dropoff = vec3(1736.85, 3284.95, 41.50),
        },
    },
    stages = function(loc)
        local vehicles = {}
        for i = 1, #loc.cars do
            vehicles[i] = { key = 'car' .. i, model = CARS[math.random(#CARS)], coords = loc.cars[i] }
        end
        return {
            {
                id = 'hauler',
                task = 'Collect the car hauler',
                blip = { coords = loc.truck.xyz, label = 'Car hauler' },
                spawn = {
                    at = loc.truck.xyz, distance = 200.0,
                    vehicles = {
                        { key = 'hauler', model = 'phantom', coords = loc.truck },
                        { key = 'trailer', model = 'tr2', coords = loc.trailer, attachTo = 'hauler' },
                    },
                },
                nodes = {
                    { id = 'gethauler', type = 'zone', coords = loc.truck.xyz, radius = 6.0, label = 'Car hauler', objective = 'Get to the hauler', keys = { 'hauler' } },
                },
            },
            {
                id = 'lot',
                task = 'Raid the lot',
                blip = { coords = loc.center, label = 'Vehicle lot' },
                spawn = { at = loc.center, distance = 220.0, guards = C.guards(loc.guards, { weapon = 'WEAPON_ASSAULTRIFLE', ground = true }), vehicles = vehicles },
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Take out the lot guards', keys = { 'hauler' } },
                },
            },
            {
                id = 'deliver',
                task = 'Deliver all three cars',
                nodes = {
                    { id = 'cars', type = 'deliver', entities = { 'car1', 'car2', 'car3' }, dropoff = loc.dropoff, radius = 18.0, label = 'Drop-off', entityLabel = 'Target car', keys = { 'hauler' } },
                },
            },
        }
    end,
}
