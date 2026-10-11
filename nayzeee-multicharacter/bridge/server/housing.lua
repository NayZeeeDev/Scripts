if not NAYZEEE_LOCK_OK then return end

--[[
    Owned properties shown in the spawn selector. Return a list of:
        { id = 'unique', label = 'Name', desc = 'small line', coords = vec4(...) }

    Built-in: qb-houses, ps-housing, qbx_properties. Add your housing script in Housing.Custom.
]]

Housing = {}

local function started(res) return GetResourceState(res) == 'started' end

local function vec(t)
    t = NZ.Decode(t)
    if not t then return nil end
    if t.enter then t = t.enter end
    if t.x then return NZ.Vec(t) end
    if t[1] then return vec4(t[1] + 0.0, t[2] + 0.0, t[3] + 0.0, (t[4] or 0.0) + 0.0) end
end

-- Your own housing script: return a list for this character (charId = ESX identifier or QB citizenid)
function Housing.Custom(src, charId)
    return nil
end

function Housing.Get(src, charId)
    local out = {}
    local custom = Housing.Custom(src, charId)
    if custom then return custom end

    if started('qb-houses') and Bridge.TableExists('player_houses', 'citizenid') then
        local rows = MySQL.query.await([[SELECT h.house, l.label, l.coords FROM player_houses h
            JOIN houselocations l ON l.name = h.house WHERE h.citizenid = ?]], { charId }) or {}
        for i = 1, #rows do
            local c = vec(rows[i].coords)
            if c then out[#out + 1] = { id = 'qbh:' .. rows[i].house, label = rows[i].label or rows[i].house, coords = c } end
        end
    end

    if started('ps-housing') and Bridge.TableExists('properties', 'owner_citizenid') then
        local rows = MySQL.query.await('SELECT property_id, street, door_data FROM properties WHERE owner_citizenid = ?', { charId }) or {}
        for i = 1, #rows do
            local c = vec(rows[i].door_data)
            if c then out[#out + 1] = { id = 'ps:' .. rows[i].property_id, label = rows[i].street or ('Property ' .. rows[i].property_id), coords = c } end
        end
    end

    if started('qbx_properties') and Bridge.TableExists('properties', 'owner') then
        local rows = MySQL.query.await('SELECT id, property_name, coords FROM properties WHERE owner = ?', { charId }) or {}
        for i = 1, #rows do
            local c = vec(rows[i].coords)
            if c then out[#out + 1] = { id = 'qbx:' .. rows[i].id, label = rows[i].property_name or ('Property ' .. rows[i].id), coords = c } end
        end
    end

    return out
end
