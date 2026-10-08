fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sneaker_box'
author 'NayZeee'
description 'Sneaker box prop with a hinged lid that animates open and closed (synced)'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

-- Build the models with tools/shoebox-prop-tool.html (see README.md).
-- Everything in stream/ is picked up automatically; the ytyp still needs this line.
data_file 'DLC_ITYP_REQUEST' 'stream/nz_shoebox/nz_shoebox.ytyp'
