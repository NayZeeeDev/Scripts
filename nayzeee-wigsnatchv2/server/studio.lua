-- Wig Studio (server): permissions, routing bucket, hairstyle names, and saving the photos.
-- Same flow as the nayzeee-backpack icon studio: admin + file name checks here, studio.js writes
-- the PNG into the photo resource (Config.Studio.Resource, default nzw_shots, next to this one, so
-- updates never wipe it), and the copy into ox_inventory/web/images is done here with SaveResourceFile.

Studio = {}

local CS = Config.Studio
local SHOTS = CS.Resource or 'nzw_shots'
SetConvar('nzwig_shots_resource', SHOTS)
local index = {}
local MAX_BYTES = 4 * 1024 * 1024
local warned = false

local function allowed(src)
    return CS.Enabled and IsPlayerAceAllowed(tostring(src), ServerConfig.StudioAce)
end
Studio.Allowed = allowed

-- the photo resource is (re)started after new photos, so players can load them
local restartAt = 0
local function restartShots(delay)
    restartAt = GetGameTimer() + (delay or 0)
    SetTimeout(delay or 0, function()
        if GetGameTimer() < restartAt then return end   -- more photos came in, a later call does it
        ExecuteCommand('refresh')
        if GetResourceState(SHOTS) == 'started' then ExecuteCommand('restart ' .. SHOTS) else ExecuteCommand('ensure ' .. SHOTS) end
        SetTimeout(4000, function()
            if GetResourceState(SHOTS) ~= 'started' then
                print(('^3[%s] Couldn\'t start %s (the Wig Studio photos). In server.cfg:^0'):format(RESOURCE, SHOTS))
                print(('^3    add_ace resource.%s command.refresh allow^0'):format(RESOURCE))
                print(('^3    add_ace resource.%s command.ensure allow^0'):format(RESOURCE))
                print(('^3    add_ace resource.%s command.restart allow^0'):format(RESOURCE))
                print(('^3  or add "ensure %s" to server.cfg after this resource.^0'):format(SHOTS))
            end
        end)
    end)
end

-- studio.js (re)built the index
AddEventHandler('nz-wig:studio:indexed', function(keys, moved)
    index = type(keys) == 'table' and keys or {}
    Wigs.SetShotIndex(index)
    if moved or GetResourceState(SHOTS) ~= 'started' then restartShots(1000) end
end)

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

RegisterNetEvent('nz-wig:s:studioSave', function(name, b64)
    local src = source
    if not allowed(src) then return end
    if type(name) ~= 'string' or not name:match('^wig_[mf]_%d+_%d+$') or #name > 32 then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nz-wig:c:studioSaved', src, name, false)
    end
    TriggerEvent('nz-wig:studio:write', src, name, b64)
end)

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

local function copyToInventory(name, b64)
    if GetResourceState('ox_inventory') == 'missing' then return false end
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then return false end
    if SaveResourceFile('ox_inventory', ('web/images/%s.png'):format(name), bin, #bin) then return true end
    if not warned then
        warned = true
        print(('^3[%s] could not write into ox_inventory/web/images. Add this to server.cfg and restart:^0'):format(RESOURCE))
        print(('^3    add_filesystem_permission %s write ox_inventory^0'):format(RESOURCE))
        print(('^3  The photos are still saved in %s/ and you can copy them over by hand.^0'):format(SHOTS))
    end
    return false
end

-- studio.js reports back here
AddEventHandler('nz-wig:studio:written', function(src, name, ok, key, b64)
    local where = ' → ' .. SHOTS
    if ok then
        Wigs.MarkShot(key)
        local found = false
        for _, k in ipairs(index) do if k == key then found = true break end end
        if not found then index[#index + 1] = key end
        restartShots(6000)   -- once the photos stop coming in
        if CS.SaveToInventory then
            where = copyToInventory(name, b64) and (' → %s + ox_inventory'):format(SHOTS) or (' → %s only (see server console)'):format(SHOTS)
        end
    end
    TriggerClientEvent('nz-wig:c:studioSaved', src, name, ok, key, where)
end)

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
