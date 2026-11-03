--[[
  nayzeee-garages <-> loaf_housing (Loaf Scripts).              Support: automatic, optional edit (both)

  RECOMMENDED (no edit): in loaf_housing's config (shared/config.lua in v2 builds, config/config.lua
  if yours has a config folder) set
      Garage = false,
  loaf_housing then draws no garage marker / target of its own (it only dispatches to
  loaf_garage / cd_garage / jg). nayzeee-garages reads the garages itself (GetHouse(id).garage
  { entrance, exit }, or loaf_realtor's loaf_houses table), the owners (loaf_properties) and the
  key holders (loaf_keysystem's loaf_keys) and draws its own points: walk-up at the entrance,
  vehicles at the exit.
  loaf's AllowGarageKey = false (key holders get no garage) is mirrored with
      set nayzeee_housing_loaf_keys 0
  in server.cfg.

  OPTIONAL EDIT (keep loaf's own garage interaction instead):
    loaf_housing/client/main.lua (escrow-ignored in v2 builds): find where the garage interaction
    dispatches to the garage scripts (an if / elseif chain over loaf_garage, cd_garage, jg ...
    with exports.loaf_garage:StoreVehicle("property", ...) and
    exports.loaf_garage:BrowseVehicles("property", ...), sometimes inside a
    CreateGarageInteraction function) and WRAP each chain as shown below: nayzeee-garages first,
    loaf's existing chain unchanged in the else branch. `id` is the property id in that code
    (named differently in some builds: use the variable holding the property id). Keep
    Garage = true, and add
      set nayzeee_housing_hooked "loaf_housing"
    to server.cfg so nayzeee-garages does not draw a second point.

    Do NOT add an early `return` instead of the else branch: in builds where this code sits in
    loaf's `while true do` marker loop, a return ends the whole loop and loaf's markers stop.

  UNCONFIRMED
    The exact code around the dispatch differs between builds (stock marker callback vs. ox_target
    edits); the config path; v3 builds.
]]

-- context only (loaf's variable holding the property id); do NOT paste this line:
local id = ...

-- store chain (in a vehicle at the garage exit)
    if GetResourceState('nayzeee-garages') == 'started' then
        exports['nayzeee-garages']:StoreHouseGarage('loaf:' .. tostring(math.tointeger(tonumber(id)) or id))
    else
        -- loaf's existing store chain, unchanged, e.g.
        -- if GetResourceState("loaf_garage") == "started" then
        --     exports.loaf_garage:StoreVehicle("property", ...)
        -- elseif ... end
    end

-- browse chain (on foot at the garage entrance)
    if GetResourceState('nayzeee-garages') == 'started' then
        exports['nayzeee-garages']:OpenHouseGarage('loaf:' .. tostring(math.tointeger(tonumber(id)) or id))
    else
        -- loaf's existing browse chain, unchanged, e.g.
        -- if GetResourceState("loaf_garage") == "started" then
        --     exports.loaf_garage:BrowseVehicles("property", ...)
        -- elseif ... end
    end
