fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NayZeee'
description 'Pulse - live streaming for FiveM. Go live from in game, watch on laptops, tablets, phones and TVs.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/*.lua',
}

client_scripts {
    'bridge/framework/client.lua',
    'bridge/notify.lua',
    'bridge/target.lua',
    'bridge/phones/client.lua',
    'bridge/phones/lb-phone.lua',
    'bridge/phones/yseries.lua',
    'bridge/phones/qs-smartphone.lua',
    'bridge/phones/qs-smartphone-pro.lua',
    'bridge/phones/npwd.lua',
    'bridge/phones/gksphone.lua',
    'bridge/phones/okokphone.lua',
    'bridge/phones/roadphone.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework/server.lua',
    'bridge/inventory/custom.lua',
    'bridge/inventory/server.lua',
    'bridge/notify.lua',
    'bridge/phones/server.lua',
    'server/*.lua',
}

ui_page 'html/index.html'
ui_page_preload 'yes'   -- the root frame exists from the start so phone app frames can reach it

files {
    'html/**/*',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

-- Custom streamed props (see stream/README.md). Uncomment after adding a .ytyp to stream/.
-- data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'

escrow_ignore {
    'config.lua',
    'locales/*.lua',
    'bridge/**/*.lua',
    'items/*',
    'stream/README.md',
    'html/**/*',
}
