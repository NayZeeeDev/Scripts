--[[
    NAYZEEE RADIO - English strings: core (shared)

    Keys: core.*   used by server/core/base.lua (command replies, notification title) and
                   bridge/client/notify.lua (title for notify resources that need one)
    Translate by copying this file to locales/<lang>/core.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── general
    ['core.title']              = 'Radio',

    -- ── commands
    ['core.cmd_no_perm']        = 'You are not allowed to use this command',
    ['core.cmd_param_id']       = 'Player id (empty = you)',
    ['core.cmd_no_target']      = 'No player with that id',
    ['core.err_failed']         = 'That did not work. The server console has the details',
})
