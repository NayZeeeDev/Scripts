-- nayzeee-chainsnatch addon for illenium-appearance
--
-- Chains that nayzeee-chainsnatch turned into jewellery can't be picked as clothing: they're bought at
-- the jewelry store. Called from setPedComponent (game/util.lua), which every path goes through: the
-- clothing menu, saved outfits, outfit codes, job outfits and loading a skin.

local RES = 'nayzeee-chainsnatch'
local last = 0

local function jewellery(ped, drawable)
    local ok, yes = pcall(function() return exports[RES]:IsJewelleryDrawable(ped, drawable) end)
    return ok and yes == true
end

--- true = don't put this component on
function NZC_BlockComponent(ped, component)
    if type(component) ~= 'table' or component.component_id ~= 7 then return false end
    if GetResourceState(RES) ~= 'started' or not jewellery(ped, component.drawable) then return false end

    -- what's on right now is jewellery too (an old outfit): take it off
    if jewellery(ped, GetPedDrawableVariation(ped, 7)) then SetPedComponentVariation(ped, 7, 0, 0, 0) end

    if ped == PlayerPedId() and GetGameTimer() - last > 2500 then
        last = GetGameTimer()
        pcall(function() exports[RES]:NotifyJewellery() end)
    end
    return true
end
