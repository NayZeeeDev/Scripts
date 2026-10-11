local radarShown = nil
local minimapMovie = nil
local lastResX, lastResY, lastSafe = 0, 0, 0

local function hideHealthBars()
    if not Config.Minimap.hideHealthBars then return end
    if not minimapMovie then minimapMovie = RequestScaleformMovie('minimap') end
    BeginScaleformMovieMethod(minimapMovie, 'SETUP_HEALTH_ARMOUR')
    ScaleformMovieMethodAddParamInt(3)
    EndScaleformMovieMethod()
end
NHUD.hideHealthBars = hideHealthBars

-- Screen-space rectangle of the radar (percent), so the UI can frame it and dock the street bar / speed sign.
local function anchor()
    local safe = GetSafeZoneSize()
    local aspect = GetAspectRatio(false)
    local resX, resY = GetActiveScreenResolution()
    local xs, ys = 1.0 / resX, 1.0 / resY
    local w = xs * (resX / (4 * aspect))
    local h = ys * (resY / 5.674)
    local margin = math.abs(safe - 1.0) * 10
    local left = xs * (resX * ((1.0 / 20.0) * margin))
    local bottom = 1.0 - ys * (resY * ((1.0 / 20.0) * margin))
    return { l = left * 100, b = bottom * 100, w = w * 100, h = h * 100 }
end

function NHUD.sendMap(force)
    local resX, resY = GetActiveScreenResolution()
    local safe = GetSafeZoneSize()
    if not force and resX == lastResX and resY == lastResY and safe == lastSafe then return end
    lastResX, lastResY, lastSafe = resX, resY, safe
    NHUD.send('map', { m = anchor() })
end

function NHUD.updateRadar(inVehicle, force)
    if inVehicle == nil then inVehicle = GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 end
    local mode = NHUD.settings.minimap
    local show = NHUD.visible and (mode == 'always' or (mode == 'vehicle' and inVehicle))
    if show ~= radarShown or force then
        radarShown = show
        DisplayRadar(show)
        NHUD.set('radar', show)
        if show then hideHealthBars() end
    end
end

-- Native HUD text hiding. In 'smart' mode the per-frame thread only exists for a few seconds at a time.
local burstUntil, burstRunning = 0, false
local HideHudComponentThisFrame, GetGameTimer = HideHudComponentThisFrame, GetGameTimer

function NHUD.burstHide(ms)
    if not Config.HideNativeHud then return end
    local t = GetGameTimer() + ms
    if t > burstUntil then burstUntil = t end
    if burstRunning then return end
    burstRunning = true
    CreateThread(function()
        local always = Config.HideNativeHud == 'always'
        while always or GetGameTimer() < burstUntil do
            HideHudComponentThisFrame(3)  -- cash
            HideHudComponentThisFrame(4)  -- mp cash
            HideHudComponentThisFrame(6)  -- vehicle name
            HideHudComponentThisFrame(7)  -- area name
            HideHudComponentThisFrame(8)  -- vehicle class
            HideHudComponentThisFrame(9)  -- street name
            HideHudComponentThisFrame(13) -- cash change
            Wait(0)
        end
        burstRunning = false
    end)
end

CreateThread(function()
    SetRadarBigmapEnabled(false, false)
    hideHealthBars()
    if Config.HideNativeHud == 'always' then NHUD.burstHide(0) end
end)
