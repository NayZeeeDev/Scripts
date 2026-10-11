fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-tuning'
author 'NayZeee Development'
description 'Tuning shops, mechanic work orders, stance, ECU, nitrous, air ride, wear, diagnostics and business management'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/config.shops.lua',
    'config/config.parts.lua',
    'config/config.colors.lua',
    'config/config.performance.lua',
    'config/config.jobs.lua',
    'config/config.install.lua',
    'config/config.items.lua',
    'locales/*.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/core.lua',
    'client/garages.lua',
    'client/apply.lua',
    'client/camera.lua',
    'client/menu.lua',
    'client/shops.lua',
    'client/install.lua',
    'client/tablet.lua',
    'client/items.lua',
    'client/driving.lua',
    'client/perftest.lua',
    'client/testdrive.lua',
    'client/tools.lua',
    'client/missions.lua',
    'client/towing.lua',
    'client/supply.lua',
    'client/editor.lua',
    'client/scrapyard.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/core.lua',
    'server/pricing.lua',
    'server/vehicles.lua',
    'server/checkout.lua',
    'server/orders.lua',
    'server/business.lua',
    'server/features.lua',
    'server/avatars.lua',
    'server/items.lua',
    'server/tablet.lua',
    'server/missions.lua',
    'server/stock.lua',
    'server/supply.lua',
    'server/bays.lua',
    'server/editor.lua',
    'server/commands.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/fonts/*.woff2',
    'web/img/*.webp',
    'web/sounds/*.ogg',
    'web/webfonts/*.woff2',
}

