UI = { ready = false, focus = false }

function UI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function UI.On(name, fn)
    RegisterNUICallback(name, function(data, cb)
        local ok, res = pcall(fn, data or {})
        if not ok then print(('^1[nayzeee-tuning] NUI %s: %s^7'):format(name, res)) res = false end
        cb(res == nil and true or res)
    end)
end

function UI.Focus(state, keepInput)
    UI.focus = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(keepInput == true)
end

function Notify(msg, kind, duration) Bridge.Notify(msg, kind, duration) end
RegisterNetEvent('nayzeee-tuning:notify', function(msg, kind) Notify(msg, kind) end)

--------------------------------------------------------------------- vehicle helpers

VehUtil = {}

function VehUtil.Label(veh)
    local model = GetEntityModel(veh)
    local name = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(name)
    if label == 'NULL' then label = name:sub(1, 1):upper() .. name:sub(2):lower() end
    local makeName = GetMakeNameFromVehicleModel and GetMakeNameFromVehicleModel(model) or ''
    local make = makeName ~= '' and GetLabelText(makeName) or ''
    if make == 'NULL' then make = '' end
    return label, make, name:lower()
end

function VehUtil.Control(veh, timeout)
    if NetworkHasControlOfEntity(veh) then return true end
    NetworkRequestControlOfEntity(veh)
    local t = GetGameTimer() + (timeout or 1500)
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < t do
        Wait(25)
        NetworkRequestControlOfEntity(veh)
    end
    return NetworkHasControlOfEntity(veh)
end

function VehUtil.Closest(maxDist)
    local coords = GetEntityCoords(cache.ped)
    local veh = lib.getClosestVehicle(coords, maxDist or 4.0, false)
    return veh
end

function VehUtil.BoneCoords(veh, names)
    for _, b in ipairs(names) do
        local idx = GetEntityBoneIndexByName(veh, b)
        if idx ~= -1 then return GetWorldPositionOfEntityBone(veh, idx), b end
    end
    return GetEntityCoords(veh), nil
end

function VehUtil.Plate(veh) return NZ.TrimPlate(GetVehicleNumberPlateText(veh)) end

--------------------------------------------------------------------- NUI boot

local function uiConfig()
    local parts = {}
    for id, p in pairs(Config.Parts) do
        parts[id] = { label = p.label, icon = p.icon, kind = p.kind, cam = p.cam }
    end
    local cats = {}
    for i, c in ipairs(Config.Categories) do cats[i] = { id = c.id, label = c.label, icon = c.icon, items = c.items } end
    local swaps = {}
    for i, s in ipairs(Config.EngineSwaps.List) do swaps[i] = { sound = s.sound, label = s.label, power = s.power } end
    local ui = (Locales[Config.Locale] or {}).ui or (Locales.en and Locales.en.ui) or {}
    return {
        version = Config.Version, parts = parts, categories = cats,
        paints = Config.Paints, chameleon = Config.ChameleonPaints.Enabled and Config.ChameleonPaints.colors or nil,
        finishes = Config.PaintFinishes, xenon = Config.XenonColors, xenonRGB = Config.XenonCustomRGB,
        tints = Config.WindowTints, plates = Config.PlateStyles, wheelTypes = Config.WheelTypes,
        neonPresets = Config.NeonPresets, smokePresets = Config.SmokePresets, patterns = Config.NeonPatterns,
        ecu = { params = Config.ECU.Params, presets = Config.ECU.Presets },
        nitrous = Config.Nitrous.Levels, swaps = swaps,
        stance = { offset = Config.Stance.Offset, camber = Config.Stance.Camber },
        dims = Config.WheelDimensions, height = Config.RideHeight, air = Config.AirRide.Presets,
        perf = { tests = Config.PerfTest.Tests, units = Config.PerfTest.Units, enabled = Config.PerfTest.Enabled },
        plate = { min = Config.Plates.MinLength, max = Config.Plates.MaxLength },
        builds = Config.Builds.Enabled, testDrive = Config.TestDrive.Enabled, testDriveTime = Config.TestDrive.Duration,
        discounts = Config.Discounts.Enabled,
        strings = ui,
    }
end

UI.On('ready', function()
    UI.ready = true
    UI.Send('init', uiConfig())
    return true
end)

UI.On('close', function()
    TriggerEvent('nayzeee-tuning:uiClosed')
    return true
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if UI.focus then SetNuiFocus(false, false) end
    Bridge.TextUI(false)
end)
