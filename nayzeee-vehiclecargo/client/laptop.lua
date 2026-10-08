-----------------------------------------------------------------
-- Office laptop: prop, third eye, camera glide into the screen,
-- open/close of the laptop UI.
-----------------------------------------------------------------
Laptop = { open = false }
local handlers = Client.Handlers
local C = Config.Laptop

local prop, point, cams = nil, nil, {}
local hidden = {}

-- Hide GTA's own laptop on the desk (and any other listed model) near our spots.
-- Our prop is a script object, so it is never hidden.
function Laptop.HideDefaults(points)
    Laptop.ShowDefaults()
    for _, p in ipairs(points) do
        for _, m in ipairs(C.HideModels or {}) do
            local h = joaat(m)
            CreateModelHideExcludingScriptObjects(p.x, p.y, p.z, C.HideRadius, h, true)
            hidden[#hidden + 1] = { p.x, p.y, p.z, h }
        end
    end
end

function Laptop.ShowDefaults()
    for _, e in ipairs(hidden) do RemoveModelHide(e[1], e[2], e[3], C.HideRadius, e[4], false) end
    hidden = {}
end

function Laptop.Setup(p)
    Laptop.Teardown()
    point = p
    if C.SpawnProp then
        local hash = Client.LoadModel(C.Model)
        if hash then
            prop = CreateObject(hash, p.x, p.y, p.z, false, false, false)
            SetEntityHeading(prop, p.w or 0.0)
            FreezeEntityPosition(prop, true)
            SetModelAsNoLongerNeeded(hash)
        end
    end
    Bridge.AddPoint('nz_laptop', vec3(p.x, p.y, p.z), 1.3, {
        { label = L('ti_laptop'), icon = 'fa-solid fa-laptop', onSelect = function() Laptop.Open() end,
          canInteract = function() return not Laptop.open and not Client.mission end },
    })
end

function Laptop.Teardown()
    Bridge.RemovePoint('nz_laptop')
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
end

-- The side of the laptop the screen faces (unit vector)
local function screenSide()
    local h = math.rad(point.w or 0.0)
    local fx, fy = math.sin(h), -math.cos(h)
    if C.FlipSide then fx, fy = -fx, -fy end
    return fx, fy
end

local function destroyCams()
    for _, c in ipairs(cams) do if DoesCamExist(c) then DestroyCam(c, false) end end
    cams = {}
end

-- Camera from where the player is looking, gliding to the laptop screen.
local function glideIn()
    local fx, fy = screenSide()
    local screen = vec3(point.x, point.y, point.z + 0.14)
    local to = vec3(screen.x + fx * C.CamDistance, screen.y + fy * C.CamDistance, screen.z + C.CamHeight)

    local gc, gr = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local from = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', gc.x, gc.y, gc.z, gr.x, gr.y, gr.z, GetGameplayCamFov(), false, 2)
    local target = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', to.x, to.y, to.z, 0.0, 0.0, 0.0, 42.0, false, 2)
    PointCamAtCoord(target, screen.x, screen.y, screen.z)
    cams = { from, target }
    SetCamActive(from, true)
    RenderScriptCams(true, false, 0, true, false)
    SetCamActiveWithInterp(target, from, C.Transition, 1, 1)
    Wait(C.Transition)
end

-- Step in front of the screen, facing it
local function standInFront(ped)
    local fx, fy = screenSide()
    local d = C.StandDistance or 0.75
    local sx, sy = point.x + fx * d, point.y + fy * d
    local face = (math.deg(math.atan(-fx, fy)) + 180.0) % 360    -- look back at the laptop
    local pc = GetEntityCoords(ped)
    if #(vec2(pc.x, pc.y) - vec2(sx, sy)) > 0.25 then
        TaskGoStraightToCoord(ped, sx, sy, pc.z, 1.0, 2500, face, 0.1)
        local t = GetGameTimer() + 2500
        while GetGameTimer() < t do
            local c = GetEntityCoords(ped)
            if #(vec2(c.x, c.y) - vec2(sx, sy)) < 0.3 then break end
            Wait(50)
        end
    end
    ClearPedTasks(ped)
    SetEntityHeading(ped, face)
    Wait(150)
end

function Laptop.Open()
    if Laptop.open or not point or not Client.inside then return end
    local payload = lib.callback.await('nz_cargo:terminal', false)
    if not payload then return end
    Laptop.open = true
    local ped = cache.ped
    standInFront(ped)
    if C.Anim and C.Anim.dict then
        lib.requestAnimDict(C.Anim.dict)
        TaskPlayAnim(ped, C.Anim.dict, C.Anim.name, 3.0, 3.0, -1, 49, 0, false, false, false)
    end
    glideIn()
    payload.username = C.Username == 'player' and payload.profile.name or C.Username
    Client.OpenUI('laptop', payload)
end

function Laptop.Close(instant)
    if not Laptop.open then return end
    Laptop.open = false
    Client.CloseUI()
    RenderScriptCams(false, not instant, instant and 0 or math.floor(C.Transition * 0.75), true, false)
    destroyCams()
    if C.Anim and C.Anim.dict then StopAnimTask(cache.ped, C.Anim.dict, C.Anim.name, 2.0) end
end

-- Reopen the laptop straight on an app (after the design bay etc.)
function Laptop.Reopen(app)
    if not point then return end
    CreateThread(function()
        Laptop.Open()
        if Laptop.open and app then Client.Send('laptopApp', { app = app }) end
    end)
end

handlers.laptopClose = function() Laptop.Close() return true end

-- Owner places their own spots on the floor (closes the laptop first)
handlers.layoutCustom = function()
    Laptop.Close()
    CreateThread(function() Wait(800) Layout.Start() end)
    return true
end

-- Floor plan app: owner removed some spots
handlers.layoutSet = function(d)
    if type(d.slots) ~= 'table' or #d.slots == 0 then return { ok = false } end
    if not lib.callback.await('nz_cargo:layout:custom', false, d.slots) then return { ok = false } end
    return lib.callback.await('nz_cargo:terminal', false) or { ok = false }
end

handlers.trackerHowTo = function()
    Bridge.Notify('Go to the spot you want outside and use /cargotrackerspot.', 'info', 'Tracker Workshop', 8000)
    return true
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Laptop.open then RenderScriptCams(false, false, 0, true, false) end
    destroyCams()
    Laptop.Teardown()
    Laptop.ShowDefaults()
end)
