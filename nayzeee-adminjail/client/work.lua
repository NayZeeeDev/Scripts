--[[ Work program — per-frame only while within viewDistance of the current task ]]

Work = {}

local Event = AJ.Event
local cfg = Config.Work

local state      -- latest work state from the server
local blip
local running = false
local busy = false
local prompt = false
local refreshTimer = 0

local BLOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 140, 141, 142, 257, 263, 264 }

local function setPrompt(label)
    if (label ~= nil) == prompt then return end
    prompt = label ~= nil
    if Config.Progress == 'nayzeee' then
        Hud.Prompt(label)
    elseif label then
        lib.showTextUI(locale('work_prompt', label), { position = 'right-center' })
    else
        lib.hideTextUI()
    end
end

local function removeBlip()
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
end

local function setBlip(coords)
    removeBlip()
    if not cfg.blip then return end
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 566)
    SetBlipColour(blip, 2)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Work task')
    EndTextCommandSetBlipName(blip)
end

local function drawMarker(c, dist)
    local t = GetGameTimer()
    local bob = math.sin(t / 350) * 0.12
    local pulse = 0.5 + math.sin(t / 220) * 0.5
    local near = dist <= cfg.interactDistance
    local a = near and 235 or 190

    DrawMarker(0, c.x, c.y, c.z + 1.05 + bob, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.32, 0.32, 0.32, 8, 175, 162, a, false, false, 2, true, nil, nil, false)
    DrawMarker(25, c.x, c.y, c.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        1.25, 1.25, 1.25, 8, 175, 162, near and 170 or 110, false, false, 2, true, nil, nil, false)
    -- outer ripple
    local r = 1.3 + pulse * 0.55
    DrawMarker(25, c.x, c.y, c.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        r, r, r, 15, 212, 196, math.floor(90 * (1.0 - pulse)), false, false, 2, false, nil, nil, false)
end

--[[ Animation, prop, particles ]]

local function startTask(ped, task)
    local handles = {}

    if task.scenario then
        TaskStartScenarioInPlace(ped, task.scenario, 0, true)
    elseif task.anim then
        handles.dict = lib.requestAnimDict(task.anim.dict)
        TaskPlayAnim(ped, handles.dict, task.anim.clip, 3.0, -3.0, -1, task.anim.flag or 1, 0, false, false, false)
    end

    if task.prop then
        local model = lib.requestModel(task.prop.model)
        local c = GetEntityCoords(ped)
        local prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, false, false)
        local pos, rot = task.prop.pos, task.prop.rot
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, task.prop.bone), pos.x, pos.y, pos.z,
            rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(model)
        handles.prop = prop
    end

    if task.ptfx then
        local fx = task.ptfx
        if pcall(lib.requestNamedPtfxAsset, fx.asset, 1500) then
            UseParticleFxAssetNextCall(fx.asset)
            local o = fx.offset or vec3(0.0, 0.0, 0.0)
            handles.ptfx = StartParticleFxLoopedOnEntity(fx.name, ped, o.x, o.y, o.z, 0.0, 0.0, 0.0, fx.scale or 1.0, false, false, false)
            handles.asset = fx.asset
        end
    end

    return handles
end

local function stopTask(ped, task, h)
    if task.scenario then ClearPedTasks(ped) else StopAnimTask(ped, h.dict, task.anim.clip, 2.0) end
    if h.dict then RemoveAnimDict(h.dict) end
    if h.prop and DoesEntityExist(h.prop) then DeleteEntity(h.prop) end
    if h.ptfx then StopParticleFxLooped(h.ptfx, false) end
    if h.asset then RemoveNamedPtfxAsset(h.asset) end
end

--- Built-in progress (NUI ring). Movement/combat are blocked only while it runs.
local function progress(task, point)
    if Config.Progress ~= 'nayzeee' then
        local fn = Config.Progress == 'bar' and lib.progressBar or lib.progressCircle
        return fn({
            duration = task.duration, label = task.label, position = 'bottom', canCancel = true,
            disable = { move = true, car = true, combat = true },
        })
    end

    Hud.Task({ label = task.label, icon = task.icon, duration = task.duration, step = state.step + 1, of = state.of })
    local started = GetGameTimer()
    local ped = cache.ped
    while GetGameTimer() - started < task.duration do
        for i = 1, #BLOCKED do DisableControlAction(0, BLOCKED[i], true) end
        if IsControlJustPressed(0, cfg.cancelKey) or IsEntityDead(ped) or Jail.Phase() ~= 'active' then
            return false
        end
        Wait(0)
    end
    return true
end

local function perform(point)
    busy = true
    setPrompt(nil)

    if not lib.callback.await(Event('server:work:begin'), false, point.index) then
        busy = false
        return
    end

    local task = cfg.tasks[point.task] or cfg.tasks.sweep
    local ped = cache.ped

    TaskTurnPedToFaceCoord(ped, point.coords.x, point.coords.y, point.coords.z, 500)
    Wait(450)

    local handles = startTask(ped, task)
    local done = progress(task, point)
    stopTask(ped, task, handles)

    if not done then
        TriggerServerEvent(Event('server:work:cancel'))
        Hud.TaskEnd(false)
        busy = false
        return
    end

    local res = lib.callback.await(Event('server:work:finish'), false, point.index)
    if res and res.ok then
        Fx.TaskDone(res.cycle)
        Hud.TaskEnd(true, { cycle = res.cycle, reduction = res.reduction })
        if res.cycle then
            Bridge.Notify(locale('work_cycle', res.reduction), 'success')
            Hud.Flash('teal', ('-%d min'):format(res.reduction))
        end
    else
        Hud.TaskEnd(false)
        if res and res.moved then Bridge.Notify(locale('work_moved'), 'error') end
    end
    busy = false
end

local function loop()
    if running then return end
    running = true
    CreateThread(function()
        while state and state.point and Jail.Phase() ~= 'idle' do
            local point = state.point
            local dist = #(GetEntityCoords(cache.ped) - point.coords)

            if dist > cfg.viewDistance or busy or Jail.Phase() ~= 'active' then
                setPrompt(nil)
                Wait(dist > cfg.viewDistance * 2 and 1000 or 500)
            else
                drawMarker(point.coords, dist)
                if dist <= cfg.interactDistance then
                    setPrompt(point.label)
                    if IsControlJustReleased(0, 38) then perform(point) end
                else
                    setPrompt(nil)
                end
                Wait(0)
            end
        end
        setPrompt(nil)
        running = false
    end)
end

RegisterNetEvent(Event('client:work'), function(data)
    if Jail.Phase() == 'idle' or not cfg.enabled then return end
    state = data
    Hud.Work(data)

    if data.locked then
        removeBlip()
        refreshTimer = refreshTimer + 1
        local mine = refreshTimer
        SetTimeout((data.resetIn + 2) * 1000, function()
            if mine == refreshTimer and Jail.Phase() ~= 'idle' then
                TriggerServerEvent(Event('server:work:refresh'))
            end
        end)
        return
    end

    if data.point then
        setBlip(data.point.coords)
        loop()
    end
end)

function Work.Stop()
    state = nil
    refreshTimer = refreshTimer + 1
    removeBlip()
    setPrompt(nil)
    if busy then
        if lib.progressActive() then lib.cancelProgress() end
        ClearPedTasks(cache.ped)
        Hud.TaskEnd(false)
    end
end
