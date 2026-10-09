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

local function hidePrompt()
    if prompt then
        lib.hideTextUI()
        prompt = false
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
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 2)
    SetBlipScale(blip, 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Work task')
    EndTextCommandSetBlipName(blip)
end

local function drawMarker(c)
    local bob = math.sin(GetGameTimer() / 350) * 0.12
    DrawMarker(0, c.x, c.y, c.z + 1.05 + bob, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.35, 0.35, 0.35, 8, 175, 162, 210, false, false, 2, true, nil, nil, false)
    DrawMarker(25, c.x, c.y, c.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        1.3, 1.3, 1.3, 8, 175, 162, 120, false, false, 2, false, nil, nil, false)
end

local function perform(point)
    busy = true
    hidePrompt()

    if not lib.callback.await(Event('server:work:begin'), false, point.index) then
        busy = false
        return
    end

    local task = cfg.tasks[point.task] or cfg.tasks.sweep
    local ped = cache.ped
    local prop

    TaskTurnPedToFaceCoord(ped, point.coords.x, point.coords.y, point.coords.z, 600)
    Wait(400)

    if task.scenario then
        TaskStartScenarioInPlace(ped, task.scenario, 0, true)
    elseif task.anim then
        local dict = lib.requestAnimDict(task.anim.dict)
        TaskPlayAnim(ped, dict, task.anim.clip, 8.0, -8.0, -1, task.anim.flag or 49, 0, false, false, false)
        RemoveAnimDict(dict)
    end

    if task.prop then
        local model = lib.requestModel(task.prop.model)
        local c = GetEntityCoords(ped)
        prop = CreateObject(model, c.x, c.y, c.z, true, false, false)
        local pos, rot = task.prop.pos, task.prop.rot
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, task.prop.bone), pos.x, pos.y, pos.z,
            rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(model)
    end

    local progress = Config.Progress == 'bar' and lib.progressBar or lib.progressCircle
    local done = progress({
        duration = task.duration,
        label = task.label,
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(ped)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end

    if not done then
        TriggerServerEvent(Event('server:work:cancel'))
        busy = false
        return
    end

    local res = lib.callback.await(Event('server:work:finish'), false, point.index)
    if res and res.ok and res.cycle then
        Bridge.Notify(locale('work_cycle', res.reduction), 'success')
        Hud.Flash('teal', ('-%d min'):format(res.reduction))
    elseif res and res.moved then
        Bridge.Notify(locale('work_moved'), 'error')
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
                hidePrompt()
                Wait(dist > cfg.viewDistance * 2 and 1000 or 500)
            else
                drawMarker(point.coords)
                if dist <= cfg.interactDistance then
                    if not prompt then
                        lib.showTextUI(locale('work_prompt', point.label), { position = 'right-center' })
                        prompt = true
                    end
                    if IsControlJustReleased(0, 38) then perform(point) end
                else
                    hidePrompt()
                end
                Wait(0)
            end
        end
        hidePrompt()
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
    hidePrompt()
    if busy then
        if lib.progressActive() then lib.cancelProgress() end
        ClearPedTasks(cache.ped)
    end
end
