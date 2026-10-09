-- Wig Studio (server): permissions, routing bucket, hairstyle names, and saving the photos.
-- Same flow as the nayzeee-backpack icon studio: the NUI keys a small PNG, this file checks it and
-- saves it into shots/ and the database (so updates never lose it), and copies it into
-- ox_inventory/web/images with SaveResourceFile.

Studio = {}

local CS = Config.Studio
local MAX_BYTES = 4 * 1024 * 1024
local NAME = '^wig_[mf]_%d+_%d+$'
local index = {}        -- { 'f/12_0', ... }
local warned = false

local function allowed(src)
    return CS.Enabled and IsPlayerAceAllowed(tostring(src), ServerConfig.StudioAce)
end
Studio.Allowed = allowed

local function keyOf(name)
    local m, d, t = name:match('^wig_([mf])_(%d+)_(%d+)$')
    return m and ('%s/%d_%d'):format(m, tonumber(d), tonumber(t)) or nil
end

local function addKey(key)
    if not key then return end
    for _, k in ipairs(index) do if k == key then return end end
    index[#index + 1] = key
    table.sort(index)
    Wigs.MarkShot(key)
end

local function shotList()
    return index
end

lib.callback.register('nz-wig:studioOpen', function(src)
    if not allowed(src) then return false end
    return {
        names = StyleNames,
        shots = shotList(),
        size = CS.Size,
        allTextures = CS.AllTextures,
        saveToInventory = CS.SaveToInventory and GetResourceState('ox_inventory') ~= 'missing',
    }
end)

-- which hairstyles have a photo (the workshop shows them)
lib.callback.register('nz-wig:shots', function()
    return shotList()
end)

lib.callback.register('nz-wig:studioShots', function(src)
    if not allowed(src) then return {} end
    return shotList()
end)

RegisterNetEvent('nz-wig:s:studioBucket', function(on)
    local src = source
    if not allowed(src) then return end
    SetPlayerRoutingBucket(src, on and CS.RoutingBucket or 0)
end)

-- saving -------------------------------------------------------------------------------------------

-- plain base64 decoder, binary safe
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local LOOKUP = {}
for i = 1, #B64 do LOOKUP[B64:byte(i)] = i - 1 end

local function decode(data)
    data = data:gsub('^data:[^,]*,', ''):gsub('[^%w%+/]', '')
    local out, n = {}, 0
    for i = 1, #data, 4 do
        local a, b, c, d = LOOKUP[data:byte(i)], LOOKUP[data:byte(i + 1)], LOOKUP[data:byte(i + 2)], LOOKUP[data:byte(i + 3)]
        if not a or not b then break end
        local v = (a << 18) | (b << 12) | ((c or 0) << 6) | (d or 0)
        n = n + 1
        if d then
            out[n] = string.char((v >> 16) & 255, (v >> 8) & 255, v & 255)
        elseif c then
            out[n] = string.char((v >> 16) & 255, (v >> 8) & 255)
        else
            out[n] = string.char((v >> 16) & 255)
        end
    end
    return table.concat(out)
end
Studio.Decode = decode

local function encode(bin)
    local out, n = {}, 0
    for i = 1, #bin, 3 do
        local a, b, c = bin:byte(i, i + 2)
        local v = (a << 16) | ((b or 0) << 8) | (c or 0)
        n = n + 1
        out[n] = B64:sub((v >> 18) + 1, (v >> 18) + 1) .. B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
            .. (b and B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) or '=')
            .. (c and B64:sub((v & 63) + 1, (v & 63) + 1) or '=')
    end
    return table.concat(out)
end
Studio.Encode = encode


local function copyToInventory(name, b64)
    if GetResourceState('ox_inventory') == 'missing' then return false end
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then return false end
    if SaveResourceFile('ox_inventory', ('web/images/%s.png'):format(name), bin, #bin) then return true end
    if not warned then
        warned = true
        print(('^3[%s] could not write into ox_inventory/web/images. Add this to server.cfg and restart:^0'):format(RESOURCE))
        print(('^3    add_filesystem_permission %s write ox_inventory^0'):format(RESOURCE))
        print(('^3  The photos are still saved in %s/shots/ and you can copy them over by hand.^0'):format(RESOURCE))
    end
    return false
end

-- saving -------------------------------------------------------------------------------------------
-- Every photo is kept twice: in this resource's shots/ folder (that's what the UI loads) and in the
-- database. Updating the script replaces the folder; on the next start the photos come back from
-- the database by themselves.

