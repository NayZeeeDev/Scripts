-- ██╗    ██╗███████╗ █████╗ ██████╗  ██████╗ ███╗   ██╗███████╗
-- ██║    ██║██╔════╝██╔══██╗██╔══██╗██╔═══██╗████╗  ██║██╔════╝
-- ██║ █╗ ██║█████╗  ███████║██████╔╝██║   ██║██╔██╗ ██║███████╗
-- ██║███╗██║██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██║╚██╗██║╚════██║
-- ╚███╔███╔╝███████╗██║  ██║██║     ╚██████╔╝██║ ╚████║███████║
--  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝╚══════╝

--[[
    LOBBY WEAPON SHOWCASE — a character can hold a weapon in the lobby (Customize > Weapon).

    mode
      'inventory'  (default) only weapons the character actually owns (ox_inventory, qb-inventory, qs-inventory, ESX loadout)
      'whitelist'  only the curated list below
      'both'       owned weapons + the whitelist
    Players also get 'Auto' (best weapon they own, by `priority`) and 'None'.
    Attachments and tints are kept from the inventory when the inventory stores them.
]]

Config.WeaponShowcase = {
    enabled   = true,
    mode      = 'inventory',
    allowAuto = true,
    allowNone = true,
    default   = 'auto',                -- what a character holds before picking: 'auto' | 'none'

    -- Class priority for 'Auto' (first match wins)
    priority = { 'rifle', 'mg', 'sniper', 'shotgun', 'smg', 'pistol', 'melee' },

    whitelist = {
        { name = 'WEAPON_CARBINERIFLE', label = 'Carbine Rifle' },
        { name = 'WEAPON_SPECIALCARBINE', label = 'Special Carbine' },
        { name = 'WEAPON_PISTOL50', label = 'Pistol .50' },
        { name = 'WEAPON_SMG', label = 'SMG' },
        { name = 'WEAPON_PUMPSHOTGUN', label = 'Pump Shotgun' },
        { name = 'WEAPON_BAT', label = 'Baseball Bat' },
    },

    -- Weapon -> class. Anything missing is classified client-side from the weapon group.
    classes = {
        pistol  = { 'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50', 'WEAPON_SNSPISTOL',
                    'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_REVOLVER', 'WEAPON_DOUBLEACTION', 'WEAPON_CERAMICPISTOL', 'WEAPON_STUNGUN' },
        smg     = { 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG' },
        rifle   = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE',
                    'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_MILITARYRIFLE', 'WEAPON_TACTICALRIFLE' },
        shotgun = { 'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN',
                    'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_COMBATSHOTGUN' },
        sniper  = { 'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE', 'WEAPON_MARKSMANRIFLE_MK2', 'WEAPON_PRECISIONRIFLE' },
        mg      = { 'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_COMBATMG_MK2', 'WEAPON_GUSENBERG' },
        melee   = { 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_CROWBAR', 'WEAPON_GOLFCLUB', 'WEAPON_HAMMER', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE',
                    'WEAPON_KNUCKLE', 'WEAPON_NIGHTSTICK', 'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_POOLCUE', 'WEAPON_HATCHET', 'WEAPON_DAGGER' },
    },

    -- Relaxed low-ready hold per class so nobody stands in a stiff combat stance.
    -- If a dict is missing on your game build the ped simply keeps the natural weapon idle.
    holds = {
        pistol  = { dict = 'move_weapon@pistol@copa', clip = 'idle', flag = 49 },
        smg     = { dict = 'anim@heists@heist_corona@team_idles@male_c', clip = 'idle', flag = 1 },
        rifle   = { dict = 'anim@heists@heist_corona@team_idles@male_a', clip = 'idle', flag = 1 },
        shotgun = { dict = 'anim@heists@heist_corona@team_idles@male_a', clip = 'idle', flag = 1 },
        sniper  = { dict = 'anim@heists@heist_corona@team_idles@male_b', clip = 'idle', flag = 1 },
        mg      = { dict = 'anim@heists@heist_corona@team_idles@male_b', clip = 'idle', flag = 1 },
        melee   = { dict = 'anim@heists@heist_corona@team_idles@male_d', clip = 'idle', flag = 1 },
    },
}
