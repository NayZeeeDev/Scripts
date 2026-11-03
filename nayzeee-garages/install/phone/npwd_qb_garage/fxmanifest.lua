--[[
  npwd_qb_garage manifest for use with nayzeee-garages.

  WHERE IT GOES  npwd_qb_garage/fxmanifest.lua  (replace the file; keep a backup)
  WHAT CHANGED   compared with the original: no '@qb-garages/config.lua' (the server part now
                 gets garage names from nayzeee-garages) and no oxmysql (no SQL any more).
                 If your copy's manifest lists other files, keep them and only remove the
                 '@qb-garages/config.lua' line.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'NPWD garage app (QBCore) with nayzeee-garages'

client_script 'client/client.lua'
server_script 'server/server.lua'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/**/*',
}
