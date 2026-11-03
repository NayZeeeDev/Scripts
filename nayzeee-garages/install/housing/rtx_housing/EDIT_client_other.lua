--[[
  nayzeee-garages <-> rtx_housing: client edits.                  (needs Config.GarageSystem, EDIT_config.lua)

  This is NOT a drop-in file. In rtx_housing/client/other.lua add the three marked blocks as the
  FIRST lines inside the existing functions of the same name. Keep everything else.

  Pick ONE interaction:
    a) nayzeee-garages draws the garage point (default, recommended): GarageCheck returns false
       below, rtx draws nothing at the garage.
    b) rtx_housing draws its garage interaction: change NZ_USE_RTX_INTERACTION to true, and add
         set nayzeee_housing_hooked "rtx_housing"
       to server.cfg so nayzeee-garages does not draw a second point.

  The house id is 'rtx:<houseid>'; the server checks access (owner, rtx "garage" permission,
  GetPropertyPermission) and never trusts the client. The calls are guarded: while
  nayzeee-garages is stopped or restarting nothing happens (rtx's own code keeps running).
]]

local NZ_USE_RTX_INTERACTION = false

-- context only (the functions' own parameter); do NOT paste this line:
local propertyid = ...

-- function StoreVehicleToGarage(propertyid)          (first lines)
    if Config.GarageSystem == "nayzeee-garages" then
        if GetResourceState('nayzeee-garages') == 'started' then
            local houseId = 'rtx:' .. tostring(math.tointeger(tonumber(propertyid)) or propertyid)
            local ok, err = pcall(function() return exports['nayzeee-garages']:StoreHouseGarage(houseId) end)
            if not ok then print(('[rtx_housing] nayzeee-garages garage failed: %s'):format(tostring(err))) end
        end
        return
    end

-- function OpenGarageMenu(propertyid)                (first lines)
    if Config.GarageSystem == "nayzeee-garages" then
        if GetResourceState('nayzeee-garages') == 'started' then
            local houseId = 'rtx:' .. tostring(math.tointeger(tonumber(propertyid)) or propertyid)
            local ok, err = pcall(function() return exports['nayzeee-garages']:OpenHouseGarage(houseId) end)
            if not ok then print(('[rtx_housing] nayzeee-garages garage failed: %s'):format(tostring(err))) end
        end
        return
    end

-- function GarageCheck()                             (first lines)
    if Config.GarageSystem == "nayzeee-garages" then
        return NZ_USE_RTX_INTERACTION
    end

--[[
  Put the `local NZ_USE_RTX_INTERACTION = false` line once near the top of client/other.lua.

  UNCONFIRMED
    When rtx calls these functions is decided in its escrowed client/main.lua (inferred: open on
    foot, store in a vehicle; OpenHouseGarage also stores when the player is driving).
]]
