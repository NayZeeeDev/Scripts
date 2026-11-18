fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee_tv'
author 'NAYZEEE'
description 'NAYZEEE Television — synced smart TVs, cinema screens, wall displays, remotes and phone control'
version '1.0.0'

shared_scripts {
    'config.lua',
    'data/props.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/storage.lua',
    'server/permissions.lua',
    'server/main.lua',
    'server/media.lua',
    'server/admin.lua',
    'server/items.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/render.lua',
    'client/interact.lua',
    'client/placement.lua',
    'client/remote.lua',
    'client/nui.lua',
    'client/admin.lua',
    'client/phone.lua',
}

ui_page 'html/ui/index.html'

files {
    'html/ui/*',
    'html/tv/*',
    'html/tv/vendor/*',
    'html/phone/*',
    'html/media/*',
}

dependencies {
    '/onesync',
}
