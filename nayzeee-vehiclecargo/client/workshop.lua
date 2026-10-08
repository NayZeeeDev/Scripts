-----------------------------------------------------------------
-- Design bay: local preview car, orbit camera, live build preview
-----------------------------------------------------------------
Workshop = { active = false }
local handlers = Client.Handlers
local W = Config.Workshop

local state = {}  -- { vehicle, cam, heading, pitch, dist, stock, base }

local function color(i) local c = W.Colors[i] return c and c[2], c[3], c[4] end

-- Applies a full build (missing keys = stock) on top of the stock look
function Workshop.Apply(veh, build, baseProps)
    build = build or {}
    if baseProps then Bridge.SetProps(veh, baseProps) end
    SetVehicleModKit(veh, 0)
    for _, p in ipairs(W.Parts) do
        local v = build[p.id]
        if p.type == 'level' then
            SetVehicleMod(veh, p.mod, (tonumber(v) or 0) - 1, false)
        elseif p.type == 'toggle' then
            ToggleVehicleMod(veh, p.mod, v == true)
        elseif p.type == 'part' then
            SetVehicleMod(veh, p.mod, tonumber(v) or -1, false)
        elseif p.type == 'livery' then
            if GetNumVehicleMods(veh, 48) > 0 then SetVehicleMod(veh, 48, tonumber(v) or -1, false)
            elseif v then SetVehicleLivery(veh, tonumber(v)) end
        elseif p.type == 'paint' and type(v) == 'table' then
            local finish = tonumber(v.finish) or 0
            SetVehicleModColor_1(veh, finish, 0, 0)
            SetVehicleModColor_2(veh, finish, 0)
            local r, g, b = color(v.p)
            if r then SetVehicleCustomPrimaryColour(veh, r, g, b) end
            r, g, b = color(v.s)
            if r then SetVehicleCustomSecondaryColour(veh, r, g, b) end
            local _, wheel = GetVehicleExtraColours(veh)
            SetVehicleExtraColours(veh, tonumber(v.pearl) or 0, wheel)
        elseif p.type == 'wheels' then
            if type(v) == 'table' then
                if v.type then
                    SetVehicleWheelType(veh, v.type)
                    SetVehicleMod(veh, 23, v.index or 0, v.custom == true)
                    if IsThisModelABike(GetEntityModel(veh)) then SetVehicleMod(veh, 24, v.index or 0, v.custom == true) end
                end
                if v.color then
                    local pearl = GetVehicleExtraColours(veh)
                    SetVehicleExtraColours(veh, pearl, tonumber(v.color))
                end
            end
        elseif p.type == 'tint' then
            SetVehicleWindowTint(veh, tonumber(v) or 0)
        elseif p.type == 'plate' then
            if v then SetVehicleNumberPlateTextIndex(veh, tonumber(v)) end
        elseif p.type == 'xenon' then
            ToggleVehicleMod(veh, 22, v ~= nil)
            if v ~= nil then SetVehicleXenonLightsColor(veh, v == -1 and 255 or v) end
        elseif p.type == 'neon' then
            local on = v ~= nil
            for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, on) end
            if on then
                local n = W.NeonColors[v]
                if n then SetVehicleNeonLightsColour(veh, n[2], n[3], n[4]) end
            end
        end
    end
end

-- What this specific model can fit
local function availability(veh)
    SetVehicleModKit(veh, 0)
    local out = { parts = {}, wheels = {}, livery = 0 }
    for _, p in ipairs(W.Parts) do
        if p.type == 'part' or p.type == 'level' then out.parts[p.id] = GetNumVehicleMods(veh, p.mod) end
    end
    out.livery = GetNumVehicleMods(veh, 48)
    if out.livery == 0 then out.livery = GetVehicleLiveryCount(veh) end
    if out.livery < 0 then out.livery = 0 end
    local origType = GetVehicleWheelType(veh)
    for _, wt in ipairs(W.WheelTypes) do
        SetVehicleWheelType(veh, wt[1])
        out.wheels[tostring(wt[1])] = GetNumVehicleMods(veh, 23)
    end
    SetVehicleWheelType(veh, origType)
    out.bike = IsThisModelABike(GetEntityModel(veh))
    return out
end

