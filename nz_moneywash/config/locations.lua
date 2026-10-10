--[[
    THE WASH — locations

    OPERATIONS  : fixed machine layouts. `access` empty = anyone can use them.
                  coords are the prop's ground pivot (vec4 with heading).
    FRONTS      : legit-looking businesses where washed stacks are "declared" (Cook the Books).
                  Every front has a plausible revenue mix + a daily cap. Stray from it and the
                  Treasury starts asking questions.

    The default operation lives in the basement of the lev_laundromat MLO, and the laundromat's
    back office is a front. Admins can drag any machine to a new spot in game ("Move machine (admin)").
]]

Config.Operations = {
    {
        -- Lev's Laundromat MLO (lev_laundromat) — the wash room is the basement.
        -- Coordinates come straight from the MLO's ymap/ytyp: building origin (898.048, -1038.157, 34.252),
        -- no rotation, basement floor at z 29.59. Fine-tune in game with "Move machine (admin)".
        id     = 'laundromat',
        label  = 'Laundromat Basement',
        blip   = false, -- { sprite = 500, colour = 2, scale = 0.7 }
        access = {
            -- jobs  = { laundromat = 0 },
            -- gangs = { vagos = 0 },
            -- items = { 'nzmw_keycard' },
        },
        stations = {
            { type = 'washer',  coords = vec4(899.95, -1029.46, 29.59, 0.0) },   -- north wall, door faces the room
            { type = 'washer',  coords = vec4(901.15, -1029.46, 29.59, 0.0) },
            { type = 'cutter',  coords = vec4(900.75, -1032.26, 29.59, 0.0) },   -- middle of the room
            { type = 'printer', coords = vec4(901.30, -1035.16, 29.59, 180.0) }, -- along the south wall, operator side faces in
        },
        decor = {},
        -- basement clutter (MLO props) that sits where the machines go — hidden while this resource runs
        hide = {
            { model = 0x8f97d8bc, coords = vec3(899.431, -1034.933, 29.597) },
            { model = 0x672acd25, coords = vec3(901.031, -1035.587, 29.591) },
            { model = 0x676ab38e, coords = vec3(900.220, -1033.664, 29.782) },
            { model = 0xb7c2d445, coords = vec3(900.355, -1034.365, 29.602) },
            { model = 0xa8231f27, coords = vec3(903.395, -1034.759, 29.588) },
            { model = 0xa8231f27, coords = vec3(902.850, -1035.778, 29.588) },
            { model = 0x02ea1fea, coords = vec3(900.857, -1032.628, 30.019) },
            { model = 0x4da19524, coords = vec3(900.639, -1032.833, 30.575) },
            { model = 0xd519d463, coords = vec3(900.619, -1032.432, 30.447) },
        },
    },

    --[[ Demo layout on the Alta rooftop the prop author tested on (no MLO needed)
    {
        id = 'alta_roof', label = 'Alta Rooftop Plant', access = {},
        stations = {
            { type = 'washer',  coords = vec4(240.20, -271.60, 68.30, 160.0) },
            { type = 'washer',  coords = vec4(239.35, -271.29, 68.30, 160.0) },
            { type = 'printer', coords = vec4(246.40, -268.40, 68.30, 160.0) },
            { type = 'cutter',  coords = vec4(243.20, -264.40, 68.30, 160.0) },
        },
        decor = {
            { model = 'bzzz_money_crate_a', coords = vec4(248.90, -267.10, 68.30, 70.0) },
            { model = 'bzzz_money_crate_c', coords = vec4(245.10, -263.60, 68.30, 160.0) },
        },
    },
    ]]
}

Config.Fronts = {
    {
        id = 'laundromat',
        label = 'Laundromat',
        sub = 'Coin laundry · La Mesa',
        coords = vec3(889.45, -1031.61, 35.25), -- back office desk
        radius = 1.6,
        dailyCap = 120000,
        categories = {
            { key = 'machines', label = 'Self-service machines', share = 0.50 },
            { key = 'washfold', label = 'Wash & fold',           share = 0.30 },
            { key = 'dryclean', label = 'Dry cleaning',          share = 0.12 },
            { key = 'vending',  label = 'Vending & soap',        share = 0.08 },
        },
    },
    {
        id = 'unicorn',
        label = 'Vanilla Unicorn',
        sub = 'Adult entertainment · Strawberry',
        coords = vec3(95.30, -1293.90, 29.27),
        radius = 1.1,
        dailyCap = 160000,
        categories = {
            { key = 'door',    label = 'Door & cover',   share = 0.20 },
            { key = 'bar',     label = 'Bar sales',      share = 0.45 },
            { key = 'private', label = 'Private dances', share = 0.35 },
        },
    },
    {
        id = 'handson',
        label = 'Hands On Car Wash',
        sub = 'Car wash · Strawberry',
        coords = vec3(24.60, -1391.70, 29.33),
        radius = 1.3,
        dailyCap = 90000,
        categories = {
            { key = 'wash',    label = 'Exterior wash',  share = 0.55 },
            { key = 'detail',  label = 'Detailing',      share = 0.30 },
            { key = 'vending', label = 'Vending & air',  share = 0.15 },
        },
    },
}
