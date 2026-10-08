--[[ Car Boosting (new) - steal a tracked supercar, kill the tracker, drop it at the chop shop ]]

local CARS = { 'zentorno', 't20', 'osiris', 'entityxf', 'turismor', 'nero', 'tempesta', 'reaper', 'italigtb', 'xa21' }

return {
    label = 'Car Boosting',
    description = 'A client wants a specific supercar. It has a GPS tracker that pings the police until you jam it.',
    category = 'small',
    icon = 'car',
    level = 2,
    police = 1,
    members = { min = 1, max = 3 },
    cooldown = 0,
    locationCooldown = 20,
    playerCooldown = 10,
    timeLimit = 20,
    simultaneous = 3,
    escape = false,
    rewards = { xp = 300, money = { 3500, 6000 } },
    requiredItems = { { name = 'lockpick', count = 1, label = 'Lockpick' } },
    briefing = {
        'Find the marked car and pick the door lock.',
        'The car has a GPS tracker - the police get its position every 30 seconds.',
        'Optional: use a GPS Jammer at the rear of the car to kill the tracker.',
        'Deliver the car to the chop shop in one piece.',
    },
    loot = {
        jam = { { item = 'money', min = 400, max = 800 } },
    },
    locations = {
        { label = 'Pink Cage Motel',   center = vec3(277.62, -340.01, 44.48),   car = vec4(277.62, -340.01, 44.48, 70.0) },
        { label = 'Alta Street',       center = vec3(69.84, 12.60, 68.96),      car = vec4(69.84, 12.60, 68.96, 160.0) },
        { label = 'Vinewood Lot',      center = vec3(364.37, 297.83, 103.49),   car = vec4(364.37, 297.83, 103.49, 340.0) },
        { label = 'LSIA Parking',      center = vec3(-773.12, -2033.04, 8.88),  car = vec4(-773.12, -2033.04, 8.88, 315.0) },
        { label = 'Vespucci Beach',    center = vec3(-1185.32, -1500.64, 4.38), car = vec4(-1185.32, -1500.64, 4.38, 125.0) },
        { label = 'Harmony Motel',     center = vec3(1137.77, 2663.54, 37.90),  car = vec4(1137.77, 2663.54, 37.90, 0.0) },
    },
    dropoff = vec3(1204.50, -3116.20, 5.54),
    stages = function(loc, inst)
        local model = CARS[math.random(#CARS)]
        local drop = vec3(1204.50, -3116.20, 5.54)
        return {
            {
                id = 'steal',
                task = 'Break into the target car',
                blip = { coords = loc.center, label = 'Target vehicle' },
                spawn = { vehicles = { { key = 'car', model = model, coords = loc.car, lockedUntil = 'unlocked' } }, distance = 200.0 },
                nodes = {
                    {
                        id = 'unlock', type = 'interact', action = 'lockpick', label = 'Pick the door lock', icon = 'fas fa-key',
                        attach = { entity = 'car', offset = vec3(-1.1, 0.4, 0.0) }, radius = 1.3,
                        minigame = { type = 'lockpick', difficulty = 3 }, flag = 'unlocked', alert = 0.3,
                        item = { name = 'lockpick', label = 'Lockpick', remove = 0.3, removeOnFail = true },
                    },
                },
            },
            {
                id = 'deliver',
                task = 'Deliver the car to the chop shop',
                nodes = {
                    { id = 'tracker', type = 'tracker', entity = 'car', flag = 'jammed', interval = 30 },
                    {
                        id = 'jam', type = 'interact', action = 'hack', label = 'Jam the GPS tracker', icon = 'fas fa-satellite-dish',
                        attach = { entity = 'car', offset = vec3(0.0, -2.6, 0.0) }, radius = 1.3, required = false,
                        minigame = { type = 'datacrack', difficulty = 2 }, flag = 'jammed', reward = 'jam',
                        item = { name = 'gps_jammer', label = 'GPS Jammer', remove = true },
                    },
                    { id = 'drop', type = 'deliver', entity = 'car', dropoff = drop, radius = 6.0, label = 'Chop shop', entityLabel = 'Target car' },
                },
            },
        }
    end,
}
