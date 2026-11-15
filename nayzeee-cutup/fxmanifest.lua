fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-cutup'
author 'NayZeee Development'
description 'CUT UP - No Hesi style highway cut-up: traffic, near-miss scoring, crews, ghosting, leaderboards, cockpit FOV and race wheel support'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/wheel.js',
}

shared_scripts {
    'config.lua',
    'locales/*.lua',
    'shared/util.lua',
}

client_scripts {
    'client/state.lua',
    'client/ui.lua',
    'client/camera.lua',
    'client/traffic.lua',
    'client/awareness.lua',
    'client/collision.lua',
    'client/transmission.lua',
    'client/wheel.lua',
    'client/crew.lua',
    'client/radar.lua',
    'client/scoring.lua',
    'client/main.lua',
}

server_scripts {
    'server/db.lua',
    'server/leaderboard.lua',
    'server/crews.lua',
    'server/main.lua',
}

-- OneSync (Infinity) is strongly recommended so traffic, crews and ghosting sync between players.
-- oxmysql is optional: without it everything is saved to data/db.json.
