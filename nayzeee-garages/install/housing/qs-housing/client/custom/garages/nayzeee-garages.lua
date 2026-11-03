--[[
  nayzeee-garages <-> qs-housing (Quasar) client garage bridge.   Support: automatic (this file is optional)

  qs-housing keeps the qb-houses tables, so nayzeee-garages reads every house garage
  (houselocations.garage) and its owners / key holders (player_houses) by itself and draws its
  own point there: nothing has to be installed for house garages to work.

  Install this file (with its server half, server/custom/garages/nayzeee-garages.lua) when you want
    - qs-housing to stop looking for another garage script (no "not correctly configured" spam),
    - new / moved / removed house garages to show up at once instead of within 5 minutes,
    - anything in qs-housing that calls OpenGarage / StoreVehicle to use nayzeee-garages.

  WHERE IT GOES
    qs-housing/client/custom/garages/nayzeee-garages.lua
    (the folder is "garages" in every build seen; one doc page spells it "garage").

  WHAT TO SET
    Config.Garage = 'nayzeee-garages'  in qs-housing's config (config/config_garage.lua,
    config/config.lua or shared/config.lua depending on the build). If your build picks the garage
    with an auto-detect table, add 'nayzeee-garages' to it and ensure nayzeee-garages before
    qs-housing in server.cfg.

  UNCONFIRMED
    qs-housing is escrowed: the bridge function names come from public bridge files of other
    garage scripts. This file defines no loop and draws nothing (nayzeee-garages draws the point).
]]

if Config == nil or Config.Garage ~= 'nayzeee-garages' then
    return
end

local RESOURCE = 'nayzeee-garages'

-- The bridge functions qs-housing calls are globals (`function _G.X` is `function X`).

local function houseOf(house)
    -- qs-housing passes the house name; older bridges read the global closesthouse instead
    if house == nil then house = rawget(_G, 'closesthouse') or rawget(_G, 'CurrentHouse') end
    if type(house) == 'table' then house = house.name or house.house or house.id end
    if house == nil then return nil end
    return ('qs:%s'):format(tostring(house))
end

local function call(fn, house)
    local houseId = houseOf(house)
    if not houseId then return end
    if GetResourceState(RESOURCE) ~= 'started' then return end
    local ok, err = pcall(function() return exports[RESOURCE][fn](exports[RESOURCE], houseId) end)
    if not ok then print(('[qs-housing] nayzeee-garages %s failed: %s'):format(fn, tostring(err))) end
end

-- Open the garage menu of a house (stores the vehicle instead when the player is driving).
function _G.OpenGarage(house)
    call('OpenHouseGarage', house)
end

-- Store the vehicle the player is driving in the house garage.
function _G.StoreVehicle(house)
    call('StoreHouseGarage', house)
end

-- Garage added / moved on the client: nayzeee-garages gets the change from the server.
function _G.TriggerHouseUpdateGarage()
    if GetResourceState(RESOURCE) == 'started' then
        pcall(function() exports[RESOURCE]:RefreshHouseGarages() end)
    end
end
