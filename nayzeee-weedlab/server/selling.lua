--[[
    Selling.
      Corner: the player offers packaged product to a person on the street. The server picks
              what the customer takes, rolls the answer from the quality, pays and takes the items.
      Bulk:   a buyer takes pressed bricks at a share of their street value, a few a day.
    The client only says "this person"; everything else is decided here.
]]

Selling = {}

local SC, PROD = Config.Selling, Config.Product
local seen = {}       -- ped net id -> os.time() it last bought / refused
local bulkDay = {}    -- identifier -> { day, n }

local PACKS = { { item = PROD.baggie, per = PROD.unitsPerBaggie }, { item = PROD.jar, per = PROD.unitsPerJar } }

local function qmult(q) return SC.quality[Utils.clamp(q or 2, 0, 4)] or 1.0 end

--- street value of one unit of `pid` at quality `q`
function Selling.unitPrice(pid, q)
    return Products.value(pid) * qmult(q)
end

local function policeOk()
    return (SC.minPolice or 0) <= 0 or FW.policeCount() >= SC.minPolice
end

--[[ ─────────────── corner sales ─────────────── ]]

--- what the customer takes: a random packaged stack the player carries
local function pickStack(src)
    local list = {}
    for _, pk in ipairs(PACKS) do
        if SC.corner.wants[pk.item] then
            for _, s in ipairs(Inv.slots(src, pk.item)) do
                if s.meta and s.meta.pid and Products.get(s.meta.pid) then
                    list[#list + 1] = { item = pk.item, per = pk.per, slot = s.slot, count = s.count, meta = s.meta }
                end
            end
        end
    end
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

Guard.callback('nzwl:sell:offer', function(src, net)
    local P = Profile.get(src)
    local C = SC.corner
    if not P or not C.enabled or type(net) ~= 'number' then return false end
    if Labs.inside(src) then return false end
    if not Guard.rate(src, 'sell', (C.cooldown - 0.5) * 1000) then return false, 'Take it easy' end
    if not policeOk() then return false, 'Nobody\'s buying right now' end
    local ped = NetworkGetEntityFromNetworkId(net)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityType(ped) ~= 1 or IsPedAPlayer(ped) then return false end
    if #(GetEntityCoords(ped) - GetEntityCoords(GetPlayerPed(src))) > C.radius + 1.5 then return false end
    local now = os.time()
    if seen[net] and now - seen[net] < C.remember then return false, 'They already talked to you' end
    seen[net] = now

    local stack = pickStack(src)
    if not stack then return false, 'You have nothing bagged to sell' end
    local q = stack.meta.quality or 2
    local A = C.accept
    local chance = Utils.clamp(A.base + (q - 2) * A.perQuality, A.min, A.max)
    if math.random() > chance then
        if math.random(100) <= C.alertChance then
            Dispatch.alert(src, { coords = GetEntityCoords(GetPlayerPed(src)), title = 'Drug sale', message = 'A caller reports someone selling weed on the street.', code = '10-31' })
            return true, { accepted = false, called = true }
        end
        return true, { accepted = false }
    end

    local want = C.wants[stack.item]
    local n = math.min(stack.count, math.random(want[1], want[2]))
    local units = n * stack.per
    local h = C.haggle
    local price = math.floor(Selling.unitPrice(stack.meta.pid, q) * units * (h[1] + math.random() * (h[2] - h[1])) + 0.5)
    if not Inv.removeSlot(src, stack.item, n, stack.slot, stack.meta) then return false end
    if not Inv.payMoney(src, price, 'weedlab-sale') then
        Inv.add(src, stack.item, n, stack.meta)
        return false
    end
    P.stats.sold = (P.stats.sold or 0) + units
    P.stats.earned = (P.stats.earned or 0) + price
    Profile.dirty(src)
    Profile.addXp(src, C.xpPerUnit * units, 'Sale')
    Story.progress(src, 'sell')
    return true, { accepted = true, n = n, item = stack.item, label = Products.label(stack.meta.pid), price = price }
end)

--[[ ─────────────── bulk buyer (bricks) ─────────────── ]]

local function today() return math.floor(os.time() / 86400) end

local function bulkLeft(src)
    local id = Profile.identifier(src)
    local b = bulkDay[id]
    if not b or b.day ~= today() then b = { day = today(), n = 0 } bulkDay[id] = b end
    return SC.bulk.perDay - b.n, b
end

local function bricks(src)
    local out = {}
    for _, s in ipairs(Inv.slots(src, PROD.brick)) do
        local pid = s.meta and s.meta.pid
        if pid and Products.get(pid) then
            local units = s.meta.units or PROD.unitsPerBrick
            out[#out + 1] = {
                slot = s.slot, n = s.count, pid = pid, q = s.meta.quality or 2, units = units, name = Products.label(pid),
                bud = Products.bud(pid), price = math.floor(Selling.unitPrice(pid, s.meta.quality or 2) * units * SC.bulk.rate + 0.5),
            }
        end
    end
    return out
end

local function nearBuyer(src)
    return Guard.near(src, SC.bulk.ped, 4.0)
end

Guard.callback('nzwl:bulk:open', function(src)
    local P = Profile.get(src)
    if not P or not SC.bulk.enabled or not nearBuyer(src) then return false end
    if Profile.level(P) < SC.bulk.level then return false, ('Come back when you\'re level %d'):format(SC.bulk.level) end
    return { bricks = bricks(src), left = (bulkLeft(src)), perDay = SC.bulk.perDay }
end)

Guard.callback('nzwl:bulk:sell', function(src, slot, n)
    local P = Profile.get(src)
    if not P or not SC.bulk.enabled or not nearBuyer(src) or Profile.level(P) < SC.bulk.level then return false end
    if not Guard.rate(src, 'bulk', 1500) then return false end
    if not policeOk() then return false, 'Not today' end
    n = math.floor(tonumber(n) or 0)
    local left, rec = bulkLeft(src)
    if n < 1 then return false end
    if n > left then return false, ('He only takes %d more today'):format(math.max(0, left)) end
    local stack
    for _, b in ipairs(bricks(src)) do if b.slot == slot then stack = b end end
    if not stack or stack.n < n then return false, 'You don\'t have those' end
    local meta
    for _, s in ipairs(Inv.slots(src, PROD.brick)) do if s.slot == slot then meta = s.meta end end
    if not Inv.removeSlot(src, PROD.brick, n, slot, meta) then return false end
    local total = stack.price * n
    if not Inv.payMoney(src, total, 'weedlab-bulk') then
        Inv.add(src, PROD.brick, n, meta)
        return false
    end
    rec.n = rec.n + n
    P.stats.sold = (P.stats.sold or 0) + stack.units * n
    P.stats.earned = (P.stats.earned or 0) + total
    Profile.dirty(src)
    Profile.addXp(src, SC.bulk.xpPerBrick * n, 'Bricks sold')
    Story.progress(src, 'sell')
    Logs.send('Bulk sale', ('%s sold %dx %s brick for %s'):format(P.name or src, n, stack.name, Utils.money(total)), 3066993)
    return true, { total = total, panel = { bricks = bricks(src), left = (bulkLeft(src)), perDay = SC.bulk.perDay } }
end)

-- forget people nobody has talked to for a while (keeps the table small)
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for net, t in pairs(seen) do
            if now - t > SC.corner.remember then seen[net] = nil end
        end
    end
end)
