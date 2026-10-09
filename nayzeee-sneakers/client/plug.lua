--[[
    The Plug app on lb-phone: your stash, buyer offers, the active deal, what's
    trending, your stats.

    web/plug.html is added to lb-phone as a custom app (AddCustomApp). It asks
    for data through the NUI callbacks below (lb-phone apps fetch
    https://<resourceName>/<callback>), and gets a 'refresh' message through
    SendCustomAppMessage whenever something changes on the server.

    Selling needs lb-phone. Without it the rest of the script works, but there
    is no way to sell.
]]

Plug = {}

local APP_ID = 'nayzeee-plug'
local RES = GetCurrentResourceName()

local function lbRunning() return GetResourceState('lb-phone') == 'started' end

local function addApp()
    if not lbRunning() then return end
    local ok, added, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier = APP_ID,
            name = Config.Text.plugTitle,
            description = 'Sell your sneakers to buyers around the city',
            developer = 'NayZeee',
            defaultApp = Config.Phone.DefaultApp,   -- true = on every phone already, false = download it from the App Store
            size = 4096,
            ui = RES .. '/web/plug.html',
            icon = ('https://cfx-nui-%s/web/plug-icon.png'):format(RES),
            fixBlur = false,                        -- the app is laid out in px
        })
    end)
    if not ok or added == false then
        print(('^3[nayzeee-sneakers] could not add the Plug app to lb-phone: %s^7'):format(tostring(ok and err or added)))
    end
end

CreateThread(function()
    for _ = 1, 60 do
        if lbRunning() then return addApp() end
        Wait(1000)
    end
    print('^3[nayzeee-sneakers] lb-phone is not running: the Plug app (selling) is unavailable^7')
end)

-- lb-phone restarted: put the app back
AddEventHandler('onClientResourceStart', function(res)
    if res == 'lb-phone' then SetTimeout(1500, addApp) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES and lbRunning() then pcall(function() exports['lb-phone']:RemoveCustomApp(APP_ID) end) end
end)

--- Send something to the open app
function Plug.Send(msg)
    if lbRunning() then pcall(function() exports['lb-phone']:SendCustomAppMessage(APP_ID, msg) end) end
end

RegisterNetEvent('nayzeee-sneakers:client:plugUpdate', function()
    Plug.Send({ type = 'refresh' })
end)

--------------------------------------------------------------------------------
-- NUI callbacks the app calls
--------------------------------------------------------------------------------

local function relay(name, fn)
    RegisterNUICallback(name, function(data, cb)
        CreateThread(function() cb(fn(data or {}) or {}) end)
    end)
end

relay('plug:data', function()
    return lib.callback.await('nayzeee-sneakers:plugData', false) or {}
end)

relay('plug:find', function(d)
    local ok, msg = lib.callback.await('nayzeee-sneakers:plugFind', false, d.serial)
    if not ok and msg then UI.Notify(msg, 'error') end
    return { ok = ok == true, message = (not ok) and msg or nil }
end)

relay('plug:accept', function(d)
    local ok, msg = lib.callback.await('nayzeee-sneakers:plugAccept', false, d.id)
    if not ok and msg then UI.Notify(msg, 'error') end
    return { ok = ok == true, message = (not ok) and msg or nil }
end)

relay('plug:decline', function(d)
    lib.callback.await('nayzeee-sneakers:plugDecline', false, d.id)
    return { ok = true }
end)

relay('plug:cancel', function()
    return { ok = lib.callback.await('nayzeee-sneakers:plugCancel', false) == true }
end)

relay('plug:gps', function()
    Selling.GPS()
    return { ok = true }
end)

relay('plug:dropEnter', function()
    local ok, msg = lib.callback.await('nayzeee-sneakers:dropEnter', false)
    if msg then UI.Notify(msg, ok and 'success' or 'error') end
    return { ok = ok == true }
end)

relay('plug:dropGps', function()
    Drops.Gps()
    return { ok = true }
end)
