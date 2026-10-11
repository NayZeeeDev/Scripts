--[[
    Client bridge: framework job data, vehicle properties, notify, text UI, target and progress.
]]

Bridge = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') == 'started' then fw = 'qbx'
    elseif GetResourceState('es_extended') == 'started' then fw = 'esx'
    elseif GetResourceState('qb-core') == 'started' then fw = 'qb'
    else fw = 'none' end
end
Bridge.Framework = fw

local ESX, QB
if fw == 'esx' then ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then QB = exports['qb-core']:GetCoreObject() end

local target = Config.Target
if target == 'auto' then
    if GetResourceState('ox_target') == 'started' then target = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then target = 'qb-target'
    else target = 'none' end
end
Bridge.Target = target

--------------------------------------------------------------------- job

Bridge.Job = { name = 'none', grade = 0, onDuty = false }

local function setEsxJob(j)
    if not j then return end
    Bridge.Job = { name = j.name, grade = j.grade, label = j.label, gradeLabel = j.grade_label, onDuty = j.onDuty ~= false }
    TriggerEvent('nayzeee-tuning:jobChanged', Bridge.Job)
end

local function setQbJob(j)
    if not j then return end
    Bridge.Job = { name = j.name, grade = j.grade and j.grade.level or 0, label = j.label, gradeLabel = j.grade and j.grade.name, onDuty = j.onduty ~= false }
    TriggerEvent('nayzeee-tuning:jobChanged', Bridge.Job)
end

if fw == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function(data) setEsxJob(data.job) end)
    RegisterNetEvent('esx:setJob', function(job) setEsxJob(job) end)
    CreateThread(function()
        local data = ESX.GetPlayerData()
        if data and data.job then setEsxJob(data.job) end
    end)
elseif fw == 'qb' or fw == 'qbx' then
    local function pull()
        local data = fw == 'qbx' and exports.qbx_core:GetPlayerData() or QB.Functions.GetPlayerData()
        if data and data.job then setQbJob(data.job) end
    end
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', pull)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) setQbJob(job) end)
    RegisterNetEvent('QBCore:Client:SetDuty', function(duty) Bridge.Job.onDuty = duty TriggerEvent('nayzeee-tuning:jobChanged', Bridge.Job) end)
    CreateThread(pull)
end

--------------------------------------------------------------------- vehicle properties

function Bridge.GetProps(veh)
    if fw == 'esx' then return ESX.Game.GetVehicleProperties(veh) end
    if fw == 'qb' then return QB.Functions.GetVehicleProperties(veh) end
    return lib.getVehicleProperties(veh)
end

function Bridge.SetProps(veh, props)
    if not props then return end
    if fw == 'esx' then return ESX.Game.SetVehicleProperties(veh, props) end
    if fw == 'qb' then return QB.Functions.SetVehicleProperties(veh, props) end
    -- ox_lib refuses vehicles this client doesn't own (mechanic on a customer's car): never abort the caller
    local ok, err = pcall(lib.setVehicleProperties, veh, props)
    if not ok then NZ.Debug('SetProps: ' .. tostring(err)) end
    return ok
end

--------------------------------------------------------------------- feedback

function Bridge.Notify(msg, kind, duration)
    kind = kind or 'inform'
    if Config.Notify == 'framework' then
        if fw == 'esx' then return ESX.ShowNotification(msg) end
        if fw == 'qb' then return QB.Functions.Notify(msg, kind == 'inform' and 'primary' or kind, duration) end
    elseif Config.Notify == 'custom' then
        -- exports['your-notify']:Notify(msg, kind, duration)
    end
    lib.notify({ description = msg, type = kind, duration = duration or 5000, position = 'top-right' })
end

function Bridge.TextUI(text)
    if Config.TextUI == 'custom' then return end
    if text then lib.showTextUI(text, { position = 'left-center' }) else lib.hideTextUI() end
end

-- returns true when finished, false when cancelled
function Bridge.Progress(label, duration, anim, prop, canCancel)
    return lib.progressCircle({
        label = label, duration = duration, position = 'bottom', useWhileDead = false,
        canCancel = canCancel ~= false,
        disable = { move = true, car = true, combat = true },
        anim = anim and { dict = anim[1], clip = anim[2], flag = anim[3] or 49 } or nil,
        prop = prop,
    })
end

function Bridge.SkillCheck(difficulty)
    if not Config.Orders.SkillChecks then return true end
    return lib.skillCheck(difficulty or Config.Orders.Difficulty, { 'e' })
end

-- hide HUD resources while the tuning camera is active
function Bridge.HideHud(state)
    DisplayRadar(not state)
    if GetResourceState('nayzeee-hud') == 'started' then pcall(function() exports['nayzeee-hud']:Display(not state) end) end
end

--------------------------------------------------------------------- target

local zones, globalLabels = {}, {}

-- options: { { name, label, icon, canInteract = fn, onSelect = fn } }
function Bridge.AddSphere(name, coords, radius, options)
    if target == 'ox_target' then
        zones[name] = exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = options })
        return true
    elseif target == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { label = o.label, icon = 'fa-solid ' .. (o.icon or 'fa-circle'), action = function() o.onSelect() end, canInteract = o.canInteract }
        end
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = Config.Debug, useZ = true }, { options = opts, distance = 2.0 })
        zones[name] = name
        return true
    end
    return false
end

function Bridge.RemoveZone(name)
    local z = zones[name]
    if not z then return end
    if target == 'ox_target' then exports.ox_target:removeZone(z)
    elseif target == 'qb-target' then exports['qb-target']:RemoveZone(z) end
    zones[name] = nil
end

function Bridge.AddGlobalVehicle(options)
    if target == 'ox_target' then
        exports.ox_target:addGlobalVehicle(options)
        return true
    elseif target == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do
            globalLabels[o.name] = o.label
            opts[i] = { label = o.label, icon = 'fa-solid ' .. (o.icon or 'fa-circle'),
                action = function(entity) o.onSelect({ entity = entity }) end,
                canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil }
        end
        exports['qb-target']:AddGlobalVehicle({ options = opts, distance = 2.5 })
        return true
    end
    return false
end

function Bridge.RemoveGlobalVehicle(names)
    if target == 'ox_target' then exports.ox_target:removeGlobalVehicle(names)
    elseif target == 'qb-target' then
        local labels = {}
        for _, n in ipairs(names) do labels[#labels + 1] = globalLabels[n] or n end
        pcall(function() exports['qb-target']:RemoveGlobalVehicle(labels) end)
    end
end
