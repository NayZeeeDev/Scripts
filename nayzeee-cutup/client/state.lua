-- Shared client state. Every client module reads/writes the global CU table.
CU = {
    Active    = false,        -- CUT UP mode on
    Ped       = 0,
    Veh       = 0,
    IsDriver  = false,
    Speed     = 0.0,          -- m/s
    Settings  = {},
    MenuOpen  = false,
    HudHidden = false,

    Profile = {
        pbSolo = 0, pbCrew = 0, position = 0, crewPosition = 0, totalPlayers = 0,
        crew = nil, name = '',
    },

    Run = nil,                -- active run table (scoring.lua)

    Bonus = { fpv = false, physics = false, aggro = 0, sync = 0.0, syncLabel = nil },

    Wheel = {
        active = false, lastInput = 0,
        steer = 0.0, throttle = 0.0, brake = 0.0, clutch = 0.0, handbrake = false,
    },

    Trans = { gear = 1, mode = 'auto', clutchKey = false },

    Sync = { pct = 0.0, flow = false, partner = nil, crew = false, gap = 0.0, gapMax = 0.0, mates = 0 },

    NearbyNPC = {},           -- refreshed every 250 ms: { veh, driver, dist }
    Flash = { pending = false, last = 0 },
}

local KVP_SETTINGS = 'nayzeee-cutup:settings'

-- Player settings start from the server config. Players override them in F5 (saved with KVP).
function CU.BuildDefaults()
    local c = Config.Camera
    return {
        camera = {
            mode = c.Default, cockpitFov = c.CockpitFov, hoodFov = c.HoodFov, chaseFov = c.ChaseFov,
            seatX = 0.0, seatY = 0.0, seatZ = 0.0, pitch = c.Pitch, lookSpeed = c.LookSpeed,
            speedFov = c.SpeedFov, speedFovAmount = c.SpeedFovAmount, shake = c.Shake,
            chaseDistance = c.ChaseDistance, chaseHeight = c.ChaseHeight, chaseLag = c.ChaseLag,
            chaseTilt = c.ChaseTilt,
        },
        gameplay = {
            units = 'kmh', transmission = Config.Transmission.Default, density = 1.0,
            showArrows = true, ghostAlpha = true,
        },
        hud = { show = true, tacho = true, pb = true, bonuses = true, popups = true },
        ui = {
            accent = Config.UI.Accent, accent2 = Config.UI.Accent2, alert = Config.UI.Alert,
            scale = Config.UI.Scale, toastPosition = Config.UI.ToastPosition,
            sounds = Config.UI.Sounds, volume = Config.UI.Volume, reduceMotion = Config.UI.ReduceMotion,
        },
    }
end

function CU.LoadSettings()
    CU.Defaults = CU.BuildDefaults()
    local raw = GetResourceKvpString(KVP_SETTINGS)
    local saved = raw and json.decode(raw) or nil
    CU.Settings = Util.Merge(CU.Defaults, saved)
    if not Config.UI.PlayerPrefs then CU.Settings.ui = Util.DeepCopy(CU.Defaults.ui) end
    CU.Settings.ui.scale = Util.Clamp(CU.Settings.ui.scale, 0.8, 1.25)
    CU.Settings.gameplay.density = Util.Clamp(CU.Settings.gameplay.density, 0.25, 1.5)
    CU.Trans.mode = CU.Settings.gameplay.transmission
end

function CU.SaveSettings()
    SetResourceKvp(KVP_SETTINGS, json.encode(CU.Settings))
end

function CU.Debug(...)
    if Config.Debug then print('[nayzeee-cutup]', ...) end
end

function CU.Kmh(ms) return ms * 3.6 end

function CU.DisplaySpeed(ms)
    if CU.Settings.gameplay and CU.Settings.gameplay.units == 'mph' then
        return math.floor(ms * 2.23694 + 0.5), 'MPH'
    end
    return math.floor(ms * 3.6 + 0.5), 'KMH'
end

function CU.IsNPCVehicle(veh)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    local driver = GetPedInVehicleSeat(veh, -1)
    return driver ~= 0 and not IsPedAPlayer(driver)
end

local dimCache = {}
function CU.Dimensions(model)
    local d = dimCache[model]
    if not d then
        local mn, mx = GetModelDimensions(model)
        d = { min = mn, max = mx, width = mx.x - mn.x, length = mx.y - mn.y, height = mx.z - mn.z }
        dimCache[model] = d
    end
    return d
end

function CU.VehicleLabel(veh)
    local model = GetEntityModel(veh)
    local disp = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(disp)
    if label == 'NULL' or label == '' then label = disp end
    local make = GetMakeNameFromVehicleModel and GetMakeNameFromVehicleModel(model) or ''
    local makeLabel = make ~= '' and GetLabelText(make) or ''
    if makeLabel ~= '' and makeLabel ~= 'NULL' then return makeLabel .. ' ' .. label end
    return label
end
