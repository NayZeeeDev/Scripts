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

--- Key hint pill at the bottom of the screen; nil hides it
function UI.Hint(text)
    SendNUIMessage({ action = 'hint', text = text })
end

--- Crafting stage bar: { label, step, steps, time, hint }; nil hides it
function UI.Progress(data)
    SendNUIMessage({ action = 'progress', data = data })
end

--- Card shown when a pair is finished: { name, real, quality, passed, checks, image }
function UI.Result(data)
    SendNUIMessage({ action = 'result', data = data })
end

function UI.Notify(text, kind, title)
    Bridge.Notify(text, kind or 'inform', title)
end

RegisterNetEvent('nayzeee-sneakers:notify', UI.Notify)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and pendingMenu then SetNuiFocus(false, false) end
end)

-- A buyer's text when no phone resource took it (Config.Phone.Fallback): an ox_lib notification
RegisterNetEvent('nayzeee-sneakers:sms', function(m)
    Bridge.Notify(m.text, 'inform', m.from, 8000)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
end)
