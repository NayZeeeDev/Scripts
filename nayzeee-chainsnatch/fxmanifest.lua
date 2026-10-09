fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NAYZEEE Development'
description 'Chain Snatch: wear, flex, throw, set down and snatch chains converted from clothing'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/chains.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/util.lua',
    'client/nui.lua',
    'client/clothing.lua',
    'client/worn.lua',
    'client/menu.lua',
    'client/hold.lua',
    'client/place.lua',
    'client/drops.lua',
    'client/snatch.lua',
    'client/give.lua',
    'client/store.lua',
    'client/appearance.lua',
    'client/studio.lua',
    'client/icons.lua',
}

server_scripts {
    'config_server.lua',
    'bridge/framework.lua',
    'bridge/inventory.lua',
    'server/logs.lua',
    'server/registry.lua',
    'server/main.lua',
    'server/drops.lua',
    'server/throw.lua',
    'server/snatch.lua',
    'server/give.lua',
    'server/store.lua',
    'server/studio.lua',
    'server/icons.lua',
    'server/chainprops.lua',
    'server/icons.js',
    'server/chainkit.js',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'icons/*.png',          -- studio icon shots (the NUI shows them)
}

dependencies {
    '/assetpacks',       -- needed once the resource is escrowed through Tebex
    'ox_lib',
}

-- Left readable for buyers when escrowed. Everything else stays encrypted.
escrow_ignore {
    'config.lua',
    'config_server.lua',
    'bridge/*.lua',
    'install/*',
    'README.md',
}
