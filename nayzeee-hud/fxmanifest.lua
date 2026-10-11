fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-hud'
author 'Nayzeee'
description 'Nayzeee HUD - player status, speedometers, vehicle controls, squads & seasonal styles'
version '1.1.0'

-- the squads module used to be its own resource; old exports['nayzeee-squads'] calls keep working
provide 'nayzeee-squads'

dependencies { 'ox_lib' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/squads/index.html',
    'html/squads/style.css',
    'html/squads/team-hud.css',
    'html/squads/hud-skin.css',
    'html/squads/app.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/data.lua',
    'squads/config.lua',
}

client_scripts {
    'client/core.lua',
    'client/bridge.lua',
    'client/minimap.lua',
    'client/vehicle.lua',
    'client/main.lua',
    'client/stress.lua',
    'client/nui.lua',

    'squads/bridge/client.lua',
    'squads/client/main.lua',
    'squads/client/hud.lua',
    'squads/client/world.lua',
    'squads/client/ping.lua',
    'squads/client/combat.lua',
    'squads/client/revive.lua',
    'squads/client/exports.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',

    'squads/bridge/server.lua',
    'squads/server/ranks.lua',
    'squads/server/db.lua',
    'squads/server/discord.lua',
    'squads/server/webhook.lua',
    'squads/server/roles.lua',
    'squads/server/main.lua',
    'squads/server/combat.lua',
    'squads/server/allies.lua',
    'squads/server/admin.lua',
    'squads/server/exports.lua',
}

escrow_ignore {
    'config.lua',
    'shared/data.lua',
    'client/bridge.lua',
    'squads/config.lua',
    'squads/bridge/*.lua',
    'squads/sql/*.sql',
}
