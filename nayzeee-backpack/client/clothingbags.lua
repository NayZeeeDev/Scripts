-----------------------------------------------------------------
-- Clothing bags (client)
--
-- The server converts bag clothing into props (server/clothingbags.lua)
-- and sends the result here; the bags go into Config.Backpacks like
-- any other bag (key nzb_..., `converted = { bone, centre }` for the
-- automatic fit in client/autofit.lua).
-----------------------------------------------------------------

local function apply(list)
    for key, bag in pairs(Config.Backpacks) do
        if type(bag) == 'table' and bag.converted then Config.Backpacks[key] = nil end
    end
    for key, def in pairs(type(list) == 'table' and list or {}) do
        if not Config.Backpacks[key] then Config.Backpacks[key] = def end
    end
    Bags.cache = {}
    -- a clothing bag someone already wears could only now be drawn
    if RefreshAllBags then RefreshAllBags() end
end

RegisterNetEvent('nayzeee-backpack:clothingBags', apply)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('nayzeee-backpack:clothingBags:get')
end)
