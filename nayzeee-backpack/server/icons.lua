-----------------------------------------------------------------
-- Icon studio (server)
--
-- Admin + filename checks here. icons.js writes the PNG into this
-- resource's icons/ folder; the copy into ox_inventory/web/images is
-- done here with SaveResourceFile, which isn't caught by the Node
-- filesystem permission that newer FXServer builds enforce.
-----------------------------------------------------------------

local MAX_BYTES = 6 * 1024 * 1024
local warned = false

RegisterNetEvent('nayzeee-backpack:icon:save', function(name, b64)
    local src = source
    if not Framework.isAdmin(src) then return end
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') or #name > 80 then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nayzeee-backpack:icon:saved', src, name, false)
    end
    TriggerEvent('nayzeee-backpack:icon:write', src, name, b64)
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

local function copyToInventory(name, b64)
    if GetResourceState('ox_inventory') == 'missing' then return false end
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then return false end

    local ok = SaveResourceFile('ox_inventory', ('web/images/%s.png'):format(name), bin, #bin)
    if ok then return true end

    if not warned then
        warned = true
        print('^3[nayzeee-backpack] could not write into ox_inventory/web/images. Add this to server.cfg and restart:^0')
        print(('^3    add_filesystem_permission %s write ox_inventory^0'):format(GetCurrentResourceName()))
        print('^3  Your icons are still saved in nayzeee-backpack/icons/ — you can copy them over by hand.^0')
    end
    return false
end

-- icons.js reports back here
AddEventHandler('nayzeee-backpack:icon:written', function(src, name, ok, b64)
    local where = ' → icons/'
    if ok and Config.IconCapture and Config.IconCapture.saveToInventory then
        if copyToInventory(name, b64) then
            where = ' → icons/ + ox_inventory'
        else
            where = ' → icons/ only (see server console)'
        end
    end
    TriggerClientEvent('nayzeee-backpack:icon:saved', src, name, ok, where)
    if ok then TriggerEvent('nayzeee-backpack:iconWritten', name) end
end)
