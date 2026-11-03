--[[
  nayzeee-garages — server entry point (loaded last).

  Boots the server in order (migrate -> settings -> locations -> interiors -> private
  garages -> vehicles -> housing), then flags NZ.Ready and syncs online players.
  Registers the 'nz:state:bootstrap' callback, player lifecycle handlers and the chat
  commands from Config.Commands.
]]

local Utils = NZ.Utils

NZ.Ready = false

local ADMIN_PAGES = {
  garages = true, jobs = true, private = true, impounds = true,
  interiors = true, vehicles = true, settings = true,
}

-- Modules may define NZ.<Module>.onPlayerDropped(src) for extra cleanup (offers, invites...).
local DROP_HOOK_MODULES = { 'Vehicles', 'Actions', 'Impound', 'Jobs', 'Private', 'Interiors', 'Admin', 'Housing' }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function notify(src, message, kind)
  TriggerClientEvent('nz:client:notify', src, { type = kind or 'error', message = message })
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function memberLocations(identifier)
  if not identifier or type(NZ.Private.memberLocations) ~= 'function' then return {} end
  local ok, res = pcall(NZ.Private.memberLocations, identifier)
  if ok and type(res) == 'table' then return res end
  if not ok then lib.print.warn(('private memberLocations failed: %s'):format(tostring(res))) end
  return {}
end

local function syncGroups(src)
  if type(NZ.Private.syncMember) ~= 'function' then return end
  local ok, err = pcall(NZ.Private.syncMember, src)
  if not ok then lib.print.warn(('private syncMember failed: %s'):format(tostring(err))) end
end

local function leaveInterior(src)
  if type(NZ.Interiors.leave) ~= 'function' then return end
  local ok, err = pcall(NZ.Interiors.leave, src)
  if not ok then Utils.debug('interior leave on drop failed', tostring(err)) end
end

--- Run one boot step; failures are printed and the boot continues.
local function runStep(label, fn)
  if type(fn) ~= 'function' then
    lib.print.error(('boot: step "%s" is unavailable (did its file fail to load?)'):format(label))
    return false
  end
  local ok, err = pcall(fn)
  if not ok then
    lib.print.error(('boot: step "%s" failed: %s'):format(label, tostring(err)))
    return false
  end
  return true
end

local function migrationFailed(reason)
  local line = string.rep('=', 78)
  lib.print.error(line)
  lib.print.error('nayzeee-garages could NOT prepare its database and will not start.')
  lib.print.error(('Reason: %s'):format(tostring(reason)))
  lib.print.error('Check the oxmysql connection (mysql_connection_string) and that the database user')
  lib.print.error('may CREATE and ALTER tables, then restart the resource.')
  lib.print.error(line)
end

