fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-speaker'
author 'NAYZEEE Development'
description 'Speakers, boomboxes, a turntable, a record shop and CarPlay with synced 3D audio'
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
    'client/looks.lua',
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
    -- 'stream/nayzeee_console.ytyp',      -- record console upgrade: uncomment after converting it (see nayzeee-speaker-assets/README.md)
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/fonts/*.woff2',
    'html/phone/index.html',
    'html/phone/app.css',
    'html/phone/app.js',
    'html/phone/icon.png',
    'html/img/*.png',
    'html/dui/*.html',                    -- in-world pages: the console's record label, the shop's sleeves
    'html/looks/**/*',                    -- speaker looks: colour / design images, the RGB light and record pages
}

data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_audio.ytyp'
-- data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_console.ytyp'   -- record console upgrade: uncomment after converting it

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
