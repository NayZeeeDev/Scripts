--[[
    nayzeee-sneakers · crafting: tables, materials, recipes, XP and the supplier
]]

-- ████████╗ █████╗ ██████╗ ██╗     ███████╗███████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝██╔════╝
--    ██║   ███████║██████╔╝██║     █████╗  ███████╗
--    ██║   ██╔══██║██╔══██╗██║     ██╔══╝  ╚════██║
--    ██║   ██║  ██║██████╔╝███████╗███████╗███████║
--    ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚══════╝

-- The tables are Dragons Lab's "Shoe Table Pack" by SasDragon. They are NOT part
-- of this script: every server buys them from her and installs her resource
-- next to this one. The script finds her models by name, so her folder can be
-- called anything.
--
-- Without her pack the tables fall back to a plain GTA workbench (or are turned
-- off, with fallback = false).

Config.Tables = {
    store = 'https://discord.com/invite/KEhZqcuv6m',   -- where to buy her tables (printed in the console)

    -- item name = table. The item names match the icons in her pack's install-images folder.
    items = {
        blueshoetable   = { label = 'Blue shoe table',   model = `sasdragonslab_blue_shoetable` },
        pinkshoetable   = { label = 'Pink shoe table',   model = `sasdragonslab_pink_shoetable` },
        purpleshoetable = { label = 'Purple shoe table', model = `sasdragonslab_purple_shoetable` },
        redshoetable    = { label = 'Red shoe table',    model = `sasdragonslab_red_shoetable` },
    },
    surface = 0.93,               -- height of her table top (metres above the floor)
    stand   = 0.45,               -- how far from the table edge the player stands
    side    = 'nearest',          -- where they stand: 'nearest' long side | 'front' | 'back' of the table
    workOffset = vector3(0.0, 0.0, 0.0),   -- nudge where the shoes sit (x = along the table, y = across); 0 = the middle

    -- what the player does at the table: an upright "working on the bench" loop
    anim = { dict = 'anim@amb@business@coc@coc_unpack_cut_left@', clip = 'coke_cut_v1_coccutter' },

    fallback = `prop_tool_bench02`,   -- used when her pack isn't installed; false = no tables without it
    fallbackSurface = nil,            -- nil = work it out from the model

    maxPerPlayer = 1,
    streamDistance = 60.0,
    interactDistance = 2.0,
    anyoneCanUse = true,          -- false = only the owner can craft at a placed table

    -- Tables that are always there (a shop, a warehouse). They can't be picked up.
    -- { item = 'pinkshoetable', coords = vector4(x, y, z, heading) },
    fixed = {},
}

-- ███╗   ███╗ █████╗ ████████╗███████╗██████╗ ██╗ █████╗ ██╗     ███████╗
-- ████╗ ████║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██║██╔══██╗██║     ██╔════╝
-- ██╔████╔██║███████║   ██║   █████╗  ██████╔╝██║███████║██║     ███████╗
-- ██║╚██╔╝██║██╔══██║   ██║   ██╔══╝  ██╔══██╗██║██╔══██║██║     ╚════██║
-- ██║ ╚═╝ ██║██║  ██║   ██║   ███████╗██║  ██║██║██║  ██║███████╗███████║
-- ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

-- Bought from the supplier, used up by crafting. level = player level needed to buy it.

Config.Materials = {
    nz_leather  = { label = 'Leather hide',   price = 45 },
    nz_fabric   = { label = 'Mesh fabric',    price = 25 },
    nz_sole     = { label = 'Rubber sole',    price = 35 },
    nz_heel     = { label = 'Heel block',     price = 40 },
    nz_thread   = { label = 'Waxed thread',   price = 12 },
    nz_glue     = { label = 'Shoe glue',      price = 18 },
    nz_laces    = { label = 'Laces',          price = 8 },
    nz_authtag  = { label = 'Authentic tag',  price = 650, level = 4 },  -- only real pairs use these
}

-- ██████╗ ███████╗ ██████╗██╗██████╗ ███████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██║██╔══██╗██╔════╝██╔════╝
-- ██████╔╝█████╗  ██║     ██║██████╔╝█████╗  ███████╗
-- ██╔══██╗██╔══╝  ██║     ██║██╔═══╝ ██╔══╝  ╚════██║
-- ██║  ██║███████╗╚██████╗██║██║     ███████╗███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝╚═╝     ╚══════╝╚══════╝

-- What one pair takes, by box size. A model can override it with Config.Crafting.models[model].recipe.
Config.Recipes = {
    shoe = { nz_fabric = 2, nz_leather = 1, nz_sole = 1, nz_thread = 1, nz_glue = 1, nz_laces = 1 },
    heel = { nz_leather = 2, nz_heel = 1, nz_thread = 1, nz_glue = 1 },
    boot = { nz_leather = 3, nz_sole = 1, nz_thread = 2, nz_glue = 1 },
}

