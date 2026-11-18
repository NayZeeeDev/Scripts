if not NAYZEEE_LOCK_OK then return end

--[[
    Owned weapons of an OFFLINE character, read straight from the database (lobby weapon showcase).

    Bridge.OwnedWeapons(charId, row) -> { { name = 'WEAPON_X', components = { hash, ... }, tint = n|nil } ... }
        row = the framework db row when we already have it (users / players), saves a query.

    Supported out of the box
      ox_inventory   QB/Qbox: players.inventory   ESX: users.inventory   metadata = { components = { 'at_flashlight' }, tint }
      qb / ps / lj   players.inventory            info = { attachments = { { component = 'COMPONENT_...' } }, tint }
      qs-inventory   QB: players.inventory        ESX: users.inventory   (same item style as qb)
      ESX default    users.loadout  { WEAPON_X = { components = { 'flashlight' }, tintIndex } } or an array of { name, ... }
    Anything else: fill Bridge.CustomWeapons below.

    ox_inventory component items ('at_flashlight') can map to several component hashes (one per weapon family);
    the client keeps only the ones the weapon accepts (DoesWeaponTakeWeaponComponent).
]]

local function started(res) return GetResourceState(res) == 'started' end

-- Your own inventory: return the list above for this character, or nil to use the built-in readers
function Bridge.CustomWeapons(charId, row)
    return nil
end

-- ── ox_inventory component item -> hashes ───────────────────────────────────
local oxComp   -- [itemName] = { hash, ... }

local function addHashes(list, into)
    if type(list) ~= 'table' then list = { list } end
    for _, h in ipairs(list) do
        if type(h) == 'number' then into[#into + 1] = h
        elseif type(h) == 'string' then into[#into + 1] = joaat(h) end
    end
end

-- Server-side ox_inventory strips `client` from items, so read data/weapons.lua once as a fallback
local function loadOxData()
    oxComp = {}
    if not started('ox_inventory') then return end
    local ok, err = pcall(function()
        local src = LoadResourceFile('ox_inventory', 'data/weapons.lua')
        if not src then return end
        local env = setmetatable({}, { __index = _G })
        local chunk = load(src, '@ox_inventory/data/weapons.lua', 't', env)
        local data = chunk and chunk()
        for name, def in pairs(type(data) == 'table' and data.Components or {}) do
            local hashes = {}
            addHashes(type(def) == 'table' and def.client and def.client.component, hashes)
            if #hashes > 0 then oxComp[name:lower()] = hashes end
        end
    end)
    if not ok then NZ.Debug('ox weapons.lua parse failed', err) end
end

local function oxComponentHashes(item)
    if not oxComp then loadOxData() end
    item = item:lower()
    if oxComp[item] then return oxComp[item] end
    local hashes = {}
    if started('ox_inventory') then
        local ok, data = pcall(function() return exports.ox_inventory:Items(item) end)
        if ok and type(data) == 'table' and type(data.client) == 'table' then addHashes(data.client.component, hashes) end
    end
    oxComp[item] = hashes
    return hashes
end

-- ── item parsers ───────────────────────────────────────────────────────────
local function addComponents(out, list)
    if type(list) ~= 'table' then return end
    for _, v in pairs(list) do
        local c = v
        if type(v) == 'table' then c = v.component or v.hash or v.name end
        if type(c) == 'number' then
            out[#out + 1] = c
        elseif type(c) == 'string' and c ~= '' then
            if c:upper():find('^COMPONENT_') then
                out[#out + 1] = joaat(c:upper())
            else
                for _, h in ipairs(oxComponentHashes(c)) do out[#out + 1] = h end
            end
        end
    end
end

-- ox / qb / qs / ps / lj item list (array or slot-keyed map)
local function parseItems(items, out, seen)
    if type(items) ~= 'table' then return end
    for _, it in pairs(items) do
        if type(it) == 'table' and type(it.name) == 'string' then
            local name = it.name:upper()
            if name:sub(1, 7) == 'WEAPON_' and not seen[name] then
                seen[name] = true
                local meta = (type(it.metadata) == 'table' and it.metadata) or (type(it.info) == 'table' and it.info) or {}
                local comps = {}
                addComponents(comps, meta.components)
                addComponents(comps, meta.attachments)
                out[#out + 1] = { name = name, components = comps, tint = tonumber(meta.tint) }
            end
        end
    end
end

-- ESX default loadout (keyed by weapon name, or an array of { name, ... })
local function parseLoadout(lo, out, seen)
    if type(lo) ~= 'table' then return end
    for k, w in pairs(lo) do
        local name = type(k) == 'string' and k or (type(w) == 'table' and w.name)
        if type(name) == 'string' then
            name = name:upper()
            if name:sub(1, 7) == 'WEAPON_' and not seen[name] then
                seen[name] = true
                local comps = {}
                for _, c in ipairs(type(w) == 'table' and type(w.components) == 'table' and w.components or {}) do
                    local h = type(c) == 'string' and Bridge.ESXComponentHash and Bridge.ESXComponentHash(name, c)
                    if h then comps[#comps + 1] = h
                    elseif type(c) == 'string' and c:upper():find('^COMPONENT_') then comps[#comps + 1] = joaat(c:upper()) end
                end
                out[#out + 1] = { name = name, components = comps, tint = type(w) == 'table' and tonumber(w.tintIndex or w.tint) or nil }
            end
        end
    end
end

local function column(tbl, key, col, charId, row)
    if row and row[col] ~= nil then return row[col] end
    if not Bridge.TableExists(tbl, col) then return nil end
    return MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE `%s` = ?'):format(col, tbl, key), { charId })
end

function Bridge.OwnedWeapons(charId, row)
    local ok, custom = pcall(Bridge.CustomWeapons, charId, row)
    if ok and type(custom) == 'table' then return custom end

    local out, seen = {}, {}
    if NZ.IsESX then
        parseItems(NZ.Decode(column('users', 'identifier', 'inventory', charId, row)), out, seen)
        if not started('ox_inventory') then
            parseLoadout(NZ.Decode(column('users', 'identifier', 'loadout', charId, row)), out, seen)
        end
    elseif NZ.IsQB then
        parseItems(NZ.Decode(column('players', 'citizenid', 'inventory', charId, row)), out, seen)
    end
    return out
end

-- ── labels ─────────────────────────────────────────────────────────────────
local labels = {}

function Bridge.WeaponLabel(name)
    if labels[name] then return labels[name] end
    local label
    for _, w in ipairs(Config.WeaponShowcase.whitelist or {}) do
        if w.name:upper() == name then label = w.label break end
    end
    if not label and started('ox_inventory') then
        local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
        if ok and type(item) == 'table' then label = item.label end
    end
    if not label and Bridge.FrameworkWeaponLabel then
        local ok, l = pcall(Bridge.FrameworkWeaponLabel, name)
        if ok then label = l end
    end
    -- WEAPON_PUMPSHOTGUN_MK2 -> "Pumpshotgun Mk2"
    label = label or NZ.Capitalize(name:gsub('^WEAPON_', ''):gsub('_', ' '))
    labels[name] = label
    return label
end
