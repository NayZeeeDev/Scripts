--[[
    ox_inventory (also Qbox): paste these into ox_inventory/data/items.lua, inside the main table.
    Item images go in ox_inventory/web/images/ with the same names (streamer_laptop.png, ...).

    Every item uses the client export, so do not register them anywhere else.
    consume = 0: the script removes spark cards itself when they are redeemed.

    Copy the entries between "return {" and the last "}".
]]

return {
    ['streamer_laptop'] = {
        label = 'Streaming Laptop',
        weight = 2200,
        stack = false,
        close = true,
        consume = 0,
        description = 'Opens Pulse. Watch streams or go live. Can be set down on a table.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['streamer_tablet'] = {
        label = 'Tablet',
        weight = 650,
        stack = false,
        close = true,
        consume = 0,
        description = 'Opens Pulse to watch streams and manage your channel.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_webcam'] = {
        label = 'Webcam',
        weight = 150,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 1 camera. 480p at 24 fps.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_camera_hd'] = {
        label = 'HD Camera',
        weight = 900,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 2 camera. 720p at 30 fps with a clean picture.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_camera_cinema'] = {
        label = 'Cinema Camera',
        weight = 4500,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 3 camera. 1080p at 30 fps with depth of field. Unlocks the Orbit scene.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_mic_headset'] = {
        label = 'Headset',
        weight = 300,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 1 mic. Clearer than the built-in mic.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_mic_usb'] = {
        label = 'USB Mic',
        weight = 450,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 2 mic. Wide range with a compressor.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_mic_studio'] = {
        label = 'Studio Mic',
        weight = 600,
        stack = false,
        close = true,
        consume = 0,
        description = 'Tier 3 mic. Full range, broadcast sound.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_tripod'] = {
        label = 'Camera Tripod',
        weight = 3500,
        stack = false,
        close = true,
        consume = 0,
        description = 'Place it, mount a camera and stream from it.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['stream_ringlight'] = {
        label = 'Ring Light',
        weight = 2800,
        stack = false,
        close = true,
        consume = 0,
        description = 'Place it to light your stream. Brightness and colour can be adjusted.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['spark_card_500'] = {
        label = '500 Spark Card',
        weight = 10,
        stack = true,
        close = true,
        consume = 0,
        description = 'Redeem for 500 Sparks on Pulse.',
        client = { export = 'nayzeee-streamer.useItem' },
    },

    ['spark_card_2500'] = {
        label = '2,500 Spark Card',
        weight = 10,
        stack = true,
        close = true,
        consume = 0,
        description = 'Redeem for 2,500 Sparks on Pulse.',
        client = { export = 'nayzeee-streamer.useItem' },
    },
}
