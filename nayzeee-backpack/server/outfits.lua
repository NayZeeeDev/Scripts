-----------------------------------------------------------------
-- Outfit bag (server)
--
-- A bag is either SET DOWN (a networked prop, outfits held here and
-- mirrored on the prop's statebag) or IN YOUR POCKETS (outfits live
-- in the item metadata). Every action takes a handle for either:
--   { netId = n }  a bag on the ground
--   { slot = n }   the bag item in your own inventory (quick change)
--
-- A set-down bag is also written to KVP, so a server crash or a
-- disconnect can never eat it: it comes back on the next login.
-----------------------------------------------------------------

local cfg = Config.OutfitBag
if not cfg or not cfg.enabled then return end

local ox = exports.ox_inventory
local ITEM = cfg.item or 'outfit_bag'

local placed = {}     -- [src] = { object, metadata }
local cooldowns = {}  -- [src] = os.clock() of last action
local monitor = false

local TAGS = {}
for _, t in ipairs(cfg.tags or {}) do TAGS[t.key] = true end

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end

-----------------------------------------------------------------
-- validation
-----------------------------------------------------------------

local function cleanLabel(label)
    if type(label) ~= 'string' then return nil end
    label = label:gsub('^%s+', ''):gsub('%s+$', ''):gsub('[<>]', '')
    if #label < 1 or #label > (cfg.maxLabelLength or 30) then return nil end
    return label
end

--- Only keys from the config, only whole numbers.
local function cleanOutfit(outfit)
    if type(outfit) ~= 'table' then return nil end
    local out, any = {}, false
    for name, data in pairs(outfit) do
        local known = cfg.components[name] ~= nil or cfg.props[name] ~= nil or (name == 'hair' and cfg.saveHair)
        if known and type(data) == 'table' and type(data.dId) == 'number' and type(data.tId) == 'number' then
            local e = { dId = math.floor(data.dId), tId = math.floor(data.tId) }
            if name == 'hair' then
                e.c = math.floor(tonumber(data.c) or 0)
                e.h = math.floor(tonumber(data.h) or 0)
            end
            out[name] = e
            any = true
        end
    end
    return any and out or nil
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function newId(outfits)
    local id
    repeat id = lib.string.random('aaaaaaaa') until outfits[id] == nil
    return id
end

local function copyOutfit(o)
    local c = {}
    for k, v in pairs(o) do c[k] = { dId = v.dId, tId = v.tId, c = v.c, h = v.h } end
    return c
end

local function onCooldown(src)
    local now = os.clock()
    if cooldowns[src] and now - cooldowns[src] < 0.35 then return true end
    cooldowns[src] = now
    return false
end

-----------------------------------------------------------------
-- share codes  (NZO1-<base64 json>)
-----------------------------------------------------------------

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64R = {}
for i = 1, #B64 do B64R[B64:byte(i)] = i - 1 end

local function b64encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = (a << 16) | ((b or 0) << 8) | (c or 0)
        out[#out + 1] = B64:sub((v >> 18) + 1, (v >> 18) + 1) .. B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
            .. (b and B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) or '=')
            .. (c and B64:sub((v & 63) + 1, (v & 63) + 1) or '=')
    end
    return table.concat(out)
end

