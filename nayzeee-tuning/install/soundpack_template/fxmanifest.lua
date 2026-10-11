-- Template for an engine sound pack resource. Copy this folder, rename it (e.g. nz-sounds),
-- drop your pack's files in and replace "mysound" with the pack's audio name.
--
--   nz-sounds/
--     fxmanifest.lua
--     audioconfig/mysound_game.dat151.rel
--     audioconfig/mysound_sounds.dat54.rel
--     audioconfig/mysound_amp.dat10.rel        (only some packs have this one)
--     sfx/dlc_mysound/mysound.awc
--     sfx/dlc_mysound/mysound_npc.awc          (only some packs have this one)
--
-- Several packs can live in one resource: repeat the three data_file lines per pack.
-- If your pack already comes with its own fxmanifest.lua, use that one instead.

fx_version 'cerulean'
game 'gta5'

files {
    'audioconfig/*.dat151.rel',
    'audioconfig/*.dat54.rel',
    'audioconfig/*.dat10.rel',
    'sfx/**/*.awc',
}

data_file 'AUDIO_GAMEDATA'  'audioconfig/mysound_game.dat'
data_file 'AUDIO_SOUNDDATA' 'audioconfig/mysound_sounds.dat'
data_file 'AUDIO_SYNTHDATA' 'audioconfig/mysound_amp.dat'   -- delete this line if the pack has no amp.dat10.rel
data_file 'AUDIO_WAVEPACK'  'sfx/dlc_mysound'
