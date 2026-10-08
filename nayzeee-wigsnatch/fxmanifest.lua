fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NayZeee Development'
description 'Wig Snatch V3 - snatching, minigames, first person cuts, restraints, products, wig workshop, phone app, wig studio'
version '3.0.0'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/notify.lua',
    'bridge/client.lua',
    'client/nui.lua',
    'client/prefs.lua',
    'bridge/phone.lua',
    'client/anims.lua',
    'client/hair.lua',
    'client/snatch.lua',
    'client/restrain.lua',
    'client/cutting.lua',
    'client/interact.lua',
    'client/phone.lua',
    'client/studio.lua',
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
    'server/restrain.lua',
    'server/cutting.lua',
    'server/products.lua',
    'server/workshop.lua',
    'server/market.lua',
    'server/social.lua',
    'server/vault.lua',
    'server/studio.lua',
    'server/studio.js',
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
    'web/phone/*',
    'data/*.json',
    'shots/**/*',
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
