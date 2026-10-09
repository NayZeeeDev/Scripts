fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-sneakers'
author 'NayZeee'
description 'Sneaker reselling - shoes, shoe boxes, wearing (phase 1)'
version '0.1.0'

dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/shoes.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'bridge/client/target.lua',
    'client/ui.lua',
    'client/camera.lua',
    'client/boxes.lua',
    'client/shoes.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'bridge/custom/inventory.lua',
    'bridge/server/inventory.lua',
    'server/items.lua',
    'server/boxes.lua',
    'server/wear.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/*.png',
}

-- Everything in stream/ is streamed automatically; each ytyp needs its line.
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box/nzs_box.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_cups/nzs_cups.ytyp'
