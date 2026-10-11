-- Notifications, progress bars and text prompts in the HUD's style.
-- Nothing here runs until something calls it: no loops while idle.
local UI = Config.UI

local function strip(s)
    -- GTA colour codes (~r~, ~h~ ...) from framework messages; the HUD colours by type instead
    return (tostring(s or ''):gsub('~[%a]~', ''))
end

local TYPES = { success = 'success', error = 'error', warning = 'warning', info = 'info',
    inform = 'info', primary = 'info', police = 'info', ambulance = 'info', warn = 'warning', danger = 'error' }

-- ─── notifications ─────────────────────────────────────────
--- Notify({ title, message|description|text, type, duration, icon }) or Notify(text, type, duration, title)
function NHUD.notify(data, kind, duration, title)
    if type(data) ~= 'table' then
        data = { message = data, type = kind, duration = duration, title = title }
    end
    local msg = data.message or data.description or data.text or data.msg
    if (msg == nil or msg == '') and not data.title then return end
    NHUD.send('notify', {
        title = data.title and strip(data.title) or nil,
        message = msg and strip(msg) or nil,
        kind = TYPES[data.type or data.kind or 'info'] or 'info',
        duration = math.max(1000, math.min(tonumber(data.duration or data.length) or UI.Notify.Duration, 30000)),
        icon = data.icon,
    })
end

exports('Notify', NHUD.notify)
RegisterNetEvent('nhud:notify', NHUD.notify)        -- server: TriggerClientEvent('nhud:notify', src, { ... })
AddEventHandler('nayzeee-hud:notify', NHUD.notify)  -- client scripts: TriggerEvent('nayzeee-hud:notify', { ... })

-- ─── progress bar ──────────────────────────────────────────
local progress = nil
local progressOk = false

local DISABLE = {
    move = { 21, 22, 30, 31, 36, 44 },
    car = { 59, 60, 63, 64, 71, 72, 75 },
    combat = { 24, 25, 37, 47, 58, 140, 141, 142, 143, 257, 263, 264 },
    mouse = { 1, 2, 106 },
}

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    model = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(model) and model or nil
end

local function attachProp(ped, p)
    local model = loadModel(p.model)
    if not model then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, true)
    local pos, rot = p.pos or p.coords or vec3(0, 0, 0), p.rot or p.rotation or vec3(0, 0, 0)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, p.bone or 60309), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
        true, true, false, true, 0, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

-- qb progressbar tables ({ name, label, duration, controlDisables, animation, prop }) map onto ours
local function fromQB(d)
    local cd, an = d.controlDisables or {}, d.animation or {}
    return {
        label = d.label, duration = d.duration, canCancel = d.canCancel, useWhileDead = d.useWhileDead, icon = d.icon,
        disable = { move = cd.disableMovement, car = cd.disableCarMovement, combat = cd.disableCombat, mouse = cd.disableMouse },
        anim = (an.animDict and { dict = an.animDict, clip = an.anim, flag = an.flags }) or (an.task and { scenario = an.task }) or nil,
        prop = d.prop and d.prop.model and { model = d.prop.model, bone = d.prop.bone, pos = d.prop.coords, rot = d.prop.rotation } or nil,
        prop2 = d.propTwo and d.propTwo.model and { model = d.propTwo.model, bone = d.propTwo.bone, pos = d.propTwo.coords, rot = d.propTwo.rotation } or nil,
    }
end

