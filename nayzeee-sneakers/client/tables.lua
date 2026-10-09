--[[
    Crafting tables on this client.

    Each client spawns the tables near it as local objects. A table uses
    Dragons Lab's model when this client has her pack, otherwise the fallback.
]]

Tables = {}

local T = Config.Tables
local list = {}        -- [id] = { id, item, coords, heading, fixed, ownerSrc }
local spawned = {}     -- [id] = entity
local byEnt = {}       -- [entity] = id
local surfaces = {}    -- [model] = table-top height
local warned = false

--- Model and table-top height for a table item, or nil if nothing can be shown
local function modelFor(item)
    local def = T.items[item]
    if def and IsModelInCdimage(def.model) then return def.model, T.surface end
    if not warned then
        warned = true
        print(('^3[nayzeee-sneakers]^7 Dragons Lab Shoe Table Pack not found. Buy it at %s'):format(T.store))
    end
    if T.fallback and IsModelInCdimage(T.fallback) then return T.fallback, T.fallbackSurface end
end

local function surfaceOf(model, given)
    if given then return given end
    if not surfaces[model] then
        local _, max = GetModelDimensions(model)
        surfaces[model] = max.z
    end
    return surfaces[model]
end

local function spawn(id)
    local t = list[id]
    local model, surface = modelFor(t.item)
    if not model or not LoadModel(model) then return end
    if not list[id] or spawned[id] then return SetModelAsNoLongerNeeded(model) end
    local obj = CreateObjectNoOffset(model, t.coords.x, t.coords.y, t.coords.z, false, false, false)
    SetEntityHeading(obj, t.heading)
    FreezeEntityPosition(obj, true)
    t.surface = surfaceOf(model, surface)
    SetModelAsNoLongerNeeded(model)
    spawned[id], byEnt[obj] = obj, id
end

local function despawn(id)
    local obj = spawned[id]
    if not obj then return end
    if DoesEntityExist(obj) then DeleteEntity(obj) end
    spawned[id], byEnt[obj] = nil, nil
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, t in pairs(list) do
            local d = #(pos - t.coords)
            if d < T.streamDistance and not spawned[id] then spawn(id)
            elseif d > T.streamDistance + 10.0 and spawned[id] then despawn(id) end
        end
        Wait(1000)
    end
end)

function Tables.Refresh()
    for id in pairs(spawned) do despawn(id) end
    list = {}
    for _, t in ipairs(lib.callback.await('nayzeee-sneakers:tables', false) or {}) do list[t.id] = t end
end

Bridge.OnPlayerLoaded(Tables.Refresh)

RegisterNetEvent('nayzeee-sneakers:client:tableAdded', function(t)
    list[t.id] = t
end)

RegisterNetEvent('nayzeee-sneakers:client:tableRemoved', function(id)
    despawn(id)
    list[id] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)

--- Table id and data for a spawned table entity
function Tables.FromEntity(ent)
    local id = byEnt[ent]
    return id, id and list[id]
end

--- Where the player stands and where the work sits, on whichever long side
--- of the table the player is on. Returns stand, work, heading, and two flat
--- directions: `along` the table and `out` from the work towards the player.
function Tables.WorkSpot(ent)
    local _, t = Tables.FromEntity(ent)
    local min, max = GetModelDimensions(GetEntityModel(ent))
    local rel = GetOffsetFromEntityGivenWorldCoords(ent, GetEntityCoords(PlayerPedId()))
    local side = rel.y < (min.y + max.y) / 2 and -1 or 1
    local x = math.max(min.x + 0.45, math.min(max.x - 0.45, rel.x))
    local edge = side < 0 and min.y or max.y
    local stand = GetOffsetFromEntityInWorldCoords(ent, x, edge + side * 0.42, 0.0)
    local work = GetOffsetFromEntityInWorldCoords(ent, x, edge - side * 0.2, (t and t.surface or 0.9) + 0.005)
    local heading = GetHeadingFromVector_2d(work.x - stand.x, work.y - stand.y)
    local d = stand - work
    local len = math.max(0.01, math.sqrt(d.x * d.x + d.y * d.y))
    local out = vector3(d.x / len, d.y / len, 0.0)
    local along = vector3(-out.y, out.x, 0.0)
    return stand, work, heading, along, out
end

-- Interactions ------------------------------------------------------------------

local function mine(t)
    return t and not t.fixed and t.ownerSrc == GetPlayerServerId(PlayerId())
end

local function pickUp(ent)
    if Busy then return end
    local id = Tables.FromEntity(ent)
    if not id then return end
    Busy = true
    Anim.Face(ent)
    Anim.PickUp()
    Wait(600)
    lib.callback.await('nayzeee-sneakers:pickUpTable', false, id)
    Wait(400)
    Busy = false
end

local tableOptions = {
    { name = 'nzs_table_use', label = Config.Text.useTable, icon = 'fa-solid fa-scissors',
      canInteract = function(e) return byEnt[e] ~= nil and not Busy end,
      onSelect = function(e) Crafting.Open(e) end },
    { name = 'nzs_table_pickup', label = Config.Text.pickUpTable, icon = 'fa-solid fa-hand-holding',
      canInteract = function(e) local _, t = Tables.FromEntity(e); return mine(t) and not Busy end,
      onSelect = pickUp },
}

CreateThread(function()
    local models = {}
    for _, def in pairs(T.items) do models[#models + 1] = def.model end
    if T.fallback then models[#models + 1] = T.fallback end
    Target.AddModel(models, tableOptions, T.interactDistance)
end)

-- Placing a table ---------------------------------------------------------------

local NO_ATTACK = { 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17, 199, 200 }

RegisterNetEvent('nayzeee-sneakers:client:placeTable', function(slot, item)
    local ped = PlayerPedId()
    if Busy or IsPedInAnyVehicle(ped, false) then return end
    local model = modelFor(item)
    if not model then return UI.Notify(Config.Text.noTableModel, 'error') end
    if not LoadModel(model) then return end
    Busy = true

    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0)
    local heading = GetEntityHeading(ped)
    local ghost = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityHeading(ghost, heading)
    UI.Hint(Config.Text.placeHint)

    local place, valid = false, false
    while true do
        Wait(0)
        for _, c in ipairs(NO_ATTACK) do DisableControlAction(0, c, true) end
        local hit, _, coords, normal = lib.raycast.cam(1, 4, 7.0)
        if hit then pos = coords end
        valid = hit and normal.z > 0.85 and #(pos - GetEntityCoords(ped)) < 5.0
        SetEntityCoords(ghost, pos.x, pos.y, pos.z, false, false, false, false)
        SetEntityHeading(ghost, heading)
        SetEntityAlpha(ghost, valid and 200 or 90, false)

        if IsDisabledControlPressed(0, 15) then heading = heading + 7.5 end   -- scroll up
        if IsDisabledControlPressed(0, 14) then heading = heading - 7.5 end   -- scroll down
        if IsDisabledControlPressed(0, 44) then heading = heading + 1.5 end   -- Q
        if IsDisabledControlPressed(0, 38) then heading = heading - 1.5 end   -- E
        heading = heading % 360.0
        if IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 191) then
            if valid then place = true break end
            UI.Notify(Config.Text.cantPlace, 'error')
        end
        if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then break end
    end

    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(model)
    UI.Hint(nil)
    if place then
        TaskTurnPedToFaceCoord(ped, pos.x, pos.y, pos.z, 600)
        Wait(600)
        Anim.PutDown()
        Wait(700)
        lib.callback.await('nayzeee-sneakers:placeTable', false, slot, pos, heading)
    end
    Busy = false
end)
