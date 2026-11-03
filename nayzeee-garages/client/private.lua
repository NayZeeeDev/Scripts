--[[
  nayzeee-garages — private garages for sale (NZ.PrivateClient).
  "Garage for sale" card (app 'forSale'): buying a copy (then opening it) and touring
  the garage interior before buying (§4.6, §8.2 For sale).
]]

local Private = NZ.PrivateClient

local current = nil      -- { locationId, data } of the open for-sale card
local opening = false

local function doOpen(locationId)
  local result = NZ.NUI.await('nz:forSale:info', { locationId = locationId })
  if not result.ok then
    NZ.NUI.notify('error', result.error)
    return false
  end
  if type(result.data) ~= 'table' then
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  current = { locationId = locationId, data = result.data }
  NZ.NUI.open('forSale', result.data)
  return true
end

--- Show the "garage for sale" card of a purchasable private location.
---@param locationId number
---@return boolean
function Private.openForSale(locationId)
  if opening then return false end
  if NZ.Points.incapacitated() then
    NZ.NUI.notify('error', L('You cannot do that right now'))
    return false
  end
  opening = true
  local ok, res = pcall(doOpen, locationId)
  opening = false
  if not ok then
    lib.print.error(('[nayzeee-garages] for-sale card failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  return res == true
end

local function locationIdOf(data)
  local id = tonumber(data.locationId)
  if id then return id end
  return current and tonumber(current.locationId) or nil
end

NZ.NUI.register('forSale:buy', function(data)
  local locationId = locationIdOf(data)
  if not locationId then return NZ.Utils.fail(L('This garage is not available here')) end
  local result = NZ.NUI.await('nz:forSale:buy', { locationId = locationId })
  if not result.ok then return result end

  NZ.NUI.close('forSale')
  NZ.NUI.notify('success', L('Garage purchased'))
  -- The server also syncs groups; mark membership now so the prompt updates at once.
  if type(NZ.State.groups) ~= 'table' then NZ.State.groups = {} end
  NZ.State.groups[locationId] = true
  CreateThread(function()
    NZ.Points.rebuild()
    NZ.Garage.open(locationId)
  end)
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('forSale:tour', function(data)
  local locationId = locationIdOf(data)
  if not locationId then return NZ.Utils.fail(L('This garage is not available here')) end
  NZ.NUI.close('forSale')
  local result = NZ.NUI.await('nz:forSale:tour', { locationId = locationId })
  if not result.ok then
    if current and current.data then NZ.NUI.open('forSale', current.data) end
    return result
  end
  CreateThread(function()
    if not (NZ.Interior and NZ.Interior.enter) then return end
    local ok, err = pcall(NZ.Interior.enter, result.data)
    if not ok then
      lib.print.error(('[nayzeee-garages] garage tour failed: %s'):format(err))
      NZ.NUI.notify('error', L('Something went wrong'))
    end
  end)
  return NZ.Utils.ok(nil)
end)
