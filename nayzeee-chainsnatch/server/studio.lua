-----------------------------------------------------------------
-- Studio (server): who may open it, and saving what admins change.
-- Nothing from the client is written without going through clean().
-----------------------------------------------------------------

Studio = {}

function Studio.allowed(src) return Bridge.IsAdmin(src) end

lib.callback.register('nzc:studio:allowed', function(src) return Studio.allowed(src) end)

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.max(lo, math.min(hi, v))
end

local function vec(t, lo, hi)
    if type(t) ~= 'table' then return nil end
    local x, y, z = num(t.x, lo, hi), num(t.y, lo, hi), num(t.z, lo, hi)
    if not x or not y or not z then return nil end
    local r = function(v) return math.floor(v * 10000 + 0.5) / 10000 end
    return { x = r(x), y = r(y), z = r(z) }
end

local MODES = { worn = true, worn_f = true, hold = true, hold_f = true }

local function clean(patch)
    if type(patch) ~= 'table' then return nil end
    local out, what = {}, {}
    if type(patch.fit) == 'table' then
        out.fit = {}
        for mode, f in pairs(patch.fit) do
            if MODES[mode] and type(f) == 'table' then
                local bone, pos, rot = num(f.bone, 0, 65535), vec(f.pos, -3.0, 3.0), vec(f.rot, -360.0, 360.0)
                if bone and pos and rot then
                    out.fit[mode] = { bone = math.floor(bone), pos = pos, rot = rot }
                    what[#what + 1] = mode
                end
            end
        end
        if not next(out.fit) then out.fit = nil end
    end
    if type(patch.label) == 'string' and #patch.label > 0 then
        out.label = patch.label:sub(1, 48):gsub('[<>]', '')
        what[#what + 1] = 'label'
    end
    if patch.value ~= nil then
        local v = num(patch.value, 0, 100000000)
        if v then out.value = math.floor(v); what[#what + 1] = 'value' end
    end
    if type(patch.vlabels) == 'table' then
        out.vlabels = {}
        for l, name in pairs(patch.vlabels) do
            if type(l) == 'string' and l:match('^%l$') and type(name) == 'string' then
                out.vlabels[l] = name:sub(1, 24):gsub('[<>]', '')
            end
        end
        what[#what + 1] = 'texture names'
    end
    if patch.forSale ~= nil then out.forSale = patch.forSale == true; what[#what + 1] = 'for sale' end
    if patch.craftable ~= nil then out.craftable = patch.craftable == true; what[#what + 1] = 'craftable' end
    if patch.price ~= nil then
        local v = num(patch.price, 0, 100000000)
        if v then out.price = math.floor(v); what[#what + 1] = 'price' end
    end
    if type(patch.owners) == 'table' then
        out.owners = {}
        for _, w in ipairs(patch.owners) do
            if type(w) == 'table' and type(w.license) == 'string' and w.license:match('^license:%x+$') and #out.owners < 20 then
                out.owners[#out.owners + 1] = { license = w.license, name = tostring(w.name or 'Player'):sub(1, 40):gsub('[<>]', '') }
            end
        end
        what[#what + 1] = #out.owners > 0 and ('exclusive to %d'):format(#out.owners) or 'open to everyone'
    end
    return out, table.concat(what, ', ')
end

local function apply(key, out)
    local entry = Registry.overrides[key] or {}
    for k, v in pairs(out) do
        if k == 'fit' then
            entry.fit = entry.fit or {}
            for m, f in pairs(v) do entry.fit[m] = f end
        elseif k == 'owners' then
            entry.owners = #v > 0 and v or nil
        elseif k == 'vlabels' then
            entry.vlabels = entry.vlabels or {}
            for l, n in pairs(v) do entry.vlabels[l] = n ~= '' and n or nil end
        else
            entry[k] = v
        end
    end
    Registry.overrides[key] = entry
end

RegisterNetEvent('nzc:studio:save', function(key, patch)
    local src = source
    if not Studio.allowed(src) then return end
    if not Chains.exists(key) then return end
    local out, what = clean(patch)
    if not out or what == '' then
        return TriggerClientEvent('nzc:studio:result', src, false, 'Nothing valid to save.')
    end
    apply(key, out)
    local ok = Registry.saveOverrides()
    Registry.reload()
    Logs.send('admin', 'Studio', ('%s saved %s (%s)'):format(Logs.who(src), Chains.label(key), what))
    TriggerClientEvent('nzc:studio:result', src, ok, ok and ('Saved %s (%s).'):format(Chains.list[key].label, what) or 'Could not write data/overrides.json')
end)

-- "Fit every chain": many fits in one go, one reload
RegisterNetEvent('nzc:studio:saveMany', function(patches)
    local src = source
    if not Studio.allowed(src) or type(patches) ~= 'table' then return end
    local n = 0
    for key, patch in pairs(patches) do
        if Chains.exists(key) then
            local out, what = clean(patch)
            if out and what ~= '' then apply(key, out); n = n + 1 end
        end
    end
    if n == 0 then return end
    Registry.saveOverrides()
    Registry.reload()
    Logs.send('admin', 'Studio', ('%s fitted %d chain(s) from their clothing spot'):format(Logs.who(src), n))
end)

RegisterNetEvent('nzc:studio:clear', function(key, mode)
    local src = source
    if not Studio.allowed(src) or not Registry.overrides[key] then return end
    if mode and MODES[mode] then
        if Registry.overrides[key].fit then Registry.overrides[key].fit[mode] = nil end
    else
        Registry.overrides[key] = nil
    end
    Registry.saveOverrides()
    Registry.reload()
    TriggerClientEvent('nzc:studio:result', src, true, mode and ('Cleared the %s fit.'):format(mode) or 'Back to the converter / config values.')
end)

-- a chain to try on, straight from the studio
RegisterNetEvent('nzc:studio:give', function(key, letter)
    local src = source
    if not Studio.allowed(src) or not Chains.exists(key) then return end
    local ok = Worn.give(src, key, letter)
    TriggerClientEvent('nzc:studio:result', src, ok, ok and ('%s is in your pockets.'):format(Chains.label(key, letter)) or 'No room in your pockets.')
end)

-- exclusive chains: who's online (to add as an owner), and who owns a chain now
lib.callback.register('nzc:studio:owners', function(src, key)
    if not Studio.allowed(src) then return nil end
    local online = {}
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        online[#online + 1] = { id = p, name = Bridge.GetCharName(p), license = Bridge.GetLicense(p) }
    end
    table.sort(online, function(a, b) return a.id < b.id end)
    return { owners = Registry.owners[key] or {}, online = online }
end)
