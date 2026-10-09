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
    'client/stream.lua',
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
    'client/drops.lua',
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
    'server/drops.lua',
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
-- The props live in their own resources (nayzeee-sneakers-shoes, nayzeee-sneakers-boxes), locked too.
escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'bridge/**/*.lua',
    'install/*.lua',
}
