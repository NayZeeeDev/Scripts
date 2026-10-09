Target = {}

local function ready()
    if GetResourceState('ox_target') == 'started' then return true end
    print('^1[nayzeee-sneakers]^7 ox_target is not running - interactions are disabled')
    return false
end

local function convert(options, distance)
    local list = {}
    for _, o in ipairs(options) do
        list[#list + 1] = {
            name = o.name,
            label = o.label,
            icon = o.icon,
            distance = distance or Config.Box.interactDistance,
            canInteract = function(entity) return o.canInteract == nil or o.canInteract(entity) end,
            onSelect = function(data) o.onSelect(data.entity) end,
        }
    end
    return list
end

--- options: { { name, label, icon, canInteract(entity), onSelect(entity) }, ... }
function Target.AddModel(model, options, distance)
    if not ready() then return end
    exports.ox_target:addModel(model, convert(options, distance))
end

function Target.RemoveModel(model, names)
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeModel(model, names)
    end
end

--- Options on one (local) entity, e.g. the supplier ped
function Target.AddEntity(entity, options, distance)
    if not ready() then return end
    exports.ox_target:addLocalEntity(entity, convert(options, distance))
end
