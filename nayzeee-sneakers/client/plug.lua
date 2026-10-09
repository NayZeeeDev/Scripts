--[[
    The Plug app: your stash, buyer offers, the active deal, what's trending, your stats.

    The same page (web/plug.html) runs in two places:
      - inside lb-phone, as a custom app (Config.Phone.App 'auto' / 'lb-phone')
      - in this script's own phone, opened with /plug, a key or the burner item

    It asks for data through the NUI callbacks below, and gets a 'refresh' nudge
    whenever something changes on the server (a new offer, a deal ending...).
]]

Plug = {}

local P = Config.Phone
local APP_ID = 'nayzeee-plug'
local RES = GetCurrentResourceName()
local builtinOpen = false

local function lbRunning() return GetResourceState('lb-phone') == 'started' end
local function useLb() return P.App ~= 'builtin' and lbRunning() end

local function registerLb()
    if not useLb() then return end
    local ok, err = pcall(function()
        exports['lb-phone']:AddCustomApp({
            identifier = APP_ID,
            name = Config.Text.plugTitle,
            description = 'Sell your sneakers',
            developer = 'NayZeee',
            defaultApp = true,
            size = 4096,
            ui = RES .. '/web/plug.html',
            icon = ('https://cfx-nui-%s/web/plug-icon.png'):format(RES),
            fixBlur = true,
        })
    end)
    if not ok then print(('^3[nayzeee-sneakers] could not add the lb-phone app: %s^7'):format(tostring(err))) end
end

CreateThread(function()
    Wait(1500)
    registerLb()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'lb-phone' then SetTimeout(2000, registerLb) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if lbRunning() then pcall(function() exports['lb-phone']:RemoveCustomApp(APP_ID) end) end
    if builtinOpen then SetNuiFocus(false, false) end
end)

--- Send something to the app, wherever it's open
function Plug.Send(msg)
    if useLb() then pcall(function() exports['lb-phone']:SendCustomAppMessage(APP_ID, msg) end) end
    if builtinOpen then SendNUIMessage({ action = 'plug', data = msg }) end
end

RegisterNetEvent('nayzeee-sneakers:client:plugUpdate', function()
    Plug.Send({ type = 'refresh' })
end)

--------------------------------------------------------------------------------
-- The built-in phone
--------------------------------------------------------------------------------

function Plug.Open()
    if builtinOpen or Busy then return end
    if P.App == 'lb-phone' then return end
    if P.NeedItem and not lib.callback.await('nayzeee-sneakers:hasBurner', false) then
        return UI.Notify(Config.Text.needBurner, 'error')
    end
    builtinOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'phone', open = true })
end

function Plug.Close()
    if not builtinOpen then return end
    builtinOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'phone', open = false })
end

if P.Command then
    RegisterCommand(P.Command, Plug.Open, false)
    if P.Key and P.Key ~= '' then
        RegisterKeyMapping(P.Command, 'Open the Plug app', 'keyboard', P.Key)
    end
end

RegisterNetEvent('nayzeee-sneakers:client:openPlug', Plug.Open)

--------------------------------------------------------------------------------
-- NUI callbacks (both the lb-phone app and the built-in phone call these)
--------------------------------------------------------------------------------

local function relay(name, fn)
    RegisterNUICallback(name, function(data, cb)
        CreateThread(function() cb(fn(data or {}) or {}) end)
    end)
end

relay('plug:data', function()
    local d = lib.callback.await('nayzeee-sneakers:plugData', false) or {}
    d.host = builtinOpen and 'builtin' or 'lb'
    return d
end)

relay('plug:find', function(d)
    local ok, msg = lib.callback.await('nayzeee-sneakers:plugFind', false, d.serial)
    if not ok and msg then UI.Notify(msg, 'error') end
    return { ok = ok == true }
end)

relay('plug:accept', function(d)
    local ok, msg = lib.callback.await('nayzeee-sneakers:plugAccept', false, d.id)
    if not ok and msg then UI.Notify(msg, 'error') end
    if ok and builtinOpen then Plug.Close() end
    return { ok = ok == true }
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

relay('plug:close', function()
    Plug.Close()
    return { ok = true }
end)
