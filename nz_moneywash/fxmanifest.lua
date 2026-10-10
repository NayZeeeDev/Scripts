fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nz_moneywash'
author 'nayzeee'
version '1.0.0'
description 'THE WASH — a living money-laundering pipeline: washer → re-serial press → guillotine → cook the books'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/locations.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/sv_config.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/market.lua',
    'server/batches.lua',
    'server/stations.lua',
    'server/pallet.lua',
    'server/books.lua',
    'server/police.lua',
    'server/placement.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/nui.lua',
    'client/util.lua',
    'client/render.lua',
    'client/washer.lua',
    'client/printer.lua',
    'client/cutter.lua',
    'client/pallet.lua',
    'client/common.lua',
    'client/books.lua',
    'client/police.lua',
    'client/placement.lua',
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'bzzz_money', -- props: keep the prop pack as its own resource and start it first
}
