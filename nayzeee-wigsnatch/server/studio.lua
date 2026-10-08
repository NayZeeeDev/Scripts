-- Wig Studio (server, Lua side): permissions, routing buckets, hairstyle names.
-- Image processing lives in server/studio.js.

Studio = {}

SetConvar('nzwig_studio_ace', ServerConfig.StudioAce)

local function allowed(src)
    return Config.Studio.Enabled and IsPlayerAceAllowed(tostring(src), ServerConfig.StudioAce)
end
Studio.Allowed = allowed

-- the photo index from studio.js
AddEventHandler('nz-wig:studio:indexed', function() Wigs.LoadShotIndex() end)
AddEventHandler('nz-wig:studio:saved', function() Wigs.LoadShotIndex() end)

lib.callback.register('nz-wig:studioOpen', function(src)
    if not allowed(src) then return false end
    local raw = LoadResourceFile(RESOURCE, 'shots/index.json')
    local ok, list = pcall(json.decode, raw or '[]')
    return {
        names = StyleNames,
        shots = ok and list or {},
        styles = Config.Styles,
    }
end)

RegisterNetEvent('nz-wig:s:studioBucket', function(on)
    local src = source
    if not allowed(src) then return end
    SetPlayerRoutingBucket(src, on and Config.Studio.RoutingBucket or 0)
end)

-- save names typed in the studio browser: { ['f:12'] = 'Knotless Braids', ... } ('' removes a name)
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
    if GetPlayerRoutingBucket(src) == Config.Studio.RoutingBucket then SetPlayerRoutingBucket(src, 0) end
end)
