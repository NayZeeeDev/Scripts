-- ██████╗ ██████╗ ███████╗███████╗███████╗████████╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝██████╔╝█████╗  ███████╗█████╗     ██║   ███████╗
-- ██╔═══╝ ██╔══██╗██╔══╝  ╚════██║██╔══╝     ██║   ╚════██║
-- ██║     ██║  ██║███████╗███████║███████╗   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝

--[[
    Invoice presets (templates).

    society = 'cardealer'  -> seeded as that society's templates the first time it loads.
                              Managers then edit them in-game (Templates page): rename, recolour,
                              reorder (drag & drop), change prices, add or remove items.
    society = nil          -> global template everyone can use (personal invoices too). Read-only.

    icon:  any icon name from the UI picker (car, file, sparkle, wrench, medkit, badge, burger, ...)
    color: blue / red / amber / teal / cyan / violet / gray / rainbow
]]

Config.Presets = {
    -- ══════════ Global ══════════
    {
        name = 'Services', icon = 'briefcase', color = 'gray',
        items = {
            { label = 'Labour (1 hour)', amount = 150 },
            { label = 'Delivery', amount = 75 },
            { label = 'Consultation', amount = 200 },
        },
    },

    -- ══════════ Premium Deluxe Motorsport ══════════
    {
        society = 'cardealer', name = 'Vehicle Sales', icon = 'car', color = 'blue',
        items = {
            { label = 'New Vehicle', amount = 85000 },
            { label = 'Used Vehicle', amount = 32000 },
            { label = 'Performance Package', amount = 12000 },
            { label = 'Trade-in Adjustment', amount = 8500 },
        },
    },
    {
        society = 'cardealer', name = 'Paperwork & Fees', icon = 'file', color = 'teal',
        items = {
            { label = 'Registration', amount = 1500 },
            { label = 'Insurance (30 days)', amount = 3500 },
            { label = 'Down Payment', amount = 5000 },
        },
    },
    {
        society = 'cardealer', name = 'Extras & After-sales', icon = 'sparkle', color = 'violet',
        items = {
            { label = 'Custom Paint', amount = 2200 },
            { label = 'Window Tint', amount = 900 },
            { label = 'Detailing', amount = 400 },
        },
    },

    -- ══════════ Police ══════════
    {
        society = 'police', name = 'Traffic', icon = 'car', color = 'blue',
        items = {
            { label = 'Speeding', amount = 500 },
            { label = 'Running a Red Light', amount = 380 },
            { label = 'Reckless Driving', amount = 1000 },
            { label = 'Illegal Parking', amount = 200 },
            { label = 'DUI', amount = 5000 },
        },
    },
    {
        society = 'police', name = 'Citations', icon = 'badge', color = 'red',
        items = {
            { label = 'Public Disturbance', amount = 500 },
            { label = 'Trespassing', amount = 750 },
            { label = 'Impound Fee', amount = 500 },
        },
    },

    -- ══════════ EMS ══════════
    {
        society = 'ambulance', name = 'Medical', icon = 'medkit', color = 'red',
        items = {
            { label = 'Ambulance Ride', amount = 550 },
            { label = 'Hospital Admission', amount = 1200 },
            { label = 'Treatment', amount = 300 },
            { label = 'Surgery', amount = 3000 },
        },
    },

    -- ══════════ Mechanic ══════════
    {
        society = 'mechanic', name = 'Repairs', icon = 'wrench', color = 'amber',
        items = {
            { label = 'Engine Repair', amount = 800 },
            { label = 'Bodywork', amount = 520 },
            { label = 'Full Repair', amount = 1500 },
            { label = 'Tow', amount = 250 },
        },
    },

    -- ══════════ Burgershot ══════════
    {
        society = 'burgershot', name = 'Menu', icon = 'burger', color = 'amber',
        items = {
            { label = 'Bleeder Burger', amount = 8.99 },
            { label = 'Money Shot Burger', amount = 12.99 },
            { label = 'Fries', amount = 3.99 },
            { label = 'E-Cola', amount = 2.49 },
        },
    },
}