-----------------------------------------------------------------
-- Camera
-----------------------------------------------------------------
local presets = {
    wheels = { 70, 4.6, 0.45 }, spoiler = { 180, 6.0, 2.0 }, rbumper = { 180, 5.4, 0.8 }, exhaust = { 165, 4.8, 0.5 },
    fbumper = { 0, 5.4, 0.8 }, grille = { 0, 4.8, 0.8 }, hood = { 10, 5.4, 2.2 }, roof = { 40, 6.4, 3.2 },
    skirts = { 90, 5.2, 0.5 }, plate = { 180, 4.2, 0.6 }, xenon = { 15, 5.0, 0.7 }, neon = { 60, 6.5, 0.4 },
}

local function placeCam()
    local veh = state.vehicle
    if not veh or not state.cam then return end
    local c = GetEntityCoords(veh)
    local rad = math.rad(state.heading + GetEntityHeading(veh))
    -- heading 0 = in front of the car (GTA forward is -sin, +cos)
    local x = c.x - math.sin(rad) * state.dist
    local y = c.y + math.cos(rad) * state.dist
    SetCamCoord(state.cam, x, y, c.z + state.height)
    PointCamAtCoord(state.cam, c.x, c.y, c.z + 0.35)
end

local function createCam()
    local cfg = Client.inside.interior.cam or {}
    state.heading, state.dist, state.height = 35.0, cfg.distance or 6.2, cfg.height or 1.4
    state.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(state.cam, cfg.fov or 42.0)
    placeCam()
    SetCamActive(state.cam, true)
    RenderScriptCams(true, true, 600, true, false)
end

