--[[
  nayzeee-garages <-> esx_property (ESX Legacy).                Support: automatic, optional edit (both)

  Without any edit nayzeee-garages reads every esx_property garage (exports GetProperties: garage
  { enabled, pos, Heading }, Owner, Keys; the esx_properties table or properties.json as
  fallbacks) and draws its own garage point there, refreshed when esx_property syncs a property.

  esx_property ALWAYS draws its own garage marker (marker + E for owners and key holders). This
  optional edit makes that marker use nayzeee-garages, so there is one garage per property:

  WHERE IT GOES
    esx_property/client/main.lua: add the marked blocks as the FIRST lines inside the existing
    functions StoreVehicle(PropertyId) and AccessGarage(PropertyId). Keep the rest of each body.
    Then add  set nayzeee_housing_hooked "esx_property"  to server.cfg so nayzeee-garages does not
    draw a second point at the same spot.
    (Alternative without the convar: delete esx_property's garage marker block instead, the
    `if Properties[i].garage.enabled and Properties[i].garage.pos and ...` block in its marker
    loop, and keep nayzeee-garages' point.)

  HOW IT WORKS
    House id 'esx:<PropertyId>' (the property's index, as esx_property numbers them). The server
    checks access (owner, Keys, DoesPlayerHaveKeys) and uses esx_property's garage position.
    Vehicles stored in esx_property's own garages before are not moved: retrieve them with
    esx_property once, or leave the edit out until they are out.

  esx_property is GPL-3.0: your edited copy stays under its license.
]]

-- context only (the functions' own parameter); do NOT paste this line:
local PropertyId = ...

-- function StoreVehicle(PropertyId)                  (first lines)
    if GetResourceState('nayzeee-garages') == 'started' then
        local ok, err = pcall(function() return exports['nayzeee-garages']:StoreHouseGarage('esx:' .. tostring(PropertyId)) end)
        if not ok then print(('[esx_property] nayzeee-garages garage failed: %s'):format(tostring(err))) end
        return
    end

-- function AccessGarage(PropertyId)                  (first lines)
    if GetResourceState('nayzeee-garages') == 'started' then
        local ok, err = pcall(function() return exports['nayzeee-garages']:OpenHouseGarage('esx:' .. tostring(PropertyId)) end)
        if not ok then print(('[esx_property] nayzeee-garages garage failed: %s'):format(tostring(err))) end
        return
    end
