fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-drugempire'
author 'nayzeee'
version '1.0.0'
description 'nayzeee drug empire - Schedule I inspired: Uncle Benson, stolen RV lab, first person growing / cooking, mixing, customers, dealers, deliveries and a phone app'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config/main.lua',
    'config/products.lua',
    'config/stations.lua',
    'config/customers.lua',
    'config/shops.lua',
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
    'server/quests.lua',
    'server/messages.lua',
    'server/story.lua',
    'server/rv.lua',
    'server/stations.lua',
    'server/customers.lua',
    'server/dealers.lua',
    'server/deliveries.lua',
    'server/phone.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'bridge/framework/client.lua',
    'bridge/target/client.lua',
    'bridge/dispatch/client.lua',
    'bridge/phone/client.lua',
    'client/nui.lua',
    'client/util.lua',
    'client/dialogue.lua',
    'client/interact.lua',
    'client/story.lua',
    'client/rv.lua',
    'client/placement.lua',
    'client/stations.lua',
    'client/customers.lua',
    'client/dealers.lua',
    'client/deliveries.lua',
    'client/phone.lua',
    'client/main.lua',
}

files {
    'web/index.html',
    'web/**/*',
    'stream/nz_drugempire.ytyp',
}

-- custom props (grow tent, packaging bench + lid, zip bag, jar): stream/*.ydr
data_file 'DLC_ITYP_REQUEST' 'stream/nz_drugempire.ytyp'

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}
