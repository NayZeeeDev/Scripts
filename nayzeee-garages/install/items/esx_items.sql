-- nayzeee-garages — items for the default ESX inventory (table `items`).
-- The default ESX inventory cannot store item metadata: the car lock uses virtual keys there,
-- so vehicle_key / vehicle_fob are only listed for completeness (a metadata inventory such as
-- ox_inventory uses install/items/ox_inventory.lua instead). Tools, fake plates and contracts
-- work without metadata. Item names must match Config.CarLock.items (config/carlock.lua).

INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
  ('vehicle_key', 'Vehicle key', 1, 0, 1),
  ('vehicle_fob', 'Key fob', 1, 0, 1),
  ('key_blank', 'Key blank', 1, 0, 1),
  ('lockpick', 'Lockpick', 1, 0, 1),
  ('advancedlockpick', 'Advanced lockpick', 1, 0, 1),
  ('screwdriver', 'Flathead screwdriver', 1, 0, 1),
  ('hacking_device', 'Hacking device', 1, 0, 1),
  ('fake_plate', 'Fake plate', 1, 0, 1),
  ('vehicle_contract', 'Vehicle sale contract', 1, 0, 1),
  ('signed_contract', 'Signed sale contract', 1, 0, 1),
  ('immobiliser', 'Immobiliser', 1, 0, 1),
  ('ghost_immobiliser', 'Ghost immobiliser', 1, 0, 1),
  ('hotwire_kit', 'Hotwire kit', 1, 0, 1),
  ('signal_reader', 'Signal reader', 1, 0, 1);
