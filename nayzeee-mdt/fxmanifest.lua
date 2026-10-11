fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-mdt'
author 'NAYZEEE Development'
description 'Tablet MDT and Dispatch — lock screen, home screen and app windows over a dispatch board, live map, BOLOs, warrants, incidents, charges, evidence, registries, roster, cameras, notepad and 10-codes'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua'
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_dispatch.lua',
    'client/cl_duty.lua',
    'client/cl_alpr.lua',
    'client/cl_photos.lua',
    'client/cl_cameras.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_core.lua',
    'server/sv_dispatch.lua',
    'server/sv_officers.lua',
    'server/sv_records.lua',
    'server/sv_reports.lua',
    'server/sv_bolo.lua',
    'server/sv_photos.lua',
    'server/sv_links.lua',
    'server/sv_cameras.lua',
    'server/sv_admin.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/style.css',
    'web/js/app.js',
    'web/img/atlas.webp',
    'web/img/midnight.webp',
    'web/img/satellite.webp',
    'web/img/wallpaper.svg',
    'web/img/wallpaper-grid.svg'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'es_extended'
}