-----------------------------------------------------------------
-- Open / close
-----------------------------------------------------------------
-----------------------------------------------------------------
-- External mechanic: the player sits in a real copy of the car in
-- the bay and uses their own mechanic menu, then we read the result.
-----------------------------------------------------------------
local function openExternal(data)
    local spot = Client.inside.interior.design
    local hash = Client.LoadModel(data.stock.model)
    if not hash then return false end
    Workshop.active = true
    Client.Fade(true, 250)
    RequestCollisionAtCoord(spot.x, spot.y, spot.z)
    local veh = CreateVehicle(hash, spot.x, spot.y, spot.z, spot.w or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    local t = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < t do Wait(0) end
    SetVehicleOnGroundProperly(veh)
    Bridge.SetProps(veh, data.stock.props)
    SetVehicleNumberPlateText(veh, data.stock.plate or '')
    SetVehicleFixed(veh)
    Warehouse.HideDisplay(data.stock.id, true)
    TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    SetVehicleEngineOn(veh, false, true, true)
    FreezeEntityPosition(veh, true)
    Client.Fade(false, 250)

    local finished = false
    local function done() finished = true end
    local opened = Bridge.OpenMechanic(veh, done)
    if not opened then
        Bridge.Notify('Use your mechanic menu on this car. Press ENTER when you are finished, BACKSPACE to cancel.', 'info', 'Design Bay', 10000)
    end
    local cancelled = false
    while not finished and not cancelled and DoesEntityExist(veh) do
        Bridge.ShowText('', 'ENTER  Finish build   ·   BACKSPACE  Cancel')
        if IsControlJustPressed(0, 191) then finished = true end
        if IsControlJustPressed(0, 177) then cancelled = true end
        Wait(0)
    end
    Bridge.HideText()
    if finished and DoesEntityExist(veh) then
        local props = Bridge.GetProps(veh)
        local res = lib.callback.await('nz_cargo:workshop:external', false, data.stock.id, props)
        if not res then Bridge.Notify('Build not saved.', 'error') end
    end
    Client.Fade(true, 250)
    TaskLeaveVehicle(cache.ped, veh, 16)
    Wait(100)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    Client.Teleport(vec3(spot.x + 2.5, spot.y, spot.z), spot.w)
    Warehouse.HideDisplay(data.stock.id, false)
    Workshop.active = false
    Client.Fade(false, 250)
    return true
end

function Workshop.Open(stockId, mode, fromLaptop)
    if Workshop.active or not Client.inside then return false end
    local data = lib.callback.await('nz_cargo:workshop:open', false, stockId)
    if not data then return false end
    mode = mode or data.mode
    if mode == 'both' then
        local pick = lib.inputDialog('Design Bay', {
            { type = 'select', label = 'How do you want to build it?', required = true, default = 'builtin',
              options = { { value = 'builtin', label = 'Design bay menu' }, { value = 'external', label = 'My mechanic menu' } } },
        })
        if not pick then return false end
        mode = pick[1]
    end
    if mode == 'external' then return openExternal(data) end

    local spot = Client.inside.interior.design
    local hash = Client.LoadModel(data.stock.model)
    if not hash then return false end
    Client.Fade(true, 250)
    local veh = CreateVehicle(hash, spot.x, spot.y, spot.z, spot.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetVehicleOnGroundProperly(veh)
    Bridge.SetProps(veh, data.stock.props)
    SetVehicleNumberPlateText(veh, data.stock.plate or '')
    SetVehicleFixed(veh)
    SetVehicleDirtLevel(veh, tonumber(data.stock.props and data.stock.props.dirtLevel) or 0.0)   -- wash it from the menu
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleLights(veh, 2)

    state = { vehicle = veh, stock = data.stock, base = data.stock.props, fromLaptop = fromLaptop }
    Workshop.active = true
    Warehouse.HideDisplay(stockId, true)
    Workshop.Apply(veh, data.stock.build, state.base)
    createCam()
    FreezeEntityPosition(cache.ped, true)
    SetEntityVisible(cache.ped, false, false)
    Client.Fade(false, 250)

    data.avail = availability(veh)
    Workshop.Apply(veh, data.stock.build, state.base)
    Client.OpenUI('workshop', data)
    return true
end

function Workshop.Close(silent)
    if not Workshop.active then return end
    Workshop.active = false
    if state.cam then
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(state.cam, false)
    end
    if state.vehicle and DoesEntityExist(state.vehicle) then DeleteEntity(state.vehicle) end
    if state.stock then Warehouse.HideDisplay(state.stock.id, false) end
    FreezeEntityPosition(cache.ped, false)
    SetEntityVisible(cache.ped, true, false)
    local fromLaptop = state.fromLaptop
    state = {}
    if not silent and fromLaptop then Laptop.Reopen('stock') end
end

-----------------------------------------------------------------
-- UI handlers
-----------------------------------------------------------------
handlers.design = function(d)
    Laptop.Close(true)
    CreateThread(function()
        Wait(300)
        if not Workshop.Open(d.id, d.mode, true) then Laptop.Reopen('stock') end
    end)
    return true
end

handlers.wsPreview = function(d)
    if not Workshop.active then return false end
    Workshop.Apply(state.vehicle, d.build, state.base)
    if d.focus and presets[d.focus] then
        local p = presets[d.focus]
        state.heading, state.dist, state.height = p[1], p[2], p[3]
        placeCam()
    end
    return true
end

handlers.wsCam = function(d)
    if not Workshop.active then return false end
    state.heading = (state.heading + (tonumber(d.dx) or 0) * 0.35) % 360
    state.height = Cargo.Clamp(state.height - (tonumber(d.dy) or 0) * 0.01, 0.2, 4.0)
    if d.zoom then state.dist = Cargo.Clamp(state.dist + d.zoom * 0.6, 3.2, 10.0) end
    placeCam()
    return true
end

handlers.wsBuy = function(d)
    if not Workshop.active then return false end
    Workshop.Apply(state.vehicle, d.build, state.base)
    local props = Bridge.GetProps(state.vehicle)
    local res = lib.callback.await('nz_cargo:workshop:buy', false, state.stock.id, d.build, props)
    if not res then return { ok = false } end
    state.stock.build = res.stock.build
    state.stock.score = res.stock.score
    state.stock.rarity = res.stock.rarity
    state.base = props
    return res
end

handlers.wsClose = function()
    Client.CloseUI()
    Workshop.Close(false)
    return true
end

handlers.wsWash = function()
    if not Workshop.active then return false end
    local res = lib.callback.await('nz_cargo:workshop:wash', false, state.stock.id)
    if not res then return { ok = false } end
    local veh = state.vehicle
    if veh and DoesEntityExist(veh) then
        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
        lib.requestNamedPtfxAsset('core')
        UseParticleFxAsset('core')
        local c = GetEntityCoords(veh)
        StartParticleFxNonLoopedAtCoord('ent_amb_waterfall_splash_p', c.x, c.y, c.z + 0.6, 0.0, 0.0, 0.0, 1.6, false, false, false)
    end
    if state.base then state.base.dirtLevel = 0.0 end
    return res
end

handlers.wsLights = function(d)
    if Workshop.active then SetVehicleLights(state.vehicle, d.on and 2 or 1) end
    return true
end
