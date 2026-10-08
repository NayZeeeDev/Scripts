--[[ Airfield Cargo (new) - a smuggling crew is unloading at Sandy Shores airfield ]]

local C = lib.load('config.heists._common')

return {
    label = 'Airfield Cargo',
    description = 'A smuggling crew is unloading military cargo at the Sandy Shores airfield. Hit them, grab the manifest and haul the crates.',
    category = 'major',
    icon = 'plane',
    level = 4,
    police = 2,
    members = { min = 2, max = 6 },
    cooldown = 40,
    playerCooldown = 20,
    timeLimit = 30,
    simultaneous = 1,
    escape = 300.0,
    rewards = { xp = 1150, money = { 7000, 11000 } },
    requiredItems = {},
    briefing = {
        'Drive to the Sandy Shores airfield.',
        'Kill the smugglers guarding the plane.',
        'Carry the cargo crates into your vehicle trunk and hack the flight manifest laptop.',
        'Get 300m away.',
    },
    loot = {
        crate = { { item = 'cargo_crate', min = 1, max = 1 }, { item = 'weapon_parts', min = 1, max = 3, chance = 0.6 } },
        manifest = { { item = 'data_drive', min = 1, max = 2 }, { item = 'money', min = 2000, max = 3500 } },
    },
    locations = {
        {
            label = 'Sandy Shores Airfield',
            center = vec3(1740.0, 3285.0, 41.1),
            plane = vec4(1720.0, 3270.0, 41.2, 105.0),
            guards = {
                vec4(1730.0, 3280.0, 41.2, 120.0), vec4(1745.0, 3292.0, 41.2, 200.0), vec4(1752.0, 3278.0, 41.2, 60.0),
                vec4(1725.0, 3262.0, 41.2, 300.0), vec4(1738.0, 3268.0, 41.2, 10.0), vec4(1712.0, 3276.0, 41.2, 90.0),
                vec4(1748.0, 3300.0, 41.2, 160.0),
            },
        },
    },
    stages = function(loc)
        local c = loc.center
        local function at(dx, dy) return vec3(c.x + dx, c.y + dy, c.z) end
        local crates = {}
        local spots = { at(-6.0, -4.0), at(-4.5, -5.5), at(-7.5, -2.5), at(-3.0, -7.0) }
        for i = 1, #spots do
            crates[#crates + 1] = {
                id = 'crate' .. i, type = 'carry', label = 'Carry cargo crate', icon = 'fas fa-box', coords = spots[i], radius = 1.2,
                reward = 'crate', ground = true, requires = { 'smugglers' }, objective = 'Crates',
                prop = { model = C.models.milCrate, ground = true }, carry = { model = C.models.milCrate, pos = vec3(0.0, -0.2, -0.15) },
            }
        end
        crates[#crates + 1] = { id = 'smugglers', type = 'eliminate', group = 'guards', label = 'Kill the smugglers' }
        crates[#crates + 1] = {
            id = 'manifest', type = 'interact', action = 'laptop', label = 'Hack the flight manifest', icon = 'fas fa-laptop',
            coords = at(2.0, 6.0), radius = 1.0, ground = true, minigame = { type = 'datacrack', difficulty = 2 }, reward = 'manifest',
            prop = { model = C.models.laptop, ground = true }, requires = { 'smugglers' },
        }
        return {
            {
                id = 'raid',
                task = 'Raid the airfield',
                blip = { coords = c, label = 'Airfield' },
                spawn = {
                    at = c, distance = 250.0,
                    guards = C.guards(loc.guards, { model = 'g_m_m_armgoon_01', weapons = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_COMPACTRIFLE' }, ground = true }),
                    vehicles = { { key = 'plane', model = 'cuban800', coords = loc.plane, locked = true } },
                },
                nodes = crates,
            },
        }
    end,
}
