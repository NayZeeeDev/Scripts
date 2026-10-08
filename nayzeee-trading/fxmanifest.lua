fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-trading'
author 'NAYZEEE Development'
description 'Day trading on a placeable laptop or handheld tablet: live and practice brokerage accounts, charts, Level 2, time & sales, news and more'
version '4.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/laptop.lua',
    'client/tablet.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/market.lua',
    'server/broker.lua',
    'server/props.lua',
    'server/api.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/js/apps/*.js',
}

dependencies {
    'oxmysql',
    'ox_lib',
}
