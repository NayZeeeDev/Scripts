-- ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
-- ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
-- ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
-- ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
-- ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
-- ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝

ServerConfig = {}

-- Discord webhook logs. Put the URL in server.cfg so it never ships in the resource:
--   set nzm_webhook "https://discord.com/api/webhooks/..."
ServerConfig.Logs = {
    enabled = false,
    convar  = 'nzm_webhook',
    name    = 'Multicharacter',
    events  = {
        created   = { enabled = true, color = 0x08afa2, title = 'Character created' },
        deleted   = { enabled = true, color = 0xe5484d, title = 'Character deleted' },
        loaded    = { enabled = true, color = 0x3f8cff, title = 'Character loaded' },
        relog     = { enabled = true, color = 0xe5a50a, title = 'Relog' },
        slots     = { enabled = true, color = 0x08afa2, title = 'Slots changed' },
        admin     = { enabled = true, color = 0xe5a50a, title = 'Admin action' },
        redeem    = { enabled = true, color = 0x08afa2, title = 'Code redeemed' },
        shop      = { enabled = true, color = 0x08afa2, title = 'Starter shop' },
    },
}

-- Admin permission used by every /mc_ command
ServerConfig.AdminAce = 'group.admin'

-- Tebex: players redeem their transaction id in Settings > Account for extra slots.
--   set sv_tebexSecret "your_tebex_secret"
ServerConfig.Tebex = {
    enabled  = false,
    convar   = 'sv_tebexSecret',
    -- Tebex package id -> extra slots granted per quantity
    packages = {
        -- ['1234567'] = 1,
    },
}

-- Discord role slots use this convar for the bot token (see Config.Slots.discord)
ServerConfig.DiscordTokenConvar = 'nzm_discord_token'

-- Extra rows removed when a character is deleted. Tables that don't exist on your server are skipped automatically.
-- ESX: value is the full identifier (char1:xxxx). QB/Qbox: value is the citizenid.
ServerConfig.DeleteTables = {
    esx = {
        { table = 'users',                  column = 'identifier' },
        { table = 'owned_vehicles',         column = 'owner' },
        { table = 'user_licenses',          column = 'owner' },
        { table = 'datastore_data',         column = 'owner' },
        { table = 'addon_account_data',     column = 'owner' },
        { table = 'addon_inventory_items',  column = 'owner' },
        { table = 'billing',                column = 'identifier' },
        { table = 'phone_phones',           column = 'id' },
        { table = 'ox_inventory',           column = 'owner' },
        { table = 'playerskins',            column = 'citizenid' },
    },
    qb = {
        { table = 'player_vehicles',  column = 'citizenid' },
        { table = 'playerskins',      column = 'citizenid' },
        { table = 'player_outfits',   column = 'citizenid' },
        { table = 'player_houses',    column = 'citizenid' },
        { table = 'apartments',       column = 'citizenid' },
        { table = 'player_contacts',  column = 'citizenid' },
        { table = 'player_mails',     column = 'citizenid' },
        { table = 'phone_invoices',   column = 'citizenid' },
        { table = 'bank_accounts',    column = 'citizenid' },
        { table = 'ox_inventory',     column = 'owner' },
    },
}

-- Rate limits (ms) for sensitive actions
ServerConfig.RateLimit = {
    create = 4000,
    delete = 4000,
    play   = 2500,
    redeem = 10000,
    meta   = 400,
}

-- Resources that must NOT run next to this one (checked by the install doctor)
ServerConfig.Conflicts = {
    'esx_multicharacter', 'qb-multicharacter', 'qbx_multicharacter', 'um-multicharacter', 'um-ronin-multicharacter',
    'op-multicharacter', 'bablo-multicharacter', 'vms_multichars', '0r-multicharacter', 'qs-multicharacter',
    'codem-multicharacter', 'jg-multicharacter',
}
