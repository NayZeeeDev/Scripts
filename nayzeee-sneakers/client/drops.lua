--[[
    Limited drops, client side: the drop store (a ped, with a blip while a drop is on), entering the
    raffle and collecting a pair there, and the Plug app's Drops tab. What's on is in GlobalState.nzsDrop.
]]

local D = Config.Drops
local T = Config.Text
local storePed, blip

local function drop() return GlobalState.nzsDrop end

local function showBlip(on)
    if on and not blip and D.Store.blip then
        local c = D.Store.coords
        blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, D.Store.blip.sprite)
        SetBlipColour(blip, D.Store.blip.colour)
        SetBlipScale(blip, D.Store.blip.scale or 0.85)
        SetBlipAsShortRange(blip, false)
        SetBlipFlashes(blip, true)
        SetBlipFlashTimer(blip, 8000)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(D.Store.label)
        EndTextCommandSetBlipName(blip)
    elseif not on and blip then
        RemoveBlip(blip)
        blip = nil
    end
end

AddStateBagChangeHandler('nzsDrop', 'global', function(_, _, value)
    showBlip(value ~= nil)
end)

RegisterNetEvent('nayzeee-sneakers:client:dropNews', function(_, text)
    UI.Notify(text, 'inform', T.dropFrom)
end)

local function enter()
    local ok, msg = lib.callback.await('nayzeee-sneakers:dropEnter', false)
    if msg then UI.Notify(msg, ok and 'success' or 'error') end
end

local function buy()
    local d = drop()
    if not d or Busy then return end
    local shoe = Config.Shoes[d.shoe]
    local sizes = Config.Sizes[shoe and shoe.gender == 'female' and 'female' or 'male']
    local options = {}
    for _, s in ipairs(sizes) do options[#options + 1] = { id = s, label = 'US ' .. s } end
    local size = UI.Menu({ title = T.dropSize, subtitle = ("%s '%s' · $%s"):format(d.label, d.colourway, d.price), image = d.image, options = options })
    if not size then return end
    local ok, msg = lib.callback.await('nayzeee-sneakers:dropBuy', false, size)
    if msg then UI.Notify(msg, ok and 'success' or 'error') end
end

local function whatsOn()
    local d = drop()
    if not d then return UI.Notify(T.dropNone, 'inform', T.dropFrom) end
    local v = lib.callback.await('nayzeee-sneakers:dropView', false) or d
    local line = ("%s '%s' · $%s · %d of %d left"):format(v.label, v.colourway, v.price, v.left, v.stock)
    UI.Notify(line, 'inform', T.dropFrom)
end

local function spawnStore()
    local s = D.Store
    if not LoadModel(s.ped) then return end
    local c = s.coords
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    storePed = CreatePed(4, s.ped, c.x, c.y, found and z or c.z - 1.0, c.w, false, false)
    SetEntityInvincible(storePed, true)
    SetBlockingOfNonTemporaryEvents(storePed, true)
    FreezeEntityPosition(storePed, true)
    TaskStartScenarioInPlace(storePed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    SetModelAsNoLongerNeeded(s.ped)
    Target.AddEntity(storePed, {
        { name = 'nzs_drop_enter', label = T.dropEnter, icon = 'fa-solid fa-ticket',
          canInteract = function() local d = drop() return d and d.phase == 'raffle' end, onSelect = enter },
        { name = 'nzs_drop_buy', label = T.dropCollect, icon = 'fa-solid fa-bag-shopping',
          canInteract = function() local d = drop() return d and d.phase == 'live' end, onSelect = buy },
        { name = 'nzs_drop_info', label = T.dropWhat, icon = 'fa-solid fa-circle-info', onSelect = whatsOn },
    }, 2.5)
end

if D.Enabled then
    CreateThread(function()
        showBlip(drop() ~= nil)
        -- the ped only while you're nearby
        while true do
            local c = D.Store.coords
            local near = #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z)) < 80.0
            if near and not storePed then spawnStore()
            elseif not near and storePed then
                Target.RemoveEntity(storePed)
                DeleteEntity(storePed)
                storePed = nil
            end
            Wait(near and 2500 or 4000)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if storePed and DoesEntityExist(storePed) then DeleteEntity(storePed) end
    showBlip(false)
end)

--- Plug app: enter from the phone, and a GPS to the store
Drops = {
    Enter = enter,
    Gps = function()
        local c = D.Store.coords
        SetNewWaypoint(c.x, c.y)
    end,
}
