--[[
    Fleeca Bank - all six branches.
    Every Fleeca vault is the same interior rotated, so the vault layout is recorded once
    (Great Ocean Hwy branch) and transformed onto each branch by its vault-door position/heading.
]]

local C = lib.load('config.heists._common')

local VAULT_MODELS = { 'v_ilev_gb_vauldr', 'hei_prop_heist_sec_door' }
local GATE_MODELS = { 'v_ilev_gb_vaubar' }

-- reference branch (Great Ocean Hwy): vault door + layout
local BASE = { pos = vec3(-2958.539, 482.271, 15.836), yaw = 357.54 }
local LAYOUT = {
    pad       = vec3(-2956.521, 482.065, 15.817),
    gate      = vec3(-2956.116, 485.421, 15.995),
    gatePad   = vec3(-2956.581, 483.383, 15.763),
    center    = vec3(-2957.665, 481.329, 15.707),
    entrance  = vec3(-2972.084, 482.551, 15.425),
    trolleys  = {
        { vec3(-2957.397, 485.781, 15.148), 180.0, 'cash' },
        { vec3(-2954.970, 486.311, 15.148), 180.0, 'cash' },
        { vec3(-2952.795, 485.994, 15.148), 130.0, 'gold' },
        { vec3(-2953.341, 482.446, 15.148), 0.0, 'cash' },
    },
    pile      = vec3(-2954.154, 484.371, 15.525),
    lockboxes = { { vec3(-2958.827, 484.095, 15.758), 60.0 } },
}

local branches = {
    { label = 'Fleeca - Great Ocean Hwy', door = BASE },
    { label = 'Fleeca - Legion Square',   door = { pos = vec3(148.0266, -1044.364, 29.50693), yaw = 249.846 } },
    { label = 'Fleeca - Hawick Ave',      door = { pos = vec3(-352.7365, -53.57248, 49.17543), yaw = 250.85 } },
    { label = 'Fleeca - Del Perro Blvd',  door = { pos = vec3(-1211.261, -334.5596, 37.91989), yaw = 296.86 } },
    { label = 'Fleeca - Vinewood',        door = { pos = vec3(312.358, -282.7301, 54.30365), yaw = 250.86 } },
    { label = 'Fleeca - Route 68',        door = { pos = vec3(1175.542, 2710.861, 38.22689), yaw = 90.0 } },
}

local function T(target, p) return C.transform(BASE, target, p) end

local locations = {}
for i = 1, #branches do
    local b = branches[i]
    local d = b.door
    local loc = {
        label = b.label,
        center = T(d, LAYOUT.center),
        entrance = T(d, LAYOUT.entrance),
        pad = T(d, LAYOUT.pad),
        gatePad = T(d, LAYOUT.gatePad),
        pile = T(d, LAYOUT.pile),
        trolleys = {},
        lockboxes = {},
        doors = {
            vault = { models = VAULT_MODELS, coords = d.pos, radius = 3.0, kind = 'vault', delta = -80.0 },
            gate = { models = GATE_MODELS, coords = T(d, LAYOUT.gate), radius = 3.0, kind = 'gate' },
        },
    }
    for j = 1, #LAYOUT.trolleys do
        local t = LAYOUT.trolleys[j]
        loc.trolleys[j] = { T(d, t[1]), C.transformHeading(BASE, d, t[2]), t[3] }
    end
    for j = 1, #LAYOUT.lockboxes do
        local l = LAYOUT.lockboxes[j]
        loc.lockboxes[j] = { T(d, l[1]), C.transformHeading(BASE, d, l[2]) }
    end
    locations[i] = loc
end

return {
    label = 'Fleeca Bank',
    description = 'Crack a Fleeca vault with a SafePad, breach the inner gate and empty the trolleys.',
    category = 'medium',
    icon = 'vault',
    level = 2,
    police = 2,
    members = { min = 1, max = 4 },
    cooldown = 20,
    locationCooldown = 45,
    playerCooldown = 15,
    timeLimit = 25,
    simultaneous = 2,
    escape = 200.0,
    rewards = { xp = 600, money = { 4000, 7000 } },
    requiredItems = { { name = 'safepad', count = 1, label = 'SafePad' } },
    alertTitle = 'Fleeca Bank Alarm',
    briefing = {
        'Go to the marked Fleeca branch.',
        'Plug a SafePad into the vault panel and crack it - the silent alarm trips instantly.',
        'Hack the inner gate panel, then grab the trolleys and drill the lockboxes (Heavy Drill).',
        'Get 200m away to finish.',
    },
    loot = C.with(C.loot, {
        trolley_cash = { { item = 'money', min = 7000, max = 10000 } },
        trolley_gold = { { item = 'gold_bar', min = 2, max = 4 } },
    }),
    locations = locations,
    stages = function(loc)
        local loot = {}
        for i = 1, #loc.trolleys do
            local t = loc.trolleys[i]
            loot[#loot + 1] = C.trolley('trolley' .. i, t[1], t[2], t[3], { requires = { 'gate_pad' } })
        end
        loot[#loot + 1] = C.pile('pile', loc.pile, 0.0, C.models.cashPile, 'cash_pile', { requires = { 'gate_pad' } })
        for i = 1, #loc.lockboxes do
            local l = loc.lockboxes[i]
            loot[#loot + 1] = {
                id = 'lockbox' .. i, type = 'interact', action = 'drill', label = 'Drill lockboxes', icon = 'fas fa-screwdriver',
                coords = l[1], heading = l[2], radius = 1.0, minigame = { type = 'drill', difficulty = 2 }, reward = 'lockbox', rolls = 2,
                item = { name = 'heist_drill', label = 'Heavy Drill' }, objective = 'Lockboxes',
            }
        end
        local gate = {
            id = 'gate_pad', type = 'interact', action = 'hack', label = 'Bypass the gate lock', icon = 'fas fa-terminal',
            coords = loc.gatePad, radius = 0.9, minigame = { type = 'typing', difficulty = 2 }, unlocks = { 'gate' },
        }
        loot[#loot + 1] = gate

        return {
            {
                id = 'vault',
                task = 'Crack the vault door',
                blip = { coords = loc.entrance, label = loc.label },
                nodes = {
                    {
                        id = 'vault_pad', type = 'interact', action = 'keypad', label = 'Plug in SafePad', icon = 'fas fa-microchip',
                        coords = loc.pad, radius = 0.9, minigame = { type = 'keypad', difficulty = 2 }, unlocks = { 'vault' }, alert = 1.0,
                        item = { name = 'safepad', label = 'SafePad', remove = true },
                    },
                },
            },
            {
                id = 'gate',
                task = 'Bypass the inner gate',
                nodes = loot,
            },
        }
    end,
}
