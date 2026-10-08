-----------------------------------------------------------------
-- Warehouse interior: both floors, display cars, doors, stairs
-----------------------------------------------------------------
Warehouse = { display = {}, interiorId = nil, lowerId = nil, floor = 'main' }

local handlers = Client.Handlers

local function v3(t) return vec3(t.x, t.y, t.z) end

local function applyStyle(styleSet)
    local id = Warehouse.interiorId
    if not id or id == 0 then return end
    for _, s in ipairs(Config.Upgrades.style.styles) do
        if IsInteriorEntitySetActive(id, s.set) then DeactivateInteriorEntitySet(id, s.set) end
    end
    ActivateInteriorEntitySet(id, styleSet or 'basic_style_set')
    RefreshInterior(id)
end

local function loadIpl(ipl, c)
    RequestIpl(ipl)
    local id = GetInteriorAtCoords(c.x, c.y, c.z)
    local t = GetGameTimer() + 4000
    while (id == 0 or not IsInteriorReady(id)) and GetGameTimer() < t do
        Wait(50)
        id = GetInteriorAtCoords(c.x, c.y, c.z)
    end
    if id ~= 0 then PinInteriorInMemory(id) end
    return id
end

local function loadInterior(interior, styleSet)
    Warehouse.interiorId = loadIpl(interior.ipl, interior.coords)
    if Warehouse.interiorId ~= 0 then
        for _, set in ipairs(interior.sets or {}) do ActivateInteriorEntitySet(Warehouse.interiorId, set) end
        applyStyle(styleSet)
    end
    -- always load downstairs: the stairs are part of the building (locked without the upgrade)
    if interior.lower then
        Warehouse.lowerId = loadIpl(interior.lower.ipl, interior.lower.coords)
    end
end

-----------------------------------------------------------------
-- Display cars (local only, never networked)
-----------------------------------------------------------------
-- Bumped on every clear / respawn so a spawn still loading stops and cleans up
-- after itself (two overlapping spawns stacked cars on top of each other).
local displayGen = 0

local function clearDisplay()
    displayGen = displayGen + 1
    for id, d in pairs(Warehouse.display) do
        Bridge.RemoveEntity(d.entity, 'nz_car_' .. id)
        if DoesEntityExist(d.entity) then DeleteEntity(d.entity) end
    end
    Warehouse.display = {}
end

local function rarityLabel(id)
    local r = Cargo.Rarity[id]
    return r and r.label or id
end

-- Wheels on the floor. Spots are saved at floor height, so the car's resting
-- height is known even when the interior collision hasn't streamed in yet.
local function settle(veh, slot)
    local mn = GetModelDimensions(GetEntityModel(veh))
    local want = slot.z - mn.z
    FreezeEntityPosition(veh, false)
    local ok = SetVehicleOnGroundProperly(veh)
    local c = GetEntityCoords(veh)
    -- no ground found yet, or it landed somewhere else (on another car, under the floor)
    if not ok or math.abs(c.z - want) > 1.0 then
        SetEntityCoordsNoOffset(veh, slot.x, slot.y, want, false, false, false)
        SetEntityHeading(veh, slot.w or 0.0)
    end
end

-- Spawn one car on its spot and make sure it sits on the floor
local function placeCar(car, slot, gen)
    local hash = Client.LoadModel(car.model)
    if not hash or gen ~= displayGen then return nil end
    local mn = GetModelDimensions(hash)
    RequestCollisionAtCoord(slot.x, slot.y, slot.z)
    local veh = CreateVehicle(hash, slot.x, slot.y, slot.z - mn.z, slot.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(veh, true)
    SetEntityCollision(veh, true, true)
    local t = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < t and gen == displayGen do
        RequestCollisionAtCoord(slot.x, slot.y, slot.z)
        Wait(0)
    end
    if gen ~= displayGen then DeleteEntity(veh) return nil end
    Bridge.SetProps(veh, car.props)
    if car.plate then SetVehicleNumberPlateText(veh, car.plate) end
    SetVehicleDoorsLocked(veh, 2)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, car.condition < 80 and 9.0 or 0.0)
    if car.condition < 70 then
        for _ = 1, math.floor((70 - car.condition) / 12) + 1 do
            SetVehicleDamage(veh, math.random(-10, 10) / 10, math.random(-20, 20) / 10, 0.1, 160.0, 400.0, true)
        end
    end
    Wait(0)
    if gen ~= displayGen then DeleteEntity(veh) return nil end
    settle(veh, slot)
    FreezeEntityPosition(veh, true)
    return veh
