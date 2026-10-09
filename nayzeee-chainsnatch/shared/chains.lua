-----------------------------------------------------------------
-- The chain registry, the same on server and clients.
--
-- The server builds it (server/registry.lua) from three things:
--   chainmap.json   what chainkit converted (nayzeee-chainprops)
--   Config.Chains   props you added by hand
--   overrides.json  what admins saved in the studio (fits, names, values)
-- and sends the result to every client.
--
-- def = {
--   key, label, origin ('drop' | 'server' | 'config'), gender, collection, local,
--   centre = {x,y,z} (where the mesh sat on the body as clothing), min, max,
--   variants = { { letter = 'a', prop = 'nzc_..._a', label = 'Gold' }, ... },
--   fit = { worn, worn_f, hold, hold_f },  value,
-- }
-----------------------------------------------------------------

Chains = { list = {}, order = {} }

local function sorted()
    local keys = {}
    for k in pairs(Chains.list) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local la, lb = Chains.list[a].label or a, Chains.list[b].label or b
        if la == lb then return a < b end
        return la:lower() < lb:lower()
    end)
    return keys
end

function Chains.set(list)
    Chains.list = type(list) == 'table' and list or {}
    Chains.order = sorted()
end

function Chains.def(key) return key and Chains.list[key] or nil end
function Chains.exists(key) return key ~= nil and Chains.list[key] ~= nil end
function Chains.keys() return Chains.order end

function Chains.variant(key, letter)
    local d = Chains.list[key]
    if not d or not d.variants or #d.variants == 0 then return nil end
    for _, v in ipairs(d.variants) do
        if v.letter == letter then return v end
    end
    return d.variants[1]
end

function Chains.model(key, letter)
    local v = Chains.variant(key, letter)
    return v and v.prop or nil
end

--- 'Diamond Cuban Chain' or 'Female Cuban Choker · Silver'
function Chains.label(key, letter)
    local d = Chains.list[key]
    if not d then return 'Chain' end
    local v = Chains.variant(key, letter)
    if d.variants and #d.variants > 1 and v then
        return ('%s · %s'):format(d.label, v.label or v.letter:upper())
    end
    return d.label
end

function Chains.value(key)
    local d = Chains.list[key]
    return d and d.value or Config.DefaultValue or 0
end

local function copy(f)
    return {
        bone = f.bone,
        pos = { x = f.pos.x, y = f.pos.y, z = f.pos.z },
        rot = { x = f.rot.x, y = f.rot.y, z = f.rot.z },
    }
end

--- Where a chain sits. mode 'worn' | 'hold'; female peds use their own fit when one was saved.
function Chains.fit(key, mode, female)
    local d = Chains.list[key]
    local fits = d and d.fit or {}
    local f = (female and fits[mode .. '_f']) or fits[mode] or (not female and fits[mode .. '_f'])
    if not f and mode == 'worn' and d and d.centre then
        -- not fitted yet: a converted chain sits exactly where it sat as clothing (clothing is modelled
        -- around the ped root). Fine standing still; fit it in the studio so it follows the neck.
        f = { bone = 0, pos = d.centre, rot = { x = 0.0, y = 0.0, z = 0.0 } }
    end
    return copy(f or Config.DefaultFit[mode])
end

function Chains.hasFit(key, mode, female)
    local d = Chains.list[key]
    if not d or not d.fit then return false end
    return d.fit[mode .. (female and '_f' or '')] ~= nil
end

local function money(n)
    local s = tostring(math.floor(n or 0))
    return '$' .. s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end
Chains.money = money

--- Item metadata for a chain. `extra` is kept (owner, serial, stolenFrom ...).
function Chains.meta(key, letter, extra)
    local v = Chains.variant(key, letter)
    local m = {}
    for k, val in pairs(extra or {}) do m[k] = val end
    m.chain = key
    m.variant = v and v.letter or letter or 'a'
    m.label = Chains.label(key, m.variant)
    m.image = v and v.prop or nil
    local parts = { money(Chains.value(key)) }
    if m.stolenFrom then parts[#parts + 1] = 'snatched from ' .. m.stolenFrom end
    m.description = table.concat(parts, ' · ')
    return m
end

--- What's in an item's metadata, cleaned up. Returns key, letter or nil.
function Chains.fromMeta(meta)
    if type(meta) ~= 'table' then return nil end
    local key = meta.chain
    if not Chains.exists(key) then return nil end
    local v = Chains.variant(key, meta.variant)
    return key, v and v.letter or 'a'
end

function Chains.debug(...)
    if Config.Debug then print(('[%s]'):format(GetCurrentResourceName()), ...) end
end
