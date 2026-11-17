if not NAYZEEE_LOCK_OK then return end

NZ = NZ or {}
NZ.Resource = GetCurrentResourceName()
NZ.Version = GetResourceMetadata(NZ.Resource, 'version', 0) or '1.0.0'

local L = Locales[Config.Locale] or Locales['en']
NZ.Strings = L

function NZ.T(key, ...)
    local s = L[key] or (Locales['en'] and Locales['en'][key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        return ok and out or s
    end
    return s
end

function NZ.Debug(...)
    if not Config.Debug then return end
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print(('^5[nzm]^7 %s'):format(table.concat(parts, ' ')))
end

function NZ.Trim(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- "jOHN o'neil-smith" -> "John O'Neil-Smith"
function NZ.Capitalize(s)
    s = NZ.Trim(s):lower():gsub('%s+', ' ')
    return (s:gsub("(%f[%a])(%a)", function(_, c) return c:upper() end))
end

function NZ.Decode(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return nil end
    local ok, out = pcall(json.decode, v)
    return ok and out or nil
end

function NZ.Truthy(v)
    return v == true or v == 1 or v == '1' or v == 'true'
end

function NZ.Vec(t)
    if not t then return nil end
    local x, y, z = tonumber(t.x), tonumber(t.y), tonumber(t.z)
    if not x or not y or not z then return nil end
    return vec4(x + 0.0, y + 0.0, z + 0.0, (tonumber(t.w or t.heading or t.h) or 0.0) + 0.0)
end

function NZ.Copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = NZ.Copy(v) end
    return o
end

-- Theme / mood / pose lookups (config is shared, so both sides use the same helpers)
function NZ.Theme(id) return id and Config.LobbyThemes[id] or nil end

function NZ.MoodById(id)
    if not id then return nil end
    for _, m in ipairs(Config.Moods) do if m.id == id then return m end end
end

function NZ.PoseById(id)
    if not id then return nil end
    for _, p in ipairs(Config.Poses) do if p.id == id then return p end end
end

function NZ.CoupleById(id)
    if not id then return nil end
    for _, p in ipairs(Config.CoupleAnimations) do if p.id == id then return p end end
end

function NZ.PetById(id)
    if not id then return nil end
    for _, p in ipairs(Config.Pets.list) do if p.id == id then return p end end
end

-- Theme ids in display order
function NZ.ThemeIds()
    local ids = {}
    for id in pairs(Config.LobbyThemes) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (Config.LobbyThemes[a].order or 99) < (Config.LobbyThemes[b].order or 99) end)
    return ids
end

-- Weapon class from Config.WeaponShowcase.classes (nil when unknown)
local weaponClass
function NZ.WeaponClass(name)
    if not weaponClass then
        weaponClass = {}
        for class, list in pairs(Config.WeaponShowcase.classes) do
            for _, w in ipairs(list) do weaponClass[w:upper()] = class end
        end
    end
    return name and weaponClass[name:upper()] or nil
end
