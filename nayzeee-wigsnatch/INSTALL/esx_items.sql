-- Only for ESX WITHOUT ox_inventory. The default ESX inventory has no metadata,
-- so wigs there are generic (no tiers, styles or wearing). ox_inventory is strongly recommended.
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('wig', 'Wig', 1, 0, 1),
    ('wig_glue', 'Lace Glue', 1, 0, 1),
    ('wig_kit', 'Wig Kit', 1, 0, 1),
    ('hair_clippers', 'Hair Clippers', 1, 0, 1),
    ('scissors', 'Scissors', 1, 0, 1);
