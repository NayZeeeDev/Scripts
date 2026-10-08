--[[ Yacht Raid - take a dinghy out to a party yacht, clear the deck, take the stash ]]

local C = lib.load('config.heists._common')

local GUARDS = {
    vec4(-2045.30, -1026.74, 11.91, 303.25), vec4(-2047.91, -1035.59, 11.90, 283.14),
    vec4(-2068.73, -1024.59, 11.91, 241.88), vec4(-2068.32, -1021.88, 11.91, 274.19),
    vec4(-2075.48, -1021.31, 11.91, 251.82), vec4(-2076.23, -1024.51, 11.91, 185.52),
}

return {
    label = 'Yacht Raid',
    description = 'A cartel accountant is throwing a party on his yacht. Board it, clear the security and take the stash.',
    category = 'medium',
    icon = 'yacht',
    level = 3,
    police = 2,
    members = { min = 2, max = 6 },
    cooldown = 30,
    playerCooldown = 15,
    timeLimit = 30,
    simultaneous = 1,
    escape = 300.0,
    rewards = { xp = 750, money = { 5000, 8000 } },
    ipls = { 'hei_yacht_heist', 'hei_yacht_heist_Bar', 'hei_yacht_heist_Bedrm', 'hei_yacht_heist_Bridge', 'hei_yacht_heist_DistantLights', 'hei_yacht_heist_enginrm', 'hei_yacht_heist_LODLights', 'hei_yacht_heist_Lounge' },
    briefing = {
        'Take the dinghy waiting at the Puerta del Sol marina.',
        'Board the yacht and take out the armed security.',
        'Grab the cash, coke and weed from the lounge and deck.',
        'Get 300m away from the yacht.',
    },
    loot = {
        weed = { { item = 'weed_brick', min = 2, max = 4 } },
        coke = { { item = 'coke_brick', min = 1, max = 3 } },
        cash = { { item = 'money', min = 4000, max = 6500 } },
        safe = { { item = 'money', min = 3000, max = 5000 }, { item = 'rolex', min = 1, max = 3 }, { item = 'diamond', min = 1, max = 2, chance = 0.4 } },
    },
    locations = {
        { label = 'Pacific Ocean - Party Yacht', center = vec3(-2043.25, -1032.14, 11.98), boat = vec4(-802.60, -1504.60, 0.50, 110.0) },
    },
    stages = function(loc)
        return {
            {
                id = 'board',
                task = 'Take the boat to the yacht',
                blip = { coords = loc.boat.xyz, label = 'Boat' },
                spawn = { at = loc.boat.xyz, distance = 200.0, vehicles = { { key = 'boat', model = 'dinghy', coords = loc.boat } } },
                nodes = {
                    { id = 'reach', type = 'zone', coords = loc.center, radius = 45.0, label = 'Party yacht', objective = 'Reach the yacht', keys = { 'boat' }, blipEntity = 'boat', entityLabel = 'Boat', blip = { label = 'Party yacht', route = false } },
                },
            },
            {
                id = 'clear',
                task = 'Clear the yacht security',
                spawn = { at = loc.center, distance = 160.0, guards = C.guards(GUARDS, { weapons = { 'WEAPON_SMG', 'WEAPON_CARBINERIFLE', 'WEAPON_PISTOL50' } }) },
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Neutralize security' },
                    C.pile('weed1', vec3(-2051.92, -1031.92, 11.87), 0.0, C.models.weedBlock, 'weed'),
                    C.pile('weed2', vec3(-2053.33, -1033.30, 11.87), 0.0, C.models.weedBlock, 'weed'),
                    C.pile('coke1', vec3(-2058.58, -1029.30, 12.01), 0.0, C.models.cokeBlock, 'coke'),
                    C.pile('cash1', vec3(-2072.64, -1019.72, 11.82), 0.0, C.models.moneyWrapped, 'cash'),
                    C.pile('cash2', vec3(-2074.00, -1024.05, 11.82), 0.0, C.models.moneyWrapped, 'cash'),
                    {
                        id = 'safe', type = 'interact', action = 'safecrack', label = 'Crack the captain\'s safe', icon = 'fas fa-vault',
                        coords = vec3(-2074.20, -1024.74, 11.82), radius = 1.0, minigame = { type = 'safecrack', difficulty = 3 }, reward = 'safe',
                        requires = { 'guards' },
                    },
                },
            },
        }
    end,
}
