--[[
    NAYZEEE RADIO - English strings: client core (client)

    Keys: client.*   client/core/state.lua (keys, commands, toasts), client/modules/firmware.lua
                     (everything written on the radio screens: client.scr_*), interact.lua (key
                     mappings, overlay hints), held.lua (/radiogrip)
    The scr_* lines appear on the radio's own small screen: keep them short and in capitals
    where they are capitals here (the screens are a few centimetres wide).
    Translate by copying this file to locales/<lang>/client.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── general / toasts
    ['client.title']                = 'Radio',
    ['client.no_radio']             = 'You have no radio on you',
    ['client.not_in_vehicle']       = 'Get out of the vehicle to use the handheld',
    ['client.raise_water']          = 'This radio is not waterproof',
    ['client.raise_cuffed']         = 'Not with your hands cuffed',
    ['client.raise_unavailable']    = 'The radio models are not loaded. Ask an admin to start nayzeee-radio-props.',
    ['client.callsign_set']         = 'Callsign set to %s',
    ['client.callsign_cleared']     = 'Callsign cleared',
    ['client.callsign_failed']      = 'That callsign was not accepted',
    ['client.callsign_off']         = 'Callsigns are turned off on this server',
    ['client.emergency_hold']       = 'Emergency alert',
    ['client.grip_debug']           = 'Grip tuning is for admins, or for everyone while Config.Debug is on',
    ['client.grip_usage']           = 'Use /%s x y z rx ry rz',
    ['client.grip_printed']         = 'Grip line printed to the F8 console',

    -- ── commands (chat suggestions)
    ['client.cmd_radio']            = 'Raise or lower your radio',
    ['client.cmd_callsign']         = 'Set the callsign shown next to your name on the radio',
    ['client.cmd_callsign_param']   = 'Up to %d characters, empty to clear',
    ['client.cmd_grip']             = 'Tune how the radio sits in your hand',

    -- ── key bindings (Settings > Key Bindings > FiveM)
    ['client.key_ptt']              = 'Radio: hold to talk',
    ['client.key_raise']            = 'Radio: raise / lower (head unit in a radio car)',
    ['client.key_handsfree']        = 'Radio: hands-free mic on / off',
    ['client.key_mute']             = 'Radio: mute / unmute',
    ['client.key_nextslot']         = 'Radio: talk on the next channel slot',
    ['client.key_roster']           = 'Radio: show / hide who is on the channel',
    ['client.key_emergency']        = 'Radio: hold for the emergency alert',
    ['client.key_pad_k0']           = 'Radio keypad: 0',
    ['client.key_pad_k1']           = 'Radio keypad: 1',
    ['client.key_pad_k2']           = 'Radio keypad: 2',
    ['client.key_pad_k3']           = 'Radio keypad: 3',
    ['client.key_pad_k4']           = 'Radio keypad: 4',
    ['client.key_pad_k5']           = 'Radio keypad: 5',
    ['client.key_pad_k6']           = 'Radio keypad: 6',
    ['client.key_pad_k7']           = 'Radio keypad: 7',
    ['client.key_pad_k8']           = 'Radio keypad: 8',
    ['client.key_pad_k9']           = 'Radio keypad: 9',
    ['client.key_pad_back']         = 'Radio keypad: delete / back',
    ['client.key_pad_ok']           = 'Radio keypad: OK',
    ['client.key_pad_up']           = 'Radio keypad: up',
    ['client.key_pad_down']         = 'Radio keypad: down',
    ['client.key_pad_left']         = 'Radio keypad: left (volume down)',
    ['client.key_pad_right']        = 'Radio keypad: right (volume up)',
    ['client.key_pad_star']         = 'Radio keypad: * (decimal point)',

    -- ── key hints beside the raised radio (overlay)
    ['client.hint_press']           = 'Press',
    ['client.hint_lower']           = 'Lower',
    ['client.hint_talk']            = 'Talk',
    ['client.hint_zoom']            = 'Zoom',
    ['client.hint_keypad']          = 'Keypad',
    ['client.hint_arrows']          = 'Move',
    ['client.hint_knob_key']        = 'VOL',
    ['client.hint_power']           = 'Knob up: on · hold down: off',

    -- ── on the radio's screen: headings and help lines
    ['client.scr_selftest']         = 'SELF TEST',
    ['client.scr_tune']             = 'TUNE',
    ['client.scr_tune_hint']        = '* point  ·  OK join',
    ['client.scr_code']             = 'ACCESS CODE',
    ['client.scr_code_hint']        = '4 digits  ·  OK send',
    ['client.scr_memory']           = 'MEMORY',
    ['client.scr_memories_hint']    = 'keys: store · OK: tune',
    ['client.scr_free']             = 'free slot',
    ['client.scr_slots']            = 'SLOTS',
    ['client.scr_slots_hint']       = 'OK talk here  ·  # leave',
    ['client.scr_menu']             = 'MENU',
    ['client.scr_menu_hint']        = 'OK select  ·  BACK exit',
    ['client.scr_emergency']        = 'EMERGENCY',
    ['client.scr_emergency_hint']   = 'ALERT SENT  ·  MIC OPEN',
    ['client.scr_on']               = 'ON',
    ['client.scr_off']              = 'OFF',
    ['client.scr_none']             = '—',

    -- ── on the radio's screen: menu entries
    ['client.scr_menu_memories']    = 'MEMORIES',
    ['client.scr_menu_slots']       = 'SLOTS',
    ['client.scr_menu_mute']        = 'MUTE',
    ['client.scr_menu_handsfree']   = 'HANDS-FREE',
    ['client.scr_menu_clicks']      = 'MIC CLICKS',
    ['client.scr_menu_earpiece']    = 'EARPIECE',
    ['client.scr_menu_roster']      = 'ROSTER',
    ['client.scr_menu_callsign']    = 'CALLSIGN',
    ['client.scr_menu_close']       = 'CLOSE',

    -- ── on the radio's screen: short notices
    ['client.scr_badcode']          = 'CODE REJECTED',
    ['client.scr_denied']           = 'RESTRICTED',
    ['client.scr_locked']           = 'TRY LATER',
    ['client.scr_invalid']          = 'OUT OF BAND',
    ['client.scr_busy']             = 'ONE MOMENT',
    ['client.scr_onslot']           = 'ALREADY ON S%d',
    ['client.scr_error']            = 'NO REPLY',
    ['client.scr_stored']           = 'STORED',
    ['client.scr_cleared']          = 'CLEARED',
    ['client.scr_notsaved']         = 'NOT SAVED',
    ['client.scr_nomem']            = 'NO MEMORIES',
    ['client.scr_mem']              = 'M%d · %s',
    ['client.scr_left']             = 'S%d CLEARED',
    ['client.scr_txslot']           = 'TALK ON S%d',
    ['client.scr_muted']            = 'MUTED',
    ['client.scr_unmuted']          = 'SOUND ON',
    ['client.scr_hf_on']            = 'OPEN MIC',
    ['client.scr_hf_off']           = 'MIC CLOSED',
    ['client.scr_clicks_on']        = 'CLICKS ON',
    ['client.scr_clicks_off']       = 'CLICKS OFF',
    ['client.scr_ear_in']           = 'EARPIECE IN',
    ['client.scr_ear_out']          = 'EARPIECE OUT',
    ['client.scr_roster_on']        = 'ROSTER ON',
    ['client.scr_roster_off']       = 'ROSTER OFF',
    ['client.scr_nosignal']         = 'NO SIGNAL',
    ['client.scr_nofreq']           = 'NO CHANNEL',
    ['client.scr_cooldown']         = 'WAIT',
    ['client.scr_callsign_hint']    = 'SET WITH /%s',
})
