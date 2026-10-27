fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-radio'
author 'NAYZEEE'
description 'NAYZEEE Radio - handheld, field and tactical radios you hold and press, vehicle head units, signal range and jammers'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'lock.lua',
    'shared/init.lua',
    'shared/util.lua',
    'config/config.lua',
    'config/items.lua',
    'config/modules/*.lua',
    'locales/**/*.lua',
    'bridge/shared.lua',
    'shared/signal.lua',
    'shared/props_layout.lua',
}

client_scripts {
    'bridge/client/*.lua',
    'client/core/*.lua',
    'client/modules/*.lua',
}

-- oxmysql is optional: when it is started the database goes through its exports,
-- otherwise everything is saved as JSON in this resource's data/ folder.
server_scripts {
    'config_server.lua',
    'bridge/server/*.lua',
    'server/core/*.lua',
    'server/modules/*.lua',
}

ui_page 'html/index.html'

-- Sub folders need '**'. FiveM cannot match a folder written as a lone '*'
-- ('html/apps/*/*' matches nothing), so never use that form here.
-- tools/ (the prop pipeline) is not part of the released resource and is left out on purpose.
files {
    'html/index.html',
    'html/core/**/*',
    'html/apps/**/*',
    'html/dui/**/*',
    'html/img/**/*',
}

-- the props (models) are their own resource, so restarting this one does not stream them again
dependencies {
    '/onesync',     -- the server checks where players are (signal range, jammers, car speakers)
    'ox_lib',
    'pma-voice',
    'nayzeee-radio-props',
}

-- Left open so server owners can configure, translate and wire this into
-- their own resources. Everything else is protected.
escrow_ignore {
    'config/*.lua',
    'config/modules/*.lua',
    'config_server.lua',
    'locales/**/*.lua',
    'bridge/*.lua',
    'bridge/**/*.lua',
    'install/*',
    'sql/*',
    'tools/**',
}
