--[[
    In-game studio: sell the shoes that are already on the server.

    Where shoes come from
      built in                    Config.ShoeModels (config/shoes.lua)
      nayzeee-sneakers-props      catalogue.json, made by sneakerkit (server/props.lua, or the PC app):
                                  props and icons for the clothing packs on this server
      added in game               a drawable an admin picked in /sneakerstudio; it has no prop of its own
                                  yet, so it shows as the stand-in (Config.Studio.StandIn)

    What admins set per shoe (on sale, name, price, level, box, colour names) is kept in KVP, so it
    survives script updates. Shoe keys are gender:pack:drawable, e.g. f:mypack:007 (pack '' = base game).

    Admins' games scan the server's shoe drawables (client/studio.lua) and report them here, which is
    how new and removed shoes are spotted. Photos taken in the studio are saved at the bottom of this file.
]]

Studio = {}

local S = Config.Studio
local catalogue = {}    -- [key] = entry from catalogue.json
local settings = {}     -- [key] = what admins set
local live = {}         -- [modelId] = model def every client gets
local scan              -- last scan an admin's game reported: { at, base, drawables = { [key] = textures } }
local builtinKeys = {}  -- keys of the shoes in config/shoes.lua

local PREFIX = 'studio:shoe:'

local function pad(n) return ('%03d'):format(tonumber(n) or 0) end
local function keyOf(gender, collection, index) return ('%s:%s:%s'):format(gender == 'female' and 'f' or 'm', collection or '', pad(index)) end
local function genderOfKey(key) local g = key:sub(1, 1); return g == 'f' and 'female' or g == 'm' and 'male' or nil end
local function idOfKey(key) return 'st_' .. key:gsub('[^%w]', '_'):gsub('_+', '_'):lower() end

-- ------------------------------------------------------------------ storage

local function loadCatalogue()
    catalogue = {}
    if GetResourceState(S.PropsResource) == 'missing' then return false end
    local raw = LoadResourceFile(S.PropsResource, 'catalogue.json')
    if not raw then return false end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' or type(data.shoes) ~= 'table' then
        print(('^1[nayzeee-sneakers]^7 %s/catalogue.json could not be read'):format(S.PropsResource))
        return false
    end
    for _, sh in ipairs(data.shoes) do
        if type(sh) == 'table' and sh.key and sh.id and type(sh.colours) == 'table' then catalogue[sh.key] = sh end
    end
    return true
end