--  ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗    ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗ ███████╗
--  ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝    ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗██╔════╝
--  █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗      ███████╗██║   ██║██║   ██║██╔██╗ ██║██║  ██║███████╗
--  ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝      ╚════██║██║   ██║██║   ██║██║╚██╗██║██║  ██║╚════██║
--  ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗    ███████║╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝███████║
--  ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝    ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝
--
-- Engine sound packs that ship INSIDE this resource (no separate download for server owners).
--   1. copy each pack's files into this resource:
--        audio/audioconfig/<name>_game.dat151.rel
--        audio/audioconfig/<name>_sounds.dat54.rel
--        audio/audioconfig/<name>_amp.dat10.rel     (only if the pack has one -> synth = true)
--        audio/sfx/dlc_<name>/*.awc
--   2. add one line below. It streams with the script and appears under Performance > Engine Note.
--
--   name   the audio name (what /testsound plays, usually the dlc_<name> folder name)
--   label  what players see in the tuning menu
--   synth  true when the pack has an _amp.dat10.rel file
--   files  only when the pack's files are named differently:
--          files = { game = 'x_game', sounds = 'x_sounds', synth = 'x_amp', wavepack = 'dlc_x' }
--   wavepack = false  the pack has no sfx/dlc_ folder of its own (it plays another pack's or GTA's .awc)
local ENGINE_SOUNDS = {
    { name = 'apollosv8',            label = 'Apollo V8' },
    { name = 'argento',              label = 'Argento' },
    { name = 'aston59v12',           label = 'Aston Martin 5.9 V12' },
    { name = 'audi7a',               label = 'Audi 7A Inline-5' },
    { name = 'ea825',                label = 'Audi EA825 V8' },
    { name = 'audr8tteng',           label = 'Audi R8 Twin Turbo', synth = true },
    { name = 'b58b30',               label = 'BMW B58 Inline-6' },
    { name = 'n55b30t0',             label = 'BMW N55 Inline-6' },
    { name = 'bmws1krreng',          label = 'BMW S1000RR', synth = true },
    { name = 'bmws702',              label = 'BMW S70/2 V12' },
    { name = 's85b50b',              label = 'BMW S85 V10' },
    { name = 'brabus850',            label = 'Brabus 850 V8' },
    { name = 'bgw16',                label = 'Bugatti W16', synth = true },
    { name = 'cfmleap1b',            label = 'CFM LEAP-1B Jet' },
    { name = 'chevydmaxeng',         label = 'Chevrolet Duramax Diesel', synth = true },
    { name = 'chevroletlt4',         label = 'Chevrolet LT4 V8' },
    { name = 'aqls7raceswap',        label = 'Chevy LS7 Race Swap' },
    { name = 'czr1eng',              label = 'Corvette ZR1 LT5', synth = true },
    { name = '12vcummins',           label = 'Cummins 12V Diesel' },
    { name = 'cummins5924v',         label = 'Cummins 5.9 24V Diesel' },
    { name = 'cw2019',               label = 'CW 2019' },
    { name = 'demonv8',              label = 'Dodge Demon V8' },
    { name = 'dghmieng',             label = 'Dodge Hemi V8', synth = true },
    { name = 'viperv10',             label = 'Dodge Viper V10' },
    { name = 'elegyx',               label = 'Elegy X' },
    { name = 'f113',                 label = 'F113', synth = true },
    { name = 'fdvsffeng',            label = 'FDVSF', synth = true },
    { name = '488sound',             label = 'Ferrari 488 V8' },
    { name = 'ferrarif12',           label = 'Ferrari F12 V12' },
    { name = 'f40v8',                label = 'Ferrari F40 V8' },
    { name = 'f430v8',               label = 'Ferrari F430 V8' },
    { name = 'f50v12',               label = 'Ferrari F50 V12' },
    { name = 'laferrarisound',       label = 'Ferrari LaFerrari V12' },
    { name = 'fordvoodoo',           label = 'Ford Voodoo V8', wavepack = false },
    { name = 'frf119eng',            label = 'FRF119', synth = true },
    { name = 'gtaspanov10',          label = 'GTA Spano V10' },
    { name = 'f20c',                 label = 'Honda F20C' },
    { name = 'k20a',                 label = 'Honda K20A', synth = true },
    { name = 'k20c',                 label = 'Honda K20C Turbo' },
    { name = 'ftypesound',           label = 'Jaguar F-Type V8' },
    { name = 'agerasound',           label = 'Koenigsegg Agera V8' },
    { name = 'ktm1290r',             label = 'KTM 1290 Super Duke R' },
    { name = 'aventadorv12',         label = 'Lamborghini Aventador V12' },
    { name = 'diablov12',            label = 'Lamborghini Diablo V12' },
    { name = 'gallardov10',          label = 'Lamborghini Gallardo V10' },
    { name = 'lambomurciev12',       label = 'Lamborghini Murcielago V12' },
    { name = 'perfov10',             label = 'Lamborghini Performante V10' },
    { name = '13b-rew',              label = 'Mazda 13B-REW Rotary' },
    { name = 'rotary7',              label = 'Mazda Rotary 7' },
    { name = 'fd3sid',               label = 'Mazda RX-7 FD Rotary', synth = true },
    { name = 'm840t',                label = 'McLaren M840T V8', synth = true },
    { name = 'mercm279',             label = 'Mercedes M279 V12' },
    { name = 'w211',                 label = 'Mercedes W211 E55' },
    { name = 'amg1eng',              label = 'Mercedes-AMG ONE', synth = true },
    { name = 'evoixsound',           label = 'Mitsubishi Evo IX 4G63' },
    { name = 'monroec',              label = 'Monroe C', synth = true },
    { name = 'murciev12',            label = 'Murcielago V12 (alt)' },
    { name = 'tamustanggt50',        label = 'Mustang GT 5.0', wavepack = false },
    { name = 'tascmustanggt50',      label = 'Mustang GT 5.0 Supercharged', wavepack = false },
    { name = 'musv8',                label = 'Mustang V8' },
    { name = 'r34sound',             label = 'Nissan R34 RB26' },
    { name = 'bnr34ffeng',           label = 'Nissan R34 RB26 (FF)', synth = true },
    { name = 's15sound',             label = 'Nissan S15 SR20' },
    { name = 'nsr2teng',             label = 'Nissan SR20DET', synth = true },
    { name = 'vr38dettv6',           label = 'Nissan VR38DETT V6' },
    { name = 'novitecsvj',           label = 'Novitec Aventador SVJ' },
    { name = 'npolchar',             label = 'Police Charger' },
    { name = '918spyeng',            label = 'Porsche 918 Spyder V8', synth = true },
    { name = 'porsche57v10',         label = 'Porsche Carrera GT V10' },
    { name = 'gt3rstun',             label = 'Porsche GT3 RS', synth = true },
    { name = 'f119pw100',            label = 'Pratt & Whitney F119 Jet', synth = true },
    { name = 'rb53532',              label = 'RB535 Jet', synth = true, wavepack = false },
    { name = 'roger',                label = 'Roger' },
    { name = 'rb211535',             label = 'Rolls-Royce RB211 Jet' },
    { name = 'sentinelsg4',          label = 'Sentinel SG4' },
    { name = 'aq03ej257',            label = 'Subaru EJ257 \'03' },
    { name = 'aq05ej257el',          label = 'Subaru EJ257 Equal Length' },
    { name = 'wrxrllyeng',           label = 'Subaru WRX Rally', synth = true },
    { name = 'superchargerdemonv8',  label = 'Supercharged Demon V8' },
    { name = 'tjz1eng',              label = 'Toyota 1JZ', synth = true },
    { name = 'aq2jzgterace',         label = 'Toyota 2JZ-GTE Race' },
    { name = '4age',                 label = 'Toyota 4A-GE', synth = true },
    { name = 'toysupmk4',            label = 'Toyota Supra MK4 2JZ' },
    { name = 'trumpetzr',            label = 'Trumpet ZR' },
    { name = 'dlcenginev10',         label = 'V10 (DLC)', files = { wavepack = 'dlc_enginev10' } },
}

files {
    'audio/audioconfig/*.dat151.rel',
    'audio/audioconfig/*.dat54.rel',
    'audio/audioconfig/*.dat10.rel',
    'audio/sfx/**/*.awc',
}

for _, p in ipairs(ENGINE_SOUNDS) do
    local f = p.files or {}
    data_file 'AUDIO_GAMEDATA'  ('audio/audioconfig/' .. (f.game or (p.name .. '_game')) .. '.dat')
    data_file 'AUDIO_SOUNDDATA' ('audio/audioconfig/' .. (f.sounds or (p.name .. '_sounds')) .. '.dat')
    if p.synth or f.synth then
        data_file 'AUDIO_SYNTHDATA' ('audio/audioconfig/' .. (f.synth or (p.name .. '_amp')) .. '.dat')
    end
    if p.wavepack ~= false then
        data_file 'AUDIO_WAVEPACK' ('audio/sfx/' .. (f.wavepack or ('dlc_' .. p.name)))
    end
    nz_engine_sound (p.name .. '|' .. (p.label or p.name))
end

dependencies {
    'ox_lib',
    'oxmysql',
}

escrow_ignore {
    'config/*.lua',
    'locales/*.lua',
    'bridge/*.lua',
}
