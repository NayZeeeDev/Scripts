fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-billing'
author 'NAYZEEE Development'
description 'Billing, invoicing, society billing and point-of-sale with banking integrations'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'societies.lua',
    'presets.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/registers.lua',
    'client/placement.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/console.lua',
    'bridge/framework/esx.lua',
    'bridge/framework/qb.lua',
    'bridge/framework/custom.lua',
    'bridge/banking.lua',
    'bridge/inventory.lua',
    'bridge/logger.lua',
    'server/database.lua',
    'server/core.lua',
    'server/templates.lua',
    'server/invoices.lua',
    'server/payments.lua',
    'server/dashboard.lua',
    'server/permissions.lua',
    'server/admin.lua',
    'server/registers.lua',
    'server/tasks.lua',
    'server/compat.lua',
    'server/exports.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.json',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}
