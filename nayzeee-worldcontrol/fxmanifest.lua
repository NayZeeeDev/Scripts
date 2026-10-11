fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NayZeee Development'
description 'World Control - Weather, Time, Traffic & Population'
version '2.0.0'

shared_scripts {
    'shared/config.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
    'client/world.lua',
    'client/traffic.lua',
}

server_scripts {
    'server/main.lua',
    'server/weather.lua',
    'server/time.lua',
    'server/actions.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}

-- Lets resources that depend on these weather syncs start with World Control instead.
-- Remove the original resources from your server when using this.
provide 'qb-weathersync'
provide 'vSync'
provide 'cd_easytime'

escrow_ignore {
    'shared/config.lua'
}
