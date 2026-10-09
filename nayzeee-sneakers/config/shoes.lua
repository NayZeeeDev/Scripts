--[[
    Shoe catalogue. One entry per colourway.

    prop      the boxed-pair prop in stream/ (used in the box, when floating and when inspecting)
    image     inventory icon (install/images/<image>.png and <image>_box.png)
    gender    'male' | 'female' | 'unisex'
    clothing  the feet component players get when they put them on.
              drawable = the feet drawable id of the shoe on YOUR server (addon clothing ids depend on
              your clothing pack's order, check it in your clothing menu). texture = the colourway.
              For unisex shoes give male = {...} and female = {...} instead.
    retail    reference price, used by the selling phase
]]

Config.Shoes = {
    cups_black = {
        label = 'Prada Cup', colourway = 'Black', gender = 'male',
        prop = `nzs_cups_black`, image = 'nzs_cups_black',
        clothing = { drawable = nil, texture = 0 },     -- feet_diff_000_a
        retail = 950,
    },
    cups_mint = {
        label = 'Prada Cup', colourway = 'Mint', gender = 'male',
        prop = `nzs_cups_mint`, image = 'nzs_cups_mint',
        clothing = { drawable = nil, texture = 1 },     -- feet_diff_000_b
        retail = 950,
    },
    cups_lime = {
        label = 'Prada Cup', colourway = 'Lime', gender = 'male',
        prop = `nzs_cups_lime`, image = 'nzs_cups_lime',
        clothing = { drawable = nil, texture = 2 },     -- feet_diff_000_c
        retail = 950,
    },
    cups_pink = {
        label = 'Prada Cup', colourway = 'Pink', gender = 'male',
        prop = `nzs_cups_pink`, image = 'nzs_cups_pink',
        clothing = { drawable = nil, texture = 3 },     -- feet_diff_000_d
        retail = 950,
    },
    cups_blue = {
        label = 'Prada Cup', colourway = 'Blue', gender = 'male',
        prop = `nzs_cups_blue`, image = 'nzs_cups_blue',
        clothing = { drawable = nil, texture = 4 },     -- feet_diff_000_e
        retail = 950,
    },
}

Config.Sizes = {
    male = { '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5', '11', '11.5', '12', '13' },
    female = { '5', '5.5', '6', '6.5', '7', '7.5', '8', '8.5', '9', '10' },
}

-- Condition grades, best first
Config.Conditions = {
    { id = 'DS', label = 'Deadstock' },
    { id = 'VNDS', label = 'Very near deadstock' },
    { id = 'USED', label = 'Used' },
    { id = 'BEAT', label = 'Beat' },
}
