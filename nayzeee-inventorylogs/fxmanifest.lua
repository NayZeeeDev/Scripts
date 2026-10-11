fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-inventorylogs'
author 'NAYZEEE Development'
description 'Inventory Manager: logs, player inventories, server-wide actions, rollbacks and a live inventory data editor (ox_inventory, qb-inventory or your own)'
version '3.1.1'

dependencies {
    'oxmysql',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/luadoc.lua',
    'server/core.lua',
    'server/inventory.lua',
    'inventories/*.lua',
    'server/logging.lua',
    'server/database.lua',
    'server/webhooks.lua',
    'server/discord.lua',
    'server/attribution.lua',
    'server/money.lua',
    'server/players.lua',
    'server/global.lua',
    'server/snapshots.lua',
    'server/dupe.lua',
    'server/economy.lua',
    'server/editor.lua',
    'server/commands.lua',
    'server/boot.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/webfonts/*.woff2',
}

escrow_ignore {
    'config.lua',
    'inventories/*.lua',
    'bridge/*.lua',
    'ox_bridge/**/*.lua',
    'framework_bridge/*.lua',
}
