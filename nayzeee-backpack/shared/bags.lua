-----------------------------------------------------------------
-- Bags
--
-- One place that answers "what is this bag": its storage, where it
-- sits, which model/texture a variant uses, and how it's carried.
-- Admin edits from the studio (data/overrides.json) are merged in
-- here, so every other file just asks Bags and never reads Config
-- directly.
-----------------------------------------------------------------

Bags = {}

local IS_SERVER = IsDuplicityVersion()
local overrides = {}

--- Replace the live override table. Server loads it from disk, clients
--- receive it through GlobalState.
function Bags.setOverrides(tbl)
    overrides = type(tbl) == 'table' and tbl or {}
    Bags.cache = {}
end

function Bags.getOverrides() return overrides end

if not IS_SERVER then
    CreateThread(function()
        Bags.setOverrides(GlobalState.nayzeee_bag_overrides)
    end)

    AddStateBagChangeHandler('nayzeee_bag_overrides', 'global', function(_, _, value)
        Bags.setOverrides(value)
        TriggerEvent('nayzeee-backpack:overridesChanged')
    end)
end

local function copyVec(v)
    return v and { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 } or nil
end

--- The bag definition, nil if the key isn't a backpack.
function Bags.def(key)
    return key and Config.Backpacks[key] or nil
end

function Bags.exists(key)
    return key ~= nil and Config.Backpacks[key] ~= nil
end

function Bags.label(key)
    local bag = Bags.def(key)
    local o = overrides[key]
    return (o and o.label) or (bag and bag.label) or key or 'Backpack'
end

function Bags.price(key)
    local bag = Bags.def(key)
    if not bag then return nil end
    local o = overrides[key]
    if o and o.price ~= nil then return tonumber(o.price) end
    return bag.price
end

--- Storage settings for a bag, falling back to the defaults.
function Bags.storage(key)
    local bag = Bags.def(key)
    local o = overrides[key] or {}
    return {
        slots  = math.floor(tonumber(o.slots)  or (bag and bag.slots)  or Config.Storage.slots),
        weight = math.floor(tonumber(o.weight) or (bag and bag.weight) or Config.Storage.weight),
    }
end

-- Kept so older snippets that call Config.GetStorage still work
function Config.GetStorage(key) return Bags.storage(key) end

-----------------------------------------------------------------
-- carry styles and poses
-----------------------------------------------------------------

function Bags.carryStyle(key)
    local bag = Bags.def(key)
    if not bag or not Config.Carry or not Config.Carry.enabled then return nil end
    local o = overrides[key]
    local styleKey = (o and o.carry) or bag.carry
    if not styleKey or styleKey == 'none' then return nil end
    return Config.Carry.Styles and Config.Carry.Styles[styleKey] or nil, styleKey
end

function Bags.pose(poseKey)
    if not poseKey or not Config.Carry or not Config.Carry.Poses then return nil end
    for i, p in ipairs(Config.Carry.Poses) do
        if p.key == poseKey then return p, i end
    end
    return nil
end

--- Which pose a worn bag should play. Player choice > bag default > style default.
function Bags.poseFor(key, chosen)
    local style = Bags.carryStyle(key)
    if not style then return nil end
    local bag = Bags.def(key)
    local o = overrides[key]
    return Bags.pose(chosen) or Bags.pose(o and o.pose) or Bags.pose(bag and bag.pose) or Bags.pose(style.pose)
end

--- The offset from config alone, ignoring studio saves (studio "Factory" button).
function Bags.configOffset(key)
    local saved = overrides[key]
    overrides[key] = nil
    local bone, pos, rot = Bags.offset(key)
    overrides[key] = saved
    return bone, pos, rot
end

-----------------------------------------------------------------
-- offsets
-----------------------------------------------------------------

