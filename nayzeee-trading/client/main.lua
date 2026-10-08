Trading = { open = false, busy = false }

local onClose

function Trading.Notify(text, kind)
    if Config.UI.notify == 'ox' then
        lib.notify({ title = Config.UI.brand, description = text, type = kind or 'inform' })
    else
        SendNUIMessage({ action = 'toast', data = { text = text, kind = kind or 'info' } })
    end
end

function Trading.Hint(title, keys)
    SendNUIMessage({ action = 'hint', data = title and { title = title, keys = keys } or false })
end

-- Opens the NUI for a device. `closed` runs once the UI has fully closed.
function Trading.Open(device, closed)
    if Trading.open then return false end
    local res = lib.callback.await('nz_trading:api', false, 'boot')
    if not res or not res.ok then
        Trading.Notify(res and res.err or 'Trading service unavailable', 'error')
        return false
    end
    Trading.open, onClose = true, closed
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = { device = device, boot = res.data } })
    TriggerServerEvent('nz_trading:server:view', true)
    return true
end

-- Asks the UI to play its shutdown animation; it calls back into 'close'.
function Trading.RequestClose()
    if Trading.open then SendNUIMessage({ action = 'shutdown' }) end
end

local function finishClose()
    if not Trading.open then return end
    Trading.open = false
    SetNuiFocus(false, false)
    TriggerServerEvent('nz_trading:server:view', false)
    local cb = onClose
    onClose = nil
    if cb then CreateThread(cb) end
end

RegisterNUICallback('close', function(_, cb)
    cb(true)
    finishClose()
end)

RegisterNUICallback('api', function(req, cb)
    local res = lib.callback.await('nz_trading:api', false, req.action, req.data)
    cb(res or { ok = false, err = 'No response' })
end)

-- ── server pushes → NUI ─────────────────────────────────────────

local function relay(event, action, always)
    RegisterNetEvent(event, function(data)
        if Trading.open or always then SendNUIMessage({ action = action, data = data }) end
    end)
end

relay('nz_trading:client:quotes', 'quotes')
relay('nz_trading:client:news', 'news')
relay('nz_trading:client:calendar', 'calendar')
relay('nz_trading:client:session', 'session')
relay('nz_trading:client:halt', 'halt')
relay('nz_trading:client:rollover', 'rollover')
relay('nz_trading:client:account', 'account')
relay('nz_trading:client:order', 'order')

-- These still sound/notify while the device is closed.
relay('nz_trading:client:fill', 'fill', true)
relay('nz_trading:client:alert', 'alert', true)
relay('nz_trading:client:margin', 'margin', true)

-- ── tablet command ──────────────────────────────────────────────

if Config.Command then
    RegisterCommand(Config.Command, function()
        if Trading.open then return Trading.RequestClose() end
        if Config.CommandRequiresItem and not lib.callback.await('nz_trading:hasItem', false, Config.Tablet.item) then
            return Trading.Notify('You need a trading tablet', 'error')
        end
        Trading.UseTablet()
    end, false)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Trading.open then return end
    SetNuiFocus(false, false)
end)
