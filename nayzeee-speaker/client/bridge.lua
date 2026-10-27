-- Client bridge: notifications, progress bars, targets and a few game helpers. Edit freely.
Bridge = {}

function Bridge.Notify(msg, kind) Config.Notify(msg, kind) end

-- Plays an animation for `duration` ms (with ox_lib's progress bar when it runs). Returns true if it finished.
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
    local played = anim and Bridge.LoadAnimDict(anim.dict)
    if played then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, duration, anim.flag or 1, 0, false, false, false)
    end
    local t = GetGameTimer()
    while GetGameTimer() - t < duration do
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)   -- no walking off mid-task
        if IsEntityDead(ped) then ClearPedTasks(ped) return false end
        Wait(0)
    end
    if played then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
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

-- Targets on one local (non-networked) entity, e.g. a shopkeeper ped.
-- options: { { name, label, icon, action(entity), canInteract(entity)? } }
function Bridge.AddEntityTarget(entity, options, distance)
    distance = distance or Config.Actions.useRange
    if targetRes == 'ox_target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                name = o.name, label = o.label, icon = o.icon, distance = distance,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
                onSelect = function(data) o.action(data.entity) end,
            }
        end
        exports.ox_target:addLocalEntity(entity, list)
        return true
    elseif targetRes == 'qb-target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                label = o.label, icon = o.icon,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
                action = function(ent) o.action(ent) end,
            }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = list, distance = distance })
        return true
    end
    return false
end

function Bridge.RemoveEntityTarget(entity, names)
    if targetRes == 'ox_target' then
        pcall(function() exports.ox_target:removeLocalEntity(entity, names) end)
    elseif targetRes == 'qb-target' then
        pcall(function() exports['qb-target']:RemoveTargetEntity(entity) end)
    end
end

---------------------------------------------------------------- helpers (models, animations, shopkeepers, prompts)
-- Loads a model, returns its hash (nil if it isn't in the game files or didn't load in time).
function Bridge.LoadModel(model, timeout)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < (timeout or 5000) do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

-- Loads an animation dictionary. False if it isn't in the game (the 2.0 models ship no clips) or timed out.
function Bridge.LoadAnimDict(dict, timeout)
    if type(dict) ~= 'string' or not DoesAnimDictExist(dict) then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer()
    while not HasAnimDictLoaded(dict) and GetGameTimer() - t < (timeout or 3000) do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- A local shopkeeper standing still at `coords` (feet on the ground below it), facing `heading`.
function Bridge.SpawnShopPed(model, coords, heading, scenario)
    local hash = Bridge.LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    if scenario and scenario ~= '' then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    return ped
end

-- One frame of a small floating prompt (the [E] on speakers and record shops).
function Bridge.DrawPrompt(pos, text)
    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    SetTextScale(0.32, 0.32) SetTextFont(4) SetTextCentre(true) SetTextOutline()
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end
