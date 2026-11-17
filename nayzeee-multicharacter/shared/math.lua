if not NAYZEEE_LOCK_OK then return end

--[[
    "Rel space": theme layouts are authored relative to the main character.
    offset = vec3(right, forward, up) where forward is the way the main character faces.
]]

NZ = NZ or {}

local rad, sin, cos, deg, atan = math.rad, math.sin, math.cos, math.deg, math.atan

function NZ.Fwd(h)
    local r = rad(h or 0.0)
    return vec3(-sin(r), cos(r), 0.0)
end

function NZ.Right(h)
    local r = rad(h or 0.0)
    return vec3(cos(r), sin(r), 0.0)
end

-- World position of `off` (vec3 right/forward/up) from `base` (vec4)
function NZ.Rel(base, off)
    if not off then return vec3(base.x, base.y, base.z) end
    local f, r = NZ.Fwd(base.w), NZ.Right(base.w)
    return vec3(base.x + r.x * off.x + f.x * off.y, base.y + r.y * off.x + f.y * off.y, base.z + (off.z or 0.0))
end

-- vec4 for a ped / prop / vehicle: rel position + heading delta
function NZ.RelH(base, off, dh)
    local p = NZ.Rel(base, off)
    return vec4(p.x, p.y, p.z, ((base.w or 0.0) + (dh or 0.0)) % 360.0)
end

-- Resolve a config placement { coords = vec4 } | { offset = vec3, heading = dh } against `base`
function NZ.Place(base, def)
    if not def then return vec4(base.x, base.y, base.z, base.w or 0.0) end
    if def.coords then
        local c = def.coords
        return vec4(c.x, c.y, c.z, (c.w or base.w or 0.0) + 0.0)
    end
    return NZ.RelH(base, def.offset or vec3(0.0, 0.0, 0.0), def.heading or 0.0)
end

-- Heading (deg) that looks from `from` to `to`
function NZ.HeadingTo(from, to)
    return deg(atan(-(to.x - from.x), to.y - from.y)) % 360.0
end

function NZ.Lerp(a, b, t) return a + (b - a) * t end
