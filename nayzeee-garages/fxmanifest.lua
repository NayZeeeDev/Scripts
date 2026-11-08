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
  'config/carlock.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'shared/carlock.lua',
  'locales/*.lua',
  'bridge/shared.lua',
}

client_scripts {
  'bridge/client/qb.lua',
  'bridge/client/qbx.lua',
  'bridge/client/esx.lua',
  'bridge/client/common.lua',
  'bridge/client/notify.lua',
  'bridge/client/keys.lua',
  'bridge/client/fuel.lua',
  'bridge/client/target.lua',
  'bridge/client/housing.lua',
  'bridge/client/inventory.lua',
  'bridge/client/dispatch.lua',
  'bridge/client/listeners.lua',
  'client/nui.lua',
  'client/damage.lua',
  'client/vehicle.lua',
  'client/placement.lua',
  'client/camera.lua',
  'client/preview.lua',
  'client/points.lua',
  'client/peds.lua',
  'client/garage.lua',
  'client/impound.lua',
  'client/jobs.lua',
  'client/private.lua',
  'client/interior.lua',
  'client/creator.lua',
  'client/admin.lua',
  'client/carlock/lock.lua',
  'client/carlock/ignition.lua',
  'client/carlock/crime.lua',
  'client/carlock/locksmith.lua',
  'client/carlock/tracker.lua',
  'client/carlock/keysapp.lua',
  'client/carlock/fob.lua',
  'client/carlock/minigame.lua',
  'client/carlock/keyadmin.lua',
  'client/contracts.lua',
  'client/fakeplates.lua',
  'client/towtruck.lua',
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
  'bridge/server/housing/qb.lua',
  'bridge/server/housing/ps.lua',
  'bridge/server/housing/qs.lua',
  'bridge/server/housing/esx.lua',
  'bridge/server/housing/loaf.lua',
  'bridge/server/housing/vms.lua',
  'bridge/server/housing/bcs.lua',
  'bridge/server/housing/tk.lua',
  'bridge/server/housing/rtx.lua',
  'bridge/server/housing/rx.lua',
  'bridge/server/housing/nolag.lua',
  'bridge/server/inventory.lua',
  'bridge/server/dispatch.lua',
  'bridge/server/listeners.lua',
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
  'server/phone.lua',
  'server/carlock/keys.lua',
  'server/carlock/main.lua',
  'server/carlock/crime.lua',
  'server/carlock/locksmith.lua',
  'server/carlock/tracker.lua',
  'server/carlock/exports.lua',
  'server/contracts.lua',
  'server/fakeplates.lua',
  'server/towtruck.lua',
  'server/main.lua',
}

dependencies {
  '/onesync', -- server-side entity checks, routing buckets and state bags need OneSync
  'ox_lib',
  'oxmysql',
}
