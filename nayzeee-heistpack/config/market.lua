--[[
    Black market (tablet "Market" tab). Orders are delivered by drone.
    Prices are validated server-side - clients only send item names + amounts.
]]

return {
    enabled = true,
    delivery = {
        seconds = 45,          -- 0 = instant (straight to inventory)
        droneModel = 'ch_prop_casino_drone_02a',
        bagModel = 'xm_prop_x17_bag_01a',
        blip = { sprite = 627, color = 27, scale = 0.8, label = 'Market Delivery' },
        -- undelivered orders are kept until the player collects them (even after reconnecting)
    },
    maxPerItem = 10,
    categories = {
        { id = 'tools',      label = 'Tools' },
        { id = 'electronics', label = 'Electronics' },
        { id = 'explosives', label = 'Explosives' },
        { id = 'gear',       label = 'Gear' },
    },
    items = {
        { name = 'lockpick',         label = 'Advanced Lockpick', price = 600,   category = 'tools',       level = 1, used = 'Store, House, Boosting' },
        { name = 'heist_drill',      label = 'Heavy Drill',       price = 9500,  category = 'tools',       level = 2, used = 'Fleeca, ATM, Vangelico' },
        { name = 'angle_grinder',    label = 'Angle Grinder',     price = 4500,  category = 'tools',       level = 2, used = 'Ammunation, Barn Raid' },
        { name = 'heavy_rope',       label = 'Tow Rope',          price = 800,   category = 'tools',       level = 1, used = 'ATM' },
        { name = 'hacking_device',   label = 'Hacking Device',    price = 2500,  category = 'electronics', level = 1, used = 'ATM, House, Grid Hack' },
        { name = 'safepad',          label = 'SafePad',           price = 6000,  category = 'electronics', level = 2, used = 'Fleeca, Paleto, Pacific' },
        { name = 'heist_laptop',     label = 'Encrypted Laptop',  price = 12000, category = 'electronics', level = 4, used = 'Pacific, Cartel, Convoy' },
        { name = 'gps_jammer',       label = 'GPS Jammer',        price = 3500,  category = 'electronics', level = 2, used = 'Boosting, Vehicle Theft' },
        { name = 'heist_drone',      label = 'Recon Drone',       price = 15000, category = 'electronics', level = 3, used = 'Vangelico, Pacific' },
        { name = 'thermite',         label = 'Thermite Charge',   price = 3000,  category = 'explosives',  level = 2, used = 'Paleto, Pacific, Train' },
        { name = 'c4_charge',        label = 'C4 Charge',         price = 7500,  category = 'explosives',  level = 3, used = 'Bobcat, Money Truck, Convoy, ATM' },
        { name = 'gasmask',          label = 'Gas Mask',          price = 1500,  category = 'gear',        level = 2, used = 'Vangelico' },
        { name = 'heist_bag',        label = 'Duffel Bag',        price = 500,   category = 'gear',        level = 1, used = 'All heists (cosmetic)' },
    },
}
