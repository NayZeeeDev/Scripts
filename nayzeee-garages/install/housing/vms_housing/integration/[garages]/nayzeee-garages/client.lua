--[[
  nayzeee-garages <-> vms_housing (VMS Store) garage hook.            Support: hook file (required)

  WHERE IT GOES
    Copy this file to  vms_housing/integration/[garages]/nayzeee-garages/client.lua

  WHAT TO SET
    1. Search vms_housing for "DetectActiveGarage" (config.integrations.lua on 1.2.0+, config.lua
       before) and add 'nayzeee-garages' to the garage list it checks. Remove the other garage
       scripts you do not run from that list (how it picks one when several run is unconfirmed).
    2. server.cfg: ensure nayzeee-garages BEFORE vms_housing (the detection runs when vms_housing
       starts).
    3. Restart both. If the garage never opens, vms_housing's fxmanifest may not load new folders
       by itself: add this file to its client_scripts.

  HOW IT WORKS
    vms_housing draws the garage point of each property and calls OpenGarage(propertyId,
    propertyData) here. On foot that opens the nayzeee-garages menu of house 'vms:<propertyId>';
    driving, it stores the vehicle there (OpenHouseGarage switches to storing by itself).
    The server checks access with vms_housing (owner / renter, HasKeys, HasAnyPermission) and
    places the garage where the player stands (server-side position) the first time it is used;
    no marker or target is drawn by nayzeee-garages for these houses.

  UNCONFIRMED
    The DetectActiveGarage list format, whether the folder loads without a manifest edit,
    what propertyData contains, and whether apartments pass their own id or their building's id.
]]

if Config == nil or Config.Garages ~= 'nayzeee-garages' then
    return
end

local RESOURCE = 'nayzeee-garages'

local function houseLabel(propertyId, propertyData)
    if type(propertyData) == 'table' then
        local label = propertyData.name or propertyData.label or propertyData.address
        if type(label) == 'string' and label ~= '' then return label end
    end
    return ('Property %s'):format(tostring(propertyId))
end

-- Global function vms_housing calls (same as `function OpenGarage(...)`).
function _G.OpenGarage(propertyId, propertyData)
    if propertyId == nil then return end
    if GetResourceState(RESOURCE) ~= 'started' then
        print('[vms_housing] nayzeee-garages is not started')
        return
    end
    -- Numeric ids as plain integers (12.0 and '12' both become 'vms:12').
    local houseId = ('vms:%s'):format(tostring(math.tointeger(tonumber(propertyId)) or propertyId))
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local ok, err = pcall(function()
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            exports[RESOURCE]:StoreHouseGarage(houseId)
        else
            exports[RESOURCE]:OpenHouseGarage(houseId, { name = houseLabel(propertyId, propertyData) })
        end
    end)
    if not ok then print(('[vms_housing] nayzeee-garages garage failed: %s'):format(tostring(err))) end
end
