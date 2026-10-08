fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-heistpack'
author 'nayzeee'
version '2.0.0'
description 'nayzeee heistpack - complete, server-authoritative heist system (21 heists, crews, levels, market, fence, drone, minigames)'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config/main.lua',
    'shared/utils.lua',
    'shared/registry.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'bridge/framework/server.lua',
    'bridge/inventory/server.lua',
    'bridge/dispatch/server.lua',
    'server/guard.lua',
    'server/db.lua',
    'server/profile.lua',
    'server/crew.lua',
    'server/chat.lua',
    'server/market.lua',
    'server/fence.lua',
    'server/heist/cooldowns.lua',
    'server/heist/rewards.lua',
    'server/heist/engine.lua',
    'server/heist/watchers.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'bridge/framework/client.lua',
    'bridge/target/client.lua',
    'bridge/dispatch/client.lua',
    'client/nui.lua',
    'client/anims.lua',
    'client/props.lua',
    'client/doors.lua',
    'client/spawns.lua',
    'client/carry.lua',
    'client/drone.lua',
    'client/heist/runtime.lua',
    'client/heist/nodes.lua',
    'client/heist/special.lua',
    'client/market.lua',
    'client/employer.lua',
    'client/menu.lua',
}

files {
    'locales/*.json',
    'config/main.lua',
    'config/market.lua',
    'config/fence.lua',
    'config/heists/*.lua',
    'web/index.html',
    'web/**/*',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}
