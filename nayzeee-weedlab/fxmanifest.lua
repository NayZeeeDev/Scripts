fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-weedlab'
author 'nayzeee'
version '0.1.0'
description 'nayzeee weed lab - Schedule I inspired weed production: Uncle Benson, the Ballas RV, first person growing, packaging, drying, mixing, brick press, levels and three lab tiers'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config/main.lua',
    'config/strains.lua',
    'config/equipment.lua',
    'config/shop.lua',
    'shared/utils.lua',
    'shared/mixing.lua',
    'shared/grow.lua',
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
    'server/products.lua',
    'server/story.lua',
    'server/labs.lua',
    'server/stations.lua',
    'server/shop.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'bridge/framework/client.lua',
    'bridge/target/client.lua',
    'bridge/dispatch/client.lua',
    'client/nui.lua',
    'client/util.lua',
    'client/dialogue.lua',
    'client/interact.lua',
    'client/story.lua',
    'client/labs.lua',
    'client/placement.lua',
    'client/stations.lua',
    'client/packaging.lua',
    'client/processing.lua',
    'client/shop.lua',
    'client/main.lua',
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/icons.js',
    'web/fonts/*.woff2',
    'install/images/*.png',
    'stream/nzw_weedlab.ytyp',
}

-- custom props: stream/*.ydr + the shared texture dictionary stream/nzw_weedlab.ytd
data_file 'DLC_ITYP_REQUEST' 'stream/nzw_weedlab.ytyp'

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}
