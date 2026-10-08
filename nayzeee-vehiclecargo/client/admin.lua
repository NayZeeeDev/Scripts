-----------------------------------------------------------------
-- Admin tools (command only: /cargoadmin, /cargoslots, /cargocoords)
-- Locations, brokers and the whole interior are placed with the
-- aim-based placer: points get a cylinder + line, car spots a ghost.
-----------------------------------------------------------------
local handlers = Client.Handlers

local function isAdmin() return lib.callback.await('nz_cargo:admin:isAdmin', false) end

local function here()
    local ped = cache.ped
    local veh = GetVehiclePedIsIn(ped, false)
    local e = veh ~= 0 and veh or ped
    local c = GetEntityCoords(e)
    return { x = Cargo.Round(c.x * 100) / 100, y = Cargo.Round(c.y * 100) / 100, z = Cargo.Round(c.z * 100) / 100, w = Cargo.Round(GetEntityHeading(e) * 10) / 10 }
end

RegisterCommand('cargocoords', function()
    if not isAdmin() then return end
    local p = here()
    local s = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(p.x, p.y, p.z, p.w)
    lib.setClipboard(s)
    Bridge.Notify(s, 'success', 'Copied')
end, false)

-- Admin data plus where the admin is right now (the Interior tab needs it)
local function adminData()
    local d = lib.callback.await('nz_cargo:admin:data', false)
    if d then
        d.here = {
            inside = Client.inside ~= nil,
            preview = Client.inside ~= nil and Client.inside.role == 'admin',
            floor = Warehouse.Floor(),
        }
    end
    return d
end

local function reopen(tab, extra)
    local d = adminData()
    if not d then return end
    local data = { admin = d, tab = tab }
    if extra then for k, v in pairs(extra) do data[k] = v end end
    Client.OpenUI('admin', data)
end

-----------------------------------------------------------------
-- Panel
-----------------------------------------------------------------
RegisterCommand('cargoadmin', function()
    if Client.nui or not isAdmin() then return end
    reopen(nil)
end, false)

-- Straight to the interior setup
RegisterCommand('cargoslots', function()
    if Client.nui or not isAdmin() then return end
    reopen('interior')
end, false)

handlers.adminData = function() return adminData() end
handlers.adminSaveVehicle = function(d) return lib.callback.await('nz_cargo:admin:saveVehicle', false, d) end
handlers.adminDeleteVehicle = function(d) return lib.callback.await('nz_cargo:admin:deleteVehicle', false, d.model) end
handlers.adminWipe = function(d) return lib.callback.await('nz_cargo:admin:wipeWarehouse', false, d.id) end
handlers.adminXp = function(d) return lib.callback.await('nz_cargo:admin:giveXp', false, d.identifier, d.amount) end
handlers.adminCooldowns = function(d) return lib.callback.await('nz_cargo:admin:resetCooldowns', false, d.identifier) end
handlers.adminSaveLocation = function(d) return lib.callback.await('nz_cargo:admin:saveLocation', false, d) end
handlers.adminDeleteLocation = function(d) return lib.callback.await('nz_cargo:admin:deleteLocation', false, d.id) end
handlers.adminRemoveBroker = function(d) return lib.callback.await('nz_cargo:admin:removeBroker', false, d.index) end
handlers.adminDeletePreset = function(d) return lib.callback.await('nz_cargo:admin:deletePreset', false, d.id) end

handlers.adminTeleport = function(d)
    if not d.coords then return false end
    Client.CloseUI()
    if Client.inside then Warehouse.Exit() end
    SetEntityCoords(cache.ped, d.coords.x, d.coords.y, d.coords.z, false, false, false, false)
    return true
end

-----------------------------------------------------------------
-- Locations: door, drive-in garage, sale spawn
-----------------------------------------------------------------
local LOCATION_POINTS = {
    { key = 'door',       label = 'Front door (face the door)',           kind = 'point' },
    { key = 'garage',     label = 'Garage entrance (drive in here)',       kind = 'car' },
    { key = 'garageExit', label = 'Garage exit (face the way you come out)', kind = 'point' },
    { key = 'spawn',      label = 'Sale car spawn (face the road)',        kind = 'car' },
}

