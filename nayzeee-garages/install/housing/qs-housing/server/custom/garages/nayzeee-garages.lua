--[[
  nayzeee-garages <-> qs-housing (Quasar) server garage bridge.   Support: automatic (this file is optional)

  See client/custom/garages/nayzeee-garages.lua for when to install it.

  WHERE IT GOES
    qs-housing/server/custom/garages/nayzeee-garages.lua

  WHAT TO SET
    Config.Garage = 'nayzeee-garages' in qs-housing's config (same as the client half).

  HOW IT WORKS
    When qs-housing adds, moves or removes a house garage it calls these functions; they only ask
    nayzeee-garages to read the qs-housing tables again (RefreshHousing, a second later so the
    database write has landed). Their arguments are ignored on purpose: their shape is not
    documented and the database is the source of truth.

  UNCONFIRMED
    The function names (TriggerAddHouseGarage / TriggerHouseUpdateGarage / TriggerHouseRemoveGarage)
    come from Quasar's integration page and public bridge files; your build may use others. Without
    them nayzeee-garages still picks the change up on its 5-minute refresh.
]]

if Config == nil or Config.Garage ~= 'nayzeee-garages' then
    return
end

local RESOURCE = 'nayzeee-garages'

-- The bridge functions qs-housing calls are globals (`function _G.X` is `function X`).
local queued = false

local function refreshSoon()
    if queued then return end
    queued = true
    SetTimeout(1000, function()
        queued = false
        if GetResourceState(RESOURCE) ~= 'started' then return end
        local ok, err = pcall(function() return exports[RESOURCE]:RefreshHousing('qs-housing') end)
        if not ok then print(('[qs-housing] nayzeee-garages refresh failed: %s'):format(tostring(err))) end
    end)
end

function _G.TriggerAddHouseGarage()
    refreshSoon()
end

function _G.TriggerHouseUpdateGarage()
    refreshSoon()
end

function _G.TriggerHouseRemoveGarage()
    refreshSoon()
end
