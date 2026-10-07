fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NayZeee Development'
description 'Wig Snatch V2 - player vs player wig snatching'
version '2.0.0'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/nui.lua',
    'client/hair.lua',
    'client/snatch.lua',
    'client/tools.lua',
    'client/buyer.lua',
    'client/barber.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config_server.lua',
    'bridge/framework.lua',
    'bridge/inventory.lua',
    'server/db.lua',
    'server/players.lua',
    'server/wigs.lua',
    'server/hair.lua',
    'server/clash.lua',
    'server/economy.lua',
    'server/social.lua',
    'server/tools.lua',
    'server/vault.lua',
    'server/admin.lua',
    'server/main.lua',
}

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/webfonts/*.woff2',
    'web/sounds/*.ogg',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'config_server.lua',
    'locales/*.lua',
    'bridge/*.lua',
}
