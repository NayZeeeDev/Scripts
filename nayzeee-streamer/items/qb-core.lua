--[[
    QBCore (qb-inventory, ps-inventory, lj-inventory): paste these into qb-core/shared/items.lua,
    inside QBShared.Items. Images go in your inventory's html/images/ folder with the same names.
    Qbox uses ox_inventory, see items/ox_inventory.lua instead.

    Copy the lines between "return {" and the last "}".
]]

return {
    streamer_laptop = { name = 'streamer_laptop', label = 'Streaming Laptop', weight = 2200, type = 'item', image = 'streamer_laptop.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Opens Pulse. Watch streams or go live. Can be set down on a table.' },
    streamer_tablet = { name = 'streamer_tablet', label = 'Tablet', weight = 650, type = 'item', image = 'streamer_tablet.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Opens Pulse to watch streams and manage your channel.' },
    stream_webcam = { name = 'stream_webcam', label = 'Webcam', weight = 150, type = 'item', image = 'stream_webcam.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 1 camera. 480p at 24 fps.' },
    stream_camera_hd = { name = 'stream_camera_hd', label = 'HD Camera', weight = 900, type = 'item', image = 'stream_camera_hd.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 2 camera. 720p at 30 fps with a clean picture.' },
    stream_camera_cinema = { name = 'stream_camera_cinema', label = 'Cinema Camera', weight = 4500, type = 'item', image = 'stream_camera_cinema.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 3 camera. 1080p at 30 fps with depth of field. Unlocks the Orbit scene.' },
    stream_mic_headset = { name = 'stream_mic_headset', label = 'Headset', weight = 300, type = 'item', image = 'stream_mic_headset.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 1 mic. Clearer than the built-in mic.' },
    stream_mic_usb = { name = 'stream_mic_usb', label = 'USB Mic', weight = 450, type = 'item', image = 'stream_mic_usb.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 2 mic. Wide range with a compressor.' },
    stream_mic_studio = { name = 'stream_mic_studio', label = 'Studio Mic', weight = 600, type = 'item', image = 'stream_mic_studio.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Tier 3 mic. Full range, broadcast sound.' },
    stream_tripod = { name = 'stream_tripod', label = 'Camera Tripod', weight = 3500, type = 'item', image = 'stream_tripod.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Place it, mount a camera and stream from it.' },
    stream_ringlight = { name = 'stream_ringlight', label = 'Ring Light', weight = 2800, type = 'item', image = 'stream_ringlight.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Place it to light your stream. Brightness and colour can be adjusted.' },
    spark_card_500 = { name = 'spark_card_500', label = '500 Spark Card', weight = 10, type = 'item', image = 'spark_card_500.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Redeem for 500 Sparks on Pulse.' },
    spark_card_2500 = { name = 'spark_card_2500', label = '2,500 Spark Card', weight = 10, type = 'item', image = 'spark_card_2500.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Redeem for 2,500 Sparks on Pulse.' },
}
