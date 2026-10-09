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
    -- show it now rather than on the next streaming pass
    if not spawned[t.id] and #(GetEntityCoords(PlayerPedId()) - t.coords) < T.streamDistance then spawn(t.id) end
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

--- Where the player stands and where the work sits. The work is always the middle of
--- the table top; the player stands at the middle of whichever long side they're on.
--- Returns stand, work, heading, and two flat directions: `along` the table and
--- `out` from the work towards the player.
function Tables.WorkSpot(ent)
    local _, t = Tables.FromEntity(ent)
    local min, max = GetModelDimensions(GetEntityModel(ent))
    local cx, cy = (min.x + max.x) / 2, (min.y + max.y) / 2
    local nudge = T.workOffset or vector3(0.0, 0.0, 0.0)
    local rel = GetOffsetFromEntityGivenWorldCoords(ent, GetEntityCoords(PlayerPedId()))
    local longX = (max.x - min.x) >= (max.y - min.y)
    local gap = T.stand or 0.45
    local stand, work
    -- which long side: the one you're on, or always the table's front / back (Config.Tables.side)
    local function pick(relAxis, centre)
        if T.side == 'front' then return -1 elseif T.side == 'back' then return 1 end
        return relAxis < centre and -1 or 1
    end
    if longX then
        local side = pick(rel.y, cy)
        stand = GetOffsetFromEntityInWorldCoords(ent, cx + nudge.x, (side < 0 and min.y or max.y) + side * gap, 0.0)
        work = GetOffsetFromEntityInWorldCoords(ent, cx + nudge.x, cy + side * nudge.y, (t and t.surface or 0.9) + 0.005)
    else
        local side = pick(rel.x, cx)
        stand = GetOffsetFromEntityInWorldCoords(ent, (side < 0 and min.x or max.x) + side * gap, cy + nudge.x, 0.0)
        work = GetOffsetFromEntityInWorldCoords(ent, cx + side * nudge.y, cy + nudge.x, (t and t.surface or 0.9) + 0.005)
    end
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

RegisterNetEvent('nayzeee-sneakers:client:placeTable', function(slot, item)
    local ped = PlayerPedId()
    if Busy or IsPedInAnyVehicle(ped, false) then return end
    local model = modelFor(item)
    if not model then return UI.Notify(Config.Text.noTableModel, 'error') end
    Busy = true
    local pos, heading, ghostDone = Place.Ghost(model, { range = 5.0, flags = 1, minNormal = 0.85, heading = GetEntityHeading(ped), keep = true })
    if pos then
        Anim.PutDown()
        lib.callback.await('nayzeee-sneakers:placeTable', false, slot, pos, heading)
        Wait(150)   -- the real table spawns from tableAdded, which arrives with the answer
        ghostDone()
    end
    Busy = false
end)
