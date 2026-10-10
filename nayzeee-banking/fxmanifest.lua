fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-banking'
author 'NAYZEEE Development'
description 'Immersive banking — personal, shared, society and savings accounts, cards, loans, bills, scheduled transfers'
version '1.0.0'

shared_scripts {
    'lock.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/locale.lua'
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_atm.lua',
    'client/cl_atm_dui.lua',
    'client/cl_atm_props.lua',
    'client/cl_phone.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_framework.lua',     -- ESX / QBCore / Qbox, before anything else
    'server/sv_core.lua',
    'server/sv_multijob.lua',
    'server/sv_accounts.lua',
    'server/sv_cards.lua',
    'server/sv_session.lua',
    'server/sv_credit.lua',
    'server/sv_loans.lua',
    'server/sv_savings.lua',
    'server/sv_overdraft.lua',
    'server/sv_statements.lua',
    'server/sv_bills.lua',
    'server/sv_payroll.lua',
    'server/sv_market.lua',
    'server/sv_phone.lua',
    'server/sv_bridge.lua',
    'server/sv_esx.lua',
    'server/sv_admin.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/style.css',
    'web/js/app.js',

    'web/atm.html',
    'web/css/atm.css',
    'web/js/atm.js',

    'web/phone/index.html',
    'web/phone/app.js',
    'web/phone/style.css',
    'web/phone/icon.png',

    'web/images/*.png',
    'web/images/cards/*.png',     -- the rendered cards the bank, phone and ATM show

    'web/sounds/key.ogg',
    'web/sounds/card.ogg',
    'web/sounds/cash.ogg',
    'web/sounds/dispense.ogg',
    'web/sounds/approved.ogg',
    'web/sounds/declined.ogg',
    'web/sounds/receipt.ogg'
}

dependencies {
    '/onesync',     -- the server checks where players are before cash moves
    'ox_lib',
    'oxmysql',
    -- and one of es_extended, qb-core or qbx_core (Config.Framework)
}

-- Left open so server owners can configure, translate and wire this into
-- their own resources. Everything else is protected.
escrow_ignore {
    'config.lua',
    'lock.lua',
    'locales/*.lua',
    'install/*',
    'server/sv_bridge.lua',     -- billing integrations
    'server/sv_esx.lua',        -- framework mirror
    'server/sv_multijob.lua',   -- multi-job adapters
    'server/sv_phone.lua',      -- phone contacts lookup
    'client/cl_phone.lua',      -- phone app registration
    'web/images/*'              -- so server owners can drop their own logo in
}
