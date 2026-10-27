--[[
    NAYZEEE RADIO - English strings: HUD apps (ui.*)

    The NUI apps that never take focus: overlay (raised-radio key dock, part names on the
    hover outline, jammer placement card), roster, vhud (passenger mini HUD) and alert
    (emergency card). Sent to the page with the rest of ui.* in '_core' config
    (client/core/ui.lua PushConfig); the apps read them with NZR.t('ui.<key>', fallback).
    Lines the Lua side sends itself (key hints, the placement status) live in client.lua and
    world.lua.
    Translate by copying this file to locales/<lang>/hud.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── overlay: key dock + placement card
    ['ui.ov_title']             = 'Radio up',
    ['ui.ov_place_label']       = 'Setting down',
    ['ui.ov_place_title']       = 'Signal jammer',
    ['ui.ov_place_ok']          = 'Clear to set down',
    ['ui.ov_place_bad']         = "Can't go here",

    -- ── overlay: the chip next to the hovered part (name, then what it does)
    ['ui.part_key']             = 'Key',
    ['ui.part_star']            = 'Key *',
    ['ui.part_star_h']          = 'decimal point',
    ['ui.part_hash']            = 'Key #',
    ['ui.part_hash_h']          = 'clear slot',
    ['ui.part_ok']              = 'OK',
    ['ui.part_ok_h']            = 'select',
    ['ui.part_back']            = 'Back',
    ['ui.part_back_h']          = 'delete',
    ['ui.part_menu']            = 'Menu',
    ['ui.part_menu_h']          = '',
    ['ui.part_up']              = 'Up',
    ['ui.part_up_h']            = 'slot',
    ['ui.part_down']            = 'Down',
    ['ui.part_down_h']          = 'slot',
    ['ui.part_left']            = 'Left',
    ['ui.part_left_h']          = 'volume',
    ['ui.part_right']           = 'Right',
    ['ui.part_right_h']         = 'volume',
    ['ui.part_dpad']            = 'Navigation pad',
    ['ui.part_dpad_h']          = 'slots · volume',
    ['ui.part_p1']              = 'P1',
    ['ui.part_p1_h']            = 'memories',
    ['ui.part_p2']              = 'P2',
    ['ui.part_p2_h']            = 'mute',
    ['ui.part_power']           = 'Power',
    ['ui.part_power_h']         = 'hold',
    ['ui.part_knob_channel']    = 'Channel knob',
    ['ui.part_knob_channel_h']  = 'memories',
    ['ui.part_knob_volume']     = 'Volume knob',
    ['ui.part_knob_volume_h']   = 'turn · low to switch off',
    ['ui.part_emerg']           = 'Emergency',
    ['ui.part_emerg_h']         = 'hold to alert',
    ['ui.part_ptt']             = 'Push to talk',
    ['ui.part_ptt_h']           = 'hold',
    ['ui.part_side1']           = 'Side key 1',
    ['ui.part_side1_h']         = 'hands-free',
    ['ui.part_side2']           = 'Side key 2',
    ['ui.part_side2_h']         = 'roster',
    ['ui.part_mute']            = 'Mute',
    ['ui.part_mute_h']          = '',
    ['ui.part_pre']             = 'Memories',
    ['ui.part_pre_h']           = '',

    -- ── roster
    ['ui.rs_tuned']             = 'tuned',
    ['ui.rs_you']               = 'you',
    ['ui.rs_more']              = 'more',
    ['ui.rs_drag']              = 'drag to move',
    ['ui.rs_nochan']            = 'No channel on your TX slot',
    ['ui.rs_nobody']            = 'Nobody tuned in yet',

    -- ── passenger HUD (state word under the model code)
    ['ui.vh_ready']             = 'standby',
    ['ui.vh_rx']                = 'receiving',
    ['ui.vh_muted']             = 'muted',
    ['ui.vh_tune']              = 'no channel',
    ['ui.vh_off']               = 'off',
    ['ui.vh_offword']           = 'OFF',

    -- ── emergency alert card
    ['ui.al_title']             = 'EMERGENCY',
    ['ui.al_unknown']           = 'Unknown caller',
    ['ui.al_channel']           = 'Channel',
    ['ui.al_label']             = 'Label',
    ['ui.al_where']             = 'Position',
    ['ui.al_time']              = 'Received',
})
