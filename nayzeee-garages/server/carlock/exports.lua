--[[
  nayzeee-garages — car lock: server exports (docs/CARLOCK.md §7). Open file.

  exports['nayzeee-garages']:
    HasKey(src, plate) -> boolean, kind ('temp'|'item'|'virtual'|'owner')
    GiveKey(src, plate|netId, hours?) -> boolean           temporary key (reason 'export')
    RemoveKey(src, plate) -> boolean                       temporary key of that player
    GiveKeyItem(src, plate) -> boolean, error?             physical mode: signed key / fob item
    GetKeyVersion(plate) -> integer
    Rekey(plate) -> integer|nil                             new version: older keys stop working
    SetVehicleLocked(netId, locked) -> boolean
    IsVehicleLocked(netId) -> boolean

  Server code is trusted: no distance checks here (the calling script decides). Plates are
  real plates; a fake plate text read from a vehicle near the player is mapped to the real
  one. Every export is protected: a bad argument returns false / nil, never an error.
  SendDispatch / StartTow live with their modules.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local function safe(name, fn)
  return function(...)
    local res = table.pack(pcall(fn, ...))
    if not res[1] then
      lib.print.warn(('[nayzeee-garages] export %s failed: %s'):format(name, tostring(res[2])))
      return false
    end
    return table.unpack(res, 2, res.n)
  end
end

local function vehicleOf(netId)
  local id = tonumber(netId)
  if not id or id <= 0 or id ~= math.floor(id) then return nil end
  local entity = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
  return entity
end

--- Plate argument -> real plate (number = net id of the vehicle).
local function plateArg(src, value)
  if type(value) == 'number' then
    local entity = vehicleOf(value)
    return entity and CarLock.realPlate(entity) or nil
  end
  if type(value) ~= 'string' or #value > 16 then return nil end
  return CarLock.plateFromText(value, src)
end

exports('HasKey', safe('HasKey', function(src, plate)
  plate = plateArg(src, plate)
  if not plate then return false end
  local has, kind = CarLock.hasKey(src, plate)
  return has == true, kind
end))

exports('GiveKey', safe('GiveKey', function(src, plateOrNetId, hours)
  local plate = plateArg(src, plateOrNetId)
  if not plate then return false end
  return CarLock.grantTemp(src, plate, 'export', tonumber(hours)) == true
end))

exports('RemoveKey', safe('RemoveKey', function(src, plate)
  plate = plateArg(src, plate)
  if not plate then return false end
  CarLock.revokeTemp(src, plate)
  return true
end))

exports('GiveKeyItem', safe('GiveKeyItem', function(src, plate)
  plate = plateArg(src, plate)
  if not plate then return false, L('Invalid plate') end
  return CarLock.giveKeyItem(src, plate, { reason = 'export' })
end))

exports('GetKeyVersion', safe('GetKeyVersion', function(plate)
  plate = Utils.plate(plate)
  if not plate then return 0 end
  return CarLock.keyVersion(plate)
end))

exports('Rekey', safe('Rekey', function(plate)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 then return nil end
  return CarLock.rekey(plate)
end))

exports('SetVehicleLocked', safe('SetVehicleLocked', function(netId, locked)
  local entity = vehicleOf(netId)
  if not entity then return false end
  return CarLock.setLocked(entity, locked == true, true)
end))

exports('IsVehicleLocked', safe('IsVehicleLocked', function(netId)
  local entity = vehicleOf(netId)
  if not entity then return false end
  return CarLock.isLocked(entity)
end))
