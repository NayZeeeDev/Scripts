-----------------------------------------------------------------
-- Icons (server)
--
-- Every chain texture gets an inventory picture named after its
-- prop (nzc_xxxxxxxx_a.png), which is what the item's metadata.image
-- points at. Two sources:
--   chainkit draws one for every chain it converts (instant)
--   the studio's icon tab shoots a real in-game one (nicer, wins)
-- Both end up in ox_inventory/web/images. The copy is done here with
-- SaveResourceFile, which newer FXServer builds allow where Node can't.
-----------------------------------------------------------------

local MAX_BYTES = 6 * 1024 * 1024
local warned = false

local function knownProp(name)
    for _, d in pairs(Chains.list) do
        for _, v in ipairs(d.variants) do if v.prop == name then return true end end
    end
    return false
end

RegisterNetEvent('nzc:icon:save', function(name, b64)
    local src = source
    if not Studio.allowed(src) then return end
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') or #name > 80 or not knownProp(name) then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nzc:icon:saved', src, name, false)
    end
    TriggerEvent('nzc:icon:write', src, name, b64)
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
        if d then out[n] = string.char((v >> 16) & 255, (v >> 8) & 255, v & 255)
        elseif c then out[n] = string.char((v >> 16) & 255, (v >> 8) & 255)
        else out[n] = string.char((v >> 16) & 255) end
    end
    return table.concat(out)
end

local function toInventory(name, b64)
    if not Config.Icons.SaveToInventory or GetResourceState('ox_inventory') == 'missing' then return false end
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then return false end
    if SaveResourceFile('ox_inventory', ('web/images/%s.png'):format(name), bin, #bin) then return true end
    if not warned then
        warned = true
        print('^3[nayzeee-chainsnatch] could not write into ox_inventory/web/images. Add this to server.cfg and restart:^0')
        print(('^3    add_filesystem_permission %s write ox_inventory^0'):format(GetCurrentResourceName()))
        print('^3  Your icons are still in nayzeee-chainsnatch/icons/ and nayzeee-chainprops/icons/, copy them over by hand.^0')
    end
    return false
end

AddEventHandler('nzc:icon:written', function(src, name, ok, b64)
    local where = ' → icons/'
    if ok then where = toInventory(name, b64) and ' → icons/ + ox_inventory' or ' → icons/ only' end
    TriggerClientEvent('nzc:icon:saved', src, name, ok, where)
end)

AddEventHandler('nzc:icon:copy', function(name, b64) toInventory(name, b64) end)

--- Hand chainkit's icons to the inventory (skips ones the studio already shot unless force).
function CopyKitIcons(force)
    local names = {}
    for _, d in pairs(Chains.list) do
        for _, v in ipairs(d.variants) do names[#names + 1] = v.prop end
    end
    if #names > 0 then TriggerEvent('nzc:icons:fromKit', Config.PropsResource, names, force == true) end
end

CreateThread(function() Wait(4000); CopyKitIcons(false) end)
