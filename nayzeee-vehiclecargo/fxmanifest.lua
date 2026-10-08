fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-vehiclecargo'
author 'NayZeee Development'
description 'Vehicle Cargo - private warehouses, vehicle sourcing, design bay and export sales'
version '1.0.0'

dependencies {
    'ox_lib',
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/vehicles.lua',
    'config/locations.lua',
    'config/workshop.lua',
    'locales/en.lua',
    'shared/utils.lua',
    'integrations/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/main.lua',
    'server/radio.lua',
    'server/warehouse.lua',
    'server/raid.lua',
    'server/source.lua',
    'server/workshop.lua',
    'server/sell.lua',
    'server/admin.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/music.lua',
    'client/warehouse.lua',
    'client/placer.lua',
    'client/laptop.lua',
    'client/layout.lua',
    'client/scenarios.lua',
    'client/source.lua',
    'client/heists.lua',
    'client/raid.lua',
    'client/workshop.lua',
    'client/sell.lua',
    'client/admin.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/webfonts/*.woff2',
    'web/sounds/*.ogg',
    'web/sounds/*.mp3',
}

escrow_ignore {
    'config/*.lua',
    'bridge/*.lua',
    'locales/*.lua',
    'integrations/*.lua',
}
