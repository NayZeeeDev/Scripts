fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nayzeee-multicharacter'
author 'NayZeee Development'
description 'Cinematic AAA lobby multicharacter: themed scenes, squads & couples, pets, showcase weapons, departure cutscenes and spawn selector for ESX Legacy, QBCore and Qbox'
version '2.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
}

shared_scripts {
    'lock.lua',
    '@ox_lib/init.lua',
    'shared/math.lua',
    'config/config.lua',
    'config/themes.lua',
    'config/moods.lua',
    'config/poses.lua',
    'config/weapons.lua',
    'config/pets.lua',
    'config/spawns.lua',
    'config/nationalities.lua',
    'locales/*.lua',
    'shared/utils.lua',
    'shared/framework.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'bridge/server/common.lua',
    'bridge/server/esx.lua',
    'bridge/server/qb.lua',
    'bridge/server/housing.lua',
    'bridge/server/inventory.lua',
    'bridge/server/pets.lua',
    'server/db.lua',
    'server/logs.lua',
    'server/slots.lua',
    'server/validate.lua',
    'server/buckets.lua',
    'server/characters.lua',
    'server/weapons.lua',
    'server/squads.lua',
    'server/main.lua',
    'server/commands.lua',
    'server/exports.lua',
}

client_scripts {
    'bridge/client/framework.lua',
    'bridge/client/appearance.lua',
    'bridge/client/world.lua',
    'bridge/client/pets.lua',
    'client/utils.lua',
    'client/settings.lua',
    'client/audio.lua',
    'client/camera.lua',
    'client/lights.lua',
    'client/scene.lua',
    'client/actors.lua',
    'client/couple.lua',
    'client/plates.lua',
    'client/cutscene.lua',
    'client/spawn.lua',
    'client/create.lua',
    'client/start.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/relog.lua',
    'client/editor.lua',
}

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*.*',
    'web/dist/sounds/*.*',
}
