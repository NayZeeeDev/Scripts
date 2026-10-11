fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-multicharacter'
author 'NayZeee Development'
description 'Cinematic multicharacter, registration, starter shop and spawn selector for ESX Legacy, QBCore and Qbox'
version '1.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
}

shared_scripts {
    'lock.lua',
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/scenes.lua',
    'config/spawns.lua',
    'config/nationalities.lua',
    'locales/*.lua',
    'shared/utils.lua',
    'shared/framework.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'bridge/server/common.lua',
    'bridge/server/esx.lua',
    'bridge/server/qb.lua',
    'bridge/server/housing.lua',
    'server/db.lua',
    'server/logs.lua',
    'server/slots.lua',
    'server/validate.lua',
    'server/characters.lua',
    'server/main.lua',
    'server/partner.lua',
    'server/commands.lua',
    'server/doctor.lua',
    'server/exports.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'bridge/client/appearance.lua',
    'bridge/client/world.lua',
    'client/utils.lua',
    'client/settings.lua',
    'client/camera.lua',
    'client/scene.lua',
    'client/spawn.lua',
    'client/create.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/relog.lua',
    'client/tools.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
}

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'bridge/client/*.lua',
    'bridge/server/*.lua',
}
