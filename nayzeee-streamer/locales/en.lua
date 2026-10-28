Locales = Locales or {}

-- Error codes from the gateway and the Lua server. The same table is sent to the app as ui.errors.
local errors = {
    -- gateway
    unauthorized = 'This server is not connected to the network.',
    rate_limited = 'Slow down a little.',
    internal = 'Something went wrong. Try again.',
    bad_request = 'That did not work.',
    not_found = 'Not found.',
    forbidden = 'You are not allowed to do that.',
    no_account = 'Create your channel first.',
    banned = 'You are banned.',
    insufficient_sparks = 'Not enough Sparks.',
    insufficient_points = 'Not enough points.',
    offline = 'This channel is offline.',
    handle_taken = 'That handle is taken.',
    handle_invalid = 'Handles use 3 to 20 letters, numbers or _.',
    handle_cooldown = 'You changed your handle recently. Try again later.',
    bad_image_host = 'Images from that site are not allowed.',
    too_long = 'That is too long.',
    self = 'You can\'t do that on your own channel.',
    min_cheer = 'That is below the minimum cheer.',
    no_recipients = 'Nobody here can get a gift sub right now.',
    min_cashout = 'That is below the minimum cash out.',
    insufficient_earnings = 'Not enough earnings.',
    title_invalid = 'Add a stream title.',
    timeout = 'You are timed out in this chat.',
    slow = 'Slow mode is on. Wait a moment.',
    followers_only = 'Only followers can chat here.',
    subs_only = 'Only subscribers can chat here.',
    emote_only = 'Emote-only mode is on.',
    filtered = 'Your message was blocked.',
    links = 'Links are not allowed in this chat.',
    empty = 'Type a message first.',
    cooldown = 'That is on cooldown.',
    limit = 'Limit reached for this stream.',
    disabled = 'That is turned off.',
    target_offline = 'That channel is not live.',

    -- network state
    network = 'Pulse can\'t be reached right now. Try again soon.',
    not_configured = 'Network not configured. Ask staff to set the server key.',

    -- scenes and gear
    no_tripod = 'No tripod with a camera nearby.',
    no_camera = 'You need a camera.',
    too_far = 'You are too far away.',
    no_laptop = 'You need a laptop nearby.',
    need_tier = 'This needs a better camera.',
    scene_disabled = 'That scene is turned off on this server.',
    no_device = 'You need a laptop or tablet.',
    no_item = 'You don\'t have that item.',
    invalid_item = 'Unknown item.',
    gear_limit = 'You have placed the most gear you can.',
    not_owner = 'That is not yours.',
    occupied = 'Someone is using that.',

    -- streams
    not_live = 'You are not live.',
    already_live = 'You are already live.',

    -- money and shop
    no_money = 'Not enough money.',
    cant_carry = 'You can\'t carry that.',
    invalid_amount = 'Enter a valid amount.',
    cashout_disabled = 'Cash out is turned off on this server.',
    daily_limit = 'You reached today\'s cash out limit.',
    shop_closed = 'This shop is closed.',

    -- other
    busy = 'Busy. Try again in a moment.',
    unknown = 'Something went wrong.',
}

