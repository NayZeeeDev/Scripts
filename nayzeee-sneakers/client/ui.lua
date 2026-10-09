UI = {}

local pendingMenu

--- Shows a menu and waits for a choice. Returns the option id, or nil if closed.
--- menu = { title, subtitle, image, options = { { id, label, description, icon, disabled } } }
function UI.Menu(menu)
    if pendingMenu then return nil end
    pendingMenu = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'menu', menu = menu })
    local choice = Citizen.Await(pendingMenu)
    pendingMenu = nil
    return choice
end

local function finishMenu(id)
    SetNuiFocus(false, false)
    if pendingMenu then pendingMenu:resolve(id) end
end

RegisterNUICallback('menuSelect', function(data, cb) cb('ok'); finishMenu(data.id) end)
RegisterNUICallback('menuClose', function(_, cb) cb('ok'); finishMenu(nil) end)

function UI.Inspect(show, data)
    SendNUIMessage({ action = 'inspect', show = show, data = data, hint = Config.Text.inspectHint })
end

function UI.Notify(text, kind)
    kind = kind or 'inform'
    if Config.Notify == 'nui' then
        SendNUIMessage({ action = 'toast', text = text, kind = kind })
    elseif Config.Notify == 'ox' then
        lib.notify({ description = text, type = kind })
    else
        Bridge.FrameworkNotify(text, kind)
    end
end

RegisterNetEvent('nayzeee-sneakers:notify', UI.Notify)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and pendingMenu then SetNuiFocus(false, false) end
end)
