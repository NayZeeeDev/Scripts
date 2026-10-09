AJ = AJ or {}

AJ.Resource = GetCurrentResourceName()
AJ.Event = function(name) return ('%s:%s'):format(AJ.Resource, name) end

--[[ Locations — zones are pre-processed once (bounding box + z range) so checks are cheap ]]

local byId = {}

for i = 1, #Config.Locations do
    local loc = Config.Locations[i]
    local zone = loc.zone

    if zone.points then
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for p = 1, #zone.points do
            local pt = zone.points[p]
            if pt.x < minX then minX = pt.x end
            if pt.y < minY then minY = pt.y end
            if pt.x > maxX then maxX = pt.x end
            if pt.y > maxY then maxY = pt.y end
        end
        local half = (zone.thickness or 20.0) / 2
        local baseZ = zone.points[1].z or loc.spawn.z
        zone.minZ = zone.minZ or (baseZ - half)
        zone.maxZ = zone.maxZ or (baseZ + half)
        zone.bounds = { minX, minY, maxX, maxY }
    end

    byId[loc.id] = loc
end

function AJ.GetLocation(id)
    return byId[id]
end

function AJ.DefaultLocation()
    return byId[Config.Sentence.defaultLocation] or Config.Locations[1]
end

local function pointInPoly(pts, x, y)
    local inside = false
    local j = #pts
    for i = 1, #pts do
        local xi, yi, xj, yj = pts[i].x, pts[i].y, pts[j].x, pts[j].y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function AJ.InZone(loc, coords)
    local zone = loc.zone

    if zone.radius then
        local c = zone.center
        local dx, dy, dz = coords.x - c.x, coords.y - c.y, coords.z - c.z
        return (dx * dx + dy * dy + dz * dz) <= zone.radius * zone.radius
    end

    if coords.z < zone.minZ or coords.z > zone.maxZ then return false end

    local b = zone.bounds
    if coords.x < b[1] or coords.y < b[2] or coords.x > b[3] or coords.y > b[4] then return false end

    return pointInPoly(zone.points, coords.x, coords.y)
end

function AJ.Dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function AJ.Debug(...)
    if Config.Debug then print(('^5[%s]^7'):format(AJ.Resource), ...) end
end
