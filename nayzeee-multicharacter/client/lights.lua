if not NAYZEEE_LOCK_OK then return end

--[[
    Studio lighting. Draw-lights only live for one frame, so a Wait(0) loop redraws the rig while the
    lobby / cutscene is up (and ends with it). Positions are precomputed in world space whenever the scene,
    mood, squad or settings change, so the loop itself only calls the draw natives.
      rig      theme.lights.rig or Config.Lighting.rig (key / fill / rim)
      extra    theme.lights.extra (neon practicals, worklights ...)
      fill     one soft point per extra actor (Config.Lighting.squadFill)
    Colours are multiplied by mood.tint and theme.lights.tint (/255), intensity by mood.scale × theme.lights.scale.
]]

Lights = { active = false, moodId = nil, mood = nil, draw = {}, token = 0 }

local L = Config.Lighting

local function tint(color, ...)
    local r, g, b = color[1] or 255, color[2] or 255, color[3] or 255
    for i = 1, select('#', ...) do
        local t = select(i, ...)
        if t then
            r, g, b = r * (t[1] or 255) / 255, g * (t[2] or 255) / 255, b * (t[3] or 255) / 255
        end
    end
    return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

local function entry(l, pos, target, mul, tints, shadowId)
    local r, g, b = tint(l.color or { 255, 255, 255 }, tints[1], tints[2])
    local e = {
        spot = l.type == 'spot', x = pos.x, y = pos.y, z = pos.z, r = r, g = g, b = b,
        range = (l.range or 5.0) + 0.0, intensity = (l.intensity or 1.0) * mul + 0.0,
        radius = (l.radius or 30.0) + 0.0, falloff = (l.falloff or 15.0) + 0.0,
        shadow = shadowId,
    }
    if e.spot then
        local t = target or vec3(pos.x, pos.y, pos.z - 1.0)
        local d = t - pos
        local len = #d
        if len < 0.001 then d, len = vec3(0.0, 0.0, -1.0), 1.0 end
        e.dx, e.dy, e.dz = d.x / len, d.y / len, d.z / len
    end
    return e
end

-- Rebuild the world-space light list
function Lights.Build()
    local theme, base = Scene.theme, Scene.main
    local list = {}
    if not theme or not base or not L.enabled then Lights.draw = list return end
    local tl = theme.lights or {}
    local mood = Lights.mood or {}
    local perf = Settings.Get('perf')
    local shadows = L.shadows and not perf
    local mul = (mood.scale or 1.0) * (tl.scale or 1.0)
    local tints = { mood.tint, tl.tint }
    local shadowId = 200

    local function add(l, at)
        local pos = NZ.Rel(at, l.offset or vec3(0.0, 0.0, 1.5))
        local target = l.target and NZ.Rel(at, l.target) or nil
        shadowId = shadowId + 1
        list[#list + 1] = entry(l, pos, target, mul, tints, shadows and (l.shadow ~= false) and shadowId or nil)
    end

    for _, l in ipairs(tl.rig or L.rig or {}) do add(l, base) end
    for i, l in ipairs(tl.extra or {}) do
        if not perf or i <= 2 then add(l, base) end
    end
    -- Soft fill on every extra actor so the squad is not left in the dark (skipped in performance mode)
    if L.squadFill and not perf then
        local f = L.squadFill
        for slot, a in pairs(Actors.list) do
            if slot ~= 1 and a.mark then
                add({ type = 'point', offset = f.offset, color = f.color, range = f.range, intensity = f.intensity, shadow = false }, a.mark)
            end
        end
    end
    Lights.draw = list
end

-- Actors changed (squad / pet placed)
function Lights.Refresh()
    if Lights.active then Lights.Build() end
end

function Lights.Start()
    Lights.Build()
    if Lights.active or not L.enabled then return end
    Lights.active = true
    Lights.token = Lights.token + 1
    local my = Lights.token
    CreateThread(function()
        while Lights.active and Lights.token == my do
            if not (Main.open or Cutscene.running or (Editor and Editor.active)) then break end
            local draw = Lights.draw
            for i = 1, #draw do
                local e = draw[i]
                if e.spot then
                    if e.shadow then
                        -- DrawSpotLightWithShadow(pos, dir, rgb, distance, brightness, roundness, radius, falloff, shadowId)
                        DrawSpotLightWithShadow(e.x, e.y, e.z, e.dx, e.dy, e.dz, e.r, e.g, e.b, e.range, e.intensity, 0.0, e.radius, e.falloff, e.shadow)
                    else
                        DrawSpotLight(e.x, e.y, e.z, e.dx, e.dy, e.dz, e.r, e.g, e.b, e.range, e.intensity, 0.0, e.radius, e.falloff)
                    end
                elseif e.shadow then
                    DrawLightWithRangeAndShadow(e.x, e.y, e.z, e.r, e.g, e.b, e.range, e.intensity, 1.0)
                else
                    DrawLightWithRange(e.x, e.y, e.z, e.r, e.g, e.b, e.range, e.intensity)
                end
            end
            Wait(0)
        end
        if Lights.token == my then Lights.active = false end
    end)
end

-- Mood: clock / weather / timecycle + rig tint. nil = the theme's default mood.
function Lights.SetMood(id)
    local theme = Scene.theme
    if not theme then return end
    local mood = NZ.MoodById(id) or NZ.MoodById(theme.mood)
    Lights.moodId = mood and mood.id or nil
    Lights.mood = mood

    local hour = (mood and mood.hour) or theme.hour or 12
    local minute = (mood and mood.hour and mood.minute) or (mood and mood.hour and 0) or theme.minute or 0
    World.Apply((mood and mood.weather) or theme.weather or 'CLEAR', hour, minute)

    local tc = (mood and mood.timecycle) or theme.timecycle
    ClearTimecycleModifier()
    if tc and tc.name then
        SetTimecycleModifier(tc.name)
        SetTimecycleModifierStrength((tc.strength or 1.0) + 0.0)
    end
    Lights.Build()
end

function Lights.Stop()
    Lights.active = false
    Lights.token = Lights.token + 1
    Lights.draw = {}
    ClearTimecycleModifier()
end