end

local function spawnDisplay(list)
    clearDisplay()
    local gen = displayGen
    local inside = Client.inside
    if not inside then return end
    local floors = {
        { cars = list.main or {}, slots = inside.interior.slots },
        { cars = (inside.interior.lowerOpen and list.lower) or {}, slots = inside.interior.lower and inside.interior.lower.slots or {} },
    }
    for _, f in ipairs(floors) do
        for i, car in ipairs(f.cars) do
            local slot = f.slots[i]
            if not slot or not Client.inside or gen ~= displayGen then break end
            local veh = placeCar(car, slot, gen)
            if veh then
                local options = {
                    { label = L('ti_customize'), icon = 'fa-solid fa-spray-can-sparkles',
                      onSelect = function() Workshop.Open(car.id) end,
                      canInteract = function() return Client.inside and Client.inside.role ~= 'guest' and Client.inside.role ~= 'police' end },
                    { label = L('ti_seize'), icon = 'fa-solid fa-handcuffs',
                      onSelect = function() Raid.Seize(car) end,
                      canInteract = function() return Client.inside and Client.inside.role == 'police' end },
                }
                Bridge.AddEntity(veh, 'nz_car_' .. car.id, options, 3.0)
                local _, mx = GetModelDimensions(GetEntityModel(veh))
                Warehouse.display[car.id] = { entity = veh, slot = i, car = car, top = mx.z }
            end
        end
    end
end

-----------------------------------------------------------------
-- Spec card that floats above the car you walk up to
-----------------------------------------------------------------
local specOn = false

local function specData(car)
    local r = Cargo.Rarity[car.rarity] or {}
    return {
        id = car.id, label = car.label, rarity = car.rarity, base = car.base_rarity, plate = car.plate,
        condition = car.condition, score = car.score or 0, value = car.baseValue or car.value,
        floor = Warehouse.Floor(), illegal = r.illegal or false,
    }
end

local function specLoop()
    if specOn then return end
    specOn = true
    CreateThread(function()
        local shown, lx, ly = nil, -1, -1
        local range = Config.Interact.SpecDistance or 4.5
        local warned = 0
        while Client.inside do
            -- walked down the stairs without the Lower Level upgrade
            local i = Client.inside.interior
            if not i.lowerOpen and Client.inside.role ~= 'admin' and Client.inside.role ~= 'police' and Warehouse.Floor() == 'lower' and GetGameTimer() > warned then
                warned = GetGameTimer() + 3000
                Client.Fade(true, 250)
                Client.Teleport(i.entry, i.entry.w)
                Client.Fade(false, 250)
                Bridge.Notify(L('lower_locked'), 'error')
            end
            local best, bd = nil, range
            if not Client.nui and not Placer.active and not (Workshop and Workshop.active) then
                local pc = GetEntityCoords(cache.ped)
                for _, d in pairs(Warehouse.display) do
                    if DoesEntityExist(d.entity) and IsEntityVisible(d.entity) then
                        local dist = #(pc - GetEntityCoords(d.entity))
                        if dist < bd then best, bd = d, dist end
                    end
                end
            end
            if best then
                if shown ~= best then
                    shown, lx, ly = best, -1, -1
                    Client.Send('spec', { car = specData(best.car) })
                end
                local c = GetEntityCoords(best.entity)
                local ok, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + best.top + 0.3)
                if ok and (math.abs(x - lx) > 0.0015 or math.abs(y - ly) > 0.0015) then
                    lx, ly = x, y
                    Client.Send('spec', { x = x, y = y })
                elseif not ok and lx ~= -2 then
                    lx = -2
                    Client.Send('spec', { offscreen = true })
                end
                Wait(0)
            else
                if shown then shown = nil Client.Send('spec', { hide = true }) end
                Wait(350)
            end
        end
        Client.Send('spec', { hide = true })
        specOn = false
    end)
