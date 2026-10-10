fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-billing'
author 'NAYZEEE Development'
description 'Advanced billing, invoicing & point-of-sale system with banking integrations'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'companies.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/registers.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'bridge/banking.lua',
    'bridge/inventory.lua',
    'server/database.lua',
    'server/core.lua',
    'server/invoices.lua',
    'server/payments.lua',
    'server/boss.lua',
    'server/registers.lua',
    'server/admin.lua',
    'server/tasks.lua',
    'server/exports.lua',
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
