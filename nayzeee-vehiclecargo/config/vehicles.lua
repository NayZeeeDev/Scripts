-- ██╗   ██╗███████╗██╗  ██╗██╗ ██████╗██╗     ███████╗███████╗
-- ██║   ██║██╔════╝██║  ██║██║██╔════╝██║     ██╔════╝██╔════╝
-- ██║   ██║█████╗  ███████║██║██║     ██║     █████╗  ███████╗
-- ╚██╗ ██╔╝██╔══╝  ██╔══██║██║██║     ██║     ██╔══╝  ╚════██║
--  ╚████╔╝ ███████╗██║  ██║██║╚██████╗███████╗███████╗███████║
--   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝╚══════╝╚══════╝

-- Server owners can add more (including addon cars) from the
-- in-game Admin tab. Those are saved in the database and stack on
-- top of this list. Admin entries with the same model override.
--
-- model  = spawn name
-- label  = display name (leave nil to use the game name)
-- rarity = common | uncommon | rare | epic | legendary | mythic
-- value  = base sale value at 100% condition before bonuses
Config.Vehicles = {
    -- Common
    { model = 'blista',     label = 'Blista',          rarity = 'common',    value = 14000 },
    { model = 'futo',       label = 'Futo',            rarity = 'common',    value = 16000 },
    { model = 'prairie',    label = 'Prairie',         rarity = 'common',    value = 15000 },
    { model = 'penumbra',   label = 'Penumbra',        rarity = 'common',    value = 19000 },
    { model = 'sultan',     label = 'Sultan',          rarity = 'common',    value = 22000 },
    { model = 'buffalo',    label = 'Buffalo',         rarity = 'common',    value = 21000 },
    { model = 'dominator',  label = 'Dominator',       rarity = 'common',    value = 24000 },
    { model = 'fugitive',   label = 'Fugitive',        rarity = 'common',    value = 17000 },

    -- Uncommon
    { model = 'banshee',    label = 'Banshee',         rarity = 'uncommon',  value = 38000 },
    { model = 'comet2',     label = 'Comet',           rarity = 'uncommon',  value = 42000 },
    { model = 'elegy2',     label = 'Elegy RH8',       rarity = 'uncommon',  value = 36000 },
    { model = 'feltzer2',   label = 'Feltzer',         rarity = 'uncommon',  value = 40000 },
    { model = 'coquette',   label = 'Coquette',        rarity = 'uncommon',  value = 41000 },
    { model = 'massacro',   label = 'Massacro',        rarity = 'uncommon',  value = 45000 },
    { model = 'jester',     label = 'Jester',          rarity = 'uncommon',  value = 44000 },
    { model = 'ninef',      label = '9F',              rarity = 'uncommon',  value = 43000 },

    -- Rare
    { model = 'carbonizzare', label = 'Carbonizzare',  rarity = 'rare',      value = 68000 },
    { model = 'rapidgt',    label = 'Rapid GT',        rarity = 'rare',      value = 64000 },
    { model = 'seven70',    label = 'Seven-70',        rarity = 'rare',      value = 78000 },
    { model = 'specter',    label = 'Specter',         rarity = 'rare',      value = 74000 },
    { model = 'verlierer2', label = 'Verlierer',       rarity = 'rare',      value = 72000 },
    { model = 'jester3',    label = 'Jester Classic',  rarity = 'rare',      value = 70000 },
    { model = 'comet5',     label = 'Comet SR',        rarity = 'rare',      value = 80000 },
    { model = 'sultanrs',   label = 'Sultan RS',       rarity = 'rare',      value = 66000 },

    -- Epic
    { model = 'zentorno',   label = 'Zentorno',        rarity = 'epic',      value = 118000 },
    { model = 'turismor',   label = 'Turismo R',       rarity = 'epic',      value = 112000 },
    { model = 'osiris',     label = 'Osiris',          rarity = 'epic',      value = 124000 },
    { model = 't20',        label = 'T20',             rarity = 'epic',      value = 128000 },
    { model = 'tempesta',   label = 'Tempesta',        rarity = 'epic',      value = 115000 },
    { model = 'italigtb',   label = 'Itali GTB',       rarity = 'epic',      value = 120000 },
    { model = 'nero',       label = 'Nero',            rarity = 'epic',      value = 126000 },
    { model = 'reaper',     label = 'Reaper',          rarity = 'epic',      value = 116000 },

    -- Legendary
    { model = 'x80',        label = 'X80 Proto',       rarity = 'legendary', value = 185000 },
    { model = 'entity2',    label = 'Entity XXR',      rarity = 'legendary', value = 176000 },
    { model = 'tezeract',   label = 'Tezeract',        rarity = 'legendary', value = 190000 },
    { model = 'krieger',    label = 'Krieger',         rarity = 'legendary', value = 182000 },
    { model = 'emerus',     label = 'Emerus',          rarity = 'legendary', value = 178000 },
    { model = 'thrax',      label = 'Thrax',           rarity = 'legendary', value = 180000 },
    { model = 'zorrusso',   label = 'Zorrusso',        rarity = 'legendary', value = 174000 },

    -- Mythic
    { model = 'deveste',    label = 'Deveste Eight',   rarity = 'mythic',    value = 265000 },
    { model = 'vagner',     label = 'Vagner',          rarity = 'mythic',    value = 248000 },
    { model = 'furia',      label = 'Furia',           rarity = 'mythic',    value = 242000 },
    { model = 'ignus',      label = 'Ignus',           rarity = 'mythic',    value = 258000 },
    { model = 'zeno',       label = 'Zeno',            rarity = 'mythic',    value = 252000 },
    { model = 'torero2',    label = 'Torero XO',       rarity = 'mythic',    value = 255000 },
}

