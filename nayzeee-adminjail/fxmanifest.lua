fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-adminjail'
author 'NayZeee Development'
description 'NAYZEEE Admin Jail - server authoritative OOC jail'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/hud.lua',
    'client/main.lua',
    'client/work.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/webhook.lua',
    'server/main.lua',
    'server/work.lua',
    'server/admin.lua',
    'server/commands.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'locales/*.json',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'locales/*.json',
    'bridge/*.lua',
    'install/*',
}
