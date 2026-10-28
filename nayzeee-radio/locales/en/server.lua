--[[
    NAYZEEE RADIO - English strings: server (server)

    Keys: server.*   notifications the server sends (radio, jammers, emergency), the error
                     lines the /radioadmin window shows after a refused save, and the Discord
                     webhook titles and field names.
    Used by server/modules/radio.lua, vehicles.lua, jammers.lua, alerts.lua and admin.lua.
    Translate by copying this file to locales/<lang>/server.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── radio
    ['server.no_radio']                    = 'You have no radio on you',
    ['server.kicked']                      = 'Your radio dropped %s from slot %d - you no longer have access to it',
    ['server.vehicle_untuned']             = 'The car radio dropped %s - access to that channel changed. Tune it again',
    ['server.earpiece_in']                 = 'Earpiece in. Only you hear your radio now',
    ['server.earpiece_out']                = 'Earpiece out. People next to you can hear your radio',

    -- ── jammers
    ['server.jammer_disabled']             = 'Jammers are switched off on this server',
    ['server.jammer_invalid']              = 'The jammer cannot go there',
    ['server.jammer_vehicle']              = 'Step out of the vehicle first',
    ['server.jammer_far']                  = 'That spot is out of reach',
    ['server.jammer_limit']                = 'You already have %d jammer(s) running',
    ['server.jammer_noitem']               = 'You do not have that jammer anymore',
    ['server.jammer_gone']                 = 'That jammer is no longer there',
    ['server.jammer_denied']               = 'This jammer is not yours to take',
    ['server.jammer_full']                 = 'No room for the jammer in your pockets',
    ['server.jammer_picked']               = 'Jammer packed away',
    ['server.jammer_seized_owner']         = 'Someone took your %s',
    ['server.jammer_expired']              = 'Your %s ran out of battery',

    -- ── emergency
    ['server.emergency_denied']            = 'Your radio has no emergency key enabled',

    -- ── admin window (shown after a refused save)
    ['server.admin_denied']                = 'You are not allowed to change the radio settings',
    ['server.admin_busy']                  = 'Another save is still running. Try again in a moment',
    ['server.admin_err_db']                = 'The database did not take the change. The server console has the details',
    ['server.admin_err_list']              = 'The list that was sent is broken. Close the window and open it again',
    ['server.admin_err_row']               = 'Row %d is broken',
    ['server.admin_err_too_many_channels'] = 'Keep it to %d channel rules',
    ['server.admin_err_too_many_vehicles'] = 'Keep it to %d vehicles',
    ['server.admin_err_freq']              = 'Row %d: "%s" is not a frequency the radios can tune',
    ['server.admin_err_dup']               = '%s is listed twice',
    ['server.admin_err_access']            = '%s: pick open, code or job',
    ['server.admin_err_code']              = '%s: the code has to be exactly 4 digits',
    ['server.admin_err_jobs']              = '%s: add at least one job',
    ['server.admin_err_job_name']          = '%s: a job name can only use letters, digits, - and _',
    ['server.admin_err_grade']             = '%s: the grade for %s has to be a whole number from 0 to %d',
    ['server.admin_err_too_many_jobs']     = '%s: no more than %d jobs per channel',
    ['server.admin_err_label']             = '%s: the label has to be text, %d characters at most',
    ['server.admin_err_model']             = 'Row %d: "%s" is not a spawn name (letters, digits and _ only)',
    ['server.admin_err_dup_model']         = '%s is listed twice',
    ['server.admin_err_range']             = '%s: the range multiplier goes from 0.5 to 3.0',

    -- ── webhooks
    ['server.wh_emergency']                = 'Radio emergency',
    ['server.wh_admin_saved']              = 'Radio settings changed',
    ['server.wh_jammer_placed']            = 'Jammer placed',
    ['server.wh_jammer_picked']            = 'Jammer picked up by its owner',
    ['server.wh_jammer_seized']            = 'Jammer seized',
    ['server.wh_jammer_hacked']            = 'Jammer disabled by a hack',
    ['server.wh_jammer_removed']           = 'Jammer removed by an admin',
    ['server.wh_player']                   = 'Player',
    ['server.wh_admin']                    = 'Admin',
    ['server.wh_owner']                    = 'Owner',
    ['server.wh_callsign']                 = 'Callsign',
    ['server.wh_freq']                     = 'Frequency',
    ['server.wh_coords']                   = 'Position',
    ['server.wh_type']                     = 'Type',
    ['server.wh_time']                     = 'Time taken',
    ['server.wh_channels']                 = 'Channel rules',
    ['server.wh_vehicles']                 = 'Radio vehicles',
    ['server.wh_unchanged']                = 'unchanged',
})
