fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-sneakers'
author 'NayZeee'
description 'Sneaker reselling - shoes, boxes, wearing, crafting, dirt and cleaning, selling'
version '1.0.0'

dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/shoes.lua',
    'config/crafting.lua',
    'config/selling.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'bridge/client/target.lua',
    'bridge/client/dispatch.lua',
    'client/ui.lua',
    'client/camera.lua',
    'client/place.lua',
    'client/boxes.lua',
    'client/displays.lua',
    'client/shoes.lua',
    'client/dirt.lua',
    'client/cleaning.lua',
    'client/tables.lua',
    'client/crafting.lua',
    'client/cinematic.lua',
    'client/selling.lua',
    'client/plug.lua',
    'client/studio.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'bridge/custom/inventory.lua',
    'bridge/server/inventory.lua',
    'bridge/server/phone.lua',
    'bridge/server/dispatch.lua',
    'server/items.lua',
    'server/boxes.lua',
    'server/displays.lua',
    'server/wear.lua',
    'server/xp.lua',
    'server/stats.lua',
    'server/tables.lua',
    'server/crafting.lua',
    'server/dirt.lua',
    'server/selling.lua',
    'server/studio.lua',
    'server/shots.js',
    'server/props.lua',
    'server/sneakerkit.js',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/studio.css',
    'web/studio.js',
    'web/keyer.js',
    'web/plug.html',
    'web/plug.css',
    'web/plug.js',
    'web/plug-icon.png',
    'web/fonts/*.woff2',
    'install/images/*.png',
    'shots/*.png',              -- photos taken in /sneakerstudio
    'shots/index.json',
}

-- Escrow (Tebex / Keymaster): everything is locked except these, which owners can edit.
-- The props and boxes in stream/ are locked too.
escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'bridge/**/*.lua',
    'install/*.lua',
}

-- Everything in stream/ is streamed automatically; each ytyp needs its line.
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_alice/nzs_alice.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_bianca/nzs_bianca.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box/nzs_box.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box_boot/nzs_box_boot.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_box_heel/nzs_box_heel.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_court/nzs_court.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_crevis/nzs_crevis.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_display/nzs_display.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_cup/nzs_cup.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_fang5/nzs_fang5.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_maisie/nzs_maisie.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_mia/nzs_mia.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_omnia/nzs_omnia.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nzs_stack/nzs_stack.ytyp'