--- bone, pos, rot for a bag. Studio save > bag.offset > carry style > default.
function Bags.offset(key)
    local d = Config.DefaultOffset
    local bag = Bags.def(key)
    local o = overrides[key] and overrides[key].offset
    local b = bag and bag.offset
    local style = Bags.carryStyle(key)
    local s = style and style.offset

    local src = o or b or s or d

    -- fill any missing piece from the layer beneath it
    local bone = src.bone or (b and b.bone) or (s and s.bone) or d.bone
    local pos  = src.pos  or (b and b.pos)  or (s and s.pos)  or d.pos
    local rot  = src.rot  or (b and b.rot)  or (s and s.rot)  or d.rot

    return tonumber(bone) or d.bone, copyVec(pos), copyVec(rot)
end

-----------------------------------------------------------------
-- variants
--
-- Accepts all three config formats and hands back one shape:
--   { id = n, label = 'Red', model = 'x' or nil, texture = n or nil }
-- `id` is what gets stored in item metadata.
-----------------------------------------------------------------

function Bags.variants(key)
    Bags.cache = Bags.cache or {}
    local cached = Bags.cache[key]
    if cached then return cached end

    local bag = Bags.def(key)
    local list = {}

    if bag and type(bag.variants) == 'table' then
        local isArray = bag.variants[1] ~= nil and type(bag.variants[1]) == 'table'

        if isArray then
            for i, v in ipairs(bag.variants) do
                list[#list + 1] = {
                    id      = i,
                    label   = tostring(v.label or v.name or ('Style %d'):format(i)),
                    model   = v.model,
                    texture = tonumber(v.texture or v.tex),
                }
            end
        else
            for idx, v in pairs(bag.variants) do
                local n = tonumber(idx)
                if n then
                    local label, model, texture = v, nil, n
                    if type(v) == 'table' then
                        label   = v.label or v.name
                        model   = v.model
                        texture = tonumber(v.texture or v.tex) or n
                    end
                    list[#list + 1] = {
                        id = n, label = tostring(label or ('Skin %d'):format(n)),
                        model = model, texture = texture,
                    }
                end
            end
            table.sort(list, function(a, b) return a.id < b.id end)
        end
    end

    Bags.cache[key] = list
    return list
end

--- Find a variant by id, nil if it doesn't exist.
function Bags.variant(key, id)
    id = tonumber(id)
    if not id then return nil end
    for _, v in ipairs(Bags.variants(key)) do
        if v.id == id then return v end
    end
    return nil
end

--- The variant a bag starts on when none is chosen.
function Bags.defaultVariant(key)
    local list = Bags.variants(key)
    return list[1] and list[1].id or nil
end

--- model name + texture index to actually spawn.
function Bags.resolve(key, variantId)
    local bag = Bags.def(key)
    if not bag then return nil, 0 end
    local v = Bags.variant(key, variantId)
    return (v and v.model) or bag.model, (v and v.texture) or 0
end

--- Every model a bag can spawn as, for preloading / item checks.
function Bags.models(key)
    local bag = Bags.def(key)
    if not bag then return {} end
    local seen, out = { [bag.model] = true }, { bag.model }
    for _, v in ipairs(Bags.variants(key)) do
        if v.model and not seen[v.model] then
            seen[v.model] = true
            out[#out + 1] = v.model
        end
    end
    return out
end

-----------------------------------------------------------------
-- jobs
-----------------------------------------------------------------

function Bags.jobs(key)
    local bag = Bags.def(key)
    if not bag or not bag.job then return nil end
    return type(bag.job) == 'table' and bag.job or { bag.job }
end

function Bags.isJobBag(key)
    return Bags.jobs(key) ~= nil
end

--- Does a job table { name, grade } satisfy a bag's restriction?
function Bags.jobAllows(key, job)
    local allowed = Bags.jobs(key)
    if not allowed then return true end
    if not job or not job.name then return false end
    local bag = Bags.def(key)
    for _, j in ipairs(allowed) do
        if j == job.name then
            return (tonumber(job.grade) or 0) >= (bag.grade or 0)
        end
    end
    return false
end

--- Sorted list of every bag key, for anything that wants a stable order.
function Bags.keys()
    local out = {}
    for k in pairs(Config.Backpacks) do out[#out + 1] = k end
    table.sort(out, function(a, b) return Bags.label(a) < Bags.label(b) end)
    return out
end

function Bags.debug(...)
    if Config.Debug then print('^5[nayzeee-backpack]^0', ...) end
end
