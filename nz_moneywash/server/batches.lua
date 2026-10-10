--[[ Batches — the server-side truth for every load of cash moving through the pipeline.
     Items only carry a batch id; value, heat, dye and quality live here and cannot be spoofed. ]]

Batches = { list = {} }

local charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function randomCode(len)
    local s = {}
    for i = 1, len do
        local r = math.random(#charset)
        s[i] = charset:sub(r, r)
    end
    return table.concat(s)
end

local function newSerial(prefix)
    return ('%s-%04d-%s'):format(prefix, math.random(0, 9999), randomCode(1))
end

function Batches.create(src, source, amount)
    local id
    repeat id = 'B' .. randomCode(7) until not Batches.list[id]

    local dye = 0
    if math.random() < (source.dyeChance or 0) then dye = math.random(15, 100) else dye = math.random(0, 22) end

    local b = {
        id = id,
        owner = Bridge.getIdentifier(src),
        ownerName = Bridge.getName(src),
        amount = math.floor(amount),
        source = source.label,
        sourceKey = source.key,
        heat = NZ.clamp((source.heat or 40) + math.random(-8, 8), 0, 100),
        dye = dye,
        quality = 1.0,
        serial = newSerial(source.serial or 'XX'),
        reserialized = false,
        stage = 0,
        handlers = {},
        createdAt = os.time(),
        trail = {},
    }
    Batches.list[id] = b
    Batches.trail(b, 'Loaded into washer by ' .. b.ownerName)
    DB.saveBatch(b)
    return b
end

function Batches.get(id) return id and Batches.list[id] end

function Batches.save(b) DB.saveBatch(b) end

function Batches.remove(id)
    Batches.list[id] = nil
    DB.deleteBatch(id)
end

function Batches.trail(b, text)
    b.trail[#b.trail + 1] = { t = os.time(), text = text }
    while #b.trail > 12 do table.remove(b.trail, 1) end
end

function Batches.adjustQuality(b, delta)
    b.quality = NZ.clamp(b.quality + delta, Config.Quality.min, Config.Quality.max)
end

function Batches.adjustHeat(b, delta)
    b.heat = NZ.clamp(b.heat + delta, 0, 100)
end

function Batches.reserial(b)
    b.reserialized = true
    b.serial = newSerial('NZ')
end

function Batches.markHandler(b, stage, src)
    b.handlers[stage] = Bridge.getIdentifier(src)
end

function Batches.metadata(b, item)
    return {
        batch = b.id,
        description = ('%s · %s · Q%d%%'):format(b.serial, NZ.money(b.amount), math.floor(b.quality * 100)),
        label = Config.ItemLabels[item],
    }
end

-- public summary sent to the owner's UI (never the trail)
function Batches.summary(b)
    local band = NZ.dyeBand(b.dye)
    return {
        id = b.id,
        serial = b.serial,
        amount = b.amount,
        heat = math.floor(b.heat),
        dye = b.dye,
        dyeLabel = band.label,
        dyeKey = band.key,
        quality = NZ.round(b.quality, 3),
        stage = b.stage,
        source = b.source,
        reserialized = b.reserialized,
        counted = b.counted or false,
        handlers = b.handlers,
        createdAt = b.createdAt,
    }
end

-- Find the first slot of `item` in src's inventory carrying a valid batch (optionally a specific id)
function Batches.findInInventory(src, item, wantId)
    for _, s in ipairs(Inv.batchSlots(src, item)) do
        local b = Batches.list[s.metadata.batch]
        if b and (not wantId or b.id == wantId) then return b, s.slot end
    end
end

function Batches.giveItem(src, b, item)
    local meta = Batches.metadata(b, item)
    if not Inv.canCarry(src, item, 1, meta) then return false end
    return Inv.add(src, item, 1, meta)
end
