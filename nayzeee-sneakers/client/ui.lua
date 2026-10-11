UI = {}

local pendingMenu

--- Shows a menu and waits for a choice. Returns the option id, or nil if closed.
--- menu = { title, subtitle, image, options = { { id, label, description, icon, disabled } } }
function UI.Menu(menu)
    -- a menu that's somehow still open (e.g. it lost the cursor) is closed, never left blocking every
    -- later menu: wearing shoes, box colours ...
    if pendingMenu then
        local old = pendingMenu
        pendingMenu = nil
        old:resolve(nil)
    end
    local p = promise.new()
    pendingMenu = p
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'menu', menu = menu })
    -- items are used from the inventory, which lets go of the cursor a moment after it closes and can
    -- take it from the menu: hold on to it for a little while
    CreateThread(function()
        for _ = 1, 8 do
            Wait(100)
            if pendingMenu ~= p then return end
            SetNuiFocus(true, true)
        end
    end)
    local choice = Citizen.Await(p)
    if pendingMenu == p then pendingMenu = nil end
    return choice
end

local function finishMenu(id)
    SetNuiFocus(false, false)
    local p = pendingMenu
    pendingMenu = nil
    if p then p:resolve(id) end
end

function UI.MenuOpen() return pendingMenu ~= nil end

--- Closes whatever menu is open (nothing chosen)
function UI.CloseMenu()
    SendNUIMessage({ action = 'menuHide' })
    finishMenu(nil)
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
