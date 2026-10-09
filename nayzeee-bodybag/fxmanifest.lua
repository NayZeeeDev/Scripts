fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-bodybag'
author 'NAYZEEE Development'
description 'Advanced body disposal - bags, crates, coffins, trunks, dismemberment, cremation, acid, burial, water dumps, forensics, CK'
version '1.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',      -- helpers, bagging, all third-eye options
    'client/carry.lua',     -- carrying, dropping, grave hole, water dump
    'client/disposal.lua',  -- dismember, barrel, acid, burial, police alerts
    'client/gasmask.lua',   -- wearable gas mask
    'client/trunk.lua',     -- vehicle trunks
    'client/victim.lua',    -- what the bagged player sees + CK consent
    'client/admin.lua'      -- /bodyadmin menu
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/utils.lua',     -- helpers, logs, anti-exploit checks, DB auto-setup (load first)
    'server/main.lua',      -- body registry + every disposal method
    'server/trunk.lua',     -- vehicle trunks
    'server/ck.lua',        -- character kills
    'server/admin.lua'      -- /bodyadmin
}

-- Custom 'Black LosSantos Coroner Bag' model streams from stream/
-- It REPLACES the vanilla xm_prop_body_bag, so no config change is needed.
-- Delete stream/xm_prop_body_bag.ydr to go back to the default GTA bag.

dependencies {
    '/onesync',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
    'es_extended'
}
