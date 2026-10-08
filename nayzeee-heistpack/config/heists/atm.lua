--[[ ATM Spree - rob any ATM in the city: hack it, drill it, blow it or rip it out with a tow rope ]]

return {
    label = 'ATM Spree',
    description = 'Hit three ATMs anywhere in the city. Pick your method: hack, drill, C4 or rip it off the wall with a tow rope.',
    category = 'small',
    icon = 'atm',
    level = 1,
    police = 1,
    members = { min = 1, max = 2 },
    cooldown = 0,
    playerCooldown = 10,
    timeLimit = 25,
    simultaneous = 6,
    escape = false,
    rewards = { xp = 220, money = { 500, 900 } },
    requiredItems = {},
    briefing = {
        'Any ATM in the city works - each one can only be hit once an hour.',
        'Hack: Hacking Device. Drill: Heavy Drill. Blow: C4 Charge. Rip: Tow Rope + a vehicle.',
        'Rob 3 ATMs to finish. Every attempt can tip off the police.',
    },
    loot = {
        atm_hack = { { item = 'money', min = 1200, max = 2200 } },
        atm_drill = { { item = 'money', min = 1500, max = 2600 } },
        atm_c4 = { { item = 'money', min = 2200, max = 3800 } },
        atm_rope = { { item = 'money', min = 2600, max = 4200 } },
    },
    locations = {
        { label = 'Los Santos', center = vec3(150.0, -1040.0, 29.4) },
    },
    stages = function()
        return {
            {
                id = 'atms',
                task = 'Rob 3 ATMs anywhere in the city',
                nodes = {
                    {
                        id = 'atms', type = 'atm', label = 'ATMs', objective = 'ATMs robbed', uses = 3, required = true,
                        dynamic = true, radius = 1.5, spotCooldown = 60, alert = 0.5, claimRange = 3.0, finishRange = 25.0,
                        methods = {
                            hack = { label = 'Hack ATM', icon = 'fas fa-laptop-code', item = 'hacking_device', action = 'hack', minigame = { type = 'datacrack', difficulty = 2 }, reward = 'atm_hack' },
                            drill = { label = 'Drill ATM', icon = 'fas fa-screwdriver', item = 'heist_drill', action = 'drill', minigame = { type = 'drill', difficulty = 2 }, reward = 'atm_drill' },
                            c4 = { label = 'Blow ATM (C4)', icon = 'fas fa-bomb', item = 'c4_charge', remove = true, action = 'c4', reward = 'atm_c4' },
                            rope = { label = 'Rip ATM out (rope)', icon = 'fas fa-link', item = 'heavy_rope', remove = true, reward = 'atm_rope' },
                        },
                    },
                },
            },
        }
    end,
}