local function loadSettings()
    settings = {}
    local h = StartFindKvp(PREFIX)
    if h ~= -1 then
        while true do
            local k = FindKvp(h)
            if not k then break end
            local ok, v = pcall(json.decode, GetResourceKvpString(k) or '')
            if ok and type(v) == 'table' then settings[k:sub(#PREFIX + 1)] = v end
        end
        EndFindKvp(h)
    end
    local raw = GetResourceKvpString('studio:scan')
    local ok, v = pcall(json.decode, raw or '')
    scan = ok and type(v) == 'table' and v or nil
end

local function save(key)
    if settings[key] then SetResourceKvp(PREFIX .. key, json.encode(settings[key]))
    else DeleteResourceKvp(PREFIX .. key) end
end

-- ------------------------------------------------------------------ models

local function builtinKeySet()
    builtinKeys = {}
    for id, m in pairs(Config.ShoeModels) do
        if not m.studio and m.slot then builtinKeys[keyOf(m.gender, Config.ClothingPack, m.slot)] = id end
    end
end

--- Where a shoe is worn from: { collection, index } or nil (a loose download nobody linked yet)
local function linkOf(key)
    local st, c = settings[key] or {}, catalogue[key]
    if st.link then return st.link end
    if c and not c.loose then return { collection = c.collection or '', index = c.drawable } end
    if st.manual then
        local _, col, idx = key:match('^(%a):(.*):(%d+)$')
        return { collection = col, index = tonumber(idx) }
    end
end

local function genderOf(key)
    local st, c = settings[key] or {}, catalogue[key]
    if st.gender == 'male' or st.gender == 'female' then return st.gender end
    if c and (c.gender == 'male' or c.gender == 'female') then return c.gender end
    return genderOfKey(key)
end

local function enabledOf(key)
    local st = settings[key]
    if st and st.enabled ~= nil then return st.enabled == true end
    return S.AutoEnable == true and catalogue[key] ~= nil
end

--- The model def for a studio shoe, or nil
local function modelFor(key)
    local c, st = catalogue[key], settings[key] or {}
    if not c and not st.manual then return nil end
    local box = st.box or (c and c.box) or 'shoe'
    if not Config.BoxTypes[box] then box = 'shoe' end
    local colourways = {}
    if c then
        for _, col in ipairs(c.colours) do
            local l = tostring(col.letter or 'a')
            colourways[l] = (st.colours and st.colours[l]) or col.name or l:upper()
        end
    else
        for i = 1, math.min(26, math.max(1, tonumber(st.textures) or 1)) do
            local l = string.char(96 + i)
            colourways[l] = (st.colours and st.colours[l]) or ('Colour %d'):format(i)
        end
    end
    local link = linkOf(key)
    local gender = genderOf(key)
    return {
        id = c and c.id or idOfKey(key),
        key = key,
        label = st.label or (c and c.label) or 'Shoe',
        gender = gender or 'male',
        box = box,
        retail = tonumber(st.retail) or S.Price[box] or 350,
        level = tonumber(st.level),
        colourways = colourways,
        collection = link and link.collection or nil,
        index = link and tonumber(link.index) or nil,
        studio = true,
        props = c ~= nil,
        hidden = not enabledOf(key) or st.removed == true or nil,
    }
end

local function allKeys()
    local keys = {}
    for k in pairs(catalogue) do if not builtinKeys[k] then keys[k] = true end end
    for k, st in pairs(settings) do if st.manual or catalogue[k] then keys[k] = true end end
    return keys
end

--- Rebuilds the studio shoes into Config.ShoeModels and (optionally) sends them to everyone.
--- A shoe that was ever on sale stays known while it's off, so pairs players already own keep working.
function Studio.Rebuild(broadcast)
    for id in pairs(live) do Config.ShoeModels[id] = nil end
    live = {}
    local over = {}
    for key, st in pairs(settings) do
        local id = key:match('^b:(.+)$')
        if id then over[id] = st end
    end
    Shared.ApplyBuiltinOverrides(over)
    for key in pairs(allKeys()) do
        local m = modelFor(key)
        local st = settings[key] or {}
        if m and (not m.hidden or st.everEnabled) then
            if Config.ShoeModels[m.id] then
                print(('^3[nayzeee-sneakers]^7 studio shoe %s has the same id as a built-in shoe (%s), skipped'):format(key, m.id))
            else
                Config.ShoeModels[m.id] = m
                live[m.id] = m
            end
        end
    end
    BuildShoes()
    if broadcast then TriggerClientEvent('nayzeee-sneakers:client:studioShoes', -1, Studio.Payload()) end
end

function Studio.Live() return live end

--- What admins changed on the built-in shoes: { [modelId] = settings }
local function builtinOverrides()
    local out = {}
    for key, st in pairs(settings) do
        local id = key:match('^b:(.+)$')
        if id and Config.ShoeModels[id] and not Config.ShoeModels[id].studio then out[id] = st end
    end
    return out
end

--- What every client needs: studio shoes plus changes to the built-in ones
function Studio.Payload() return { models = live, builtin = builtinOverrides() } end

-- ------------------------------------------------------------------ scans

--- Collections sneakerkit found in the server's resources: real clothing packs, never "Default GTA"
local function packSet()
    local set = { [tostring(Config.ClothingPack or ''):lower()] = true }
    for _, c in pairs(catalogue) do
        if c.collection and c.collection ~= '' then set[tostring(c.collection):lower()] = true end
    end
    return set
end

--- New drawables (not in any catalogue) and shoes whose drawable is gone, from the last scan
local function diff()
    local fresh, gone = {}, {}
    if not scan or type(scan.drawables) ~= 'table' then return fresh, gone end
    local packs = packSet()
    local keys = allKeys()
    -- drawables plain downloads were linked to are known too
    local linked = {}
    for key in pairs(keys) do
        local link = linkOf(key)
        if link and link.index then linked[keyOf(genderOf(key), link.collection, link.index)] = true end
    end
    for key, textures in pairs(scan.drawables) do
        if not keys[key] and not linked[key] and not builtinKeys[key] and not catalogue[key] then
            local g, col, idx = key:match('^(%a):(.*):(%d+)$')
            if g and (col ~= '' or S.BaseGame) then
                fresh[#fresh + 1] = { key = key, gender = g == 'f' and 'female' or 'male', collection = col, index = tonumber(idx), textures = textures,
                    gta = Shared.IsGtaCollection(col, packs) }
            end
        end
    end
    for key in pairs(keys) do
        local link = linkOf(key)
        if link and (link.collection ~= '' or scan.base) then
            local k = keyOf(genderOf(key), link.collection, link.index)
            if not scan.drawables[k] then gone[#gone + 1] = key end
        end
    end
    table.sort(fresh, function(a, b) return a.key < b.key end)
    table.sort(gone)
    return fresh, gone
end

--- Takes a scan from an admin's game, flags shoes that are gone. Returns new, gone.
local function takeScan(src, data)
    if type(data) ~= 'table' or type(data.drawables) ~= 'table' then return {}, {} end
    local drawables, n = {}, 0
    for key, t in pairs(data.drawables) do
        if type(key) == 'string' and key:match('^[mf]:[%w_%-%.]*:%d%d%d$') and n < 5000 then
            drawables[key] = math.max(1, math.min(26, tonumber(t) or 1))
            n = n + 1
        end
    end
    scan = { at = os.time(), base = data.base == true, drawables = drawables, by = GetPlayerName(src) }
    SetResourceKvp('studio:scan', json.encode(scan))

    local fresh, gone = diff()
    local goneSet, changed = {}, false
    for _, k in ipairs(gone) do goneSet[k] = true end
    for key in pairs(allKeys()) do
        local st = settings[key] or {}
        local want = goneSet[key] or nil
        if st.removed ~= want then
            st.removed = want
            settings[key] = next(st) and st or nil
            save(key)
            changed = true
        end
    end
    if changed then Studio.Rebuild(true) end
    return fresh, gone
end

-- ------------------------------------------------------------------ admin api

local function entryFor(key, packs)
    local m = modelFor(key)
    if not m then return nil end
    local c, st = catalogue[key], settings[key] or {}
    local link = linkOf(key)
    local letters = {}
    for l in pairs(m.colourways) do letters[#letters + 1] = l end
    table.sort(letters)
    local colours = {}
    for _, l in ipairs(letters) do colours[#colours + 1] = { letter = l, name = m.colourways[l], image = ('nzs_%s_%s'):format(m.id, l) } end
    return {
        key = key, id = m.id, label = m.label, gender = m.gender, box = m.box, retail = m.retail, level = m.level,
        colours = colours, props = c ~= nil, loose = c and c.loose or false, manual = st.manual or false,
        enabled = enabledOf(key), removed = st.removed == true, link = link,
        source = c and c.source or nil, pack = link and link.collection or (c and c.collection) or '',
        gta = link ~= nil and Shared.IsGtaCollection(link.collection, packs),
    }
end

--- A shoe from config/shoes.lua, as the studio lists it
local function builtinEntry(id)
    local m = Config.ShoeModels[id]
    local st = settings['b:' .. id] or {}
    local letters = {}
    for l in pairs(m.colourways) do letters[#letters + 1] = l end
    table.sort(letters)
    local colours = {}
    for _, l in ipairs(letters) do colours[#colours + 1] = { letter = l, name = m.colourways[l], image = ('nzs_%s_%s'):format(id, l) } end
    return {
        key = 'b:' .. id, id = id, label = m.label, gender = m.gender, box = m.box, retail = m.retail,
        level = Shared.ModelLevel(id), colours = colours, props = true, loose = false, manual = false, builtin = true,
        enabled = st.enabled ~= false, removed = false,
        link = m.slot and { collection = Config.ClothingPack, index = m.slot } or nil, pack = Config.ClothingPack,
    }
end

local function openData()
    local shoes = {}
    local packs = packSet()
    for key in pairs(allKeys()) do
        local e = entryFor(key, packs)
        if e then shoes[#shoes + 1] = e end
    end
    for id, m in pairs(Config.ShoeModels) do
        if not m.studio then shoes[#shoes + 1] = builtinEntry(id) end
    end
    table.sort(shoes, function(a, b)
        if a.enabled ~= b.enabled then return a.enabled end
        return a.label < b.label
    end)
    local fresh, gone = diff()
    return {
        shoes = shoes, fresh = fresh, gone = gone,
        scan = scan and { at = scan.at, by = scan.by, base = scan.base, count = (function() local n = 0 for _ in pairs(scan.drawables) do n = n + 1 end return n end)() } or nil,
        props = GetResourceState(S.PropsResource), propsResource = S.PropsResource,
        catalogueCount = (function() local n = 0 for _ in pairs(catalogue) do n = n + 1 end return n end)(),
        builtin = (function() local n = 0 for _ in pairs(builtinKeys) do n = n + 1 end return n end)(),
        maxLevel = #Config.XP.levels,
        prices = S.Price, baseGame = S.BaseGame,
        shots = Studio.Shots(),
        kit = ShoeProps and ShoeProps.Status() or nil,
        size = S.Size,
        saveToInventory = S.SaveToInventory and GetResourceState('ox_inventory') ~= 'missing',
    }
end

local function admin(src)
    if not S.Enabled or not src or src <= 0 then return false end
    return IsPlayerAceAllowed(tostring(src), S.Ace or 'command.sneakerstudio') or Bridge.IsAdmin(src)
end
Studio.Allowed = admin

function Studio.CatalogueCount()
    local n = 0
    for _ in pairs(catalogue) do n = n + 1 end
    return n
end

--- Re-reads the props resource's catalogue.json (after a build) and sends the shoes to everyone
function Studio.Reload()
    loadCatalogue()
    Studio.Rebuild(true)
end

lib.callback.register('nayzeee-sneakers:studio:isAdmin', function(src) return admin(src) end)

lib.callback.register('nayzeee-sneakers:studio:shoes', function() return Studio.Payload() end)

lib.callback.register('nayzeee-sneakers:studio:open', function(src)
    if not admin(src) then return nil end
    return openData()
end)

lib.callback.register('nayzeee-sneakers:studio:report', function(src, data)
    if not admin(src) then return nil end
    local fresh, gone = takeScan(src, data)
    return { fresh = #fresh, gone = #gone, data = openData() }
end)

local function clean(str, max)
    str = tostring(str or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return str:sub(1, max or 40)
end

lib.callback.register('nayzeee-sneakers:studio:save', function(src, key, f)
    if not admin(src) or type(key) ~= 'string' or type(f) ~= 'table' then return nil end
    local bid = key:match('^b:(.+)$')
    local isBuiltin = bid and Config.ShoeModels[bid] and not Config.ShoeModels[bid].studio
    if not isBuiltin and not catalogue[key] and not (settings[key] and settings[key].manual) then return nil end
    if isBuiltin then f.box, f.gender, f.link = nil, nil, nil end   -- built-in shoes keep their prop, box and clothing
    local st = settings[key] or {}
    if f.label ~= nil then local l = clean(f.label, 40); st.label = l ~= '' and l or nil end
    if f.retail ~= nil then st.retail = math.max(1, math.min(1000000, math.floor(tonumber(f.retail) or 0))) end
    if f.level ~= nil then local lv = tonumber(f.level); st.level = lv and math.max(1, math.floor(lv)) or nil end
    if f.box ~= nil and Config.BoxTypes[f.box] then st.box = f.box end
    if f.gender == 'male' or f.gender == 'female' then st.gender = f.gender end
    if type(f.colours) == 'table' then
        st.colours = st.colours or {}
        for l, name in pairs(f.colours) do
            if type(l) == 'string' and l:match('^%l$') then
                local n = clean(name, 30)
                st.colours[l] = n ~= '' and n or nil
            end
        end
    end
    if type(f.link) == 'table' and f.link.index then
        st.link = { collection = clean(f.link.collection, 60), index = math.floor(tonumber(f.link.index) or 0) }
    end
    if f.enabled ~= nil then
        st.enabled = f.enabled == true
        if st.enabled then st.everEnabled = true end
    end
    settings[key] = st
    save(key)
    Studio.Rebuild(true)
    Logs.Send(('Studio: %s updated %s (%s)'):format(GetPlayerName(src), st.label or key, st.enabled and 'on sale' or 'off'))
    return openData()
end)

--- Adds a drawable from the scan as a shoe (no prop of its own: it uses the stand-in)
lib.callback.register('nayzeee-sneakers:studio:add', function(src, key)
    if not admin(src) or type(key) ~= 'string' then return nil end
    local textures = scan and scan.drawables and scan.drawables[key]
    if not textures or catalogue[key] or builtinKeys[key] then return nil end
    local g, col, idx = key:match('^(%a):(.*):(%d+)$')
    local label = (col ~= '' and col:gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end) or 'Shoe') .. ' ' .. idx
    settings[key] = settings[key] or {}
    local st = settings[key]
    st.manual, st.textures, st.gender = true, textures, g == 'f' and 'female' or 'male'
    st.label = st.label or label
    st.enabled = st.enabled or false
    save(key)
    Studio.Rebuild(true)
    return openData()
end)

--- Forgets a shoe added in game (catalogue shoes can only be switched off)
lib.callback.register('nayzeee-sneakers:studio:forget', function(src, key)
    if not admin(src) or type(key) ~= 'string' or not settings[key] then return nil end
    if catalogue[key] then
        settings[key].enabled = false
    else
        settings[key] = nil
    end
    save(key)
    Studio.Rebuild(true)
    return openData()
end)

lib.callback.register('nayzeee-sneakers:studio:reload', function(src)
    if not admin(src) then return nil end
    loadCatalogue()
    Studio.Rebuild(true)
    return openData()
end)

-- ------------------------------------------------------------------ photos
-- Same flow as the wig snatch and backpack studios: the NUI keys each shot into a small PNG,
-- server/shots.js writes it into shots/, and the copy into ox_inventory/web/images is done here.

local MAX_BYTES = 4 * 1024 * 1024
local shots = {}        -- [name] = true
local warned = false

local function loadShots()
    shots = {}
    local raw = LoadResourceFile(GetCurrentResourceName(), 'shots/index.json')
    local ok, list = pcall(json.decode, raw or '[]')
    for _, n in ipairs(ok and type(list) == 'table' and list or {}) do
        if type(n) == 'string' then shots[n] = true end
    end
end

function Studio.Shots()
    local out = {}
    for n in pairs(shots) do out[#out + 1] = n end
    table.sort(out)
    return out
end

AddEventHandler('nzs:shots:indexed', loadShots)

RegisterNetEvent('nayzeee-sneakers:server:studioBucket', function(on)
    local src = source
    if not admin(src) then return end
    SetPlayerRoutingBucket(src, on and S.RoutingBucket or 0)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if GetPlayerRoutingBucket(src) == S.RoutingBucket then SetPlayerRoutingBucket(src, 0) end
end)

RegisterNetEvent('nayzeee-sneakers:server:studioPhoto', function(name, b64)
    local src = source
    if not admin(src) then return end
    if type(name) ~= 'string' or not name:match('^nzs_[%w_]+$') or #name > 64 or name:lower() ~= name then return end
    if type(b64) ~= 'string' or #b64 == 0 or #b64 > MAX_BYTES then
        return TriggerClientEvent('nayzeee-sneakers:client:studioPhoto', src, name, false)
    end
    TriggerEvent('nzs:shots:write', src, name, b64)
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
Studio.Decode = decode

local function copyToInventory(name, b64)
    if GetResourceState('ox_inventory') == 'missing' then return false end
    local bin = decode(b64)
    if #bin < 8 or bin:sub(1, 4) ~= '\137PNG' then return false end
    if SaveResourceFile('ox_inventory', ('web/images/%s.png'):format(name), bin, #bin) then return true end
    if not warned then
        warned = true
        print(('^3[nayzeee-sneakers] could not write into ox_inventory/web/images. Add this to server.cfg and restart:^0'))
        print(('^3    add_filesystem_permission %s write ox_inventory^0'):format(GetCurrentResourceName()))
        print(('^3  The photos are still saved in %s/shots/ and you can copy them over by hand.^0'):format(GetCurrentResourceName()))
    end
    return false
end

-- shots.js reports back here
AddEventHandler('nzs:shots:written', function(src, name, ok, b64)
    local where = ' > shots/'
    if ok then
        shots[name] = true
        if S.SaveToInventory then
            where = copyToInventory(name, b64) and ' > shots/ + ox_inventory' or ' > shots/ only (see server console)'
        end
    end
    TriggerClientEvent('nayzeee-sneakers:client:studioPhoto', src, name, ok, where)
end)

RegisterCommand(S.Command, function(src)
    if not admin(src) then return end
    TriggerClientEvent('nayzeee-sneakers:client:studioOpen', src)
end, false)

-- ------------------------------------------------------------------ start

CreateThread(function()
    loadShots()
    builtinKeySet()
    loadSettings()
    local ok = loadCatalogue()
    Studio.Rebuild(false)
    local n = 0
    for _ in pairs(live) do n = n + 1 end
    if ok then
        print(('^2[nayzeee-sneakers]^7 studio: %d shoes from %s'):format(n, S.PropsResource))
    elseif n > 0 then
        print(('^2[nayzeee-sneakers]^7 studio: %d shoes added in game'):format(n))
    end
    TriggerClientEvent('nayzeee-sneakers:client:studioShoes', -1, Studio.Payload())
end)

-- the props resource (re)started after a build: pick up its catalogue
AddEventHandler('onResourceStart', function(res)
    if res ~= S.PropsResource then return end
    SetTimeout(500, function()
        loadCatalogue()
        Studio.Rebuild(true)
    end)
end)

exports('StudioShoes', function() return live end)
