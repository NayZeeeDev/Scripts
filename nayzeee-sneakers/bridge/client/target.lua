--[[
    THIRD EYE / INTERACTION   Config.Target
    options = { { name, label, icon, canInteract(entity), onSelect(entity) }, ... }

    'textui' (or no target resource) falls back to a key prompt on the nearest
    matching object or ped: one option runs straight away, several open a menu.
]]

Target = {}

local function running(r) return GetResourceState(r) == 'started' end

local function system()
    local want = Config.Target
    if want ~= 'auto' then return want end
    if running('ox_target') then return 'ox_target' end
    if running('qb-target') then return 'qb-target' end
    if running('interact') then return 'interact' end
    return 'textui'
end

local function allowed(o, entity) return o.canInteract == nil or o.canInteract(entity) end

local function asList(model) return type(model) == 'table' and model or { model } end

-- text UI fallback ---------------------------------------------------------------

local textModels = {}     -- [hash] = { options, distance }
local textEntities = {}   -- [entity] = { options, distance }
local textLoop = false

local function nearest()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local best, bestDist, bestDef
    local function consider(ent, def)
        local d = #(GetEntityCoords(ent) - pos)
        if d <= def.distance and (not bestDist or d < bestDist) then best, bestDist, bestDef = ent, d, def end
    end
    for ent, def in pairs(textEntities) do
        if DoesEntityExist(ent) then consider(ent, def) else textEntities[ent] = nil end
    end
    if next(textModels) then
        for _, pool in ipairs({ 'CObject', 'CPed' }) do
            for _, ent in ipairs(GetGamePool(pool)) do
                local def = textModels[GetEntityModel(ent) & 0xFFFFFFFF]
                if def then consider(ent, def) end
            end
        end
    end
    return best, bestDef
end

local function startTextLoop()
    if textLoop then return end
    textLoop = true
    CreateThread(function()
        local target, def, shown, nextScan = nil, nil, nil, 0
        while true do
            -- something else owns the screen (placing, crafting, a cinematic): stay out of its way
            while Busy do
                if shown then UI.Hint(nil) shown = nil end
                Wait(250)
            end
            local now = GetGameTimer()
            if now >= nextScan then
                target, def = nearest()
                nextScan = now + 250
            end
            local list = {}
            if target then
                for _, o in ipairs(def.options) do if allowed(o, target) then list[#list + 1] = o end end
            end
            local label = #list == 1 and list[1].label or (#list > 1 and 'Options' or nil)
            local text = label and ('%s %s'):format(Config.Interact.KeyLabel, label) or nil
            if text ~= shown then UI.Hint(text) shown = text end
            if label and IsControlJustPressed(0, Config.Interact.Key) then
                UI.Hint(nil) shown = nil
                local ent = target
                if #list == 1 then
                    list[1].onSelect(ent)
                else
                    local menu = {}
                    for i, o in ipairs(list) do menu[i] = { id = i, label = o.label } end
                    local pick = UI.Menu({ title = 'Options', options = menu })
                    if pick and list[pick] then list[pick].onSelect(ent) end
                end
            end
            Wait(label and 0 or 200)
        end
    end)
end

-- public ------------------------------------------------------------------------

--- extra = { offset = vector3 (where interact draws the prompt), ignoreLos = true (interact: no need
--- to look straight at it - for low things like boxes on the floor) }
function Target.AddModel(model, options, distance, extra)
    extra = extra or {}
    distance = distance or Config.Box.interactDistance
    local sys = system()
    if sys == 'ox_target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                name = o.name, label = o.label, icon = o.icon, distance = distance,
                canInteract = function(entity) return allowed(o, entity) end,
                onSelect = function(data) o.onSelect(data.entity) end,
            }
        end
        exports.ox_target:addModel(model, list)
    elseif sys == 'qb-target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                type = 'client', icon = o.icon, label = o.label,
                action = function(entity) o.onSelect(entity) end,
                canInteract = function(entity) return allowed(o, entity) end,
            }
        end
        exports['qb-target']:AddTargetModel(model, { options = list, distance = distance })
    elseif sys == 'interact' then
        for _, m in ipairs(asList(model)) do
            local list = {}
            for _, o in ipairs(options) do
                list[#list + 1] = {
                    label = o.label,
                    action = function(entity) o.onSelect(entity) end,
                    canInteract = function(entity) return allowed(o, entity) end,
                }
            end
            exports.interact:AddModelInteraction({
                model = m, id = ('nzs_%s_%s'):format(m, options[1].name), distance = distance + 6.0,
                interactDst = distance, options = list, offset = extra.offset, ignoreLos = extra.ignoreLos,
            })
        end
    else
        for _, m in ipairs(asList(model)) do
            local def = textModels[m & 0xFFFFFFFF] or { options = {}, distance = distance }
            for _, o in ipairs(options) do def.options[#def.options + 1] = o end
            textModels[m & 0xFFFFFFFF] = def
        end
        startTextLoop()
    end
end

--- Options on one entity (a handle this client has), e.g. the supplier, a buyer or a placed box.
--- extra = { offset, ignoreLos } as for Target.AddModel
function Target.AddEntity(entity, options, distance, extra)
    distance = distance or 2.5
    extra = extra or {}
    local sys = system()
    if sys == 'ox_target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                name = o.name, label = o.label, icon = o.icon, distance = distance,
                canInteract = function(ent) return allowed(o, ent) end,
                onSelect = function(data) o.onSelect(data.entity) end,
            }
        end
        exports.ox_target:addLocalEntity(entity, list)
    elseif sys == 'qb-target' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                type = 'client', icon = o.icon, label = o.label,
                action = function(ent) o.onSelect(ent) end,
                canInteract = function(ent) return allowed(o, ent) end,
            }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = list, distance = distance })
    elseif sys == 'interact' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = {
                label = o.label,
                action = function(ent) o.onSelect(ent) end,
                canInteract = function(ent) return allowed(o, ent) end,
            }
        end
        exports.interact:AddLocalEntityInteraction({
            entity = entity, id = ('nzs_ent_%s'):format(entity), name = options[1].name,
            distance = distance + 6.0, interactDst = distance, options = list,
            offset = extra.offset, ignoreLos = extra.ignoreLos,
        })
    else
        textEntities[entity] = { options = options, distance = distance }
        startTextLoop()
    end
end

function Target.RemoveEntity(entity)
    local sys = system()
    if sys == 'ox_target' then pcall(function() exports.ox_target:removeLocalEntity(entity) end)
    elseif sys == 'qb-target' then pcall(function() exports['qb-target']:RemoveTargetEntity(entity) end)
    elseif sys == 'interact' then pcall(function() exports.interact:RemoveLocalEntityInteraction(entity, ('nzs_ent_%s'):format(entity)) end)
    else textEntities[entity] = nil end
end

CreateThread(function()
    Wait(2000)
    print(('^5[nayzeee-sneakers]^7 target: %s'):format(system()))
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and system() == 'textui' then UI.Hint(nil) end
end)
