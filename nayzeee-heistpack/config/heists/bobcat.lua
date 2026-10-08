--[[ Bobcat Security Depot - thermite in, fight the response team, blow the cage, hit the vault ]]

local C = lib.load('config.heists._common')

return {
    label = 'Bobcat Security Depot',
    description = 'Break into the Bobcat Security depot in Cypress Flats, fight the response team and empty the cash cage.',
    category = 'major',
    icon = 'shield',
    level = 5,
    police = 3,
    members = { min = 2, max = 8 },
    cooldown = 60,
    playerCooldown = 20,
    timeLimit = 35,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 1500, money = { 8000, 14000 } },
    requiredItems = {
        { name = 'thermite', count = 1, label = 'Thermite Charge' },
        { name = 'c4_charge', count = 1, label = 'C4 Charge' },
    },
    alertTitle = 'Bobcat Security Alarm',
    briefing = {
        'Burn through the depot door with thermite.',
        'Kill the armed Bobcat response team.',
        'Hack the vault door, blow the cash cage with C4 and empty the trolleys.',
    },
    loot = C.with(C.loot, {
        trolley_cash = { { item = 'money', min = 12000, max = 17000 } },
    }),
    locations = {
        {
            label = 'Bobcat Security - Cypress Flats',
            center = vec3(888.30, -2123.51, 31.23),
            entrance = vec3(908.10, -2120.20, 31.23),
            pad = vec3(892.29, -2107.85, 31.50),
            cage = vec3(887.95, -2130.17, 31.58),
            doors = {
                front = { model = -2023754432, coords = vec3(908.440, -2121.276, 31.381), radius = 2.5, kind = 'gate' },
                vault = { model = -1514454788, coords = vec3(889.914, -2107.781, 30.236), radius = 3.0, kind = 'gate' },
            },
            guards = {
                vec4(882.25, -2111.52, 31.23, 294.40), vec4(881.17, -2117.36, 31.23, 168.33), vec4(882.68, -2132.64, 31.23, 256.59),
                vec4(896.69, -2133.29, 31.23, 292.61), vec4(899.29, -2120.50, 31.23, 266.40), vec4(907.01, -2115.99, 31.23, 243.94),
            },
        },
    },
    stages = function(loc)
        return {
            {
                id = 'breach',
                task = 'Burn through the depot door',
                blip = { coords = loc.entrance, label = 'Bobcat Security' },
                spawn = { at = loc.center, distance = 160.0, guards = C.guards(loc.guards, { model = 's_m_m_armoured_02', weapons = { 'WEAPON_CARBINERIFLE', 'WEAPON_SMG' } }) },
                nodes = {
                    {
                        id = 'thermite', type = 'interact', action = 'thermite', label = 'Place thermite', icon = 'fas fa-fire',
                        coords = loc.entrance, radius = 1.5, minigame = { type = 'memory', difficulty = 2 }, burn = 9000,
                        unlocks = { 'front' }, item = { name = 'thermite', label = 'Thermite', remove = true }, alert = 1.0,
                    },
                },
            },
            {
                id = 'vault',
                task = 'Clear the depot and open the vault',
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Kill the response team' },
                    {
                        id = 'vault_pad', type = 'interact', action = 'hack', label = 'Hack the vault door', icon = 'fas fa-terminal',
                        coords = loc.pad, radius = 1.0, minigame = { type = 'datacrack', difficulty = 3 }, unlocks = { 'vault' },
                    },
                    {
                        id = 'cage', type = 'interact', action = 'c4', label = 'Blow the cash cage', icon = 'fas fa-bomb',
                        coords = loc.cage, radius = 1.4, fuse = 7000, flag = 'cage', item = { name = 'c4_charge', label = 'C4 Charge', remove = true },
                        requires = { 'vault_pad' },
                    },
                    C.trolley('t1', vec3(888.883, -2121.917, 30.703), 180.0, 'cash', { requiresFlag = 'cage' }),
                    C.trolley('t2', vec3(890.101, -2127.673, 30.703), 90.0, 'cash', { requiresFlag = 'cage' }),
                    C.trolley('t3', vec3(886.304, -2127.651, 30.703), 0.0, 'cash', { requiresFlag = 'cage' }),
                },
            },
        }
    end,
}
