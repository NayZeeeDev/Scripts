--[[ Phone Network Hack (new) - splice into payphones across the city and skim the network ]]

return {
    label = 'Phone Network Hack',
    description = 'Splice a hacking device into four public payphones anywhere in the city and skim the network before the trace completes.',
    category = 'small',
    icon = 'chip',
    level = 1,
    police = 0,
    members = { min = 1, max = 2 },
    cooldown = 0,
    playerCooldown = 10,
    timeLimit = 15,
    simultaneous = 6,
    escape = false,
    rewards = { xp = 180, money = { 600, 1200 } },
    requiredItems = { { name = 'hacking_device', count = 1, label = 'Hacking Device' } },
    briefing = {
        'Find any public payphone in the city.',
        'Splice your hacking device into it and solve the circuit.',
        'Hack 4 different payphones before the 15 minute trace completes.',
    },
    loot = {
        payphone = {
            { item = 'money', min = 350, max = 800 },
            { item = 'data_drive', min = 1, max = 1, chance = 0.2 },
        },
    },
    locations = {
        { label = 'Los Santos', center = vec3(150.0, -1040.0, 29.4) },
    },
    stages = function()
        return {
            {
                id = 'phones',
                task = 'Hack 4 payphones anywhere in the city',
                nodes = {
                    {
                        id = 'phones', type = 'objects', label = 'Payphones', objective = 'Payphones hacked', uses = 4, required = true,
                        dynamic = true, radius = 1.5, spotCooldown = 120, alert = 0.15, claimRange = 3.0,
                        models = { 'prop_phonebox_01a', 'prop_phonebox_01b', 'prop_phonebox_01c', 'prop_phonebox_02', 'prop_phonebox_03', 'prop_phonebox_04' },
                        methods = {
                            hack = { label = 'Splice payphone', icon = 'fas fa-phone-volume', item = 'hacking_device', action = 'hack', minigame = { type = 'circuit', difficulty = 2 }, reward = 'payphone' },
                        },
                    },
                },
            },
        }
    end,
}
