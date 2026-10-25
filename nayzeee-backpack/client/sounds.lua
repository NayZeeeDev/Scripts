-----------------------------------------------------------------
-- Bag sounds (client)
--
-- Volume falls off with distance from the camera; left / right comes
-- from where the sound is relative to where you're looking.
-----------------------------------------------------------------

local cfg = Config.Sounds or {}

Sound = {}

local function send(name, coords)
    if not cfg.enabled then return end
    local level = (cfg.levels and cfg.levels[name]) or 1.0
    if level <= 0 then return end

    local cam = GetFinalRenderedCamCoord()
    local d = #(cam - coords)
    local range = cfg.range or 12.0
    if d > range then return end

    local fall = 1.0 - d / range
    local vol = (cfg.volume or 0.6) * level * fall * fall

    -- -1 left .. 1 right
    local pan = 0.0
    if d > 0.5 then
        local rz = math.rad(GetFinalRenderedCamRot(2).z)
        local dx, dy = (coords.x - cam.x) / d, (coords.y - cam.y) / d
        pan = (dx * math.cos(rz) + dy * math.sin(rz)) * 0.8
    end

    SendNUIMessage({ action = 'sfx', data = { name = name, vol = vol, pan = pan } })
end

RegisterNetEvent('nayzeee-backpack:sound', function(name, coords)
    send(name, vector3(coords.x, coords.y, coords.z))
end)

--- A sound everyone near you hears (for menus only the client knows about).
function Sound.near(name)
    TriggerServerEvent('nayzeee-backpack:sound:ask', name)
end

--- Only you hear it (UI feedback).
function Sound.local_(name)
    send(name, GetFinalRenderedCamCoord())
end

CreateThread(function()
    Wait(1000)
    if next(cfg.files or {}) then SendNUIMessage({ action = 'sfxFiles', data = cfg.files }) end
end)
