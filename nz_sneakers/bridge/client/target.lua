Target = {}

--- options: { { name, label, icon, canInteract(entity), onSelect(entity) }, ... }
function Target.AddModel(model, options)
    if GetResourceState('ox_target') ~= 'started' then
        print('^1[nz_sneakers]^7 ox_target is not running - box interactions are disabled')
        return
    end
    local list = {}
    for _, o in ipairs(options) do
        list[#list + 1] = {
            name = o.name,
            label = o.label,
            icon = o.icon,
            distance = Config.Box.interactDistance,
            canInteract = function(entity) return o.canInteract == nil or o.canInteract(entity) end,
            onSelect = function(data) o.onSelect(data.entity) end,
        }
    end
    exports.ox_target:addModel(model, list)
end

function Target.RemoveModel(model, names)
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeModel(model, names)
    end
end
