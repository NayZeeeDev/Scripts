Items = {}

local function defaultSize(shoe)
    local list = Config.Sizes[shoe.gender == 'female' and 'female' or 'male']
    return list[math.ceil(#list / 2)]
end

--- Label, description and icon the inventory shows. Safe to call repeatedly.
function Items.Decorate(meta, boxed)
    local shoe = Config.Shoes[meta.shoe]
    meta.label = Shared.ShoeName(meta) .. (boxed and ' (boxed)' or '')
    meta.description = Shared.Describe(meta)
    if shoe and shoe.image then meta.image = shoe.image .. (boxed and '_box' or '') end
    return meta
end

--- A brand new pair. real defaults to true.
function Items.NewPair(shoeId, size, real, condition)
    local shoe = Config.Shoes[shoeId]
    if not shoe then return nil end
    real = real ~= false
    local meta = {
        shoe = shoeId,
        size = tostring(size or defaultSize(shoe)),
        real = real,
        quality = real and 100 or math.random(55, 90),   -- fake quality; crafting sets this later
        condition = condition or 'DS',
        dirt = 0,
        serial = Shared.NewSerial(real),
    }
    return meta
end

--- Strip display-only fields before storing
function Items.Clean(meta)
    local out = {}
    for k, v in pairs(meta or {}) do
        if k ~= 'label' and k ~= 'description' and k ~= 'image' then out[k] = v end
    end
    return out
end

function Items.GivePair(src, meta, boxed)
    meta = Items.Decorate(Items.Clean(meta), boxed)
    return Inv.Add(src, boxed and Config.Items.boxed or Config.Items.shoes, 1, meta)
end

--------------------------------------------------------------------------------
-- Item use
--------------------------------------------------------------------------------

CreateThread(function()
    Inv.RegisterUsable(Config.Items.shoes, function(src, it)
        if not it.metadata or not Config.Shoes[it.metadata.shoe] then return end
        local boxType = Shared.BoxTypeForShoe(it.metadata.shoe)
        local hasBox = Inv.Find(src, Config.BoxTypes[boxType].item) ~= nil
        local hasKit = Inv.Find(src, Config.Items.cleaningKit) ~= nil
        TriggerClientEvent('nayzeee-sneakers:client:useShoes', src, it.slot, Items.Clean(it.metadata), hasBox, hasKit)
    end)

    Inv.RegisterUsable(Config.Items.boxed, function(src, it)
        local shoe = it.metadata and it.metadata.shoe
        local boxType = (it.metadata and Config.BoxTypes[it.metadata.box] and it.metadata.box)
            or (shoe and Config.Shoes[shoe] and Shared.BoxTypeForShoe(shoe)) or 'shoe'
        TriggerClientEvent('nayzeee-sneakers:client:placeBox', src, it.slot, 'boxed', boxType)
    end)

    for id, t in pairs(Config.BoxTypes) do
        Inv.RegisterUsable(t.item, function(src, it)
            TriggerClientEvent('nayzeee-sneakers:client:placeBox', src, it.slot, 'empty', id)
        end)
    end
end)

--------------------------------------------------------------------------------
-- Items owed to offline players (shoes left in a box when they disconnected)
--------------------------------------------------------------------------------

Pending = {}

local function pendingKey(id) return 'pending:' .. id end

function Pending.Add(identifier, meta, boxed, boxType)
    if not identifier then return end
    local list = json.decode(GetResourceKvpString(pendingKey(identifier)) or '[]') or {}
    list[#list + 1] = { meta = Items.Clean(meta), boxed = boxed, boxType = boxType }
    SetResourceKvp(pendingKey(identifier), json.encode(list))
end

function Pending.Deliver(src)
    local id = Bridge.GetIdentifier(src)
    if not id then return end
    local list = json.decode(GetResourceKvpString(pendingKey(id)) or '[]') or {}
    if #list == 0 then return end
    local keep = {}
    for _, p in ipairs(list) do
        if p.meta and p.meta.shoe then
            if not Items.GivePair(src, p.meta, p.boxed) then keep[#keep + 1] = p end
        elseif not Inv.Add(src, (Config.BoxTypes[p.boxType] or Config.BoxTypes.shoe).item, 1) then
            keep[#keep + 1] = p
        end
    end
    if #keep > 0 then SetResourceKvp(pendingKey(id), json.encode(keep)) else DeleteResourceKvp(pendingKey(id)) end
end
