--[[
    UI layer: toasts, prompts, HUD, dialogue, interaction overlay, panels, phone.
    The page runs no timers while hidden and Lua never polls it.
]]

UI = { ready = false, focus = false }

local queue = {}

function UI.send(action, data)
    if not UI.ready then
        queue[#queue + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

local function itemLabels()
    local out = {}
    for name, row in pairs(Config.Items) do out[name] = row[1] end
    return out
end

RegisterNUICallback('ready', function(_, cb)
    UI.ready = true
    SendNUIMessage({ action = 'init', data = {
        ui = Config.UI, effects = Config.Effects, quality = Config.Quality, standards = Config.Standards,
        items = itemLabels(), ingredients = Config.Ingredients, drugs = Config.Drugs, maxEffects = Config.Mixing.maxEffects,
        resource = RES, phone = { name = Config.Phone.AppName }, mixSeconds = Config.Mixing.seconds,
    } })
    for i = 1, #queue do SendNUIMessage(queue[i]) end
    queue = {}
    cb(1)
end)

--- focus with cursor. keep = keep game input (the interaction engine reads the mouse itself)
function UI.setFocus(state, cursor, keep)
    UI.focus = state
    SetNuiFocus(state, state and cursor ~= false)
    SetNuiFocusKeepInput(state and keep == true)
end

--[[ notifications ]]
function UI.notify(msg, kind, duration, title)
    kind = kind or 'info'
    if Config.Notify == 'ox' then
        lib.notify({ title = title, description = msg, type = kind == 'info' and 'inform' or kind, duration = duration })
    elseif Config.Notify == 'framework' then
        if FW.name == 'esx' then
            TriggerEvent('esx:showNotification', msg)
        elseif FW.name == 'qbx' then
            exports.qbx_core:Notify(msg, kind == 'info' and 'inform' or kind, duration)
        elseif FW.name == 'qb' then
            TriggerEvent('QBCore:Notify', msg, kind == 'info' and 'primary' or kind, duration)
        else
            lib.notify({ description = msg, type = kind })
        end
    else
        UI.send('notify', { text = msg, kind = kind, title = title, duration = duration or Config.UI.notify.duration })
    end
end

RegisterNetEvent('nzde:notify', function(msg, kind)
    if GetInvokingResource() then return end
    UI.notify(msg, kind)
end)

--[[ [E] prompts: lines = { { key = 'E', label = '...' } } ]]
local textuiShown = false
function UI.textui(lines)
    if type(lines) == 'string' then lines = { { key = 'E', label = lines } } end
    textuiShown = true
    UI.send('textui', { lines = lines })
end

function UI.hideTextui()
    if not textuiShown then return end
    textuiShown = false
    UI.send('textui', false)
end

--[[ simple timed progress (no input) ]]
function UI.progress(label, ms, anim)
    local ped = cache.ped
    if anim then
        lib.requestAnimDict(anim.dict)
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
    end
    UI.send('progress', { label = label, duration = ms })
    local t = GetGameTimer() + ms
    local cancelled = false
    while GetGameTimer() < t do
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
        if IsControlJustPressed(0, 73) then cancelled = true break end
        Wait(0)
    end
    UI.send('progress', false)
    if anim then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
    return not cancelled
end

--[[ HUD (transparent objectives + deals, top left like the game) ]]
function UI.hud(data)
    UI.send('hud', data)
end

--[[ panels: a promise resolved by the page ]]
local panelPromise
function UI.panel(kind, data)
    if panelPromise then return nil end
    panelPromise = promise.new()
    UI.setFocus(true, true)
    UI.send('panel', { type = kind, data = data })
    local res = Citizen.Await(panelPromise)
    panelPromise = nil
    UI.setFocus(false)
    return res
end

function UI.panelUpdate(data)
    UI.send('panel:update', data)
end

function UI.closePanel(result)
    UI.send('panel', false)
    if panelPromise then panelPromise:resolve(result) end
end

RegisterNUICallback('panel:done', function(data, cb)
    cb(1)
    UI.closePanel(data)
end)

--[[ generic close from the page (escape) ]]
RegisterNUICallback('close', function(data, cb)
    cb(1)
    local what = data and data.what
    if what == 'panel' then
        UI.closePanel(false)
    elseif what == 'phone' then
        Phone.close()
    elseif what == 'ix' then
        Interact.cancel()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if UI.focus then SetNuiFocus(false, false) SetNuiFocusKeepInput(false) end
end)
