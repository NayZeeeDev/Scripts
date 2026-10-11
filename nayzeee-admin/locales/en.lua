-- English strings. Copy this file to add a language and set Config.Locale.
if Config.Locale ~= 'en' and Locales then return end
Locales = {
    no_permission   = 'You do not have permission for that.',
    player_offline  = 'Player not found.',
    banned_title    = 'You are banned from this server.',
    kicked          = 'You were kicked: %s',
    jail_released   = 'You have been released from jail.',
    report_sent     = 'Your report was sent to staff.',

    -- strings the panel reads (key = text shown)
    ui = {
        dashboard = 'Dashboard', players = 'Players', offline = 'Offline', reports = 'Reports', chats = 'Staff chat',
        moderation = 'Moderation', vehicles = 'Vehicles', items = 'Items', map = 'Live map', world = 'World',
        staff = 'Staff', logs = 'Logs', server = 'Server', settings = 'Settings',
    },
}
