--[[
    UI layer: notifications, text prompts, progress, minigames and the task HUD.
    The NUI page has no timers running while hidden, and Lua never polls it.
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

RegisterNUICallback('ready', function(_, cb)
    UI.ready = true
    local raw = LoadResourceFile(RES, ('locales/%s.json'):format(Config.Locale)) or LoadResourceFile(RES, 'locales/en.json')
    local strings = raw and json.decode(raw) or {}
    SendNUIMessage({ action = 'init', data = { ui = Config.UI, strings = strings.ui or {}, levels = Config.Levels } })
    for i = 1, #queue do SendNUIMessage(queue[i]) end
    queue = {}
    cb(1)
end)

function UI.setFocus(state, cursor)
    UI.focus = state
    SetNuiFocus(state, cursor ~= false and state)
    SetNuiFocusKeepInput(false)
end

--[[ notifications ]]
function UI.notify(msg, kind, duration)
    kind = kind or 'info'
    if Config.Notify == 'ox' then
        lib.notify({ description = msg, type = kind == 'info' and 'inform' or kind, duration = duration })
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
        UI.send('notify', { text = msg, kind = kind, duration = duration or Config.UI.notify.duration })
    end
end

RegisterNetEvent('nzh:notify', function(msg, kind)
    if GetInvokingResource() then return end
    UI.notify(msg, kind)
end)

--[[ text prompts: lines = { { key = 'E', label = '...' } } ]]
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

--[[ progress ]]
local progressActive = false

---@param opts { label: string, duration: number, anim?: table, prop?: table, canCancel?: boolean, disableMove?: boolean }
---@return boolean completed
function UI.progress(opts)
    if Config.Progress == 'ox' then
        return lib.progressBar({
            label = opts.label, duration = opts.duration, canCancel = opts.canCancel ~= false, useWhileDead = false,
            disable = { move = opts.disableMove ~= false, car = true, combat = true },
            anim = opts.anim and { dict = opts.anim.dict, clip = opts.anim.clip, flag = opts.anim.flag or 49 } or nil,
            prop = opts.prop,
        }) == true
    end
    if progressActive then return false end
    progressActive = true
    local ped = cache.ped
    local prop
    if opts.anim then
        lib.requestAnimDict(opts.anim.dict)
        TaskPlayAnim(ped, opts.anim.dict, opts.anim.clip, 3.0, 3.0, -1, opts.anim.flag or 49, 0, false, false, false)
    end
    if opts.prop then
        prop = Props.attach(ped, opts.prop.model, opts.prop.bone, opts.prop.pos, opts.prop.rot)
    end
    UI.send('progress', { label = opts.label, duration = opts.duration })
    local start = GetGameTimer()
    local cancelled = false
    while GetGameTimer() - start < opts.duration do
        if opts.disableMove ~= false then
            DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
        end
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        if (opts.canCancel ~= false and IsControlJustPressed(0, 73)) or IsEntityDead(ped) then
            cancelled = true
            break
        end
        if opts.anim and not IsEntityPlayingAnim(ped, opts.anim.dict, opts.anim.clip, 3) then
            TaskPlayAnim(ped, opts.anim.dict, opts.anim.clip, 3.0, 3.0, -1, opts.anim.flag or 49, 0, false, false, false)
        end
        Wait(0)
    end
    UI.send('progress', false)
    if opts.anim then StopAnimTask(ped, opts.anim.dict, opts.anim.clip, 1.0) end
    if prop then DeleteEntity(prop) end
    progressActive = false
    return not cancelled
end

--[[ minigames: keypad | circuit | typing | safecrack | lockpick | memory | drill | datacrack | wires ]]
local mgPromise

---@return boolean success
function UI.minigame(kind, opts)
    if mgPromise then return false end
    opts = opts or {}
    mgPromise = promise.new()
    UI.setFocus(true, kind ~= 'drill' and kind ~= 'lockpick' and kind ~= 'safecrack')
    UI.send('minigame', { type = kind, difficulty = opts.difficulty or 2, options = opts })
    local result = Citizen.Await(mgPromise)
    mgPromise = nil
    UI.setFocus(false)
    return result == true
end

RegisterNUICallback('minigame', function(data, cb)
    cb(1)
    if mgPromise then mgPromise:resolve(data.success == true) end
end)

--[[ HUD ]]
function UI.hud(data)
    UI.send('hud', data)
end

--[[ generic close from NUI (escape key) ]]
RegisterNUICallback('close', function(data, cb)
    cb(1)
    if data and data.what == 'minigame' and mgPromise then
        mgPromise:resolve(false)
    elseif data and data.what == 'menu' then
        Menu.close()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if UI.focus then SetNuiFocus(false, false) end
end)
