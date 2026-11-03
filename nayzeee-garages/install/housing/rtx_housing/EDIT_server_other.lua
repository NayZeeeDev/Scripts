--[[
  nayzeee-garages <-> rtx_housing: server edits.                  (needs Config.GarageSystem, EDIT_config.lua)

  This is NOT a drop-in file. In rtx_housing/server/other.lua:
    1. add the helper below once, above `function AddLog(`;
    2. add the marked blocks as the FIRST lines inside RegisterGarage, UpdateGarage, RemoveGarage
       and AddLog (before AddLog's `if Config.WebHooks == true` check, which wraps the rest).

  They only ask nayzeee-garages to read rtx_housing again (RefreshHousing, debounced, 1.5 s later so
  rtx has saved the change). nayzeee-garages reads garages, owners and permissions itself, so
  nothing else is passed and a missed call is caught by its 5-minute refresh.
]]

-- 1. helper (once, above `function AddLog(`)
local nzRefreshQueued = false
local function NZRefreshHousing()
    if Config.GarageSystem ~= "nayzeee-garages" or nzRefreshQueued then return end
    nzRefreshQueued = true
    SetTimeout(1500, function()
        nzRefreshQueued = false
        if GetResourceState('nayzeee-garages') ~= 'started' then return end
        pcall(function() return exports['nayzeee-garages']:RefreshHousing('rtx_housing') end)
    end)
end

-- 2a. function RegisterGarage(houseiddata)           (first lines: before its early returns, so a
--                                                     disabled or removed garage is seen as well)
    if Config.GarageSystem == "nayzeee-garages" then
        NZRefreshHousing()
        return true
    end

-- 2b. function UpdateGarage(houseiddata)             (first lines)
    if Config.GarageSystem == "nayzeee-garages" then
        NZRefreshHousing()
        return
    end

-- 2c. function RemoveGarage(houseiddata)             (first lines)
    if Config.GarageSystem == "nayzeee-garages" then
        NZRefreshHousing()
        return
    end

-- 2d. function AddLog(playersource, propertyid, action)   (first line; purchases, sales,
--                                                          transfers, rent changes)
    NZRefreshHousing()

--[[
  UNCONFIRMED
    When rtx calls RegisterGarage / UpdateGarage / RemoveGarage and which actions reach AddLog is
    decided in its escrowed server/main.lua. nayzeee-garages also listens to
    rtx_housing:Global:AddPermission / RemovePermission and rtx_housing:Global:AddLog by itself.
]]
