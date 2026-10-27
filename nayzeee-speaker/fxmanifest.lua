fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-speaker'
author 'NAYZEEE Development'
description 'Speakers, boomboxes, a record console, a record shop and CarPlay with synced 3D audio'
version '2.0.0'

shared_scripts {
    'config.lua',
    'vinyls.lua',
    'locales/*.lua',
    'shared/*.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua',
    'client/audio.lua',
    'client/boombox.lua',
    'client/turntable.lua',
    'client/carplay.lua',
    'client/tools.lua',
    'client/damage.lua',
    'client/phone.lua',
    'client/shop.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/sources.lua',
    'server/search.lua',
    'server/artwork.lua',
    'server/spotify.lua',
    'server/tracks.lua',
    'server/main.lua',
    'server/vinyl.lua',
    'server/shop.lua',
    'server/playlists.lua',
    'server/links.lua',
    'server/damage.lua',
    'server/phone.lua',
    'server/social.lua',
    'server/vehicles.lua',
}

ui_page 'html/index.html'

files {
    'stream/nayzeee_audio.ytyp',
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/fonts/*.woff2',
    'html/phone/index.html',
    'html/phone/app.css',
    'html/phone/app.js',
    'html/phone/icon.png',
    'html/img/*.png',
}

data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_audio.ytyp'

dependencies {
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'vinyls.lua',
    'locales/*.lua',
    'client/bridge.lua',
    'server/bridge.lua',
}
