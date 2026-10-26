fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-ambulance'
author 'NAYZEEE'
description 'NAYZEEE Ambulance - injuries, field care, procedures, hospitals, dispatch and NPC calls'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'lock.lua',
    'shared/init.lua',
    'shared/const.lua',
    'shared/util.lua',
    'config/config.lua',
    'config/items.lua',
    'config/props.lua',
    'config/modules/*.lua',
    'locales/**/*.lua',
    'bridge/shared.lua',
}

client_scripts {
    'bridge/client/*.lua',
    'client/core/*.lua',
    'client/modules/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server/*.lua',
    'server/core/*.lua',
    'server/modules/*.lua',
}

ui_page 'html/index.html'

-- Sub folders need '**'. FiveM cannot match a folder written as a lone '*'
-- ('html/apps/*/*' matches nothing), so never use that form here.
files {
    'html/index.html',
    'html/core/**/*',
    'html/vendor/**/*',
    'html/apps/**/*',
    'html/dui/**/*',
    'html/img/**/*',
    'html/audio/**/*',
}

-- the props (models) are their own resource, so restarting this one does not stream them again
dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
    'nayzeee-ambulance-props',
}

escrow_ignore {
    'config/*.lua',
    'config/modules/*.lua',
    'locales/**/*.lua',
    'bridge/*.lua',
    'bridge/**/*.lua',
    'install/*',
    'sql/*',
}