--  ██████╗██████╗  █████╗ ███████╗████████╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██║████╗  ██║██╔════╝
-- ██║     ██████╔╝███████║█████╗     ██║   ██║██╔██╗ ██║██║  ███╗
-- ██║     ██╔══██╗██╔══██║██╔══╝     ██║   ██║██║╚██╗██║██║   ██║
-- ╚██████╗██║  ██║██║  ██║██║        ██║   ██║██║ ╚████║╚██████╔╝
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Crafting = {
    realExtra = { nz_authtag = 1 },   -- added to the recipe for a real pair
    realLevel = 4,                    -- level needed to make real pairs

    -- Level needed per shoe model (anything not listed is level 1)
    models = {
        crevis = { level = 1 },
        court  = { level = 2 },
        cup    = { level = 3 },
        fang5  = { level = 3 },
        stack  = { level = 5 },
        bianca = { level = 1 },
        omnia  = { level = 2 },
        maisie = { level = 3 },
        alice  = { level = 4 },
        mia    = { level = 5 },
    },

    -- Each pair is made in stages. time is in ms; check is an ox_lib skill check
    -- ('easy' | 'medium' | 'hard', or false for none).
    stages = {
        shoe = {
            { label = 'Cutting the upper',   time = 4500, check = 'easy',   anim = 'cut' },
            { label = 'Stitching the panels', time = 5000, check = 'medium', anim = 'work' },
            { label = 'Gluing the sole',     time = 4000, check = 'medium', anim = 'work' },
            { label = 'Lacing up',           time = 3500, check = false,    anim = 'work' },
        },
        heel = {
            { label = 'Cutting the leather', time = 4500, check = 'easy',   anim = 'cut' },
            { label = 'Stitching',           time = 5000, check = 'medium', anim = 'work' },
            { label = 'Fitting the heel',    time = 4500, check = 'hard',   anim = 'work' },
            { label = 'Finishing',           time = 3000, check = false,    anim = 'work' },
        },
        boot = {
            { label = 'Cutting the shaft',   time = 5000, check = 'easy',   anim = 'cut' },
            { label = 'Stitching',           time = 6000, check = 'medium', anim = 'work' },
            { label = 'Gluing the sole',     time = 4500, check = 'medium', anim = 'work' },
            { label = 'Finishing',           time = 3500, check = false,    anim = 'work' },
        },
    },
    skillChecks = true,        -- false = stages just run, every check counts as passed
    speedPerLevel = 0.04,      -- each level makes crafting 4% faster (up to 40%)

    -- Fake quality (how convincing a fake is, 0-100). Legit checks use it in the selling phase.
    -- quality = base + level * perLevel + passed checks * pass - failed checks * fail, +/- spread
    fakeQuality = { base = 40, perLevel = 4, pass = 6, fail = 12, spread = 5, min = 10, max = 97 },

    xp = { shoe = 20, heel = 25, boot = 30, realBonus = 1.5, perfectBonus = 10 },
}

-- ██╗     ███████╗██╗   ██╗███████╗██╗     ███████╗
-- ██║     ██╔════╝██║   ██║██╔════╝██║     ██╔════╝
-- ██║     █████╗  ██║   ██║█████╗  ██║     ███████╗
-- ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ╚════██║
-- ███████╗███████╗ ╚████╔╝ ███████╗███████╗███████║
-- ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝╚══════╝

-- Built in, saved per character. Crafting, cleaning and selling all give XP.

Config.XP = {
    -- total XP needed for each level (level 1 starts at 0)
    levels = { 0, 120, 300, 560, 900, 1350, 1900, 2600, 3450, 4500 },
}

-- ███████╗██╗   ██╗██████╗ ██████╗ ██╗     ██╗███████╗██████╗
-- ██╔════╝██║   ██║██╔══██╗██╔══██╗██║     ██║██╔════╝██╔══██╗
-- ███████╗██║   ██║██████╔╝██████╔╝██║     ██║█████╗  ██████╔╝
-- ╚════██║██║   ██║██╔═══╝ ██╔═══╝ ██║     ██║██╔══╝  ██╔══██╗
-- ███████║╚██████╔╝██║     ██║     ███████╗██║███████╗██║  ██║
-- ╚══════╝ ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝

-- An NPC who sells the materials and cleaning kits.

Config.Supplier = {
    enabled = true,
    label = 'Shoe supplies',
    ped = `s_m_m_linecook`,
    coords = vector4(195.17, -933.77, 30.69, 145.0),  -- Legion Square; move it anywhere
    blip = { sprite = 366, colour = 48, scale = 0.75 },   -- false = no blip
    account = 'cash',           -- 'cash' | 'bank'
    maxPerItem = 50,            -- most of one item per purchase

    -- Everything else he sells, next to the materials
    Extra = {
        nz_shoebox_empty = { label = 'Empty shoe box',  price = 15 },
        nz_heelbox_empty = { label = 'Empty heel box',  price = 15 },
        nz_bootbox_empty = { label = 'Empty boot box',  price = 22 },
        nz_cleaning_kit  = { label = 'Cleaning kit',    price = 120 },
    },
}
