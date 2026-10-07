-----------------------------------------------------------------
-- Icon studio (server)
--
-- Admin check + filename check here in Lua, the actual file write
-- in icons.js (Node's fs is binary-safe, no npm packages needed).
-----------------------------------------------------------------

local MAX_BYTES = 6 * 1024 * 1024

RegisterNetEvent('nayzeee-backpack:icon:save', function(name, b64)
    local src = source
    if not Framework.isAdmin(src) then return end
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') or #name > 80 then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nayzeee-backpack:icon:saved', src, name, false)
    end

    local cfg = Config.IconCapture or {}
    TriggerEvent('nayzeee-backpack:icon:write', src, name, b64, cfg.saveToInventory and true or false)
end)

-- icons.js reports back here
AddEventHandler('nayzeee-backpack:icon:written', function(src, name, ok, where)
    TriggerClientEvent('nayzeee-backpack:icon:saved', src, name, ok, where)
    if ok then TriggerEvent('nayzeee-backpack:iconWritten', name) end
end)
