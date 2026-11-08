fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-coinshop'
author 'NAYZEEE Development'
description 'Coin shop: vehicles, items, weapons, tools, bundles, Tebex redeem, gifting, promo codes and a full admin panel'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'lock.lua',
    'config.lua',
    'shared/*.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/showroom.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server_config.lua',
    'bridge/server.lua',
    'server/seed.lua',
    'server/db.lua',
    'server/main.lua',
    'server/shop.lua',
    'server/sales.lua',
    'server/rewards.lua',
    'server/members.lua',
    'server/admin.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'server_config.lua',
    'bridge/*.lua',
    'locales/*.json',
    'install/*',
}
