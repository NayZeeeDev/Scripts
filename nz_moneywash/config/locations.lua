--[[
    THE WASH — locations

    OPERATIONS  : fixed machine layouts. `access` empty = anyone can use them.
                  coords are the prop's ground pivot (vec4 with heading).
    FRONTS      : legit-looking businesses where washed stacks are "declared" (Cook the Books).
                  Every front has a plausible revenue mix + a daily cap. Stray from it and the
                  Treasury starts asking questions.

    The demo operation sits on the Alta rooftop the prop author used for testing
    (bzzz test ymap coords). Move it anywhere — interiors work great.
]]

Config.Operations = {
    {
        id     = 'alta_roof',
        label  = 'Alta Rooftop Plant',
        blip   = false, -- { sprite = 500, colour = 2, scale = 0.7 }
        access = {
            -- jobs  = { vagos = 0 },
            -- gangs = { ballas = 0 },
            -- items = { 'nzmw_keycard' },
        },
        stations = {
            { type = 'washer',  coords = vec4(240.20, -271.60, 68.30, 160.0) },
            { type = 'washer',  coords = vec4(239.35, -271.29, 68.30, 160.0) }, -- 0.9m along the first washer's right axis
            { type = 'printer', coords = vec4(246.40, -268.40, 68.30, 160.0) },
            { type = 'cutter',  coords = vec4(243.20, -264.40, 68.30, 160.0) },
        },
        decor = {
            { model = 'bzzz_money_crate_a', coords = vec4(248.90, -267.10, 68.30, 70.0) },
            { model = 'bzzz_money_crate_c', coords = vec4(245.10, -263.60, 68.30, 160.0) },
            { model = 'bzzz_money_crate_b', coords = vec4(238.70, -269.40, 68.30, 70.0) },
        },
        -- optional teleport (e.g. into an interior)
        -- entrance = { outside = vec4(0,0,0,0), inside = vec4(0,0,0,0) },
    },
}

Config.Fronts = {
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
