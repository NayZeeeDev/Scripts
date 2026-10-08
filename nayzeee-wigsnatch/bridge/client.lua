-- Client bridge: notifications, target systems, framework load events, restraint checks
-- Open source so you can plug in anything custom.

CB = {}

local TGT = Config.Target
if TGT == 'auto' then
    if GetResourceState('ox_target') == 'started' then TGT = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then TGT = 'qb-target'
    else TGT = 'none' end
end
CB.Target = TGT

local FW = Config.Framework
if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then FW = 'qbx'
    elseif GetResourceState('es_extended') == 'started' then FW = 'esx'
    elseif GetResourceState('qb-core') == 'started' then FW = 'qb'
    else FW = 'none' end
end
CB.Framework = FW

local ESX = FW == 'esx' and exports.es_extended:getSharedObject() or nil

-- notifications ----------------------------------------------------------------------

function CB.Notify(msg, kind, duration)
    Notifier.Send(msg, kind, duration)
end

-- framework load ---------------------------------------------------------------------------

function CB.OnLoaded(cb)
    if FW == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function() cb() end)
    else
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end
end

function CB.OnUnloaded(cb)
    if FW == 'esx' then
        RegisterNetEvent('esx:onPlayerLogout', function() cb() end)
    else
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() cb() end)
    end
end

function CB.IsLoaded()
    if FW == 'esx' then return ESX.IsPlayerLoaded() end
    if FW == 'qb' or FW == 'qbx' then return LocalPlayer.state.isLoggedIn == true end
    return true
end

-- target -------------------------------------------------------------------------------------
-- option = { name, label, icon, distance, item, canInteract = fn(entity), onSelect = fn(entity) }

local function oxOpts(options)
    local out = {}
    for i, o in ipairs(options) do
        out[i] = {
            name = o.name, label = o.label, icon = o.icon, distance = o.distance, items = o.item,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
            onSelect = function(data) o.onSelect(data.entity) end,
        }
    end
    return out
end

local function qbOpts(options)
    local out, dist = {}, 2.5
    for i, o in ipairs(options) do
        dist = o.distance or dist
        out[i] = {
            icon = o.icon, label = o.label, item = o.item,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
            action = function(entity) o.onSelect(entity) end,
        }
    end
    return { options = out, distance = dist }
end

function CB.AddGlobalPlayer(options)
    if #options == 0 then return end
    if TGT == 'ox_target' then exports.ox_target:addGlobalPlayer(oxOpts(options))
    elseif TGT == 'qb-target' then exports['qb-target']:AddGlobalPlayer(qbOpts(options)) end
end

function CB.RemoveGlobalPlayer(options)
    local names, labels = {}, {}
    for i, o in ipairs(options) do names[i], labels[i] = o.name, o.label end
    if TGT == 'ox_target' then exports.ox_target:removeGlobalPlayer(names)
    elseif TGT == 'qb-target' then exports['qb-target']:RemoveGlobalPlayer(labels) end
end

function CB.AddLocalEntity(entity, options)
    if TGT == 'ox_target' then exports.ox_target:addLocalEntity(entity, oxOpts(options))
    elseif TGT == 'qb-target' then exports['qb-target']:AddTargetEntity(entity, qbOpts(options)) end
end

function CB.RemoveLocalEntity(entity, options)
    if TGT == 'ox_target' then
        local names = {}
        for i, o in ipairs(options) do names[i] = o.name end
        exports.ox_target:removeLocalEntity(entity, names)
    elseif TGT == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity)
    end
end

-- restraint checks ------------------------------------------------------------------------------

local function stateOf(ped, serverId)
    if serverId then return Player(serverId).state end
    if ped == PlayerPedId() then return LocalPlayer.state end
end

-- cuffed, tied, held, tackled (or any Config.RestrainedStates key)
function CB.IsRestrained(ped, serverId)
    if IsPedCuffed(ped) then return true end
    local st = stateOf(ped, serverId)
    if st then
        for _, k in ipairs(Config.RestrainedStates) do if st[k] then return true end end
    end
    return false
end

function CB.IsDowned(ped, serverId)
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return true end
    local st = stateOf(ped, serverId)
    if st then
        for _, k in ipairs(Config.DownedStates) do if st[k] then return true end end
    end
    return false
end

function CB.HandsUp(ped)
    return IsEntityPlayingAnim(ped, Config.HandsUpAnim.dict, Config.HandsUpAnim.clip, 3)
end

-- anything that means "can't fight back"
function CB.Helpless(ped, serverId)
    return CB.IsRestrained(ped, serverId) or CB.HandsUp(ped) or CB.IsDowned(ped, serverId)
end
