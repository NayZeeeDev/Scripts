--[[
    NAYZEEE RADIO - English strings: the world around the radio (client)

    Keys: world.*   client/modules/vehicle.lua (head unit, passenger HUD), jammers.lua
                    (placing, pick up / hack, owner notices), alerts.lua (emergency blip,
                    /radiorange), admin.lua (/radioadmin)
    The head unit screen itself uses the client.scr_* lines (locales/en/client.lua).
    Translate by copying this file to locales/<lang>/world.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── toast titles
    ['world.title_radio']           = 'Radio',
    ['world.title_jammer']          = 'Jammer',
    ['world.title_admin']           = 'Radio control',

    -- ── placing a jammer (key card at the top left while the ghost is out)
    ['world.place_title']           = '%s · %s',
    ['world.place_hint_set']        = 'Set it down',
    ['world.place_hint_turn']       = 'Turn',
    ['world.place_hint_fine']       = 'Slow turn',
    ['world.place_hint_cancel']     = 'Put it away',
    ['world.place_ok']              = 'Good spot',
    ['world.place_aim']             = 'Look at the ground in front of you',
    ['world.place_far']             = 'Closer to you',
    ['world.place_steep']           = 'Too steep here',
    ['world.place_water']           = 'Not in the water',
    ['world.place_surface']         = 'It will not stay on that',
    ['world.place_vehicle']         = 'Get out of the vehicle first',
    ['world.place_nomodel']         = 'The jammer model is not loaded. Ask an admin to start nayzeee-radio-props.',
    ['world.place_busy']            = 'Finish what you are doing first',

    -- ── on a placed jammer (third eye, or the [E] prompt without a target script)
    ['world.target_pickup']         = 'Pick up',
    ['world.target_hack']           = 'Hack',

    -- ── the hack (the minigame window has its own wording)
    ['world.hack_title']            = '%s · %s',
    ['world.hack_far']              = 'You moved away from the jammer',
    ['world.hack_gone']             = 'That jammer is no longer there',
    ['world.hack_busy']             = 'Someone else is already working on it',
    ['world.hack_denied']           = 'You would not know where to start with this one',
    ['world.hack_lockout']          = 'Give it %d s before you try again',
    ['world.hack_error']            = 'The jammer did not respond',
    ['world.hacked_owner']          = 'Your %s went quiet. Someone got into it.',

    -- ── emergency (blip on the map; the alert card is the NUI's own)
    ['world.blip_emergency']        = 'Emergency · %s',
    ['world.alert_unknown']         = 'Unknown caller',
    ['world.key_alertroute']        = 'Radio: route to the last emergency',

    -- ── /radiorange
    ['world.cmd_range']             = 'Show on the map how far your radio reaches from here',
    ['world.range_info']            = '%s: clear up to %.1f km, fades out by %.1f km from here',
    ['world.range_none']            = 'You have no radio to measure',
    ['world.range_blip']            = 'Radio reach',

    -- ── /radioadmin
    ['world.cmd_admin']             = 'Channel locks, radio cars, live channels and jammers',
    ['world.admin_denied']          = 'You are not allowed to change the radio setup',
    ['world.admin_busy']            = 'One moment, the server is still busy',
    ['world.admin_error']           = 'The server did not answer',
})
