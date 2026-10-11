fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-admin'
author 'NAYZEEE Development'
description 'Staff panel, moderation and server tools'
version '1.0.0'

dependencies { 'ox_lib', 'oxmysql' }

shared_scripts {
    '@ox_lib/init.lua',
    'shared/utils.lua',
    'shared/permissions.lua',
    'config.lua',
    'config/teleports.lua',
    'config/zones.lua',
    'locales/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/hooks.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/core.lua',
    'server/players.lua',
    'server/moderation.lua',
    'server/staff.lua',
    'server/reports.lua',
    'server/world.lua',
    'server/vehicles.lua',
    'server/server.lua',
    'server/commands.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/self.lua',
    'client/actions.lua',
    'client/spectate.lua',
    'client/tools.lua',
    'client/world.lua',
    'client/keys.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/webfonts/*.woff2',
    'web/img/*.*',
}
