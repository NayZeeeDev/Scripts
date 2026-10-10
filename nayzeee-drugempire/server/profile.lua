--[[ Character profiles: load, defaults, xp / ranks, client state sync ]]

Profile = {}

local loaded = {}     -- src -> { id, data, dirty }
local byId = {}       -- identifier -> src

local function defaults()
    return {
        v = 1,
        story = { stage = 'none' },
        xp = 0,
        stats = { sold = 0, earned = 0, deals = 0, harvests = 0, cooks = 0, samples = 0 },
        rv = { owned = false },
        objects = {},
        water = 0,
        products = {},
        customers = {},
        dealers = {},
        orders = {},
        deals = {},
        threads = {},
        unread = {},
        quests = { done = {}, prog = {} },
        seq = 0,
    }
end

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

--[[ ranks ]]
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
    if after > before then
        Messages.levelUp(src, after)
        Quests.progress(src, 'level')
    end
    TriggerClientEvent('nzde:xp', src, amount, why)
end

--[[ client state (HUD, blips, local peds). Small: sent on every change that matters. ]]
function Profile.state(src)
    local P = Profile.get(src)
    if not P then return nil end
    local level, into, need = Utils.levelFromXp(P.xp)
    local now = os.time()

    local deals = {}
    for _, d in ipairs(P.deals) do
        if d.state == 'accepted' then
            local c = Config.Customers[d.cid]
            deals[#deals + 1] = {
                id = d.id, cid = d.cid, name = c and c.name or d.cid, model = c and c.model,
                qty = d.qty, product = Products.label(d.pid), spot = d.spot, exp = d.exp,
            }
        end
    end

    local orders = {}
    for _, o in ipairs(P.orders) do
        if not o.done and o.ready <= now then orders[#orders + 1] = { id = o.id, drop = o.drop } end
    end

    local dealers = {}
    for id, d in pairs(P.dealers) do
        if d.hired then dealers[#dealers + 1] = id end
    end

    return {
        stage = P.story.stage,
        benson = P.story.spot,
        rvSpot = P.story.rvSpot,
        level = level, xp = into, need = need, rank = Utils.rankLabel(level),
        quest = Quests.current(P),
        deals = deals,
        sample = P.sample,
        orders = orders,
        dealers = dealers,
        rv = { owned = P.rv.owned, net = RV.netOf(src) },
        app = P.story.app == true,
        water = P.water,
        now = now,
    }
end

function Profile.sync(src)
    local s = Profile.state(src)
    if s then TriggerClientEvent('nzde:state', src, s) end
end

AddEventHandler('playerDropped', function()
    local src = source
    if loaded[src] then
        TriggerEvent('nzde:server:unload', src)
        Profile.unload(src)
    end
end)
