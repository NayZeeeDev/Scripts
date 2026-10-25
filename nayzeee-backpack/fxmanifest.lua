fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NAYZEEE Development'
description 'Backpacks, purses & job bags for ox_inventory (ESX / Qbox / QBCore / standalone)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/bags.lua',
    'bridge/framework.lua',
    'integrations.lua',
}

client_scripts {
    'client/util.lua',
    'client/sounds.lua',
    'client/anim.lua',
    'client/status.lua',
    'client/main.lua',
    'client/carry.lua',
    'client/open.lua',
    'client/handoff.lua',
    'client/locks.lua',
    'client/menu.lua',
    'client/place.lua',
    'client/prompts.lua',
    'client/weight.lua',
    'client/rob.lua',
    'client/shop.lua',
    'client/studio.lua',
    'client/icons.lua',
    'client/outfits.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/logs.lua',
    'server/sounds.lua',
    'server/locks.lua',
    'server/overrides.lua',
    'server/main.lua',
    'server/jobs.lua',
    'server/drop.lua',
    'server/place.lua',
    'server/weight.lua',
    'server/rob.lua',
    'server/handoff.lua',
    'server/shop.lua',
    'server/icons.lua',
    'server/icons.js',
    'server/admin.lua',
    'server/outfits.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/images/outfit/*.png',
    'web/sounds/*.ogg',
}

-- Models, textures and animations live in nayzeee-backpack-props (or any
-- stream resource of yours). This resource is code and UI only, so
-- restarting it never re-streams a single prop.

dependencies {
    '/assetpacks',       -- needed once the resource is escrowed through Tebex
    'ox_lib',
    'ox_inventory',
    'screenshot-basic',  -- icon studio
}

-- Left readable for buyers when escrowed. Everything else stays encrypted.
-- (Escrow only ever encrypts .lua; web/ and server/icons.js ship as-is.)
escrow_ignore {
    'config.lua',
    'integrations.lua',
    'bridge/*.lua',
    'install.sql',
    'INSTALL.md',
}
