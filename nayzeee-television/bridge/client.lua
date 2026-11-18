--[[ Framework / target bridge (client) ]]

Bridge = { target = 'none' }

local function started(res) return GetResourceState(res) == 'started' end

CreateThread(function()
    local t = Config.Target
    if t == 'auto' then
        if started('ox_target') then t = 'ox_target'
        elseif started('qb-target') then t = 'qb-target'
        else t = 'none' end
    end
    Bridge.target = t
end)

--- options: list of { label, icon, action = function(entity) end, canInteract = function(entity) end }
function Bridge.addEntityTarget(entity, options)
    if Bridge.target == 'ox_target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = 'nztv_' .. i, label = o.label, icon = o.icon, distance = Config.Interact.Distance,
                onSelect = function(data) o.action(data.entity) end,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
            }
        end
        exports.ox_target:addLocalEntity(entity, opts)
        return true
    elseif Bridge.target == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                label = o.label, icon = o.icon,
                action = function(ent) o.action(ent) end,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
            }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = opts, distance = Config.Interact.Distance })
        return true
    end
    return false
end

function Bridge.removeEntityTarget(entity)
    if Bridge.target == 'ox_target' then
        exports.ox_target:removeLocalEntity(entity)
    elseif Bridge.target == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity)
    end
end

-- refresh admin flag / data when a character loads
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() TriggerEvent('nztv:client:reboot') end)
RegisterNetEvent('esx:playerLoaded', function() TriggerEvent('nztv:client:reboot') end)
