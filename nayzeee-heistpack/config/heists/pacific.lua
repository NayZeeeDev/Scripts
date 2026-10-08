--[[
    Pacific Standard - the big one.
    Drone-bomb the substation, thermite the security gate, clear the guards, open the stairwell,
    crack the vault with an encrypted laptop, burn the inner gate and empty the trolleys.
]]

local C = lib.load('config.heists._common')

local GUARDS = {
    vec4(252.13, 218.38, 101.68, 136.67), vec4(259.42, 215.84, 101.68, 65.46), vec4(260.51, 225.43, 101.68, 253.23),
    vec4(263.14, 221.83, 106.28, 95.58), vec4(256.18, 217.77, 106.29, 91.06), vec4(249.95, 208.34, 106.28, 70.45),
    vec4(241.14, 220.41, 106.28, 47.07), vec4(262.74, 212.53, 106.28, 114.93), vec4(254.88, 224.88, 106.28, 79.46),
    vec4(267.22, 222.98, 110.28, 97.20), vec4(240.32, 230.20, 106.28, 150.79), vec4(256.56, 237.04, 108.22, 148.21),
}

return {
    label = 'Pacific Standard',
    description = 'The biggest score in the city. Knock out the substation with drone bombs, fight through security and empty the Pacific Standard vault.',
    category = 'major',
    icon = 'crown',
    level = 8,
    police = 4,
    members = { min = 3, max = 8 },
    cooldown = 120,
    playerCooldown = 30,
    timeLimit = 45,
    simultaneous = 1,
    escape = 350.0,
    rewards = { xp = 3000, money = { 20000, 30000 } },
    requiredItems = {
        { name = 'heist_drone', count = 1, label = 'Recon Drone' },
        { name = 'thermite', count = 2, label = 'Thermite Charge x2' },
        { name = 'heist_laptop', count = 1, label = 'Encrypted Laptop' },
    },
    alertTitle = 'Pacific Standard Alarm',
    briefing = {
        'Go to the substation launch point and fly your drone over the four transformers - press G to drop each bomb.',
        'Thermite the security gate behind the teller counters. Heavy security responds.',
        'Clear the guards and hack the stairwell door.',
        'Crack the vault with the Encrypted Laptop, burn the inner gate and empty every trolley.',
        'Get 350m away.',
    },
    loot = C.with(C.loot, {
        trolley_cash = { { item = 'money', min = 18000, max = 26000 } },
        trolley_gold = { { item = 'gold_bar', min = 6, max = 10 } },
        trolley_diamond = { { item = 'diamond', min = 6, max = 12 } },
        teller = { { item = 'money', min = 2500, max = 4000 } },
    }),
    locations = {
        {
            label = 'Pacific Standard Bank',
            center = vec3(257.06, 221.76, 107.28),
            entrance = vec3(228.18, 213.86, 105.53),
            launch = vec3(740.03, 134.37, 80.56),
            transformers = { vec3(709.07, 115.13, 85.0), vec3(683.08, 115.26, 85.0), vec3(694.03, 157.08, 85.0), vec3(674.97, 157.84, 85.0) },
            gate = vec3(256.31, 220.66, 106.43),
            stairs = vec3(262.20, 222.52, 106.43),
            vaultPad = vec3(253.25, 228.44, 101.68),
            inner = vec3(261.30, 214.51, 101.68),
            doors = {
                gate = { model = 'hei_v_ilev_bk_gate_pris', coords = vec3(256.312, 220.658, 106.430), radius = 2.0, kind = 'gate' },
                stairs = { model = 'hei_v_ilev_bk_gate2_pris', coords = vec3(262.198, 222.519, 106.430), radius = 2.0, kind = 'gate' },
                vault = { model = 'v_ilev_bk_vaultdoor', coords = vec3(255.228, 223.976, 102.393), radius = 3.0, kind = 'vault', delta = -90.0 },
                inner = { model = 'hei_v_ilev_bk_safegate_pris', coords = vec3(261.300, 214.505, 101.683), radius = 2.0, kind = 'gate' },
            },
        },
    },
    stages = function(loc)
        local bombs = {}
        for i = 1, #loc.transformers do
            bombs[i] = {
                id = 'transformer' .. i, type = 'dronedrop', coords = loc.transformers[i], radius = 3.0, label = 'Transformer', objective = 'Bomb the transformers',
                effect = { asset = 'core', name = 'exp_grd_grenade_lod' }, dropMessage = 'Transformer destroyed',
            }
        end
        bombs[#bombs + 1] = { id = 'launch', type = 'zone', coords = loc.launch, radius = 8.0, label = 'Drone launch point', required = false, blip = { label = 'Drone launch point', sprite = 627 } }

        local vault = {
            {
                id = 'vault_pad', type = 'interact', action = 'laptop', label = 'Crack the vault', icon = 'fas fa-laptop-code',
                coords = loc.vaultPad, radius = 1.0, minigame = { type = 'datacrack', difficulty = 3 }, unlocks = { 'vault' },
                item = { name = 'heist_laptop', label = 'Encrypted Laptop', remove = 0.3 },
            },
            {
                id = 'inner_gate', type = 'interact', action = 'thermite', label = 'Burn the inner gate', icon = 'fas fa-fire',
                coords = loc.inner, radius = 1.3, burn = 9000, minigame = { type = 'memory', difficulty = 3 }, unlocks = { 'inner' },
                item = { name = 'thermite', label = 'Thermite', remove = true }, requires = { 'vault_pad' },
            },
            C.trolley('t1', vec3(261.841, 213.085, 101.156), 0.0, 'cash', { requires = { 'inner_gate' } }),
            C.trolley('t2', vec3(266.207, 215.286, 101.156), 180.0, 'cash', { requires = { 'inner_gate' } }),
            C.trolley('t3', vec3(262.810, 216.518, 101.156), 170.0, 'gold', { requires = { 'inner_gate' } }),
            C.trolley('t4', vec3(265.014, 212.068, 101.156), 335.0, 'diamond', { requires = { 'inner_gate' } }),
            C.pile('stack1', vec3(257.60, 216.20, 101.68), 0.0, C.models.goldStack, 'trolley_gold', { requires = { 'vault_pad' }, label = 'Grab gold' }),
        }

        return {
            {
                id = 'grid',
                task = 'Knock out the substation',
                blip = { coords = loc.launch, label = 'Drone launch point', sprite = 627 },
                nodes = bombs,
            },
            {
                id = 'gate',
                task = 'Burn through the security gate',
                blip = { coords = loc.entrance, label = 'Pacific Standard' },
                spawn = { at = loc.center, distance = 160.0, guards = C.guards(GUARDS, { model = 's_m_m_highsec_01', weapons = { 'WEAPON_CARBINERIFLE', 'WEAPON_SMG', 'WEAPON_PUMPSHOTGUN' }, armour = 100 }) },
                nodes = {
                    {
                        id = 'gate', type = 'interact', action = 'thermite', label = 'Thermite the gate', icon = 'fas fa-fire',
                        coords = loc.gate, radius = 1.3, burn = 9000, minigame = { type = 'memory', difficulty = 2 }, unlocks = { 'gate' },
                        item = { name = 'thermite', label = 'Thermite', remove = true }, alert = 1.0,
                    },
                    C.search('teller1', vec3(237.35, 217.85, 106.29), 'teller', { label = 'Empty teller drawer', action = 'grab' }),
                    C.search('teller2', vec3(265.10, 212.10, 106.28), 'teller', { label = 'Empty teller drawer', action = 'grab' }),
                },
            },
            {
                id = 'stairs',
                task = 'Clear security and open the stairwell',
                nodes = {
                    { id = 'guards', type = 'eliminate', group = 'guards', label = 'Neutralize security' },
                    {
                        id = 'stairs', type = 'interact', action = 'hack', label = 'Hack the stairwell door', icon = 'fas fa-terminal',
                        coords = loc.stairs, radius = 1.2, minigame = { type = 'circuit', difficulty = 3 }, unlocks = { 'stairs' },
                    },
                },
            },
            {
                id = 'vault',
                task = 'Crack the vault and burn the inner gate',
                blip = { coords = loc.vaultPad, label = 'Vault' },
                nodes = vault,
            },
        }
    end,
}