-- One point (d.key) or all four in order (d.key = 'all')
handlers.adminPlace = function(d)
    if Client.inside then Bridge.Notify('Leave the warehouse first.', 'error') return false end
    Client.CloseUI()
    local steps = {}
    for _, st in ipairs(LOCATION_POINTS) do
        if d.key == 'all' or d.key == st.key then steps[#steps + 1] = st end
    end
    local placed = Placer.Steps(steps)
    reopen('locations', { placed = placed, draft = d.draft })
    return true
end

handlers.adminImportSeeds = function() return lib.callback.await('nz_cargo:admin:importSeeds', false) end

-----------------------------------------------------------------
-- Brokers
-----------------------------------------------------------------
handlers.adminPlaceBroker = function()
    if Client.inside then Bridge.Notify('Leave the warehouse first.', 'error') return false end
    Client.CloseUI()
    local p = Placer.Point({ label = 'Broker', kind = 'ped', model = Config.Broker.Model, face = true })
    if p then lib.callback.await('nz_cargo:admin:addBroker', false, p) end
    reopen('brokers')
    return true
end

-----------------------------------------------------------------
-- Interior setup
-----------------------------------------------------------------
local POINTS = {
    entry       = { floor = 'main',  label = 'Arrival point (where people appear)' },
    exit        = { floor = 'main',  label = 'Exit door' },
    laptop      = { floor = 'main',  label = 'Laptop on the desk', kind = 'prop', model = Config.Laptop.Model },
    design      = { floor = 'main',  label = 'Design bay car', kind = 'car' },
}

-- A setup copy of the interior so admins don't need to own a warehouse
handlers.adminPreview = function()
    if Client.inside then return false end
    Client.CloseUI()
    local c, h = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)
    local data = lib.callback.await('nz_cargo:admin:preview', false, { x = c.x, y = c.y, z = c.z, w = (h + 180.0) % 360 })
    if not data then return false end
    Warehouse.Load(data)
    Bridge.Notify('Setup copy: place everything, then use the exit door to go back.', 'info', 'Interior', 8000)
    Wait(300)
    reopen('interior')
    return true
end

local function needInside()
    if Client.inside then return true end
    Bridge.Notify('Open the setup copy first (Admin → Interior).', 'error')
    return false
end

local function goTo(floor)
    if Warehouse.Floor() ~= floor then Warehouse.GoFloor(floor) Wait(250) end
end

handlers.adminInterior = function(d)
    local def = POINTS[d.key]
    if not def or not needInside() then return false end
    Client.CloseUI()
    goTo(def.floor)
    local p = Placer.Point({ label = def.label, kind = def.kind or 'point', model = def.model, face = def.face })
    if p then
        lib.callback.await('nz_cargo:admin:saveInterior', false, { [d.key] = p })
        Bridge.Notify('Saved.', 'success', 'Interior')
    end
    reopen('interior')
    return true
end

handlers.adminSpots = function(d)
    if not needInside() then return false end
    Client.CloseUI()
    local lower = d.floor == 'lower'
    -- always edit the server defaults, not an owner's own layout
    local server = lib.callback.await('nz_cargo:admin:data', false)
    local def = server and server.interior or Client.inside.interior
    goTo(lower and 'lower' or 'main')
    local current = lower and (def.lower and def.lower.slots or {}) or (def.slots or {})
    local spots = Placer.Spots({
        label = lower and 'Illegal spots downstairs' or 'Default main floor spots',
        spots = current, fixed = lower and 4 or nil, max = Config.Layout.MaxSlots,
    })
    if spots then
        local save = lower and { lowerSlots = spots } or { slots = spots, preset = d.preset }
        lib.callback.await('nz_cargo:admin:saveInterior', false, save)
        Bridge.Notify(('Saved %d spots.'):format(#spots), 'success', 'Interior')
    end
    reopen('interior')
    return true
end

-- Floor area / obstacles: two opposite corners each
handlers.adminFloor = function(d)
    if not needInside() then return false end
    Client.CloseUI()
    goTo('main')
    local what = d.kind == 'obstacle' and 'prop to keep clear of' or 'open floor'
    local a = Placer.Point({ label = ('Corner 1 of the %s'):format(what), kind = 'point' })
    local b = a and Placer.Point({ label = ('Opposite corner of the %s'):format(what), kind = 'point' })
    if a and b then
        local box = { min = { x = a.x, y = a.y }, max = { x = b.x, y = b.y }, z = math.min(a.z, b.z) - 1.0 }
        lib.callback.await('nz_cargo:admin:saveInterior', false, d.kind == 'obstacle' and { obstacle = box } or { floor = box })
        Bridge.Notify(d.kind == 'obstacle' and 'Obstacle added. Presets now avoid it.' or 'Floor area saved. Presets refit to it.', 'success', 'Interior')
    end
    reopen('interior')
    return true
end

handlers.adminFloorClear = function()
    return lib.callback.await('nz_cargo:admin:saveInterior', false, { clearObstacles = true })
end

handlers.adminInteriorReset = function(d)
    if type(d.keys) ~= 'table' then return false end
    return lib.callback.await('nz_cargo:admin:saveInterior', false, { clear = d.keys })
end
