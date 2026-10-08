--[[
    Fence: sell heist loot at any employer with `fence = true`.
    Prices are per unit, paid in the account below. A random spread keeps the market moving.
]]

return {
    enabled = true,
    account = 'cash',     -- 'cash' | 'bank' | 'black_money' | 'markedbills'
    spread = 0.10,        -- +/- 10% daily price variation
    items = {
        { name = 'gold_bar',      label = 'Gold Bar',        price = 2500 },
        { name = 'diamond',       label = 'Loose Diamond',   price = 1800 },
        { name = 'rolex',         label = 'Luxury Watch',    price = 650 },
        { name = 'gold_chain',    label = 'Gold Chain',      price = 300 },
        { name = 'diamond_ring',  label = 'Diamond Ring',    price = 900 },
        { name = 'necklace',      label = 'Necklace',        price = 500 },
        { name = 'painting',      label = 'Painting',        price = 6000 },
        { name = 'electronics',   label = 'Electronics',     price = 220 },
        { name = 'laptop',        label = 'Laptop',          price = 700 },
        { name = 'coke_brick',    label = 'Cocaine Brick',   price = 3200 },
        { name = 'weed_brick',    label = 'Weed Brick',      price = 1100 },
        { name = 'weapon_parts',  label = 'Weapon Parts',    price = 850 },
        { name = 'data_drive',    label = 'Encrypted Drive', price = 2400 },
        { name = 'cargo_crate',   label = 'Sealed Cargo',    price = 4000 },
    },
}
