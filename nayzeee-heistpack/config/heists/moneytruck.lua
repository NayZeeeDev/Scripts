--[[ Armored Truck - intercept a moving Gruppe Sechs truck, kill the crew, blow the rear doors ]]

return {
    label = 'Armored Truck',
    description = 'A cash-in-transit truck is on the move. Stop it, deal with the guards, blow the back doors and grab the bags.',
    category = 'medium',
    icon = 'truck',
    level = 2,
    police = 2,
    members = { min = 1, max = 4 },
    cooldown = 20,
    playerCooldown = 15,
    timeLimit = 25,
    simultaneous = 2,
    escape = 200.0,
    rewards = { xp = 550, money = { 3000, 5000 } },
    requiredItems = { { name = 'c4_charge', count = 1, label = 'C4 Charge' } },
    briefing = {
        'The truck spawns at the marked spot once you get close and drives toward the Union Depository.',
        'Stop it - shoot the tyres or ram it - and take out the armed crew.',
        'Plant C4 on the rear doors and grab the cash bags inside.',
    },
    loot = {
        bags = { { item = 'money', min = 3500, max = 5500 }, { item = 'gold_bar', min = 1, max = 1, chance = 0.15 } },
    },
    locations = {
        { label = 'Mirror Park Freeway', center = vec3(1585.11, -994.62, 60.0), truck = vec4(1585.11, -994.62, 60.0, 300.0), route = vec3(-6.5, -671.0, 31.9) },
        { label = 'Vinewood Hills Road', center = vec3(1332.35, 600.98, 80.0), truck = vec4(1332.35, 600.98, 80.0, 312.8), route = vec3(-6.5, -671.0, 31.9) },
    },
    stages = function(loc)
        return {
            {
                id = 'intercept',
                task = 'Intercept the armored truck',
                blip = { coords = loc.center, label = 'Armored truck' },
                spawn = {
                    distance = 350.0,
                    vehicles = {
                        {
                            key = 'truck', model = 'stockade', coords = loc.truck, route = loc.route, speed = 20.0, locked = true,
                            driver = { model = 's_m_m_armoured_01', weapon = 'WEAPON_SMG', group = 'crew' },
                            passengers = { { model = 's_m_m_armoured_02', weapon = 'WEAPON_PUMPSHOTGUN' }, { model = 's_m_m_armoured_01', weapon = 'WEAPON_CARBINERIFLE' } },
                        },
                    },
                },
                nodes = {
                    { id = 'crew', type = 'eliminate', group = 'crew', label = 'Take out the truck crew', blipEntity = 'truck', entityLabel = 'Armored truck' },
                },
            },
            {
                id = 'breach',
                task = 'Blow the rear doors',
                nodes = {
                    {
                        id = 'doors', type = 'interact', action = 'c4', label = 'Plant C4 on rear doors', icon = 'fas fa-bomb',
                        attach = { entity = 'truck', offset = vec3(0.0, -4.0, 0.0) }, radius = 1.6, fuse = 6000, vehicleDoors = { 2, 3 },
                        item = { name = 'c4_charge', label = 'C4 Charge', remove = true }, flag = 'open', alert = 1.0,
                    },
                    {
                        id = 'bags', type = 'interact', action = 'grab', label = 'Grab cash bag', icon = 'fas fa-sack-dollar',
                        attach = { entity = 'truck', offset = vec3(0.0, -4.0, 0.0) }, radius = 1.6, uses = 4, duration = 5000,
                        reward = 'bags', requiresFlag = 'open', objective = 'Cash bags',
                    },
                },
            },
        }
    end,
}
