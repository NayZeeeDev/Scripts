--[[ Paleto Bay Bank - kill the power, thermite the doors, deal with security, crack the vault ]]

local C = lib.load('config.heists._common')

return {
    label = 'Blaine County Savings',
    description = 'Sabotage the power box behind the Paleto Bay bank, burn through the doors, clear security and crack the vault.',
    category = 'major',
    icon = 'bank',
    level = 5,
    police = 3,
    members = { min = 2, max = 6 },
    cooldown = 50,
    playerCooldown = 20,
    timeLimit = 35,
    simultaneous = 1,
    escape = 250.0,
    rewards = { xp = 1400, money = { 8000, 12000 } },
    requiredItems = {
        { name = 'thermite', count = 1, label = 'Thermite Charge' },
        { name = 'safepad', count = 1, label = 'SafePad' },
    },
    alertTitle = 'Paleto Bank Alarm',
    briefing = {
        'Sabotage the power box behind the bank to kill the cameras.',
        'Burn the front doors open with thermite. Security will respond.',
        'Clear the guards and crack the vault with a SafePad.',
        'Empty the trolleys and get 250m away.',
    },
    loot = C.with(C.loot, {
        trolley_cash = { { item = 'money', min = 11000, max = 16000 } },
        trolley_gold = { { item = 'gold_bar', min = 4, max = 7 } },
    }),
    locations = {
        {
            label = 'Blaine County Savings - Paleto Bay',
            center = vec3(-105.81, 6467.89, 31.62),
            entrance = vec3(-110.60, 6463.00, 31.60),
            power = vec4(-100.90, 6478.69, 30.45, 135.0),
            pad = vec3(-105.90, 6472.15, 31.87),
            doors = {
                front_l = { model = -353187150, coords = vec3(-111.480, 6463.940, 31.985), radius = 2.0, kind = 'gate' },
                front_r = { model = -1666470363, coords = vec3(-109.650, 6462.110, 31.985), radius = 2.0, kind = 'gate' },
                vault = { model = 'v_ilev_cbankvauldoor01', coords = vec3(-104.605, 6473.444, 31.795), radius = 3.0, kind = 'vault', delta = 85.0 },
            },
            guards = {
                vec4(-108.0, 6466.0, 31.63, 225.0), vec4(-103.5, 6469.0, 31.63, 135.0), vec4(-99.5, 6466.5, 31.63, 90.0),
                vec4(-112.0, 6469.5, 31.63, 315.0), vec4(-106.0, 6475.0, 31.63, 180.0),
            },
        },
    },
    stages = function(loc)
        return {
            {
                id = 'power',
                task = 'Sabotage the power box',
                blip = { coords = loc.power.xyz, label = 'Power box' },
                nodes = {
                    {
                        id = 'power', type = 'interact', action = 'repair', label = 'Sabotage power box', icon = 'fas fa-bolt',
                        coords = loc.power.xyz, heading = loc.power.w, radius = 1.2, minigame = { type = 'circuit', difficulty = 2 },
                        prop = { model = C.models.elecbox, heading = loc.power.w }, flag = 'power',
                    },
                },
            },
            {
                id = 'breach',
                task = 'Burn through the front doors',
                blip = { coords = loc.entrance, label = 'Bank entrance' },
                spawn = { at = loc.center, distance = 150.0, guards = C.guards(loc.guards, { model = 's_m_m_security_01', weapons = { 'WEAPON_PISTOL', 'WEAPON_PUMPSHOTGUN' } }) },
                nodes = {
                    {
                        id = 'thermite', type = 'interact', action = 'thermite', label = 'Place thermite', icon = 'fas fa-fire',
                        coords = loc.entrance, radius = 1.4, minigame = { type = 'memory', difficulty = 2 }, burn = 9000,
                        unlocks = { 'front_l', 'front_r' }, item = { name = 'thermite', label = 'Thermite', remove = true }, alert = 1.0,
                    },
                },
            },
            {
                id = 'vault',
                task = 'Clear security and crack the vault',
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Neutralize security' },
                    {
                        id = 'vault_pad', type = 'interact', action = 'keypad', label = 'Plug in SafePad', icon = 'fas fa-microchip',
                        coords = loc.pad, radius = 0.9, minigame = { type = 'keypad', difficulty = 3 }, unlocks = { 'vault' },
                        item = { name = 'safepad', label = 'SafePad', remove = true },
                    },
                    C.trolley('t1', vec3(-106.661, 6477.467, 31.10), 270.0, 'cash', { requires = { 'vault_pad' } }),
                    C.trolley('t2', vec3(-102.340, 6476.716, 31.10), 90.0, 'cash', { requires = { 'vault_pad' } }),
                    C.trolley('t3', vec3(-104.744, 6479.259, 31.14), 170.0, 'gold', { requires = { 'vault_pad' } }),
                    C.pile('pile1', vec3(-104.20, 6476.10, 31.62), 0.0, C.models.cashStack, 'cash_pile', { requires = { 'vault_pad' } }),
                },
            },
        }
    end,
}
