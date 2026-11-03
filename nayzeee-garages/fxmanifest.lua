fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nayzeee-garages'
author 'NayZeee'
description 'Garages, impounds, multiplayer interiors and an in-game vehicle manager for QBCore, Qbox and ESX'
version '1.0.0'

ui_page 'web/dist/index.html'

files {
  'web/dist/index.html',
  'web/dist/**/*',
}

shared_scripts {
  '@ox_lib/init.lua',
  'config/config.lua',
  'config/interiors.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'locales/*.lua',
  'bridge/shared.lua',
}

client_scripts {
  'bridge/client/qb.lua',
  'bridge/client/qbx.lua',
  'bridge/client/esx.lua',
  'bridge/client/common.lua',
  'bridge/client/keys.lua',
  'bridge/client/fuel.lua',
  'bridge/client/target.lua',
  'bridge/client/housing.lua',
  'client/nui.lua',
  'client/damage.lua',
  'client/vehicle.lua',
  'client/placement.lua',
  'client/camera.lua',
  'client/points.lua',
  'client/garage.lua',
  'client/impound.lua',
  'client/jobs.lua',
  'client/private.lua',
  'client/interior.lua',
  'client/creator.lua',
  'client/admin.lua',
  'client/main.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'config/server.lua',
  'bridge/server/qb.lua',
  'bridge/server/qbx.lua',
  'bridge/server/esx.lua',
  'bridge/server/common.lua',
  'bridge/server/keys.lua',
  'bridge/server/housing.lua',
  'server/logs.lua',
  'server/migrations.lua',
  'server/db.lua',
  'server/settings.lua',
  'server/locations.lua',
  'server/access.lua',
  'server/vehicles.lua',
  'server/actions.lua',
  'server/impound.lua',
  'server/jobs.lua',
  'server/private.lua',
  'server/interiors.lua',
  'server/import.lua',
  'server/admin.lua',
  'server/exports.lua',
  'server/main.lua',
}

dependencies {
  'ox_lib',
  'oxmysql',
}