local function writeFile(name, bin)
    return SaveResourceFile(RESOURCE, ('shots/%s.png'):format(name), bin, #bin)
end

local function store(name, bin, b64)
    MySQL.query.await('INSERT INTO nz_wig_shots (name, png, updated) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE png = VALUES(png), updated = VALUES(updated)',
        { name, b64 or encode(bin), os.time() })
end

RegisterNetEvent('nz-wig:s:studioSave', function(name, b64)
    local src = source
    if not allowed(src) then return end
    if type(name) ~= 'string' or not name:match(NAME) or #name > 32 then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nz-wig:c:studioSaved', src, name, false)
    end
    b64 = b64:gsub('^data:[^,]*,', '')
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then
        return TriggerClientEvent('nz-wig:c:studioSaved', src, name, false)
    end
    local ok = writeFile(name, bin)
    local saved = pcall(store, name, bin, b64)
    if not ok and not saved then
        print(('^1[%s]^0 wig studio: could not save %s'):format(RESOURCE, name))
        return TriggerClientEvent('nz-wig:c:studioSaved', src, name, false)
    end
    local key = keyOf(name)
    addKey(key)
    local where = ' → saved'
    if CS.SaveToInventory then
        where = copyToInventory(name, b64) and ' → saved + ox_inventory' or ' → saved (ox_inventory: see server console)'
    end
    TriggerClientEvent('nz-wig:c:studioSaved', src, name, true, key, where)
end)

-- on start: put back any photo the folder lost (an update replaced it), and once, gather the photos
-- older versions left in shots/, nzw_shots or ox_inventory/web/images into the database
local function gather(found)
    local sources = {
        { RESOURCE, 'shots/%s.png' },
        { 'nzw_shots', '%s.png' },
        { 'ox_inventory', 'web/images/%s.png' },
    }
    local function load(name)
        for _, src in ipairs(sources) do
            if GetResourceState(src[1]) ~= 'missing' then
                local bin = LoadResourceFile(src[1], src[2]:format(name))
                if bin and #bin > 8 and bin:sub(1, 4) == '\137PNG' then return bin end
            end
        end
    end
    local added = 0
    for _, m in ipairs({ 'f', 'm' }) do
        for d = 0, CS.ScanMax or 600 do
            for t = 0, 15 do
                local name = StudioShotName(m, d, t)
                if not found[name] then
                    local bin = load(name)
                    if bin then
                        if pcall(store, name, bin) then found[name] = true added = added + 1 end
                    elseif t == 0 then
                        break   -- no first texture: the other textures weren't shot either
                    end
                end
            end
        end
    end
    return added
end

function Studio.Boot()
    local rows = MySQL.query.await('SELECT name FROM nz_wig_shots') or {}
    local found = {}
    for _, r in ipairs(rows) do found[r.name] = true end

    local added = 0
    if GetResourceKvpString('nzwig:shots_gathered') ~= '1' then
        added = gather(found)
        SetResourceKvp('nzwig:shots_gathered', '1')
        if added > 0 then print(('^2[%s]^7 wig studio: saved %d photo(s) from older versions into the database'):format(RESOURCE, added)) end
    end

    local restored = 0
    index = {}
    for name in pairs(found) do
        if not LoadResourceFile(RESOURCE, ('shots/%s.png'):format(name)) then
            local row = MySQL.single.await('SELECT png FROM nz_wig_shots WHERE name = ?', { name })
            local bin = row and decode(row.png) or ''
            if #bin > 8 and writeFile(name, bin) then restored = restored + 1 end
        end
        index[#index + 1] = keyOf(name)
    end
    table.sort(index)
    Wigs.SetShotIndex(index)

    -- a file written after the resource started is only served after a restart
    if restored > 0 then
        print(('^2[%s]^7 wig studio: put back %d photo(s) after an update, restarting once so players can see them'):format(RESOURCE, restored))
        SetTimeout(1500, function()
            ExecuteCommand('refresh')
            ExecuteCommand('restart ' .. RESOURCE)
            SetTimeout(3000, function()
                print(('^3[%s] If the photos still don\'t show, restart %s once (or allow it: add_ace resource.%s command.restart allow)^0'):format(RESOURCE, RESOURCE, RESOURCE))
            end)
        end)
    end
end

-- names --------------------------------------------------------------------------------------------

-- { ['f:12'] = 'Knotless Braids', ['f:12:1'] = 'Knotless Braids (Honey)' } ('' removes a name)
RegisterNetEvent('nz-wig:s:studioNames', function(changes)
    local src = source
    if not allowed(src) or type(changes) ~= 'table' then return end
    local n = 0
    for k, v in pairs(changes) do
        if type(k) == 'string' and (k:match('^[mf]:%d+$') or k:match('^[mf]:%d+:%d+$')) and type(v) == 'string' then
            v = v:gsub('[%c<>]', ''):sub(1, 40)
            v = v:match('^%s*(.-)%s*$')
            StyleNames[k] = v ~= '' and v or nil
            n = n + 1
            if n >= 500 then break end
        end
    end
    SaveResourceFile(RESOURCE, 'data/style_names.json', json.encode(StyleNames), -1)
    TriggerClientEvent('nz-wig:c:styleNames', -1, StyleNames)
    Notify(src, L('studio_names_saved', n), 'success')
    Log('admin', 'Style names', ('%s renamed %d hairstyle(s) in the studio'):format(GetPlayerName(src) or src, n))
end)

-- clients ask for the names after joining (the file might have changed since the resource started)
RegisterNetEvent('nz-wig:s:styleNames', function()
    TriggerClientEvent('nz-wig:c:styleNames', source, StyleNames)
end)

OnPlayerDrop(function(src)
    if GetPlayerRoutingBucket(src) == CS.RoutingBucket then SetPlayerRoutingBucket(src, 0) end
end)
