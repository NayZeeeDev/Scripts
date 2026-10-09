fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-sneakers'
author 'NayZeee'
description 'Sneaker reselling - shoes, shoe boxes, wearing, crafting'
version '0.3.0'

dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/shoes.lua',
    'config/crafting.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'bridge/client/target.lua',
    'client/ui.lua',
    'client/camera.lua',
    'client/boxes.lua',
    'client/shoes.lua',
    'client/tables.lua',
    'client/crafting.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'bridge/custom/inventory.lua',
    'bridge/server/inventory.lua',
    'server/items.lua',
    'server/boxes.lua',
    'server/wear.lua',
    'server/xp.lua',
    'server/tables.lua',
    'server/crafting.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'install/images/*.png',
}

-- Everything in stream/ is streamed automatically; each ytyp needs its line.
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_alice/nzs_alice.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_bianca/nzs_bianca.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box/nzs_box.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box_boot/nzs_box_boot.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box_heel/nzs_box_heel.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_court/nzs_court.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_crevis/nzs_crevis.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_cup/nzs_cup.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_fang5/nzs_fang5.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_maisie/nzs_maisie.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_mia/nzs_mia.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_omnia/nzs_omnia.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_stack/nzs_stack.ytyp'