Locales['en'] = {
    -- general
    app_name = 'Pulse',
    notify_title = 'Pulse',

    -- going live and watching
    went_live = '%s is live: %s',
    went_live_title = 'Live now',
    stream_started = 'You are live.',
    stream_ended = 'Your stream ended.',
    stream_force_ended = 'Your stream ended: %s',
    stream_reconnecting = 'Connection lost. Reconnecting.',
    stream_error = 'The stream stopped: %s',
    points_earned = '+%s %s',
    privacy_on = 'Be right back card is on.',
    privacy_off = 'Be right back card is off.',
    muted = 'Mic muted.',
    unmuted = 'Mic on.',
    scene_changed = 'Scene: %s',
    mic_active = 'Mic: %s',
    mic_builtin = 'No mic item. Using the built-in mic.',
    mic_hold = 'Mic in hand.',
    mic_away = 'Mic put away.',
    camera_hold = 'Holding the %s. Use it again to put it away.',
    camera_away = 'Camera put away.',
    network_down = 'Pulse can\'t be reached right now.',
    network_not_configured = 'Network not configured.',

    end_reasons = {
        stale = 'connection lost',
        disconnect = 'you left the server',
        admin = 'ended by staff',
        replaced = 'you went live again',
        banned = 'your channel is banned',
        user = 'you ended it',
        unknown = 'unknown reason',
    },

    -- devices
    need_device = 'You need a laptop or tablet to open Pulse.',
    open_phone = 'Open Pulse on your phone.',

    -- money
    sparks_added = '+%s Sparks',
    sparks_bought = 'Bought %s Sparks for %s.',
    card_redeemed = 'Redeemed a card for %s Sparks.',
    cashout_done = 'Cashed out %s.',
    bought = 'Bought %sx %s for %s.',

    -- gear
    gear_placed = 'Placed.',
    gear_picked_up = 'Picked up.',
    gear_saved = 'Saved.',
    camera_mounted = '%s mounted.',
    camera_unmounted = 'Camera removed.',
    light_on = 'Light on.',
    light_off = 'Light off.',

    -- placement
    place_hint = '[Scroll] Rotate   [E] Place   [Backspace] Cancel',
    place_label = 'Placing %s',
    place_invalid = 'You can\'t place that here.',
    place_too_far = 'Too far away.',

    -- target labels
    target = {
        adjust_light = 'Adjust light',
        toggle_light = 'Turn on or off',
        adjust_tripod = 'Adjust camera',
        mount_camera = 'Mount camera',
        unmount_camera = 'Remove camera',
        stream_tripod = 'Stream from this camera',
        use_laptop = 'Use laptop',
        pick_up = 'Pick up',
        shop = 'Browse electronics',
        tune_tv = 'Watch a stream',
        tv_off = 'Turn off the TV',
    },

    -- commands and key bindings
    commands = {
        pulse = 'Open Pulse',
        pulse_arg = 'laptop, tablet or phone',
        admin = 'Open the Pulse staff panel',
        key_deck = 'Pulse: stream deck',
        key_chat = 'Pulse: chat',
        key_privacy = 'Pulse: be right back card',
        key_scene = 'Pulse: next scene',
    },

    -- console
    console = {
        ready = 'Connected to the network as %s.',
        no_key = 'No server key. Add set %s "pk_..." to server.cfg (set, not setr).',
        no_url = 'No gateway URL. Set Config.Network.Url or the pulse_api_url convar.',
        unreachable = 'Gateway unreachable (%s). Retrying.',
        framework = 'Framework: %s',
        no_framework = 'No supported framework found. Running in standalone mode (license identity, no money).',
        inventory = 'Inventory: %s',
        missing_item = 'Item "%s" is missing from %s. Add it from the items/ folder.',
        custom_inventory = 'Config.Inventory is "custom" but bridge/inventory/custom.lua has no %s function.',
        target = 'Target: %s',
        notify = 'Notify: %s',
    },

    -- item labels (used in the app and the shop)
    items = {
        streamer_laptop = 'Streaming Laptop',
        streamer_tablet = 'Tablet',
        stream_webcam = 'Webcam',
        stream_camera_hd = 'HD Camera',
        stream_camera_cinema = 'Cinema Camera',
        stream_mic_headset = 'Headset',
        stream_mic_usb = 'USB Mic',
        stream_mic_studio = 'Studio Mic',
        stream_tripod = 'Camera Tripod',
        stream_ringlight = 'Ring Light',
        spark_card_500 = '500 Spark Card',
        spark_card_2500 = '2,500 Spark Card',
    },

    scenes = {
        gameplay = 'Gameplay',
        tripod = 'Tripod',
        handheld = 'Handheld',
        phone = 'Phone',
        orbit = 'Orbit',
    },

    errors = errors,

    -- Strings for the app (NUI). Generated from the t('area.key', 'English') calls in html/js.
    -- Anything missing here falls back to the English text in the JS.
    ui = {
        errors = errors,
    },
}
