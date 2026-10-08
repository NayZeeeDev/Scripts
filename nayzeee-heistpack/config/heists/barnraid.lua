--[[ Barn Raid (new) - a biker gang stores product in a barn at the O'Neil ranch ]]

local C = lib.load('config.heists._common')

local GUARDS = {
    vec4(2440.0, 4975.0, 46.8, 180.0), vec4(2450.5, 4985.0, 46.8, 90.0), vec4(2432.0, 4990.0, 46.8, 270.0),
    vec4(2455.0, 4965.0, 46.8, 45.0), vec4(2425.0, 4970.0, 46.8, 300.0), vec4(2445.0, 4958.0, 46.8, 0.0),
}

return {
    label = 'Barn Raid',
    description = 'The Lost MC keeps product and cash in a barn at the O\'Neil ranch. Hit it, cut the padlock and load up.',
    category = 'medium',
    icon = 'barn',
    level = 3,
    police = 1,
    members = { min = 1, max = 5 },
    cooldown = 25,
    playerCooldown = 15,
    timeLimit = 25,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 650, money = { 3000, 5500 } },
    requiredItems = { { name = 'angle_grinder', count = 1, label = 'Angle Grinder' } },
    briefing = {
        'Drive to the O\'Neil ranch in Grapeseed.',
        'The bikers are armed - take them out.',
        'Cut the barn padlock with an Angle Grinder and load the product.',
        'Get 250m away.',
    },
    loot = {
        weed = { { item = 'weed_brick', min = 3, max = 6 } },
        coke = { { item = 'coke_brick', min = 1, max = 3 } },
        cash = { { item = 'money', min = 2500, max = 4500 } },
        parts = { { item = 'weapon_parts', min = 2, max = 4 } },
    },
    locations = {
        { label = 'O\'Neil Ranch', center = vec3(2440.0, 4975.0, 46.8) },
    },
    stages = function(loc)
        local c = loc.center
        local function at(dx, dy) return vec3(c.x + dx, c.y + dy, c.z) end
        return {
            {
                id = 'raid',
                task = 'Take out the bikers',
                blip = { coords = c, label = 'O\'Neil ranch' },
                alert = true,
                spawn = { distance = 200.0, guards = C.guards(GUARDS, { model = 'g_m_y_lost_01', weapons = { 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_MICROSMG', 'WEAPON_PISTOL' }, ground = true }) },
                nodes = {
                    { id = 'bikers', type = 'eliminate', group = 'guards', label = 'Take out the bikers' },
                },
            },
            {
                id = 'barn',
                task = 'Cut the barn padlock',
                nodes = {
                    {
                        id = 'padlock', type = 'interact', action = 'cut', label = 'Cut the padlock', icon = 'fas fa-scissors',
                        coords = at(8.0, 12.0), radius = 1.5, duration = 9000, ground = true, flag = 'barn_open',
                        item = { name = 'angle_grinder', label = 'Angle Grinder' },
                    },
                    C.pile('weed1', at(10.0, 15.0), 0.0, C.models.weedBlock, 'weed', { requiresFlag = 'barn_open', ground = true }),
                    C.pile('weed2', at(11.5, 16.0), 0.0, C.models.weedBlock, 'weed', { requiresFlag = 'barn_open', ground = true }),
                    C.pile('coke1', at(9.0, 17.5), 0.0, C.models.cokeBlock, 'coke', { requiresFlag = 'barn_open', ground = true }),
                    C.pile('cash1', at(12.5, 14.0), 0.0, C.models.moneyWrapped, 'cash', { requiresFlag = 'barn_open', ground = true }),
                    C.search('crate1', at(7.0, 18.0), 'parts', { label = 'Search crate', requiresFlag = 'barn_open', ground = true }),
                },
            },
        }
    end,
}
