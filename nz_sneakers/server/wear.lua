--[[
    Wearing shoes. The pair leaves the inventory while it's on your feet and is
    stored per character (server KVP), so it survives relogs and comes back
    with the same serial, size and dirt when you take it off.
]]

local function key(id) return 'worn:' .. id end

local function getWorn(id)
    local raw = id and GetResourceKvpString(key(id))
    return raw and json.decode(raw) or nil
end

local function setWorn(id, data)
    if data then SetResourceKvp(key(id), json.encode(data)) else DeleteResourceKvp(key(id)) end
end

local function pedGender(src)
    return Shared.PedGender(GetEntityModel(GetPlayerPed(src)))
end

lib.callback.register('nz_sneakers:wear', function(src, slot, prev)
    local id = Bridge.GetIdentifier(src)
    local it = Inv.GetSlot(src, slot)
    if not id or not it or it.name ~= Config.Items.shoes then return false end
    local meta = Items.Clean(it.metadata)
    local shoe = Config.Shoes[meta.shoe]
    if not shoe then return false end

    local gender = pedGender(src)
    if not gender then Bridge.Notify(src, Config.Text.notFreemode, 'error') return false end
    if Config.GenderLock and shoe.gender ~= 'unisex' and shoe.gender ~= gender then
        Bridge.Notify(src, Config.Text.wrongGender, 'error')
        return false
    end
    local clothing = Shared.ClothingFor(shoe, gender)
    if not clothing then Bridge.Notify(src, Config.Text.noClothing, 'error') return false end

    if not Inv.Remove(src, Config.Items.shoes, 1, slot) then return false end

    -- already wearing a pair: it goes back to the inventory, keep the original "previous" shoes
    local current = getWorn(id)
    if current then
        if not Items.GivePair(src, current.meta, false) then
            Items.GivePair(src, meta, false)
            Bridge.Notify(src, Config.Text.noSpace, 'error')
            return false
        end
        prev = current.prev
    end

    if type(prev) ~= 'table' or type(prev.drawable) ~= 'number' then prev = nil end
    setWorn(id, { meta = meta, prev = prev })
    return true, clothing
end)

lib.callback.register('nz_sneakers:takeOff', function(src)
    local id = Bridge.GetIdentifier(src)
    local worn = getWorn(id)
    if not worn then
        Bridge.Notify(src, Config.Text.notWearing, 'error')
        return false
    end
    if not Items.GivePair(src, worn.meta, false) then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    setWorn(id, nil)
    local gender = pedGender(src) or 'male'
    return true, worn.prev or Config.Wear.barefoot[gender]
end)

lib.callback.register('nz_sneakers:getWorn', function(src)
    local worn = getWorn(Bridge.GetIdentifier(src))
    if not worn then return nil end
    local shoe = Config.Shoes[worn.meta.shoe]
    local gender = pedGender(src)
    local clothing = shoe and gender and Shared.ClothingFor(shoe, gender)
    return clothing and { meta = worn.meta, clothing = clothing } or nil
end)

--- For other resources (dirt, selling worn pairs...)
exports('GetWorn', function(src) return getWorn(Bridge.GetIdentifier(src)) end)
exports('SetWornMeta', function(src, meta)
    local id = Bridge.GetIdentifier(src)
    local worn = getWorn(id)
    if not worn then return false end
    worn.meta = Items.Clean(meta)
    setWorn(id, worn)
    return true
end)
