if not NAYZEEE_LOCK_OK then return end

--[[
    Server bridge contract. esx.lua / qb.lua fill these in for their framework.

    Bridge.Ready()                          -> bool (core object available)
    Bridge.Owner(src)                       -> owner key (license) used for our tables
    Bridge.Fetch(src, owner)                -> list of normalised characters (see below)
    Bridge.FetchByIds(ids)                  -> list of normalised characters by id (offline previews: squads)
    Bridge.Search(query, exact)             -> list of { id, firstname, lastname } (squad search)
    Bridge.Load(src, char)                  -> ok
    Bridge.Create(src, slot, data)          -> ok, charId
    Bridge.Delete(src, charId)              -> ok
    Bridge.Logout(src)                      -> ok
    Bridge.IsLoaded(src)                    -> bool
    Bridge.ActiveId(src)                    -> charId | nil
    Bridge.ActiveJob(src)                   -> name, grade
    Bridge.NameTaken(first, last)           -> bool
    Bridge.AddMoney(src, account, amount)   account = 'cash' | 'bank'
    Bridge.FrameworkStarter(src)            QB defaults
    Bridge.Position(charId)                 -> vec4 | nil
    Bridge.FrameworkWeaponLabel(name)       -> label | nil
    Bridge.OwnedWeapons(charId, row)        (inventory.lua) -> { { name, components, tint } }

    Normalised character:
        { id, slot, owner, firstname, lastname, dob ('YYYY-MM-DD'), gender ('m'|'f'), height, nationality,
          job = { name, label, grade, gradeLabel }, cash, bank, phone, position (vec4|nil), skin, model, raw = db row }
]]

Bridge = Bridge or {}

local function started(res) return GetResourceState(res) == 'started' end
Bridge.Started = started

-- ── Inventory: item giving works the same for every framework ─────────────
function Bridge.AddItem(src, name, count, metadata)
    local ok, res = pcall(function()
        if started('ox_inventory') then
            return exports.ox_inventory:AddItem(src, name, count, metadata) ~= false
        elseif started('qs-inventory') then
            return exports['qs-inventory']:AddItem(src, name, count, nil, metadata) ~= false
        elseif started('codem-inventory') then
            return exports['codem-inventory']:AddItem(src, name, count, nil, metadata) ~= false
        elseif started('tgiann-inventory') then
            return exports['tgiann-inventory']:AddItem(src, name, count, nil, metadata, false) ~= false
        elseif started('core_inventory') then
            return exports.core_inventory:addItem(src, name, count, metadata) ~= false
        elseif started('origen_inventory') then
            return exports.origen_inventory:addItem(src, name, count, nil, metadata) ~= false
        elseif started('ps-inventory') then
            return exports['ps-inventory']:AddItem(src, name, count, nil, metadata) ~= false
        elseif started('qb-inventory') then
            return exports['qb-inventory']:AddItem(src, name, count, false, metadata) ~= false
        end
        return Bridge.FrameworkAddItem and Bridge.FrameworkAddItem(src, name, count, metadata) or false
    end)
    if not ok then NZ.Debug('AddItem failed', name, res) end
    return ok and res or false
end

-- ── Schema lookups (checked once, cached) ──────────────────────────────────
local existing
function Bridge.TableExists(name, column)
    if not existing then
        existing = {}
        local rows = MySQL.query.await('SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()') or {}
        for i = 1, #rows do existing[rows[i].TABLE_NAME:lower() .. '.' .. rows[i].COLUMN_NAME:lower()] = true end
    end
    return existing[name:lower() .. '.' .. column:lower()] == true
end

-- "?,?,?" for IN (...) lists
function Bridge.Marks(n) return ('?,'):rep(n):sub(1, -2) end

-- Escape LIKE wildcards in user input (MySQL default escape char is \)
function Bridge.LikeEscape(s) return (s:gsub('[\\%%_]', '\\%0')) end

-- ── Date helpers ───────────────────────────────────────────────────────────
-- Parse "31/12/1998", "12-31-1998", "1998-12-31" using a format hint. Returns y, m, d or nil.
function Bridge.ParseDate(str, fmt)
    if type(str) ~= 'string' then return nil end
    local a, b, c = str:match('^(%d+)%D(%d+)%D(%d+)')
    if not a then return nil end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a > 31 then return a, b, c end                                  -- YYYY-MM-DD
    fmt = fmt or 'DD/MM/YYYY'
    if fmt:sub(1, 2) == 'MM' then return c, a, b end                  -- MM/DD/YYYY
    return c, b, a                                                     -- DD/MM/YYYY
end

function Bridge.FormatDate(y, m, d, fmt)
    fmt = fmt or 'YYYY-MM-DD'
    return (fmt:gsub('YYYY', ('%04d'):format(y)):gsub('MM', ('%02d'):format(m)):gsub('DD', ('%02d'):format(d)))
end

function Bridge.ISO(str, fmt)
    local y, m, d = Bridge.ParseDate(str, fmt)
    if not y then return nil end
    return ('%04d-%02d-%02d'):format(y, m, d)
end

-- Skin model detection from any skin format
function Bridge.SkinModel(skin, fallbackGender)
    if type(skin) == 'table' then
        if skin.model then return skin.model end
        if type(skin.sex) == 'number' then return skin.sex == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01' end
    end
    return fallbackGender == 'f' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
end
