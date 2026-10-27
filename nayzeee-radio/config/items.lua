--[[
    NAYZEEE RADIO - Items

    Config.Items maps the key the script uses → the item name in your inventory.
    Rename an item here if your server already has it under another name
    (e.g. Config.Items.handheld = 'walkie'). Never edit the keys.

    Config.ItemDefs is used to build the install files in install/
    (ox_inventory, qb-core shared items, ESX SQL). Images are in html/img/items/.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Items = {
    -- radios (each one is a different model, see config/modules/radios.lua)
    handheld = 'radio',
    fieldpro = 'radio_fieldpro',
    military = 'radio_military',
    earpiece = 'radio_earpiece',     -- people next to you no longer hear your radio

    -- jammers (see config/modules/jammers.lua)
    pocket   = 'jammer_pocket',
    case     = 'jammer_case',
    heavy    = 'jammer_heavy',
}

Config.ItemDefs = {
    handheld = { label = 'Patrol Radio',     weight = 350,  stack = false, description = 'PX-740 patrol handheld. Three channels, covers most of a city.' },
    fieldpro = { label = 'Field Pro Radio',  weight = 300,  stack = false, description = 'FX-280 compact field set. Four channels, waterproof, reaches further.' },
    military = { label = 'Tactical Radio',   weight = 650,  stack = false, description = 'MX-905 rugged tactical set. Five channels, the longest reach, hard to jam.' },
    earpiece = { label = 'Radio Earpiece',   weight = 30,   stack = true,  description = 'Coiled earpiece. Keeps your radio traffic to yourself.' },
    pocket   = { label = 'Pocket Jammer',    weight = 600,  stack = true,  description = 'JX-10. Fills radios close by with noise.' },
    case     = { label = 'Field Jammer',     weight = 6500, stack = true,  description = 'JX-40 in a hard case. Reaches about a city block.' },
    heavy    = { label = 'Cabinet Jammer',   weight = 28000, stack = true, description = 'JX-90 cabinet with an aerial mast. Shuts down radios across a whole area.' },
}
