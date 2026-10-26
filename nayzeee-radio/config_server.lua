--[[
    NAYZEEE RADIO - Server Config

    Loaded on the server only. Anything secret goes here - this file is never
    sent to players, unlike the files in config/.
]]

if not NAYZEEE_LOCK_OK then return end

ServerConfig = {}

ServerConfig.Discord = {
    enabled  = false,
    -- Leave empty to read the convar instead:
    --   set nayzeee_radio_webhook "https://discord.com/api/webhooks/..."
    webhook  = '',
    username = 'NAYZEEE Radio',
    avatar   = '',
    log = {
        admin     = true,   -- channel locks and vehicle list changes
        emergency = true,   -- emergency alerts
        jammers   = true,   -- jammers placed, hacked, picked up
    },
}

-- Runs on every emergency alert. Wire your dispatch script here.
--   source     the player who pressed it
--   frequency  '155.50'
--   coords     vector3
ServerConfig.EmergencyHook = function(source, frequency, coords)
    -- exports['ps-dispatch']:CustomAlert({ coords = coords, message = 'Radio emergency', ... })
end
