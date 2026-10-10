--[[ Character profiles: load, defaults, xp / levels, objectives, client state sync ]]

Profile = {}

local loaded = {}     -- src -> { id, data, dirty }
local byId = {}       -- identifier -> src

local function defaults()
    return {
        v = 1,
        story = { stage = 'none' },
        xp = 0,
        stats = { harvests = 0, buds = 0, packaged = 0, dried = 0, mixed = 0, bricks = 0, spent = 0 },
        labs = {
            rv = { owned = false, objects = {} },
            small = { owned = false, objects = {} },
            warehouse = { owned = false, objects = {} },
        },
        water = 0,
        products = {},
        seq = 0,
    }
end

-- fill missing keys from the defaults (keeps old saves working when new fields are added)
local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = Utils.copy(v)
        elseif type(v) == 'table' and type(dst[k]) == 'table' and next(v) ~= nil and #v == 0 then
            fill(dst[k], v)
        end
    end
    return dst
end

function Profile.load(src)
    if loaded[src] then return loaded[src].data end
    local id = FW.identifier(src)
    if not id then return nil end
    local data = DB.load(id)
    data = fill(data or {}, defaults())
    loaded[src] = { id = id, data = data, dirty = false }
    byId[id] = src
    data.name = FW.charName(src)
    return data
end

function Profile.get(src)
    local p = loaded[src]
    return p and p.data
end

function Profile.identifier(src)
    local p = loaded[src]
    return p and p.id
end

function Profile.srcOf(identifier)
    return byId[identifier]
end

function Profile.all()
    return loaded
end

function Profile.dirty(src)
    local p = loaded[src]
    if p then p.dirty = true end
end

function Profile.save(src, force)
    local p = loaded[src]
    if not p or (not p.dirty and not force) then return end
    p.dirty = false
    DB.save(p.id, p.data)
end

function Profile.unload(src)
    local p = loaded[src]
    if not p then return end
    Profile.save(src, true)
    byId[p.id] = nil
    loaded[src] = nil
end

function Profile.nextId(P, prefix)
    P.seq = (P.seq or 0) + 1
    return (prefix or 'x') .. P.seq
end

--[[ levels ]]
function Profile.level(P)
    return (Utils.levelFromXp(P.xp))
end

function Profile.addXp(src, amount, why)
    local P = Profile.get(src)
    if not P or amount <= 0 then return end
    local before = Profile.level(P)
    P.xp = P.xp + math.floor(amount)
    local after = Profile.level(P)
    Profile.dirty(src)
    TriggerClientEvent('nzwl:xp', src, math.floor(amount), why)
    if after > before then
        local unlocks = {}
        for lvl = before + 1, after do
            for _, u in ipairs(Utils.unlocksAt(lvl)) do unlocks[#unlocks + 1] = u end
        end
        TriggerClientEvent('nzwl:levelup', src, { level = after, title = Utils.title(after), unlocks = unlocks })
        Logs.send('Level up', ('%s reached %s'):format(P.name or src, Utils.levelLabel(after)), 3066993)
    end
    Profile.sync(src)
end

--[[ the objective line on the HUD (top left) ]]
local OBJECTIVES = {
    steal = function(P)
        local spot = Config.Story.rv.spots[P.story.rvSpot or 1]
        return { title = 'Steal the RV', text = ('The Ballas are sitting on it at %s.'):format(spot and spot.label or 'their spot') }
    end,
    escape = function() return { title = 'Lose the Ballas', text = 'Get the RV far away from their turf.' } end,
    deaddrop = function() return { title = 'Dead drop', text = 'Collect the seeds Benson left for you.' } end,
    hardware = function() return { title = 'Gear up', text = 'Buy pots, soil, a watering can, trimmers and a packaging station at a hardware store.' } end,
    setup = function() return { title = 'Start growing', text = 'Go in the RV: place a pot, add soil, plant a seed and water it. Then harvest it.' } end,
    pack = function() return { title = 'Package it', text = 'Bag your harvest at the packaging station.' } end,
}

function Profile.objective(P)
    local fn = OBJECTIVES[P.story.stage]
    if fn then return fn(P) end
    if P.story.stage == 'none' and Config.Benson.hint then
        return { title = 'Uncle Benson', text = 'Word is an old man in a wheelchair is looking for help. Find him.' }
    end
    return nil
end

--[[ client state. Small: sent on every change that matters. ]]
function Profile.state(src)
    local P = Profile.get(src)
    if not P then return nil end
    local level, into, need = Utils.levelFromXp(P.xp)
    local labs = {}
    for id, lab in pairs(P.labs) do
        labs[id] = { owned = lab.owned == true, entrance = lab.entrance }
    end
    labs.rv.net = Labs.rvNet(src)
    return {
        stage = P.story.stage,
        objective = Profile.objective(P),
        rvSpot = P.story.rvSpot,
        drop = P.story.stage == 'deaddrop' and P.story.drop or nil,
        level = level, xp = into, need = need, title = Utils.title(level),
        labs = labs,
        water = P.water,
        now = os.time(),
    }
end

function Profile.sync(src)
    local s = Profile.state(src)
    if s then TriggerClientEvent('nzwl:state', src, s) end
end

AddEventHandler('playerDropped', function()
    local src = source
    if loaded[src] then
        TriggerEvent('nzwl:server:unload', src)
        Profile.unload(src)
    end
end)
