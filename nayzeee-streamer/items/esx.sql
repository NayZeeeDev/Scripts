-- ESX Legacy without ox_inventory: run this once on your database.
-- With ox_inventory use items/ox_inventory.lua instead.
-- Weights use ESX units (Config.MaxWeight = 24 by default).

INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('streamer_laptop', 'Streaming Laptop', 2, 0, 1),
    ('streamer_tablet', 'Tablet', 1, 0, 1),
    ('stream_webcam', 'Webcam', 1, 0, 1),
    ('stream_camera_hd', 'HD Camera', 1, 0, 1),
    ('stream_camera_cinema', 'Cinema Camera', 4, 0, 1),
    ('stream_mic_headset', 'Headset', 1, 0, 1),
    ('stream_mic_usb', 'USB Mic', 1, 0, 1),
    ('stream_mic_studio', 'Studio Mic', 1, 0, 1),
    ('stream_tripod', 'Camera Tripod', 3, 0, 1),
    ('stream_ringlight', 'Ring Light', 3, 0, 1),
    ('spark_card_500', '500 Spark Card', 0, 0, 1),
    ('spark_card_2500', '2,500 Spark Card', 0, 0, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `weight` = VALUES(`weight`);