-- ██╗██╗     ██╗     ███████╗ ██████╗  █████╗ ██╗
-- ██║██║     ██║     ██╔════╝██╔════╝ ██╔══██╗██║
-- ██║██║     ██║     █████╗  ██║  ███╗███████║██║
-- ██║██║     ██║     ██╔══╝  ██║   ██║██╔══██║██║
-- ██║███████╗███████╗███████╗╚██████╔╝██║  ██║███████╗
-- ╚═╝╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

-- Downstairs only: 4 slots, needs the Lower Level upgrade.
-- Swap these for whatever your server treats as contraband.
-- Weaponised models are fine here: sourced cars are stored, not driven around.
Config.IllegalVehicles = {
    { model = 'kuruma2',    label = 'Kuruma (Armored)', value = 300000 },
    { model = 'nightshark', label = 'Nightshark',       value = 340000 },
    { model = 'ruiner2',    label = 'Ruiner 2000',      value = 430000 },
    { model = 'stromberg',  label = 'Stromberg',        value = 450000 },
    { model = 'toreador',   label = 'Toreador',         value = 470000 },
    { model = 'deluxo',     label = 'Deluxo',           value = 480000 },
    { model = 'scramjet',   label = 'Scramjet',         value = 500000 },
    { model = 'vigilante',  label = 'Vigilante',        value = 520000 },
}

-- ███████╗██████╗ ███████╗ ██████╗██╗ █████╗ ██╗     ███████╗
-- ██╔════╝██╔══██╗██╔════╝██╔════╝██║██╔══██╗██║     ██╔════╝
-- ███████╗██████╔╝█████╗  ██║     ██║███████║██║     ███████╗
-- ╚════██║██╔═══╝ ██╔══╝  ██║     ██║██╔══██║██║     ╚════██║
-- ███████║██║     ███████╗╚██████╗██║██║  ██║███████╗███████║
-- ╚══════╝╚═╝     ╚══════╝ ╚═════╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

-- Pools for the special contracts (Config.SpecialContracts in config.lua).
-- Each car keeps its own rarity, so it designs and sells like any other car.
Config.SpecialVehicles = {
    -- Classic Collector
    classic = {
        { model = 'stinger',    label = 'Stinger',          rarity = 'rare',      value = 72000 },
        { model = 'ztype',      label = 'Z-Type',           rarity = 'epic',      value = 128000 },
        { model = 'monroe',     label = 'Monroe',           rarity = 'rare',      value = 76000 },
        { model = 'casco',      label = 'Casco',            rarity = 'rare',      value = 70000 },
        { model = 'mamba',      label = 'Mamba',            rarity = 'epic',      value = 118000 },
        { model = 'cheetah2',   label = 'Cheetah Classic',  rarity = 'epic',      value = 122000 },
        { model = 'infernus2',  label = 'Infernus Classic', rarity = 'epic',      value = 125000 },
        { model = 'torero',     label = 'Torero',           rarity = 'legendary', value = 170000 },
        { model = 'gt500',      label = 'GT500',            rarity = 'rare',      value = 68000 },
        { model = 'stirlinggt', label = 'Stirling GT',      rarity = 'epic',      value = 114000 },
    },
    -- Two-Wheel Run
    bike = {
        { model = 'bati',       label = 'Bati 801',         rarity = 'uncommon',  value = 30000 },
        { model = 'akuma',      label = 'Akuma',            rarity = 'uncommon',  value = 28000 },
        { model = 'hakuchou',   label = 'Hakuchou',         rarity = 'rare',      value = 52000 },
        { model = 'double',     label = 'Double-T',         rarity = 'uncommon',  value = 31000 },
        { model = 'vader',      label = 'Vader',            rarity = 'common',    value = 18000 },
        { model = 'carbonrs',   label = 'Carbon RS',        rarity = 'uncommon',  value = 34000 },
        { model = 'shotaro',    label = 'Shotaro',          rarity = 'epic',      value = 96000 },
        { model = 'hakuchou2',  label = 'Hakuchou Drag',    rarity = 'rare',      value = 62000 },
        { model = 'reever',     label = 'Reever',           rarity = 'rare',      value = 66000 },
    },
}
