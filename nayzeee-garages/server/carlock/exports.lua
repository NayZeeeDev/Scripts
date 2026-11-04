--[[
  nayzeee-garages — car lock: server exports (docs/CARLOCK.md §7). Open file.

  exports['nayzeee-garages']:                               (vehicle = plate | entity | netId)
    HasKey(src, vehicle) -> boolean, kind ('temp'|'item'|'virtual'|'owner')
    GiveKey(src, vehicle, hours?) -> boolean               temporary key (reason 'export')
    RemoveKey(src, vehicle) -> boolean                     temporary key of that player
    GiveKeyItem(src, vehicle) -> boolean, error?           physical mode: signed key / fob item
    GetKeyVersion(plate) -> integer|nil                    nil: invalid plate or the database
                                                            cannot be read
    Rekey(plate, keepIdentifier?) -> integer|nil           new version: older keys stop working,
                                                            virtual / temporary keys of others removed.
                                                            Call it when your script changes a
                                                            vehicle's owner (sale, transfer).
    SetVehicleLocked(netId|entity, locked) -> boolean
    IsVehicleLocked(netId|entity) -> boolean
    SendDispatch(src|nil, alert) -> boolean                police alert through the configured
                                                            dispatch system (NZ.Dispatch.alert,
                                                            docs/CARLOCK.md §6); src = offender
                                                            (nil / 0: no offender, alert.coords
                                                            required). SendDispatch(alert) works too.

  Server code is trusted: no distance checks here (the calling script decides). Plates are
  real plates; a fake plate text read from a vehicle near the player is mapped to the real
  one. Every export is protected: a bad argument returns false / nil, never an error.
  StartTow lives with its module.
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

local function isVehicle(entity)
  return DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function fromNet(id)
  local ok, entity = pcall(NetworkGetEntityFromNetworkId, id)
  if ok and entity and entity ~= 0 and isVehicle(entity) then return entity end
  return nil
end

--- Vehicle argument: a server entity handle or a network id. `preferNet` tries the network
--- id first (SetVehicleLocked / IsVehicleLocked are documented with net ids).
local function vehicleOf(value, preferNet)
  local id = tonumber(value)
  if not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return nil end
  id = math.tointeger(id)
  if preferNet then return fromNet(id) or (isVehicle(id) and id or nil) end
  return (isVehicle(id) and id or nil) or fromNet(id)
end

--- Plate argument -> real plate: plate text (a fake plate near the player maps to the real
--- one) | vehicle entity | network id.
local function plateArg(src, value)
  if type(value) == 'number' then
    local entity = vehicleOf(value, false)
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
  if not plate or #plate > 16 then return nil end
  return CarLock.keyVersion(plate)
end))

exports('Rekey', safe('Rekey', function(plate, keepIdentifier)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 then return nil end
  if type(keepIdentifier) ~= 'string' or #keepIdentifier > 64 then keepIdentifier = nil end
  return CarLock.rekey(plate, keepIdentifier)
end))

exports('SetVehicleLocked', safe('SetVehicleLocked', function(netId, locked)
  local entity = vehicleOf(netId, true)
  if not entity then return false end
  return CarLock.setLocked(entity, locked == true, true)
end))

exports('IsVehicleLocked', safe('IsVehicleLocked', function(netId)
  local entity = vehicleOf(netId, true)
  if not entity then return false end
  return CarLock.isLocked(entity)
end))

exports('SendDispatch', safe('SendDispatch', function(src, alert)
  if type(src) == 'table' and alert == nil then src, alert = nil, src end
  if type(alert) ~= 'table' or type(NZ.Dispatch.alert) ~= 'function' then return false end
  return NZ.Dispatch.alert(src, alert) == true
end))