end

function Warehouse.HideDisplay(stockId, hidden)
    local d = Warehouse.display[stockId]
    if d and DoesEntityExist(d.entity) then
        SetEntityVisible(d.entity, not hidden, false)
        SetEntityCollision(d.entity, not hidden, true)
    end
end

-----------------------------------------------------------------
-- Floors: the interior has real stairs, so the floor is read from
-- your height. The lower level stays locked until the upgrade.
-----------------------------------------------------------------
local pointIds = { 'nz_in_exit' }

local function clearPoints()
    for _, id in ipairs(pointIds) do Bridge.RemovePoint(id) end
end

local function splitZ()
    local i = Client.inside and Client.inside.interior
    return i and i.lower and i.lower.split or -44.0
end

function Warehouse.Floor()
    if not Client.inside then return 'main' end
    return GetEntityCoords(cache.ped).z < splitZ() and 'lower' or 'main'
end

-- Only used by the setup tools to put you on the right floor
function Warehouse.GoFloor(floor)
    local i = Client.inside and Client.inside.interior
    if not i or Warehouse.Floor() == floor then return end
    Client.Fade(true)
    if floor == 'lower' then
        local s = i.lower and i.lower.slots and i.lower.slots[1]
        if s then Client.Teleport(vec3(s.x + 3.0, s.y, s.z + 1.0), s.w) end
    else
        Client.Teleport(i.entry, i.entry.w)
    end
    Client.Fade(false)
end

local function buildPoints()
    clearPoints()
    local i = Client.inside.interior
    local exitOptions = {
        { label = L('ti_exit'), icon = 'fa-solid fa-door-open', onSelect = function() Warehouse.Exit('front') end },
    }
    if Config.Doors.GarageExit then
        exitOptions[#exitOptions + 1] = { label = L('ti_exit_garage'), icon = 'fa-solid fa-warehouse', onSelect = function() Warehouse.Exit('garage') end }
    end
    Bridge.AddPoint('nz_in_exit', v3(i.exit), 1.6, exitOptions)
    local d = Config.Interior.Laptop
    Laptop.HideDefaults({ i.laptop, { x = d.x, y = d.y, z = d.z } })
    if Client.inside.role ~= 'guest' and Client.inside.role ~= 'admin' and Client.inside.role ~= 'police' then Laptop.Setup(i.laptop) end
end

-----------------------------------------------------------------
-- Enter / exit
-----------------------------------------------------------------
function Warehouse.Load(data, fadeHeld)
    Client.warping = true
    if not fadeHeld then Client.Fade(true) end
    Client.ClosePrompts()
    Client.Static()
    Client.inside = data
    loadInterior(data.interior, data.style)
    local ped = cache.ped
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) Wait(50) end
    local e = data.interior.entry
    Client.Teleport(e, e.w)
    buildPoints()
    spawnDisplay(data.display or {})
    specLoop()
    Client.Fade(false)
    Client.warping = false
end

function Warehouse.Enter(id)
    if Client.mission and Client.mission.kind == 'sell' then Bridge.Notify(L('busy'), 'error') return end
    local data = lib.callback.await('nz_cargo:enter', false, id)
    if data then Warehouse.Load(data) end
end

function Warehouse.Cleanup()
    Laptop.Teardown()
    Laptop.ShowDefaults()
    clearDisplay()
    clearPoints()
    Client.ClosePrompts()
    Client.Send('spec', { hide = true })
    for _, k in ipairs({ 'interiorId', 'lowerId' }) do
        if Warehouse[k] and Warehouse[k] ~= 0 then UnpinInterior(Warehouse[k]) end
    end
    Client.inside = nil
