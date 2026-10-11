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

-- Minimap shape + height. Positive Y moves a component up from the bottom of the screen.
-- 'square' / 'circle' need the squaremap.ytd / circlemap.ytd textures in this resource's stream/ folder.
local SHAPES = {
    default = { clip = 0, map = { -0.0045, 0.002, 0.150, 0.188 }, mask = { 0.020, 0.032, 0.111, 0.159 }, blur = { -0.03, 0.022, 0.266, 0.237 } },
    square  = { dict = 'squaremap', clip = 0, map = { 0.0, -0.047, 0.1638, 0.183 }, mask = { 0.0, 0.0, 0.128, 0.20 }, blur = { -0.01, 0.025, 0.262, 0.300 } },
    circle  = { dict = 'circlemap', clip = 1, map = { -0.0100, -0.030, 0.180, 0.258 }, mask = { 0.200, 0.0, 0.065, 0.20 }, blur = { -0.00, 0.015, 0.252, 0.338 } },
}
local layout = { shape = 'default', raise = 0.0 }
local applied = nil

local function hasTextures(dict)
    if not dict then return true end
    RequestStreamedTextureDict(dict, false)
    local timeout = GetGameTimer() + 1500
    while not HasStreamedTextureDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(50)
    end
    return true
end

function NHUD.setMinimapLayout(shape, raise)
    shape = SHAPES[shape] and shape or 'default'
    raise = tonumber(raise) or 0.0
    local key = shape .. raise
    if key == applied then return end
    applied = key
    CreateThread(function()
        local def = SHAPES[shape]
        if def.dict and not hasTextures(def.dict) then
            print(('^3[nayzeee-hud]^7 Minimap shape "%s" needs stream/%s.ytd. Using the default shape.'):format(shape, def.dict))
            shape, def = 'default', SHAPES.default
        end
        layout.shape, layout.raise = shape, raise
        local resX, resY = GetActiveScreenResolution()
        local aspect = resX / resY
        local offset = aspect > (1920 / 1080) and (((1920 / 1080) - aspect) / 3.6) - 0.008 or 0.0
        if def.dict then
            AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', def.dict, 'radarmasksm')
            AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', def.dict, 'radarmasksm')
            SetBlipAlpha(GetNorthRadarBlip(), 0)
        else
            RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
            RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
            SetBlipAlpha(GetNorthRadarBlip(), 255)
        end
        SetMinimapClipType(def.clip)
        for _, part in ipairs({ { 'minimap', def.map }, { 'minimap_mask', def.mask }, { 'minimap_blur', def.blur } }) do
            local v = part[2]
            SetMinimapComponentPosition(part[1], 'L', 'B', v[1] + offset, v[2] + raise, v[3], v[4])
        end
        SetRadarBigmapEnabled(true, false)
        Wait(50)
        SetRadarBigmapEnabled(false, false)
        hideHealthBars()
        NHUD.sendMap(true)
    end)
end

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
    local bottom = 1.0 - ys * (resY * ((1.0 / 20.0) * margin)) - layout.raise
    return { l = left * 100, b = bottom * 100, w = w * 100, h = h * 100, shape = layout.shape }
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
    local show = NHUD.visible and HudBridge.loaded and (mode == 'always' or (mode == 'vehicle' and inVehicle))
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
