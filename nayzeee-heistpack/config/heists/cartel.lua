--[[ Cartel Compound (new) - assault the Madrazo ranch and crack the cartel's safe ]]

local C = lib.load('config.heists._common')

return {
    label = 'Cartel Compound',
    description = 'Assault the Madrazo ranch in the Vinewood Hills, crack the cartel\'s safe with an encrypted laptop and take the product.',
    category = 'major',
    icon = 'skull',
    level = 7,
    police = 3,
    members = { min = 3, max = 8 },
    cooldown = 75,
    playerCooldown = 25,
    timeLimit = 35,
    simultaneous = 1,
    escape = 350.0,
    rewards = { xp = 2000, money = { 12000, 18000 } },
    requiredItems = { { name = 'heist_laptop', count = 1, label = 'Encrypted Laptop' } },
    briefing = {
        'The ranch is crawling with cartel soldiers. Bring a full crew.',
        'Clear the compound.',
        'Crack the cartel safe with the Encrypted Laptop, then grab the coke and cash.',
        'Get 350m away.',
    },
    loot = {
        safe = { { item = 'money', min = 15000, max = 22000 }, { item = 'gold_bar', min = 2, max = 4 }, { item = 'diamond', min = 1, max = 3, chance = 0.5 } },
        coke = { { item = 'coke_brick', min = 2, max = 4 } },
        cash = { { item = 'money', min = 4000, max = 6500 } },
    },
    locations = {
        { label = 'Madrazo Ranch', center = vec3(1400.0, 1135.0, 114.5) },
    },
    stages = function(loc)
        local c = loc.center
        local function at(dx, dy) return vec3(c.x + dx, c.y + dy, c.z) end
        local function g(dx, dy, h) return vec4(c.x + dx, c.y + dy, c.z, h) end
        local guards = {
            g(-10, 8, 180), g(12, 6, 90), g(-14, -10, 300), g(8, -14, 20), g(20, 0, 270), g(-22, 0, 90),
            g(0, 18, 180), g(4, -22, 0), g(-6, 14, 220), g(16, 16, 135),
        }
        return {
            {
                id = 'assault',
                task = 'Assault the compound',
                blip = { coords = c, label = 'Madrazo ranch' },
                alert = true,
                spawn = { at = c, distance = 220.0, guards = C.guards(guards, { model = 'g_m_m_mexboss_01', weapons = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_MICROSMG', 'WEAPON_PUMPSHOTGUN' }, armour = 100, ground = true }) },
                nodes = {
                    { id = 'cartel', type = 'eliminate', group = 'guards', label = 'Clear the compound' },
                },
            },
            {
                id = 'safe',
                task = 'Crack the cartel safe',
                nodes = {
                    {
                        id = 'safe', type = 'interact', action = 'laptop', label = 'Crack the safe', icon = 'fas fa-laptop-code',
                        coords = at(2.0, 4.0), radius = 1.2, ground = true, minigame = { type = 'datacrack', difficulty = 3 }, reward = 'safe', required = true,
                        prop = { model = C.models.safe, ground = true }, item = { name = 'heist_laptop', label = 'Encrypted Laptop', remove = 0.5 },
                    },
                    C.pile('coke1', at(-3.0, 3.0), 0.0, C.models.cokeBlock, 'coke', { ground = true }),
                    C.pile('coke2', at(-4.0, 4.5), 0.0, C.models.cokeBlock, 'coke', { ground = true }),
                    C.pile('cash1', at(5.0, 2.0), 0.0, C.models.cashStack, 'cash', { ground = true }),
                },
            },
        }
    end,
}