local function banner(failedSteps)
  local version = GetResourceMetadata(NZ.ResourceName, 'version', 0) or '?'
  local line = string.rep('-', 60)
  lib.print.info(line)
  lib.print.info(('nayzeee-garages v%s ready'):format(version))
  lib.print.info(('framework: %s | locations: %d | online players: %d'):format(
    tostring(NZ.Framework), #NZ.Locations.all(), #GetPlayers()))
  if failedSteps > 0 then
    lib.print.warn(('%d boot step(s) failed, see the errors above'):format(failedSteps))
  end
  lib.print.info(line)
end

---------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------

local function boot()
  if type(NZ.DB.migrate) ~= 'function' then
    migrationFailed('server/db.lua or server/migrations.lua did not load (NZ.DB.migrate missing)')
    return
  end
  local ok, result = pcall(NZ.DB.migrate)
  if not ok or result == false then
    migrationFailed(ok and 'NZ.DB.migrate() reported a failure' or result)
    return
  end

  local failed = 0
  local steps = {
    { 'settings', NZ.Settings.load },
    { 'locations', NZ.Locations.load },
    { 'settings references', NZ.Settings.checkReferences },
    { 'interiors', NZ.Interiors.load },
    { 'private garages', NZ.Private.load },
    { 'vehicles', NZ.Vehicles.boot },
    { 'housing', NZ.Housing.boot },
  }
  for i = 1, #steps do
    if not runStep(steps[i][1], steps[i][2]) then failed = failed + 1 end
  end

  NZ.Ready = true

  -- Players already online (resource restart): push everything they need.
  TriggerClientEvent('nz:client:settings', -1, NZ.Settings.all())
  NZ.Locations.sync(-1)
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if src then syncGroups(src) end
  end

  banner(failed)
end

CreateThread(boot)

---------------------------------------------------------------------------------------
-- Bootstrap callback: everything a client needs once its character is loaded.
---------------------------------------------------------------------------------------

lib.callback.register('nz:state:bootstrap', Utils.safe(function(source)
  local src = tonumber(source)
  if not src then return Utils.fail(L('Something went wrong')) end
  if not NZ.Ready then return Utils.fail(L('Garages are still loading')) end
  if not NZ.Access.rateLimit(src, 'state:bootstrap', 750) then
    return Utils.fail(L('Please wait a moment'))
  end
  local identifier = identifierOf(src)
  return Utils.ok({
    settings = NZ.Settings.all(),
    locations = NZ.Locations.clientViews(identifier),
    groups = memberLocations(identifier),
    isAdmin = NZ.Access.isAdmin(src),
  })
end))

---------------------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------------------

AddEventHandler('nz:server:playerLoaded', function(src)
  src = tonumber(src)
  if not src or src <= 0 or not NZ.Ready then return end
  TriggerClientEvent('nz:client:settings', src, NZ.Settings.all())
  NZ.Locations.sync(src)
  syncGroups(src)
end)

AddEventHandler('nz:server:playerUnloaded', function(src)
  src = tonumber(src)
  if not src or src <= 0 then return end
  NZ.Access.closeSession(src)
  leaveInterior(src)
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src or src <= 0 then return end
  NZ.Access.closeSession(src)
  leaveInterior(src)
  NZ.Access.clearRateLimits(src)
  for i = 1, #DROP_HOOK_MODULES do
    local mod = NZ[DROP_HOOK_MODULES[i]]
    if type(mod) == 'table' and type(mod.onPlayerDropped) == 'function' then
      local ok, err = pcall(mod.onPlayerDropped, src)
      if not ok then
        lib.print.warn(('%s.onPlayerDropped failed: %s'):format(DROP_HOOK_MODULES[i], tostring(err)))
      end
    end
  end
end)

---------------------------------------------------------------------------------------
-- Commands (permissions are checked inside, so they are registered unrestricted)
---------------------------------------------------------------------------------------

local function inGameOnly(src)
  if src > 0 then return true end
  lib.print.info('this command can only be used in game')
  return false
end

local commands = type(Config.Commands) == 'table' and Config.Commands or {}

if type(commands.admin) == 'string' and commands.admin ~= '' then
  RegisterCommand(commands.admin, function(source, args)
    local src = tonumber(source) or 0
    if not inGameOnly(src) then return end
    if not NZ.Access.rateLimit(src, 'command:admin', 1000) then return end
    if not NZ.Ready then return notify(src, L('Garages are still loading')) end
    if not NZ.Access.isAdmin(src) then
      notify(src, L('You are not allowed to do that'))
      if type(NZ.Logs.add) == 'function' then
        pcall(NZ.Logs.add, 'security.adminCommand', src, { command = commands.admin })
      end
      return
    end
    local page = type(args) == 'table' and type(args[1]) == 'string' and args[1]:lower() or nil
    if page and not ADMIN_PAGES[page] then page = nil end
    TriggerClientEvent('nz:client:openAdmin', src, { page = page })
  end, false)
end

if type(commands.impound) == 'string' and commands.impound ~= '' then
  RegisterCommand(commands.impound, function(source)
    local src = tonumber(source) or 0
    if not inGameOnly(src) then return end
    if not NZ.Access.rateLimit(src, 'command:impound', 1000) then return end
    if not NZ.Ready then return notify(src, L('Garages are still loading')) end
    local allowed = false
    if type(NZ.Impound.canImpound) == 'function' then
      local ok, res = pcall(NZ.Impound.canImpound, src)
      allowed = ok and res == true
    end
    if not allowed then return notify(src, L('You are not allowed to impound vehicles')) end
    TriggerClientEvent('nz:client:impoundForm', src)
  end, false)
end
