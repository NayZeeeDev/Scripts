-- Client bridge: notify, progress, target. Edit freely.
Bridge = {}

function Bridge.Notify(msg, kind) Config.Notify(msg, kind) end

-- Plays an animation for `duration` ms. Returns true if it finished.
function Bridge.Progress(label, anim, duration)
    if GetResourceState('ox_lib') == 'started' then
        local ok, res = pcall(function()
            return exports.ox_lib:progressBar({
                duration = duration, label = label, canCancel = true, useWhileDead = false,
                disable = { move = true, car = true, combat = true },
                anim = anim and { dict = anim.dict, clip = anim.clip, flag = anim.flag } or nil,
            })
        end)
        if ok then return res end
    end
    local ped = PlayerPedId()
    if anim then
        RequestAnimDict(anim.dict)
        local t = GetGameTimer()
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() - t < 3000 do Wait(0) end
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, duration, anim.flag or 1, 0, false, false, false)
    end
    local t = GetGameTimer()
    while GetGameTimer() - t < duration do
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
        if IsEntityDead(ped) then ClearPedTasks(ped) return false end
        Wait(0)
    end
    if anim then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
    return true
end

local targetRes
if Config.Target == 'auto' then
    if GetResourceState('ox_target') == 'started' then targetRes = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then targetRes = 'qb-target' end
elseif Config.Target ~= 'none' then
    targetRes = Config.Target
end
Bridge.Target = targetRes

-- options: { { name, label, icon, action(entity), canInteract(entity) } }
function Bridge.AddModelTarget(models, options)
    if targetRes == 'ox_target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                name = o.name, label = o.label, icon = o.icon, distance = Config.Actions.useRange,
                canInteract = function(entity) return o.canInteract(entity) end,
                onSelect = function(data) o.action(data.entity) end,
            }
        end
        exports.ox_target:addModel(models, list)
    elseif targetRes == 'qb-target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                label = o.label, icon = o.icon,
                canInteract = function(entity) return o.canInteract(entity) end,
                action = function(entity) o.action(entity) end,
            }
        end
        exports['qb-target']:AddTargetModel(models, { options = list, distance = Config.Actions.useRange })
    end
end

function Bridge.RemoveModelTarget(models, names)
    if targetRes == 'ox_target' then exports.ox_target:removeModel(models, names)
    elseif targetRes == 'qb-target' then exports['qb-target']:RemoveTargetModel(models) end
end