--- Blocks until done. Returns true when it finished, false when cancelled.
--- { label, duration, canCancel, useWhileDead, allowRagdoll, icon,
---   maxMove (cancel when the ped walks further than this many metres), disable = { move, car, combat, mouse }, anim = { dict, clip, flag } | { scenario }, prop = { model, bone, pos, rot }, prop2 }
function NHUD.progress(d, cb)
    if type(d) ~= 'table' or progress then
        if cb then cb(true) end
        return false
    end
    if d.controlDisables or d.animation or (d.name and d.label and cb) then d = fromQB(d) end
    -- with a callback (qb style) return straight away like qb's progressbar does; without one, block and return the result
    if cb then
        CreateThread(function() NHUD.progress(d, nil) cb(not progressOk) end)
        return
    end

    local duration = math.max(100, tonumber(d.duration) or 1000)
    local ped = cache.ped
    local state = { cancelled = false }
    progress = state

    if d.anim then
        if d.anim.scenario then
            TaskStartScenarioInPlace(ped, d.anim.scenario, 0, true)
        elseif d.anim.dict and loadDict(d.anim.dict) then
            TaskPlayAnim(ped, d.anim.dict, d.anim.clip, d.anim.blendIn or 3.0, d.anim.blendOut or 3.0, -1, d.anim.flag or 49, 0, false, false, false)
        end
    end
    local props = {}
    if d.prop then props[#props + 1] = attachProp(ped, d.prop) end
    if d.prop2 then props[#props + 1] = attachProp(ped, d.prop2) end

    local cancelKey = UI.Progress.CancelKey
    NHUD.send('progress', { label = d.label and strip(d.label) or '', duration = duration, icon = d.icon,
        cancel = d.canCancel and UI.Progress.CancelLabel or false })

    local disable = {}
    for key, on in pairs(d.disable or {}) do
        if on and DISABLE[key] then
            for _, c in ipairs(DISABLE[key]) do disable[#disable + 1] = c end
        end
    end

    local endAt = GetGameTimer() + duration
    local start, maxMove, frame = GetEntityCoords(ped), tonumber(d.maxMove), 0
    while GetGameTimer() < endAt and not state.cancelled do
        frame = frame + 1
        if maxMove and frame % 10 == 0 and #(GetEntityCoords(ped) - start) > maxMove then state.cancelled = true end
        for i = 1, #disable do DisableControlAction(0, disable[i], true) end
        if d.canCancel and IsControlJustPressed(0, cancelKey) then state.cancelled = true end
        if not d.useWhileDead and IsEntityDead(ped) then state.cancelled = true end
        if not d.allowRagdoll and IsPedRagdoll(ped) then state.cancelled = true end
        Wait(0)
    end

    if d.anim then
        if d.anim.dict then StopAnimTask(ped, d.anim.dict, d.anim.clip, 1.0) else ClearPedTasks(ped) end
    end
    for i = 1, #props do
        if props[i] and DoesEntityExist(props[i]) then DetachEntity(props[i], true, true) DeleteEntity(props[i]) end
    end

    NHUD.send('progress', { done = true, cancelled = state.cancelled })
    progress = nil
    progressOk = not state.cancelled
    return progressOk
end

function NHUD.progressActive() return progress ~= nil end
function NHUD.cancelProgress() if progress then progress.cancelled = true end end

exports('Progress', NHUD.progress)
exports('ProgressActive', NHUD.progressActive)
exports('CancelProgress', NHUD.cancelProgress)

-- ─── text prompts ──────────────────────────────────────────
local textOpen = false

--- ShowTextUI('Open the door', { key = 'E', icon = 'door', position = 'left' })
function NHUD.showText(text, opts)
    opts = type(opts) == 'table' and opts or {}
    textOpen = true
    NHUD.send('textui', { text = strip(text), key = opts.key, icon = opts.icon, position = opts.position })
end

function NHUD.hideText()
    if not textOpen then return end
    textOpen = false
    NHUD.send('textui', { hide = true })
end

exports('ShowTextUI', NHUD.showText)
exports('HideTextUI', NHUD.hideText)
exports('IsTextUIOpen', function() return textOpen end)

-- qb-core DrawText events, for scripts that trigger them directly
if UI.TextUI.QBEvents then
    RegisterNetEvent('qb-core:client:DrawText', function(text, position) NHUD.showText(text, { position = position }) end)
    RegisterNetEvent('qb-core:client:ChangeText', function(text, position) NHUD.showText(text, { position = position }) end)
    RegisterNetEvent('qb-core:client:HideText', NHUD.hideText)
    RegisterNetEvent('qb-core:client:KeyPressed', NHUD.hideText)
end

-- quick test: /hudtest notify | progress | text
if UI.TestCommand then
    RegisterCommand('hudtest', function(_, args)
        local what = args[1] or 'notify'
        if what == 'notify' then
            NHUD.notify({ title = 'Garage', message = 'Your vehicle is ready at Legion Square.', type = 'success' })
            NHUD.notify({ message = 'You do not have enough cash.', type = 'error' })
            NHUD.notify({ title = 'Storm warning', message = 'Heavy rain coming in from the coast.', type = 'warning' })
        elseif what == 'progress' then
            CreateThread(function()
                local ok = NHUD.progress({ label = 'Picking the lock', duration = 5000, canCancel = true,
                    disable = { move = true, combat = true }, anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 } })
                NHUD.notify(ok and 'Done' or 'Cancelled', ok and 'success' or 'error')
            end)
        elseif what == 'text' then
            NHUD.showText('Open the stash', { key = 'E' })
            SetTimeout(5000, NHUD.hideText)
        end
    end, false)
end
