fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-hud'
author 'Nayzeee'
description 'Nayzeee HUD - player status, speedometers, vehicle controls & seasonal styles'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}

shared_scripts {
    'config.lua',
    'shared/data.lua',
}

client_scripts {
    'client/core.lua',
    'client/bridge.lua',
    'client/minimap.lua',
    'client/vehicle.lua',
    'client/main.lua',
    'client/nui.lua',
}
