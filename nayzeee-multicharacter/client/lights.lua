if not NAYZEEE_LOCK_OK then return end

--[[
    Studio lighting. Draw-lights only live for one frame, so a Wait(0) loop redraws the rig while the
    lobby / cutscene is up (and ends with it).
      rig      theme.lights.rig or Config.Lighting.rig (key / fill / rim)
      extra    theme.lights.extra (neon practicals, worklights ...)
      fill     one soft point per extra actor (Config.Lighting.squadFill)
    Offsets are rel space (right, forward, up) of an anchor ped: the rig + extras follow the LIVE position and
    heading of the main actor every frame (walk-ins, moving helicopter, departure), fills follow their actor.
    Colours are multiplied by mood.tint and theme.lights.tint (/255), intensity by mood.scale × theme.lights.scale.
    Performance mode: no shadows, at most 2 extras, no squad fills.
]]

Lights = { active = false, moodId = nil, mood = nil, draw = {}, token = 0 }

local L = Config.Lighting
local rad, sin, cos, sqrt = math.rad, math.sin, math.cos, math.sqrt

local function tint(color, a, b)
    local r, g, bl = color[1] or 255, color[2] or 255, color[3] or 255
    for _, t in ipairs({ a or false, b or false }) do
        if t then r, g, bl = r * (t[1] or 255) / 255, g * (t[2] or 255) / 255, bl * (t[3] or 255) / 255 end
    end
    return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(bl + 0.5)
end

-- Rebuild the light list (rel-space entries; world positions are resolved per frame)
function Lights.Build()
    local theme = Scene.theme
    local list = {}
    if not theme or not L.enabled then Lights.draw = list return end
    local tl = theme.lights or {}
    local mood = Lights.mood or {}
    local perf = Settings.Get('perf')
    local shadows = L.shadows and not perf
    local mul = (mood.scale or 1.0) * (tl.scale or 1.0)
    local shadowId = 200

    local function add(l, anchorSlot)
        local o = l.offset or vec3(0.0, 0.0, 1.5)
        local t = l.target or vec3(0.0, 0.0, 0.6)
        local r, g, b = tint(l.color or { 255, 255, 255 }, mood.tint, tl.tint)
        shadowId = shadowId + 1
        list[#list + 1] = {
            slot = anchorSlot, spot = l.type == 'spot',
            ox = o.x, oy = o.y, oz = o.z, tx = t.x, ty = t.y, tz = t.z,
            r = r, g = g, b = b,
            range = (l.range or 5.0) + 0.0, intensity = (l.intensity or 1.0) * mul + 0.0,
            radius = (l.radius or 30.0) + 0.0, falloff = (l.falloff or 15.0) + 0.0,
            shadow = shadows and l.shadow ~= false and shadowId or nil,
        }
    end

    for _, l in ipairs(tl.rig or L.rig or {}) do add(l, 1) end
    for i, l in ipairs(tl.extra or {}) do
        if not perf or i <= 2 then add(l, 1) end
    end
    if L.squadFill and not perf then
        local f = L.squadFill
        for slot in pairs(Actors.list) do
            if slot ~= 1 then
                add({ type = 'point', offset = f.offset, color = f.color, range = f.range, intensity = f.intensity, shadow = false }, slot)
            end
        end
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)   -- grouped by anchor: one basis per actor per frame
    Lights.draw = list
end

function Lights.Refresh()
    if Lights.active then Lights.Build() end
end

-- Anchor basis for an actor slot: live ped coords + heading, else the static mark
local function basis(slot)
    local a = Actors.list[slot]
    local ped = a and a.ped
    local x, y, z, h
    if ped and DoesEntityExist(ped) then
        local c = GetEntityCoords(ped)
        x, y, z, h = c.x, c.y, c.z, GetEntityHeading(ped)
    else
        local m = (a and a.mark) or Scene.main
        if not m then return nil end
        x, y, z, h = m.x, m.y, m.z, m.w or 0.0
    end
    local r = rad(h)
    local s, c = sin(r), cos(r)
    -- right = (cos, sin), forward = (-sin, cos)  (NZ.Right / NZ.Fwd)
    return x, y, z, c, s, -s, c
end

local function frame(draw)
    local cur, x, y, z, rx, ry, fx, fy = nil, nil, nil, nil, nil, nil, nil, nil
    for i = 1, #draw do
        local e = draw[i]
        if e.slot ~= cur then
            cur = e.slot
            x, y, z, rx, ry, fx, fy = basis(cur)
        end
        if x then
            local px, py, pz = x + rx * e.ox + fx * e.oy, y + ry * e.ox + fy * e.oy, z + e.oz
            if e.spot then
                local dx = (x + rx * e.tx + fx * e.ty) - px
                local dy = (y + ry * e.tx + fy * e.ty) - py
                local dz = (z + e.tz) - pz
                local len = sqrt(dx * dx + dy * dy + dz * dz)
                if len < 0.001 then dx, dy, dz, len = 0.0, 0.0, -1.0, 1.0 end
                dx, dy, dz = dx / len, dy / len, dz / len
                if e.shadow then
                    -- DrawSpotLightWithShadow(pos, dir, rgb, distance, brightness, roundness, radius, falloff, shadowId)
                    DrawSpotLightWithShadow(px, py, pz, dx, dy, dz, e.r, e.g, e.b, e.range, e.intensity, 0.0, e.radius, e.falloff, e.shadow)
                else
                    DrawSpotLight(px, py, pz, dx, dy, dz, e.r, e.g, e.b, e.range, e.intensity, 0.0, e.radius, e.falloff)
                end
            elseif e.shadow then
                DrawLightWithRangeAndShadow(px, py, pz, e.r, e.g, e.b, e.range, e.intensity, 1.0)
            else
                DrawLightWithRange(px, py, pz, e.r, e.g, e.b, e.range, e.intensity)
            end
        end
    end
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
            frame(Lights.draw)
            Wait(0)
        end
        if Lights.token == my then Lights.active = false end
    end)
end

-- Mood: clock / weather / timecycle + rig tint. nil = the theme's default mood.
function Lights.SetMood(id)
    local theme = Scene.theme
    if not theme then return end
    local mood = NZ.MoodById(id)
    if mood and theme.moods then
        local allowed = false
        for _, m in ipairs(theme.moods) do if m == mood.id then allowed = true end end
        if not allowed then mood = nil end
    end
    mood = mood or NZ.MoodById(theme.mood)
    Lights.moodId = mood and mood.id or nil
    Lights.mood = mood

    local hour, minute = theme.hour or 12, theme.minute or 0
    if mood and mood.hour then hour, minute = mood.hour, mood.minute or 0 end
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
