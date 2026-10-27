--[[
    NAYZEEE RADIO - English strings: bridge (client)

    Keys: bridge.*   the built-in [E] target (bridge/client/target.lua)
    Translate by copying this file to locales/<lang>/bridge.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- built-in target prompt (used when no target script runs)
    ['bridge.target_prompt']    = '[%s] %s',
    ['bridge.target_more']      = '  (+%d more)',
    ['bridge.target_menu']      = 'Interactions',
})
