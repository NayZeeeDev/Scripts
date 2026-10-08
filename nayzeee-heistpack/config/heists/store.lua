--[[ Store Robbery - pick any marked 24/7, LTD or Rob's Liquor, threaten the clerk, hit the safe ]]

-- clerk = where the clerk stands (vec4), safe = back-room safe
local stores = {
    { label = '24/7 Innocence Blvd',    clerk = vec4(24.47, -1346.62, 29.50, 271.66),    safe = vec3(28.21, -1338.83, 29.50) },
    { label = '24/7 Clinton Ave',       clerk = vec4(372.85, 328.10, 103.57, 255.00),    safe = vec3(378.17, 333.44, 103.57) },
    { label = '24/7 Palomino Fwy',      clerk = vec4(2555.22, 380.88, 108.62, 0.00),     safe = vec3(2549.19, 384.86, 108.62) },
    { label = '24/7 Sandy Shores',      clerk = vec4(1959.82, 3740.48, 32.34, 301.57),   safe = vec3(1959.26, 3748.92, 32.34) },
    { label = '24/7 Senora Fwy',        clerk = vec4(2677.47, 3279.76, 55.24, 335.08),   safe = vec3(2672.69, 3286.63, 55.24) },
    { label = '24/7 Paleto Bay',        clerk = vec4(1727.69, 6415.34, 35.04, 242.34),   safe = vec3(1734.78, 6420.84, 35.03) },
    { label = '24/7 Chumash',           clerk = vec4(-3242.97, 1000.01, 12.83, 357.57),  safe = vec3(-3250.02, 1004.43, 12.83) },
    { label = '24/7 Ineseno Rd',        clerk = vec4(-3039.54, 584.38, 7.91, 17.27),     safe = vec3(-3047.88, 585.61, 7.90) },
    { label = '24/7 Route 68',          clerk = vec4(549.24, 2670.37, 42.16, 99.39),     safe = vec3(546.41, 2662.80, 42.15) },
    { label = 'LTD Grove Street',       clerk = vec4(-47.45, -1759.12, 29.42, 44.78),   safe = vec3(-43.43, -1748.30, 29.42) },
    { label = 'LTD Mirror Park',        clerk = vec4(1165.28, -323.98, 69.21, 94.64),    safe = vec3(1159.46, -314.05, 69.20) },
    { label = 'LTD Little Seoul',       clerk = vec4(-706.06, -914.52, 19.22, 88.04),    safe = vec3(-709.74, -904.15, 19.21) },
    { label = 'LTD Richman Glen',       clerk = vec4(-1819.53, 793.51, 138.09, 135.00), safe = vec3(-1829.27, 798.76, 138.19) },
    { label = 'LTD Grapeseed',          clerk = vec4(1697.87, 4922.96, 42.06, 324.71),   safe = vec3(1707.93, 4920.47, 42.06) },
    { label = "Rob's Liquor Vespucci",  clerk = vec4(-1221.58, -908.15, 12.33, 35.49),   safe = vec3(-1220.85, -916.05, 11.32) },
    { label = "Rob's Liquor Morningwood", clerk = vec4(-1486.59, -377.68, 40.16, 139.51), safe = vec3(-1478.94, -375.50, 39.16) },
    { label = "Rob's Liquor Great Ocean", clerk = vec4(-2966.39, 391.42, 15.04, 87.48), safe = vec3(-2959.64, 387.08, 14.04) },
    { label = "Rob's Liquor El Rancho", clerk = vec4(1134.08, -983.16, 46.41, 276.54),   safe = vec3(1126.77, -980.10, 45.41) },
    { label = "Rob's Liquor Route 68",  clerk = vec4(1165.91, 2710.81, 38.16, 179.43),   safe = vec3(1169.31, 2717.79, 37.15) },
}

local locations = {}
for i = 1, #stores do
    local s = stores[i]
    locations[i] = { label = s.label, center = s.clerk.xyz, clerk = s.clerk, safe = s.safe, selectRadius = 14.0 }
end

local CLERKS = { 'mp_m_shopkeep_01', 's_m_m_linecook', 'a_m_m_genfat_01', 'a_m_y_indian_01' }

return {
    label = 'Store Robbery',
    description = 'Hit a corner store. Scare the clerk into emptying the till, then crack the back-room safe.',
    category = 'small',
    icon = 'store',
    level = 1,
    police = 1,
    members = { min = 1, max = 3 },
    cooldown = 0,
    locationCooldown = 25,
    playerCooldown = 8,
    timeLimit = 15,
    simultaneous = 4,
    locationMode = 'select',
    selectLabel = 'Pick any marked store',
    escape = 150.0,
    rewards = { xp = 150, money = { 300, 700 } },
    requiredItems = {},
    briefing = {
        'Drive to any marked store on your map.',
        'Aim your weapon at the clerk and keep them covered until the till is empty.',
        'Smash the registers and crack the back-room safe (lockpick).',
        'Get 150m away before the cops close in.',
    },
    loot = {
        clerk = { { item = 'money', min = 900, max = 1600 } },
        register = { { item = 'money', min = 250, max = 600 } },
        safe = {
            { item = 'money', min = 1200, max = 2500 },
            { item = 'rolex', min = 1, max = 1, chance = 0.35 },
            { item = 'gold_chain', min = 1, max = 2, chance = 0.4 },
        },
    },
    locations = locations,
    stages = function(loc)
        local c = loc.clerk
        local h = math.rad(c.w)
        local fwd = vec3(-math.sin(h), math.cos(h), 0.0)
        local register = c.xyz + fwd * 0.7
        return {
            {
                id = 'clerk',
                task = 'Threaten the clerk',
                blip = { coords = loc.center, label = loc.label },
                spawn = { peds = { { key = 'clerk', model = CLERKS[math.random(#CLERKS)], coords = c } }, distance = 90.0 },
                nodes = {
                    { id = 'clerk', type = 'intimidate', ped = 'clerk', label = 'Aim at the clerk', objective = 'Empty the till', duration = 12000, reward = 'clerk', required = true, alert = 1.0, coords = c.xyz },
                    { id = 'register', type = 'smash', label = 'Smash the register', coords = register, radius = 0.9, reward = 'register', requires = { 'clerk' } },
                    {
                        id = 'safe', type = 'interact', action = 'safecrack', label = 'Crack the safe', icon = 'fas fa-vault',
                        coords = loc.safe, radius = 1.0, minigame = { type = 'safecrack', difficulty = 2 }, reward = 'safe',
                        item = { name = 'lockpick', label = 'Lockpick', remove = 0.25, removeOnFail = true }, requires = { 'clerk' },
                    },
                },
            },
        }
    end,
}
