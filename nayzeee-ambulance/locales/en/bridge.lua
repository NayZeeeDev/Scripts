--[[
    NAYZEEE AMBULANCE - Bridge strings (English)
    Copy this file to locales/<lang>/bridge.lua and translate the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.AddLocale('en', {
    -- built-in target prompt
    ['bridge.target_prompt']      = '[%s] %s',
    ['bridge.target_more']        = '  (+%d more)',
    ['bridge.target_menu']        = 'Interactions',

    -- calling EMS (phone, export, radial menus)
    ['bridge.callems_title']      = 'Emergency Services',
    ['bridge.callems_call_title'] = 'Medical Emergency',
    ['bridge.callems_default']    = 'Caller needs an ambulance.',
    ['bridge.callems_unknown']    = 'Unknown caller',
    ['bridge.callems_sent']       = 'EMS dispatch received your call. Stay where you are.',
    ['bridge.callems_cooldown']   = 'You already called EMS. Wait a moment before calling again.',

    -- phones
    ['bridge.phone_call_text']    = 'Emergency call from %s',
    ['bridge.phone_reply']        = 'EMS dispatch: we received your call. Help is on the way.',
    ['bridge.mail_sender']        = 'Emergency Medical Services',

    -- external dispatch
    ['bridge.dispatch_title']     = 'EMS Call',
})
