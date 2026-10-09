--[[
    Shoe catalogue.

    Each model lists its colourways by the clothing texture letter they come from
    (a = texture 0, b = 1 ...). Every colourway becomes its own shoe id: <model>_<letter>,
    e.g. fang5_c, with the prop nzs_fang5_c and the icons nzs_fang5_c.png / _box.png.

    drawable   the feet drawable id of that shoe on YOUR server. Addon clothing ids depend on
               your clothing pack's order - find it in your clothing menu (Shoes) and put it here.
               Until it's set, the shoes can be boxed and inspected but not worn.
    gender     'male' | 'female'. Check these match your clothing pack.
    box        'shoe' | 'heel' | 'boot' (Config.BoxTypes)
    retail     reference price for the selling phase

    Names are deliberately generic (no real brands). Rename anything you like.
]]

Config.ShoeModels = {
    cup = {
        label = 'Cup Runner', gender = 'male', box = 'shoe', retail = 950,
        drawable = nil,   -- feet_000_u: use clothing/cup_runner from the debranded clothing pack
        colourways = {
            a = 'Black',
            b = 'Mint',
            c = 'Lime',
            d = 'Pink',
            e = 'Blue',
        },
    },
    fang5 = {
        label = 'Fang 5', gender = 'male', box = 'shoe', retail = 420,
        drawable = nil,   -- feet_003_u: use clothing/fang_5 from the debranded clothing pack
        colourways = {
            a = 'Maroon',
            b = 'Silver',
            c = 'Navy',
            d = 'Silver 2',
            e = 'Silver 3',
            f = 'Black',
            g = 'Navy 2',
            h = 'Black / Navy',
            i = 'Silver 4',
            j = 'Silver 5',
            k = 'Silver 6',
            l = 'Black 2',
            m = 'Navy / Charcoal',
            n = 'Grey',
            o = 'Black 3',
        },
    },
    court = {
        label = 'Backcourt Low', gender = 'male', box = 'shoe', retail = 1100,
        drawable = nil,   -- feet_004_u: use clothing/backcourt_low from the debranded clothing pack
        colourways = {
            a = 'Black / Charcoal',
            b = 'Olive / Grey',
            c = 'Black',
        },
    },
    stack = {
        label = 'Stack Trainer', gender = 'male', box = 'shoe', retail = 980,
        drawable = nil,   -- feet_023_u: use clothing/stack_trainer from the debranded clothing pack
        colourways = {
            a = 'Black',
            b = 'Grey',
        },
    },
    crevis = {
        label = 'Crevis 95', gender = 'male', box = 'shoe', retail = 260,
        drawable = nil,   -- crevis sneaker by jazlyn13 - feet_003_u
        colourways = {
            a = 'Tan',
            b = 'Brown',
            c = 'Purple',
            d = 'Purple 2',
            e = 'Blue',
            f = 'Olive',
            g = 'Green / Charcoal',
            h = 'Green',
            i = 'Grey',
        },
    },
    alice = {
        label = 'Alice Western Boot', gender = 'female', box = 'boot', retail = 540,
        drawable = nil,   -- STRUT Alice Shoes - feet_000_u
        colourways = {
            a = 'Cream',
            b = 'Black',
            c = 'White',
            d = 'Charcoal',
            e = 'Cream 2',
            f = 'Black / Maroon',
            g = 'Cream 3',
            h = 'Maroon',
            i = 'Beige / Tan',
            j = 'Gold',
            k = 'Pink',
            l = 'Red / Maroon',
            m = 'Cream 4',
            n = 'Charcoal / Mocha',
            o = 'Grey / Sky Blue',
            p = 'Charcoal 2',
            q = 'Mint',
            r = 'Orange',
            s = 'Silver',
            t = 'Silver 2',
            u = 'Cream 5',
            v = 'Beige',
            w = 'Cream 6',
            x = 'Beige / Tan 2',
            y = 'Beige / Tan 3',
            z = 'Green',
        },
    },
    bianca = {
        label = 'Bianca Heel', gender = 'female', box = 'heel', retail = 480,
        drawable = nil,   -- STRUT Bianca Shoes - feet_002_r
        colourways = {
            a = 'Teal',
            b = 'White',
            c = 'Black',
            d = 'Mocha',
            e = 'Green',
            f = 'Yellow',
            g = 'Yellow 2',
            h = 'Hot Pink',
            i = 'Red / Hot Pink',
            j = 'Hot Pink 2',
            k = 'Lilac',
            l = 'Pink / Tan',
            m = 'Grey',
            n = 'Blue',
            o = 'Silver',
            p = 'Green 2',
            q = 'Brown / Red',
            r = 'Hot Pink 3',
        },
    },
    maisie = {
        label = 'Maisie Slingback', gender = 'female', box = 'heel', retail = 420,
        drawable = nil,   -- STRUT Maisie Shoes - feet_014_r
        colourways = {
            a = 'Black',
            b = 'Silver',
            c = 'Maroon',
            d = 'Pink',
            e = 'Orange',
            f = 'Silver 2',
            g = 'Black 2',
            h = 'Beige / Lilac',
            i = 'Silver 3',
            j = 'Lilac',
            k = 'Navy',
            l = 'Green',
            m = 'Black 3',
            n = 'Black 4',
            o = 'Black 5',
            p = 'Black 6',
        },
    },
    omnia = {
        label = 'Omnia Ankle Boot', gender = 'female', box = 'heel', retail = 460,
        drawable = nil,   -- STRUT Omnia Shoes - feet_014_u
        colourways = {
            a = 'Maroon / Red',
            b = 'Brown',
            c = 'Silver',
            d = 'Purple',
            e = 'Black',
            f = 'Navy',
            g = 'Maroon',
            h = 'Mocha',
            i = 'Gold',
        },
    },
    mia = {
        label = 'Mia Knee Boot', gender = 'female', box = 'boot', retail = 520,
        drawable = nil,   -- [WM] Mia Colucci Boots - feet_000_u
        colourways = {
            a = 'Hot Pink',
            b = 'Lime',
            c = 'Purple',
            d = 'Blue / Teal',
        },
    },
}

-- Expand every colourway into Config.Shoes[<model>_<letter>]
Config.Shoes = {}
for modelId, m in pairs(Config.ShoeModels) do
    for letter, colour in pairs(m.colourways) do
        local id = ('%s_%s'):format(modelId, letter)
        local prop = ('nzs_%s_%s'):format(modelId, letter)
        Config.Shoes[id] = {
            model = modelId,
            label = m.label,
            colourway = colour,
            gender = m.gender,
            box = m.box,
            retail = m.retail,
            prop = GetHashKey(prop),
            image = prop,
            clothing = m.drawable and { drawable = m.drawable, texture = letter:byte() - 97 } or nil,
        }
    end
end

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
