-----------------------------------------------------------------
-- Chop shop integration
--
-- Vehicle Cargo cars that must be chopped (stolen tracked cars,
-- cars you can't store) can go to another creator's chop shop
-- instead of ours. Pick the system in config.lua → Config.ChopShop.
--
-- How it knows the car was chopped:
--   1. Automatic: the job car disappears within DetectRadius of
--      one of Config.ChopShop.External. Works with any chop script.
--   2. Exact (recommended): add ONE line to the other script, in the
--      server function that runs when a chop finishes:
--
--      exports['nayzeee-vehiclecargo']:VehicleChopped(source, plate)
--
--      Bablo Chop Shop  → its open server file (editable functions),
--                         where the reward is given after a chop.
--      Lation Chop Shop → its open server bridge, where the chop
--                         payout/rewards are handed out.
--      Anything else    → wherever that script pays for a chop.
--
--   `plate` is the chopped car's plate. Our job ends without paying
--   twice (unless PayOnExternal = true).
-----------------------------------------------------------------
ChopShop = {}
local C = Config.ChopShop

function ChopShop.System()
    local s = C.System or 'builtin'
    if s ~= 'auto' then return s end
    for name, res in pairs(C.Resources or {}) do
        if GetResourceState(res) == 'started' then return name end
    end
    return 'builtin'
end

function ChopShop.External() return ChopShop.System() ~= 'builtin' end

-- The shops players are sent to
function ChopShop.Locations()
    if not ChopShop.External() then
        local out = {}
        for _, c in ipairs(Config.ChopShops) do out[#out + 1] = { label = 'Chop shop', coords = c } end
        return out
    end
    return C.External or {}
end

-- Was this spot next to one of the external chop shops?
function ChopShop.Near(pos)
    if not pos then return false end
    for _, s in ipairs(C.External or {}) do
        local c = s.coords
        if #(vector3(pos.x, pos.y, pos.z) - vector3(c.x, c.y, c.z)) <= (C.DetectRadius or 40.0) then return true end
    end
    return false
end

-----------------------------------------------------------------
-- Client side: called when one of our cars has to be chopped and
-- an external system is used. Put anything that system needs here
-- (for example marking the car as allowed). Return nothing.
-----------------------------------------------------------------
function ChopShop.OnChopTarget(vehicle, data)
    local sys = ChopShop.System()
    if sys == 'bablo' then
        -- If Bablo only chops vehicles from its choppable list, add our
        -- models there (or allow any vehicle in its config).
    elseif sys == 'lation' then
        -- If Lation only chops its contract vehicles, players need one of
        -- its contracts, or allow other vehicles in its config.
    elseif sys == 'custom' then
        -- your own chop script
    end
end
