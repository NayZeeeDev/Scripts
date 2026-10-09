fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nz_cpuchip'
author 'NayZeeeDev'
description 'CPU chip prop (nz_prop_cpu_chip) + usable item helpers for PC building / crafting'
version '1.0.0'

-- streamed assets (everything in stream/ is streamed automatically; the ytyp
-- additionally has to be registered as a DLC_ITYP_REQUEST data file)
files {
    'stream/nz_prop_cpu_chip.ytyp',
}
data_file 'DLC_ITYP_REQUEST' 'stream/nz_prop_cpu_chip.ytyp'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
