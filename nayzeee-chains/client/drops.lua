-----------------------------------------------------------------
-- Chains on the ground: local props in range, picked up through
-- ox_target / qb-target, or an [E] prompt without a target script.
-----------------------------------------------------------------

local cfg = Config.Drops
local list = {}      -- [id] = data from the server
local props = {}     -- [id] = entity (only in range)
local zones = {}     -- [id] = target zone

local function v3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function label(d) return Chains.label(d.chain, d.variant) end

local function despawn(id)
    Util.delete(props[id])
    props[id] = nil
    if zones[id] then CB.RemoveSphere(zones[id]); zones[id] = nil end
end

local function remove(id)
    despawn(id)
    list[id] = nil
end

local function spawn(d)
    despawn(d.id)
    if not Chains.exists(d.chain) then return end
    local c = d.coords
    local entity = Util.spawnChain(d.chain, d.variant, c)
    if not entity then return end
    SetEntityCoordsNoOffset(entity, c.x, c.y, c.z, false, false, false)
    SetEntityRotation(entity, d.rot.x, d.rot.y, d.rot.z, 2, false)
    FreezeEntityPosition(entity, true)
    props[d.id] = entity

    if CB.Target ~= 'none' then
        zones[d.id] = CB.AddSphere('nzc_drop_' .. d.id, c, 0.45, {
            {
                name = 'nzc_pick_' .. d.id, label = Config.Text.pick_up .. ' ' .. label(d), icon = 'fa-solid fa-hand',
                distance = cfg.PickupDistance,
                onSelect = function() TriggerServerEvent('nzc:s:pickup', d.id, false) end,
            },
            {
                name = 'nzc_pickwear_' .. d.id, label = Config.Text.pick_up_wear, icon = 'fa-solid fa-gem',
                distance = cfg.PickupDistance,
                canInteract = function() return WornProps.mine() == nil end,
                onSelect = function() TriggerServerEvent('nzc:s:pickup', d.id, true) end,
            },
        })
    end
end

RegisterNetEvent('nzc:c:drops', function(all)
    for id in pairs(list) do remove(id) end
    for _, d in ipairs(all or {}) do
        d.coords = v3(d.coords)
        list[d.id] = d
    end
end)

RegisterNetEvent('nzc:c:dropAdd', function(d)
    d.coords = v3(d.coords)
    despawn(d.id)
    list[d.id] = d
    if #(GetEntityCoords(PlayerPedId()) - d.coords) < (cfg.RenderDistance or 60.0) then spawn(d) end
end)

RegisterNetEvent('nzc:c:dropRemove', function(id) remove(id) end)

AddEventHandler('nzc:registry', function()
    for id, d in pairs(list) do if props[id] then spawn(d) end end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(list) do remove(id) end
end)

-- streaming: spawn as you get close, clean up as you leave
CreateThread(function()
    local range = cfg.RenderDistance or 60.0
    local inSq, outSq = range * range, (range + 10.0) * (range + 10.0)
    while true do
        if next(list) then
            local pc = GetEntityCoords(PlayerPedId())
            for id, d in pairs(list) do
                local dx, dy, dz = d.coords.x - pc.x, d.coords.y - pc.y, d.coords.z - pc.z
                local dd = dx * dx + dy * dy + dz * dz
                if not props[id] and dd < inSq then spawn(d)
                elseif props[id] and dd > outSq then despawn(id) end
            end
            Wait(1500)
        else
            Wait(3000)
        end
    end
end)

-- [E] prompt when no target script handles it
if CB.Target == 'none' then
    local function nearest()
        local pc = GetEntityCoords(PlayerPedId())
        local best, bestD = nil, cfg.PickupDistance or 2.0
        for id in pairs(props) do
            local d = #(list[id].coords - pc)
            if d < bestD then best, bestD = id, d end
        end
        return best
    end

    CreateThread(function()
        while true do
            local sleep = 800
            if next(props) and not Place.active() and not Hold.active() then
                local id = nearest()
                if id then
                    sleep = 300
                    NUI.hint(Config.Text.hint_pickup:format(label(list[id])), 'pickup')
                    while id and not Place.active() and not Hold.active() do
                        if IsControlJustPressed(0, 38) then
                            TriggerServerEvent('nzc:s:pickup', id, false)
                            Wait(600)
                            break
                        end
                        Wait(0)
                        id = nearest()
                    end
                    if NUI.hintText and NUI.hintText:find(Config.Text.pick_up, 1, true) then NUI.hint(nil) end
                end
            end
            Wait(sleep)
        end
    end)
end
