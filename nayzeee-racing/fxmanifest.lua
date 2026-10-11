fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-racing'
author 'NAYZEEE Development'
description 'Street racing tablet: lobbies, ranked ELO, seasons, crews, track builder, wagers, pink slips, betting, practice, spectate, elimination, drift and time trials'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'lock.lua',
    'config.lua',
    'shared/*.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/classes.lua',
    'client/main.lua',
    'client/tablet.lua',
    'client/race.lua',
    'client/builder.lua',
    'client/spectate.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/main.lua',
    'server/profiles.lua',
    'server/crews.lua',
    'server/tracks.lua',
    'server/lobby.lua',
    'server/lobbies.lua',
    'server/rewards.lua',
    'server/seasons.lua',
    'server/challenges.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/dui.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/maps/*',
    'locales/*.json',
    'seed/tracks/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'bridge/*.lua',
    'locales/*.json',
    'install/*',
}
