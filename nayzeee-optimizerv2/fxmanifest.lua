shared_script '@D305-Protection/init.lua'
--[[
    
    NAYZEEE OPTIMIZER - FPS Boost, Kill Effects & Sounds
    Version: 1.1.0
    Discord: discord.gg/nayzeeedev
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- IMPORTANT: this resource only loads when its folder is named exactly
-- 'nayzeee-optimizerv2'. Renaming the folder stops it loading.

author 'NayZeee Development'
description 'Advanced FPS Optimizer with Kill/Hit Effects & Sounds'
version '1.1.0'

-- lock.lua MUST load first and stay escrow-protected
shared_script 'lock.lua'

shared_script 'config.lua'
shared_script 'grading.lua'

client_script 'client.lua'

server_script 'server.lua'

ui_page 'html/index.html'

-- probe.lua is loaded by OTHER resources via shared_script '@nayzeee-optimizerv2/probe.lua'
-- so it must be downloadable by clients and must stay unencrypted.
files {
    'probe.lua',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sounds/*.mp3',
}

