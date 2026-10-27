-- NAYZEEE RADIO - ESX items
-- Built from config/items.lua. If you rename an item there, rename it here too.
-- Weights are in kg (minimum 1) (gram based servers: take the gram weights from install/ox_inventory_items.lua).
-- Not needed with ox_inventory (use install/ox_inventory_items.lua instead).

INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('radio', 'Patrol Radio', 1, 0, 1),
    ('radio_fieldpro', 'Field Pro Radio', 1, 0, 1),
    ('radio_military', 'Tactical Radio', 1, 0, 1),
    ('radio_earpiece', 'Radio Earpiece', 1, 0, 1),
    ('jammer_pocket', 'Pocket Jammer', 1, 0, 1),
    ('jammer_case', 'Field Jammer', 7, 0, 1),
    ('jammer_heavy', 'Heavy Jammer', 28, 0, 1);
