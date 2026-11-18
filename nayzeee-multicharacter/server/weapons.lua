if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby weapon showcase (Config.WeaponShowcase).
        Weapons.ForChar(charId, row)        -> owned list { { name, label, class, components, tint } }   (cached ~60s)
        Weapons.Pickable(charId, row)       -> list, map[name]   what this character may pick (per mode)
        Weapons.List(charId, row)           -> { { name, label, class } }   Character.weapons
        Weapons.Resolve(charId, pref, row)  -> { name, label, class, components, tint } | nil   Character.weapon
        Weapons.Valid(charId, value, row)   -> normalised pref value | nil
]]

Weapons = {}

local W = Config.WeaponShowcase
local TTL = 60
local cache = {}   -- [charId] = { at, list }
local writes = 0

local function entry(name, comps, tint)
    return { name = name, label = Bridge.WeaponLabel(name), class = NZ.WeaponClass(name) or 'other', components = comps or {}, tint = tint }
end

local whitelist
local function whitelisted()
    if not whitelist then
        whitelist = {}
        for _, w in ipairs(W.whitelist or {}) do
            if type(w.name) == 'string' then whitelist[#whitelist + 1] = w.name:upper() end
        end
    end
    return whitelist
end

function Weapons.ForChar(charId, row)
    if not W.enabled or not charId then return {} end
    local now = os.time()
    local c = cache[charId]
    if c and now - c.at < TTL then return c.list end
    local list = {}
    local ok, owned = pcall(Bridge.OwnedWeapons, charId, row)
    if ok and type(owned) == 'table' then
        for _, w in ipairs(owned) do
            if type(w.name) == 'string' then list[#list + 1] = entry(w.name:upper(), w.components, w.tint) end
        end
    elseif not ok then
        NZ.Debug('OwnedWeapons failed for', charId, owned)
    end
    cache[charId] = { at = now, list = list }
    -- lazy sweep so the cache never grows without bound
    writes = writes + 1
    if writes >= 200 then
        writes = 0
        for id, e in pairs(cache) do if now - e.at >= TTL then cache[id] = nil end end
    end
    return list
end

function Weapons.Forget(charId) cache[charId] = nil end

function Weapons.Pickable(charId, row)
    local list, map = {}, {}
    if not W.enabled then return list, map end
    local function add(w) if not map[w.name] then map[w.name] = w list[#list + 1] = w end end
    local owned = {}
    if W.mode ~= 'whitelist' then
        for _, w in ipairs(Weapons.ForChar(charId, row)) do add(w) end
    end
    if W.mode == 'whitelist' or W.mode == 'both' then
        -- whitelist mode still keeps the owned attachments when the character happens to own it
        if W.mode == 'whitelist' then
            for _, w in ipairs(Weapons.ForChar(charId, row)) do owned[w.name] = w end
        end
        for _, name in ipairs(whitelisted()) do add(owned[name] or entry(name)) end
    end
    return list, map
end

function Weapons.List(charId, row)
    local out = {}
    for _, w in ipairs((Weapons.Pickable(charId, row))) do
        out[#out + 1] = { name = w.name, label = w.label, class = w.class }
    end
    return out
end

-- Best weapon by class priority (nil when nothing matches: no fire extinguishers on show)
local function best(list)
    for _, cls in ipairs(W.priority or {}) do
        for _, w in ipairs(list) do if w.class == cls then return w end end
    end
end

local function copy(w)
    return { name = w.name, label = w.label, class = w.class, components = w.components, tint = w.tint }
end

-- false = explicit "none", nil = this pref can't be used
local function try(p, list, map)
    if p == 'none' then return W.allowNone and false or nil end
    if p == 'auto' then if W.allowAuto then return best(list) or false end return nil end
    if type(p) == 'string' then return map[p:upper()] end
    return nil
end

function Weapons.Resolve(charId, pref, row)
    if not W.enabled then return nil end
    local list, map = Weapons.Pickable(charId, row)
    local r = try(pref, list, map)
    if r == nil then r = try(W.default, list, map) end         -- sold the saved weapon / no pick yet
    if r == nil and W.allowAuto then r = best(list) end
    return r and copy(r) or nil
end

function Weapons.Valid(charId, value, row)
    if not W.enabled or type(value) ~= 'string' then return nil end
    if value == 'auto' then return W.allowAuto and 'auto' or nil end
    if value == 'none' then return W.allowNone and 'none' or nil end
    local _, map = Weapons.Pickable(charId, row)
    local w = map[value:upper()]
    return w and w.name or nil
end
