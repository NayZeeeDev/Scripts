--[[ NUI bridge — NAYZEEE UI v3 panels, toasts and progress ]]

UI = {}
local pending

-- server callbacks the NUI may call directly (everything else is refused)
local allowed = {
    ['nzmw:books:submit'] = true,
    ['nzmw:audit:start'] = true,
    ['nzmw:dirtySources'] = true,
}

function UI.init()
    SendNUIMessage({ action = 'init', theme = Config.UI, labels = Config.ItemLabels })
end

-- Blocking panel: returns whatever the NUI submits, or nil if closed
function UI.await(panel, data, opts)
    if pending then return nil end
    opts = opts or {}
    pending = promise.new()
    SetNuiFocus(true, opts.cursor ~= false)
    SendNUIMessage({ action = 'open', panel = panel, data = data })
    local res = Citizen.Await(pending)
    pending = nil
    return res
end

function UI.isOpen() return pending ~= nil end

function UI.close()
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    if pending then pending:resolve(nil) end
end

RegisterNUICallback('result', function(d, cb)
    cb(1)
    if not d.keep then SetNuiFocus(false, false) end
    if pending then pending:resolve(d.result) end
end)

RegisterNUICallback('request', function(d, cb)
    if type(d) ~= 'table' or not allowed[d.name] then return cb({ ok = false, err = 'Not allowed.' }) end
    local args = d.args or {}
    cb(lib.callback.await(d.name, false, table.unpack(args)) or { ok = false, err = 'No response.' })
end)

function UI.toast(title, message, kind, duration)
    if Config.Notify == 'ox' then
        lib.notify({ title = title, description = message, type = kind == 'success' and 'success' or kind == 'error' and 'error' or 'inform', duration = duration })
        return
    end
    SendNUIMessage({ action = 'toast', title = title, message = message, type = kind or 'info', duration = duration or 5000 })
end

function UI.err(res, fallback)
    UI.toast('Not now', (res and res.err) or fallback or 'Something went wrong.', 'error')
end

RegisterNetEvent('nzmw:notify', function(d)
    UI.toast(d.title, d.message, d.type, d.duration)
end)

-- Progress bar in house style. Returns false if cancelled with [X].
function UI.progress(label, duration, opts)
    opts = opts or {}
    SendNUIMessage({ action = 'progress', label = label, duration = duration })
    local endAt = GetGameTimer() + duration
    local ok = true
    while GetGameTimer() < endAt do
        DisableControlAction(0, 21, true) -- sprint
        DisableControlAction(0, 22, true) -- jump
        DisableControlAction(0, 24, true) -- attack
        DisableControlAction(0, 25, true) -- aim
        DisableControlAction(0, 30, true) -- move LR
        DisableControlAction(0, 31, true) -- move UD
        DisableControlAction(0, 44, true) -- cover
        if opts.canCancel ~= false and (IsControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 73)) then
            ok = false
            break
        end
        if IsEntityDead(PlayerPedId()) then ok = false break end
        Wait(0)
    end
    SendNUIMessage({ action = 'progressEnd', ok = ok })
    return ok
end

-- Small persistent hint line (e.g. placement controls)
function UI.hint(text)
    SendNUIMessage({ action = 'hint', text = text })
end