end

function Warehouse.Exit(mode, toCoords)
    if not Client.inside then return end
    if Laptop.open then Laptop.Close(true) end
    Client.CloseUI()
    if Workshop.active then Workshop.Close(true) end
    Client.warping = true
    Client.Fade(true)
    local door = toCoords or lib.callback.await('nz_cargo:exit', false, mode or 'front')
    Warehouse.Cleanup()
    if door then Client.Teleport(door, (door.w or 0.0) + (mode == 'garage' and 0.0 or 180.0)) end
    Client.Fade(false)
    Client.warping = false
end

RegisterNetEvent('nz_cargo:display', function(list)
    if Client.inside then
        Client.inside.display = list
        spawnDisplay(list)
    end
end)

RegisterNetEvent('nz_cargo:style', function(set)
    if Client.inside then
        Client.inside.style = set
        applyStyle(set)
    end
end)

RegisterNetEvent('nz_cargo:interior', function(interior)
    if not Client.inside then return end
    local wasOpen = Client.inside.interior.lowerOpen
    Client.inside.interior = interior
    if interior.lowerOpen and not wasOpen and interior.lower then
        Warehouse.lowerId = loadIpl(interior.lower.ipl, interior.lower.coords)
    end
    buildPoints()
end)

RegisterNetEvent('nz_cargo:kick', function()
    if Client.inside then Warehouse.Exit('front') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearDisplay()
    clearPoints()
    Bridge.HideText()
end)

-----------------------------------------------------------------
-- Laptop app requests
-----------------------------------------------------------------
handlers.terminal = function() return lib.callback.await('nz_cargo:terminal', false) end
handlers.upgrade = function(d) return lib.callback.await('nz_cargo:upgrade', false, d.track, d.choice) or { ok = false } end
handlers.repair = function(d) return lib.callback.await('nz_cargo:repair', false, d.id) or { ok = false } end
handlers.scrap = function(d) return lib.callback.await('nz_cargo:scrap', false, d.id) or { ok = false } end
handlers.nearby = function() return lib.callback.await('nz_cargo:nearbyPlayers', false) or {} end
handlers.assocAdd = function(d) return lib.callback.await('nz_cargo:addAssociate', false, d.id) or { ok = false } end
handlers.assocRemove = function(d) return lib.callback.await('nz_cargo:removeAssociate', false, d.identifier) or { ok = false } end
handlers.setRole = function(d) return lib.callback.await('nz_cargo:setRole', false, d.identifier, d.role) or { ok = false } end
handlers.insure = function(d) return lib.callback.await('nz_cargo:insure', false, d.id) or { ok = false } end
handlers.claims = function() return lib.callback.await('nz_cargo:claims', false) or { ok = false } end
handlers.bribe = function(d) return lib.callback.await('nz_cargo:bribe', false, d.steps or 1) or { ok = false } end
handlers.prestige = function() return lib.callback.await('nz_cargo:prestige', false) or { ok = false } end
handlers.crewJob = function(d)
    if Client.mission then Bridge.Notify(L('busy'), 'error') return { ok = false } end
    local res = lib.callback.await('nz_cargo:crewjob:start', false, d.id)
    return res or { ok = false }
end
handlers.leaderboard = function() return lib.callback.await('nz_cargo:leaderboard', false) end
handlers.offers = function(d) return lib.callback.await('nz_cargo:sell:offers', false, d.id) or { ok = false } end
handlers.sellQuick = function(d) return lib.callback.await('nz_cargo:sell:quick', false, d.id) or { ok = false } end
handlers.layoutPreset = function(d) return lib.callback.await('nz_cargo:layout:preset', false, d.id) or { ok = false } end
handlers.layoutReset = function() return lib.callback.await('nz_cargo:layout:reset', false) or { ok = false } end
handlers.exit = function()
    Laptop.Close(true)
    Warehouse.Exit('front')
    return true
end
