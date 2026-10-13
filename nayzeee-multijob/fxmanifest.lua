fx_version 'cerulean'
game 'gta5'


author 'NAYZEEE'
description 'Advanced Multi-Job Management System'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'lock.lua',
    'config.lua',
    'notify/adapters.lua',
    'shared/*.lua',
}

client_scripts {
    'notify/client.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config_server.lua',
    'notify/server.lua',
    'server/*.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config.lua',
    'config_server.lua',
    'notify/adapters.lua',
    'install/REPLACE_paycheck.lua',
    'install/install.sql',
}
