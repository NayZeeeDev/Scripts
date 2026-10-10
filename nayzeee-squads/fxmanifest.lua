fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-squads'
author 'NayZeee Development'
version '3.0.0'
description 'Squads - crews with ranks, ELO, K/D/A, alliances, join requests, activity log, team HUD, compass, pings and revives'

dependencies { 'ox_lib' }

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/prompts.lua',
    'client/hud.lua',
    'client/world.lua',
    'client/ping.lua',
    'client/compass.lua',
    'client/combat.lua',
    'client/revive.lua',
    'client/exports.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/ranks.lua',
    'server/db.lua',
    'server/discord.lua',
    'server/webhook.lua',
    'server/roles.lua',
    'server/main.lua',
    'server/combat.lua',
    'server/allies.lua',
    'server/admin.lua',
    'server/exports.lua',
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

escrow_ignore {
    'config.lua',
    'bridge/*.lua',
    'sql/*.sql',
}
