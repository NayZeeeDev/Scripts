fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NAYZEEE Development'
description 'Backpack system with attachable props for ESX Legacy + ox_inventory'
version '1.0.0'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_scripts {
    'client/anim.lua',
    'client/job.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/menu.lua',
    'client/place.lua',
    'client/prompts.lua',
    'client/weight.lua',
    'client/rob.lua',
    'client/shop.lua',
    'client/tuner.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/logs.lua',
    'server/job.lua',
    'server/main.lua',
    'server/drop.lua',
    'server/place.lua',
    'server/weight.lua',
    'server/rob.lua',
    'server/shop.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html'

}

-- Bag models can live here or in your own stream resource. The script only
-- needs the model NAME in Config.Backpacks, not the files themselves.
files {
    'stream/**.ydr',
    'stream/**.ytd',
    'stream/**.ytyp'
}

-- REQUIRED for any .ytyp you put in stream/.
-- Without this line the game never registers the archetype and the script
-- reports "model is not streaming" even though the .ydr is present.
-- Add one line per ytyp. Delete them if your props live in another resource,
-- since that resource declares its own.
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_cutebear/nayzeee_backpack_cutebear.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_snorlax/nayzeee_backpack_snorlax.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_alyx/nayzeee_backpack_alyx.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_lifesaver/nayzeee_backpack_lifesaver.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_shoulderbag_01/nayzeee_backpack_shoulderbag_01.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_shoulderbag_02/nayzeee_backpack_shoulderbag_02.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_heartpurse/nayzeee_backpack_heartpurse.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_heart/nayzeee_backpack_heart.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_alien/nayzeee_backpack_alien.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_blueshark/nayzeee_backpack_blueshark.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_pug/nayzeee_backpack_pug.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_puruplegoth/nayzeee_backpack_puruplegoth.ytyp' 
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_rick/nayzeee_backpack_rick.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_space/nayzeee_backpack_space.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_street/nayzeee_backpack_street.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_survivor/nayzeee_backpack_survivor.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_usahanna/nayzeee_backpack_usahanna.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_teddyburger/nayzeee_backpack_teddyburger.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_teddyskull/nayzeee_backpack_teddyskull.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_backpack_lean/nayzeee_backpack_lean.ytyp'

dependencies {
    'ox_lib',
    'ox_inventory',
    'es_extended'
}
