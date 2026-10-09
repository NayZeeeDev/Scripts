-- Client bridge: framework load events, target systems.
-- Open source so you can plug in anything custom.

CB = {}

local FW = Config.Framework
if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then FW = 'qbx'
    elseif GetResourceState('es_extended') == 'started' then FW = 'esx'
    elseif GetResourceState('qb-core') == 'started' then FW = 'qb'
    else FW = 'none' end
end
CB.Framework = FW

local TGT = Config.Target
if TGT == 'auto' then
    if GetResourceState('ox_target') == 'started' then TGT = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then TGT = 'qb-target'
    else TGT = 'none' end
end
CB.Target = TGT

local ESX = FW == 'esx' and exports.es_extended:getSharedObject() or nil

function CB.Notify(msg, kind, duration)
    Config.Notify(msg, kind, duration)
end

function CB.OnLoaded(cb)
    if FW == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function() cb() end)
    elseif FW == 'qb' or FW == 'qbx' then
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end
end

function CB.IsLoaded()
    if FW == 'esx' then return ESX.IsPlayerLoaded() end
    if FW == 'qb' or FW == 'qbx' then return LocalPlayer.state.isLoggedIn == true end
    return true
end

-- target -------------------------------------------------------------------------------------
-- option = { name, label, icon, distance, canInteract = fn(entity), onSelect = fn(entity) }

local function oxOpts(options)
    local out = {}
    for i, o in ipairs(options) do
        out[i] = {
            name = o.name, label = o.label, icon = o.icon, distance = o.distance,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
            onSelect = function(data) o.onSelect(data.entity) end,
        }
    end
    return out
end

local function qbOpts(options)
    local out, dist = {}, 2.0
    for i, o in ipairs(options) do
        dist = o.distance or dist
        out[i] = {
            icon = o.icon, label = o.label,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
            action = function(entity) o.onSelect(entity) end,
        }
    end
    return { options = out, distance = dist }
end

function CB.AddPlayerOptions(options)
    if TGT == 'ox_target' then
        exports.ox_target:addGlobalPlayer(oxOpts(options))
    elseif TGT == 'qb-target' then
        exports['qb-target']:AddGlobalPlayer(qbOpts(options))
    end
end

function CB.RemovePlayerOptions(options)
    if TGT == 'ox_target' then
        local names = {}
        for i, o in ipairs(options) do names[i] = o.name end
        exports.ox_target:removeGlobalPlayer(names)
    elseif TGT == 'qb-target' then
        local labels = {}
        for i, o in ipairs(options) do labels[i] = o.label end
        exports['qb-target']:RemoveGlobalPlayer(labels)
    end
end

--- A sphere you can target (converted props have no collision, so we target a zone, not the entity).
function CB.AddSphere(name, coords, radius, options)
    if TGT == 'ox_target' then
        return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = oxOpts(options) })
    elseif TGT == 'qb-target' then
        local q = qbOpts(options)
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = Config.Debug, useZ = true }, q)
        return name
    end
end

function CB.RemoveSphere(id)
    if not id then return end
    if TGT == 'ox_target' then exports.ox_target:removeZone(id)
    elseif TGT == 'qb-target' then exports['qb-target']:RemoveZone(id) end
end
