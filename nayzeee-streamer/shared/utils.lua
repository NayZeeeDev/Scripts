-- Shared helpers: locale lookup, debug prints, table / number / vector helpers, item classification.

local RESOURCE = GetCurrentResourceName()

Utils = Utils or {}
PhoneBridges = PhoneBridges or {}   -- filled by bridge/phones/*.lua

---------------------------------------------------------------------------------------------------
-- Locale

local function lookup(tbl, key)
    if type(tbl) ~= 'table' or type(key) ~= 'string' then return nil end
    local value = tbl[key]
    if value ~= nil then return value end
    if not key:find('.', 1, true) then return nil end
    local node = tbl
    for part in key:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    return node
end

--- Locale string for key ('errors.no_account' style paths work). Extra args go through string.format.
---@param key string
---@return string
function L(key, ...)
    local str = lookup(Locales and Locales[Config.Locale], key)
    if type(str) ~= 'string' then str = lookup(Locales and Locales.en, key) end
    if type(str) ~= 'string' then return tostring(key) end
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        if ok then return out end
    end
    return str
end

--- Raw locale value (table or string) without formatting.
function Utils.LocaleTable(key)
    local value = lookup(Locales and Locales[Config.Locale], key)
    if value == nil then value = lookup(Locales and Locales.en, key) end
    return value
end

--- Text for an error code, falls back to the generic message.
---@param code string|nil
---@return string
function Utils.ErrorText(code)
    if type(code) ~= 'string' or code == '' then code = 'unknown' end
    local text = lookup(Locales and Locales[Config.Locale], 'errors.' .. code) or lookup(Locales and Locales.en, 'errors.' .. code)
    if type(text) == 'string' then return text end
    return L('errors.unknown')
end

---------------------------------------------------------------------------------------------------
-- Debug

local function stringify(value)
    if type(value) == 'table' then
        local ok, encoded = pcall(json.encode, value)
        if ok and encoded then return encoded end
    end
    return tostring(value)
end

function DebugPrint(...)
    if not Config.Debug then return end
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = stringify(select(i, ...))
    end
    print(('^5[%s]^7 %s'):format(RESOURCE, table.concat(parts, ' ')))
end

--- Always printed. level: 'info' | 'warn' | 'error'
function Utils.Print(level, message)
    local color = level == 'error' and '^1' or (level == 'warn' and '^3' or '^2')
    print(('%s[%s]^7 %s'):format(color, RESOURCE, tostring(message)))
end

---------------------------------------------------------------------------------------------------
-- Numbers

function Utils.IsFinite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

function Utils.Round(n, d)
    n = tonumber(n)
    if not Utils.IsFinite(n) then return 0 end
    if not d or d <= 0 then
        return math.floor(n + 0.5)
    end
    local m = 10 ^ d
    return math.floor(n * m + 0.5) / m
end

function Utils.Clamp(v, a, b)
    v = tonumber(v)
    if not Utils.IsFinite(v) then v = a end
    if a and v < a then v = a end
    if b and v > b then v = b end
    return v
end

--- Whole positive number or nil.
function Utils.PositiveInt(n, max)
    n = tonumber(n)
    if not Utils.IsFinite(n) then return nil end
    n = math.floor(n)
    if n < 1 then return nil end
    if max and n > max then return nil end
    return n
end

---------------------------------------------------------------------------------------------------
-- Strings and tables

function Utils.Trim(s)
    if type(s) ~= 'string' then return '' end
    return (s:match('^%s*(.-)%s*$'))
end

local function deepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[deepCopy(k, seen)] = deepCopy(v, seen)
    end
    return setmetatable(out, getmetatable(value))
end

function Utils.TableCopy(t)
    return deepCopy(t, {})
end

function Utils.Contains(list, value)
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function Utils.Count(t)
    local n = 0
    if type(t) == 'table' then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------------------------------
-- Vectors

local function isVector(v)
    local t = type(v)
    return t == 'vector3' or t == 'vector4'
end

--- vector3 from a vector3/vector4, { x, y, z } or { [1], [2], [3] }. nil when invalid.
---@return vector3|nil
function Utils.ToVec3(t)
    local x, y, z
    if isVector(t) then
        x, y, z = t.x, t.y, t.z
    elseif type(t) == 'table' then
        x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
    else
        return nil
    end
    if not (Utils.IsFinite(x) and Utils.IsFinite(y) and Utils.IsFinite(z)) then return nil end
    return vector3(x, y, z)
end

--- Plain { x, y, z } table (safe for json and events).
function Utils.FromVec3(v)
    if not isVector(v) and type(v) ~= 'table' then return nil end
    local x, y, z = tonumber(v.x or v[1]), tonumber(v.y or v[2]), tonumber(v.z or v[3])
    if not (Utils.IsFinite(x) and Utils.IsFinite(y) and Utils.IsFinite(z)) then return nil end
    return { x = Utils.Round(x, 4), y = Utils.Round(y, 4), z = Utils.Round(z, 4) }
end

function Utils.Distance(a, b)
    local va, vb = Utils.ToVec3(a), Utils.ToVec3(b)
    if not va or not vb then return math.huge end
    return #(va - vb)
end

--- Offset rotated by a heading (degrees), e.g. a lens offset on a placed tripod.
function Utils.RotateOffset(offset, heading)
    local rad = math.rad(tonumber(heading) or 0.0)
    local c, s = math.cos(rad), math.sin(rad)
    return vector3(offset.x * c - offset.y * s, offset.x * s + offset.y * c, offset.z)
end

---------------------------------------------------------------------------------------------------
-- Items

local itemIndex

local function addItem(index, name, entry)
    if type(name) == 'string' and name ~= '' and not index[name] then
        index[name] = entry
    end
end

local function buildItemIndex()
    local index = {}

    for name, cfg in pairs(Config.Cameras or {}) do
        addItem(index, name, { kind = 'camera', tier = cfg.tier, cfg = cfg })
    end
    for name, cfg in pairs(Config.Microphones or {}) do
        if name ~= 'none' then
            addItem(index, name, { kind = 'mic', tier = cfg.tier, cfg = cfg })
        end
    end

    local studio = Config.Studio or {}
    if studio.Tripod then addItem(index, studio.Tripod.Item, { kind = 'tripod', cfg = studio.Tripod }) end
    if studio.RingLight then addItem(index, studio.RingLight.Item, { kind = 'ringlight', cfg = studio.RingLight }) end

    local devices = Config.Devices or {}
    if devices.Laptop then
        for _, name in ipairs(devices.Laptop.Items or {}) do
            addItem(index, name, { kind = 'laptop', cfg = devices.Laptop })
        end
    end
    if devices.Tablet then
        for _, name in ipairs(devices.Tablet.Items or {}) do
            addItem(index, name, { kind = 'tablet', cfg = devices.Tablet })
        end
    end

    local economy = Config.Economy or {}
    for name, sparks in pairs(economy.SparkCards or {}) do
        addItem(index, name, { kind = 'sparkcard', sparks = sparks, cfg = { sparks = sparks } })
    end

    return index
end

--- What a configured item is.
---@param item string
---@return table|nil { kind = 'camera'|'mic'|'tripod'|'ringlight'|'laptop'|'tablet'|'sparkcard', tier?, cfg, sparks? }
function Utils.GetItemConfig(item)
    if type(item) ~= 'string' then return nil end
    if not itemIndex then itemIndex = buildItemIndex() end
    return itemIndex[item]
end

--- Every item name this resource uses, sorted.
---@return string[]
function Utils.AllItems()
    if not itemIndex then itemIndex = buildItemIndex() end
    local list = {}
    for name in pairs(itemIndex) do list[#list + 1] = name end
    table.sort(list)
    return list
end

--- Item names of one kind, sorted by tier then name.
function Utils.ItemsOfKind(kind)
    if not itemIndex then itemIndex = buildItemIndex() end
    local list = {}
    for name, info in pairs(itemIndex) do
        if info.kind == kind then list[#list + 1] = name end
    end
    table.sort(list, function(a, b)
        local ta, tb = itemIndex[a].tier or 0, itemIndex[b].tier or 0
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return list
end

--- Rebuild after changing Config at runtime.
function Utils.RebuildItemIndex()
    itemIndex = buildItemIndex()
end

--- Display label for an item (locale first, then the camera / mic label, then the name).
function Utils.ItemLabel(item)
    local label = lookup(Locales and Locales[Config.Locale], 'items.' .. tostring(item)) or lookup(Locales and Locales.en, 'items.' .. tostring(item))
    if type(label) == 'string' then return label end
    local info = Utils.GetItemConfig(item)
    if info and type(info.cfg) == 'table' and type(info.cfg.label) == 'string' then return info.cfg.label end
    return tostring(item)
end