local function b64decode(s)
    s = s:gsub('[^%w%+/]', '')
    local out = {}
    for i = 1, #s, 4 do
        local a, b, c, d = B64R[s:byte(i)], B64R[s:byte(i + 1)], B64R[s:byte(i + 2)], B64R[s:byte(i + 3)]
        if not a or not b then break end
        local v = (a << 18) | (b << 12) | ((c or 0) << 6) | (d or 0)
        out[#out + 1] = string.char((v >> 16) & 255)
        if c then out[#out + 1] = string.char((v >> 8) & 255) end
        if d then out[#out + 1] = string.char(v & 255) end
    end
    return table.concat(out)
end

local function encodeCode(entry)
    return 'NZO1-' .. b64encode(json.encode({ l = entry.label, m = entry.model, o = entry.outfit }))
end

local function decodeCode(code)
    if type(code) ~= 'string' or #code > 4096 then return nil end
    local body = code:match('^%s*NZO1%-([%w%+/=]+)%s*$')
    if not body then return nil end
    local ok, data = pcall(json.decode, b64decode(body))
    if not ok or type(data) ~= 'table' then return nil end
    local outfit = cleanOutfit(data.o)
    if not outfit then return nil end
    return { label = cleanLabel(data.l) or 'Shared outfit', model = tonumber(data.m), outfit = outfit }
end

-----------------------------------------------------------------
-- inventory side
-----------------------------------------------------------------

local function describe(meta)
    meta.description = ('%d/%d outfits'):format(count(meta.outfits), cfg.maxOutfits)
    return meta
end

local function findSlot(src)
    local slots = ox:Search(src, 'slots', ITEM)
    if slots and slots[1] then return slots[1].slot, slots[1].metadata or {} end
end

local function kvpKey(src) return ('outfitbag:%s'):format(Framework.getIdentifier(src)) end

-----------------------------------------------------------------
-- set down / pick up
-----------------------------------------------------------------

local function syncPlaced(src)
    local bag = placed[src]
    if not bag or not DoesEntityExist(bag.object) then return end
    Entity(bag.object).state:set('nb_outfitbag', {
        owner = src,
        outfits = bag.metadata.outfits or {},
        public = bag.metadata.public == true,
    }, true)
    -- keep the crash copy current
    SetResourceKvp(kvpKey(src), json.encode(bag.metadata))
end

---@param reason 'pickup'|'distance'|'dropped'|'restart'
local function removeBag(src, reason)
    local bag = placed[src]
    if not bag then return false end
    placed[src] = nil

    if DoesEntityExist(bag.object) then
        Entity(bag.object).state:set('nb_outfitbag', nil, true)
        DeleteEntity(bag.object)
    end

    -- A dropping player's inventory may already be saved, so don't hand
    -- the item to it: the KVP copy gives it back on their next login.
    if reason == 'dropped' then return true end

    if ox:AddItem(src, ITEM, 1, describe(bag.metadata)) then
        DeleteResourceKvp(kvpKey(src))
    else
        print(('^3[nayzeee-backpack] could not hand outfit bag back to %s, it will be restored on login^0'):format(src))
    end

    if reason == 'distance' then
        TriggerClientEvent('nayzeee-backpack:notify', src, S('ob_too_far'), 'inform')
    end
    TriggerClientEvent('nayzeee-backpack:outfit:returned', src)
    return true
end

local function startMonitor()
    if monitor then return end
    monitor = true
    CreateThread(function()
        while next(placed) do
            for src, bag in pairs(placed) do
                if GetPlayerPing(src) == 0 then
                    removeBag(src, 'dropped')
                elseif not DoesEntityExist(bag.object) then
                    removeBag(src, 'pickup')
                else
                    local ped = GetPlayerPed(src)
                    if ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(bag.object)) > (cfg.returnDistance or 12.0) then
                        removeBag(src, 'distance')
                    end
                end
            end
            Wait(1500)
        end
        monitor = false
    end)
end

lib.callback.register('nayzeee-backpack:outfit:place', function(src, coords, slot)
    if placed[src] then removeBag(src, 'pickup') end
    if type(coords) ~= 'table' and type(coords) ~= 'vector4' then return false end

    local slotData = ox:GetSlot(src, tonumber(slot) or -1)
    if not slotData or slotData.name ~= ITEM then return false end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) > 6.0 then return false end

    local metadata = slotData.metadata or {}
    if not ox:RemoveItem(src, ITEM, 1, nil, slotData.slot) then return false end

    local object = CreateObjectNoOffset(joaat(cfg.prop), coords.x, coords.y, coords.z, true, true, false)
    local deadline = GetGameTimer() + 5000
    while not DoesEntityExist(object) and GetGameTimer() < deadline do Wait(10) end
    if not DoesEntityExist(object) then
        ox:AddItem(src, ITEM, 1, metadata)
        return false
    end

    FreezeEntityPosition(object, true)
    SetEntityHeading(object, coords.w or 0.0)

    metadata.outfits = metadata.outfits or {}
    if metadata.public == nil then metadata.public = not cfg.access.defaultLocked end
    placed[src] = { object = object, metadata = metadata }
    syncPlaced(src)
    startMonitor()
    return NetworkGetNetworkIdFromEntity(object)
end)

lib.callback.register('nayzeee-backpack:outfit:pickup', function(src)
    return removeBag(src, 'pickup')
end)

-----------------------------------------------------------------
-- resolving a handle
-----------------------------------------------------------------

--- -> { meta, isOwner, owner, commit() } or nil
local function resolve(src, handle)
    if type(handle) ~= 'table' then return nil end

    if handle.netId then
        local entity = NetworkGetEntityFromNetworkId(tonumber(handle.netId) or 0)
        for owner, bag in pairs(placed) do
            if bag.object == entity then
                local ped = GetPlayerPed(src)
                if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > (cfg.closeDistance or 5.0) + 3.0 then
                    return nil
                end
                return {
                    meta = bag.metadata, isOwner = owner == src, owner = owner,
                    commit = function() syncPlaced(owner) end,
                }
            end
        end
        return nil
    end

    if handle.slot then
        local slotData = ox:GetSlot(src, tonumber(handle.slot) or -1)
        if not slotData or slotData.name ~= ITEM then return nil end
        local meta = slotData.metadata or {}
        meta.outfits = meta.outfits or {}
        return {
            meta = meta, isOwner = true, owner = src,
            commit = function()
                ox:SetMetadata(src, slotData.slot, describe(meta))
                TriggerClientEvent('nayzeee-backpack:outfit:sync', src, meta.outfits, meta.public == true)
            end,
        }
    end
end

-----------------------------------------------------------------
-- actions
-----------------------------------------------------------------

local MUTATING = { save = true, overwrite = true, rename = true, delete = true, favorite = true, tag = true, import = true, importcode = true }

lib.callback.register('nayzeee-backpack:outfit:action', function(src, handle, action, payload)
    payload = type(payload) == 'table' and payload or {}
    if onCooldown(src) then return { ok = false, msg = S('ob_cooldown') } end

    local bag = resolve(src, handle)
    if not bag then return { ok = false, msg = S('ob_not_found') } end

    local access = cfg.access or {}
    if not bag.isOwner and bag.meta.public ~= true then return { ok = false, msg = S('ob_no_permission') } end
    if MUTATING[action] and not bag.isOwner and not access.othersCanSave then return { ok = false, msg = S('ob_no_permission') } end
    if action == 'togglelock' and not bag.isOwner then return { ok = false, msg = S('ob_no_permission') } end
    if action == 'copy' and (bag.isOwner or not access.othersCanCopy) then return { ok = false, msg = S('ob_no_permission') } end

    local outfits = bag.meta.outfits
    local msg

    local function room()
        return count(outfits) < cfg.maxOutfits
    end

    if action == 'save' then
        local label, outfit = cleanLabel(payload.label), cleanOutfit(payload.outfit)
        if not label or not outfit then return { ok = false, msg = S('ob_invalid_name') } end
        if not room() then return { ok = false, msg = S('ob_full', count(outfits), cfg.maxOutfits) } end
        outfits[newId(outfits)] = { label = label, outfit = outfit, model = tonumber(payload.model), fav = false }
        msg = S('ob_saved', label)

    elseif action == 'overwrite' then
        local e, outfit = outfits[payload.id], cleanOutfit(payload.outfit)
        if not e or not outfit then return { ok = false, msg = S('ob_not_found') } end
        e.outfit, e.model = outfit, tonumber(payload.model)
        msg = S('ob_updated', e.label)

    elseif action == 'rename' then
        local e, label = outfits[payload.id], cleanLabel(payload.label)
        if not e or not label then return { ok = false, msg = S('ob_invalid_name') } end
        e.label = label
        msg = S('ob_renamed')

    elseif action == 'delete' then
        if not outfits[payload.id] then return { ok = false, msg = S('ob_not_found') } end
        outfits[payload.id] = nil
        msg = S('ob_deleted')

    elseif action == 'favorite' then
        local e = outfits[payload.id]
        if not e then return { ok = false } end
        e.fav = not e.fav

    elseif action == 'tag' then
        local e = outfits[payload.id]
        if not e then return { ok = false } end
        e.tag = TAGS[payload.tag] and payload.tag or nil

    elseif action == 'togglelock' then
        bag.meta.public = not bag.meta.public
        msg = bag.meta.public and S('ob_unlocked') or S('ob_locked')

    elseif action == 'share' then
        if not cfg.sharing then return { ok = false } end
        local e = outfits[payload.id]
        if not e then return { ok = false } end
        return { ok = true, code = encodeCode(e), msg = S('ob_code_copied') }

    elseif action == 'importcode' then
        if not cfg.sharing then return { ok = false } end
        local entry = decodeCode(payload.code)
        if not entry then return { ok = false, msg = S('ob_code_bad') } end
        if not room() then return { ok = false, msg = S('ob_full', count(outfits), cfg.maxOutfits) } end
        entry.fav = false
        outfits[newId(outfits)] = entry
        msg = S('ob_imported', entry.label)

    elseif action == 'copy' then
        local e = outfits[payload.id]
        if not e then return { ok = false, msg = S('ob_not_found') } end
        local copy = { label = e.label, outfit = copyOutfit(e.outfit), model = e.model, fav = false, tag = e.tag }

        local mine = placed[src]
        if mine then
            if count(mine.metadata.outfits) >= cfg.maxOutfits then return { ok = false, msg = S('ob_your_full') } end
            mine.metadata.outfits[newId(mine.metadata.outfits)] = copy
            syncPlaced(src)
        else
            local slot, meta = findSlot(src)
            if not slot then return { ok = false, msg = S('ob_need_own') } end
            meta.outfits = meta.outfits or {}
            if count(meta.outfits) >= cfg.maxOutfits then return { ok = false, msg = S('ob_your_full') } end
            meta.outfits[newId(meta.outfits)] = copy
            ox:SetMetadata(src, slot, describe(meta))
        end
        return { ok = true, msg = S('ob_copied', e.label) }

    elseif action == 'import' then
        local w = cfg.wardrobe or {}
        if not w.enabled or GetResourceState('illenium-appearance') ~= 'started' then return { ok = false, msg = S('ob_import_failed') } end
        if not room() then return { ok = false, msg = S('ob_full', count(outfits), cfg.maxOutfits) } end
        local identifier = Framework.getIdentifier(src)
        local row = MySQL.single.await(('SELECT * FROM `%s` WHERE id = ? AND citizenid = ?'):format(w.table),
            { tonumber(payload.wardrobeId) or -1, identifier })
        if not row then return { ok = false, msg = S('ob_import_failed') } end

        local outfit = {}
        local names = {}
        for n, id in pairs(cfg.components) do names['c' .. id] = n end
        for n, id in pairs(cfg.props) do names['p' .. id] = n end
        local ok1, comps = pcall(json.decode, row.components or '[]')
        for _, c in ipairs(ok1 and comps or {}) do
            local n = names['c' .. tostring(c.component_id)]
            if n and type(c.drawable) == 'number' then outfit[n] = { dId = c.drawable, tId = c.texture or 0 } end
        end
        local ok2, props = pcall(json.decode, row.props or '[]')
        for _, p in ipairs(ok2 and props or {}) do
            local n = names['p' .. tostring(p.prop_id)]
            if n and type(p.drawable) == 'number' and p.drawable ~= -1 then outfit[n] = { dId = p.drawable, tId = p.texture or 0 } end
        end
        outfit = cleanOutfit(outfit)
        if not outfit then return { ok = false, msg = S('ob_import_failed') } end

        local label = cleanLabel(row.outfitname) or 'Imported'
        local model = type(row.model) == 'string' and joaat(row.model) or nil -- older illenium tables have no model column
        outfits[newId(outfits)] = { label = label, outfit = outfit, model = model, fav = false }
        msg = S('ob_imported', label)

    else
        return { ok = false }
    end

    bag.commit()
    return { ok = true, msg = msg }
end)

lib.callback.register('nayzeee-backpack:outfit:wardrobe', function(src)
    local w = cfg.wardrobe or {}
    if not w.enabled or GetResourceState('illenium-appearance') ~= 'started' then return {} end
    local rows = MySQL.query.await(('SELECT id, outfitname FROM `%s` WHERE citizenid = ? ORDER BY outfitname'):format(w.table),
        { Framework.getIdentifier(src) }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = { id = r.id, name = r.outfitname } end
    return list
end)

--- Outfits of a bag in your own inventory, for quick change
lib.callback.register('nayzeee-backpack:outfit:slot', function(src, slot)
    local slotData = ox:GetSlot(src, tonumber(slot) or -1)
    if not slotData or slotData.name ~= ITEM then return nil end
    local meta = slotData.metadata or {}
    return { outfits = meta.outfits or {}, public = meta.public == true }
end)

-----------------------------------------------------------------
-- crash / disconnect recovery
-----------------------------------------------------------------

local function restore(src)
    if placed[src] then return end
    local key = kvpKey(src)
    local raw = GetResourceKvpString(key)
    if not raw then return end
    local ok, meta = pcall(json.decode, raw)
    if ok and type(meta) == 'table' and ox:AddItem(src, ITEM, 1, describe(meta)) then
        DeleteResourceKvp(key)
        TriggerClientEvent('nayzeee-backpack:notify', src, S('ob_restored'), 'success')
    end
end

Framework.onPlayerLoaded(function(src) SetTimeout(4000, function() restore(src) end) end)

CreateThread(function()
    Wait(5000)
    for _, id in ipairs(GetPlayers()) do restore(tonumber(id)) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if placed[src] then removeBag(src, 'dropped') end
    cooldowns[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(placed) do removeBag(src, 'restart') end
end)
