--[[ Fence: sell heist loot to employers flagged `fence = true` ]]

local Fence = lib.load('config.fence')
local byName = {}
for i = 1, #Fence.items do byName[Fence.items[i].name] = Fence.items[i] end

--- deterministic daily price (same for everyone, changes every UTC day)
local function price(item)
    local day = math.floor(os.time() / 86400)
    local seed = 0
    for i = 1, #item.name do seed = seed + item.name:byte(i) * i end
    local wave = math.sin(day * 1.37 + seed) -- -1..1
    return math.floor(item.price * (1 + wave * Fence.spread))
end

local function nearFence(src)
    for i = 1, #Config.Employers do
        local e = Config.Employers[i]
        if e.fence and Guard.near(src, e.coords, 6.0) then return true end
    end
    return false
end

Guard.callback('nzh:fence:data', function(src)
    if not Fence.enabled then return nil end
    local list = {}
    for i = 1, #Fence.items do
        local it = Fence.items[i]
        list[i] = { name = it.name, label = it.label, price = price(it), owned = Inv.count(src, it.name) }
    end
    return { items = list, near = nearFence(src) }
end)

Guard.callback('nzh:fence:sell', function(src, name, amount)
    if not Fence.enabled then return false end
    if not Guard.rate(src, 'fence', 800) then return false, locale('slow_down') end
    local item = byName[name]
    amount = math.floor(tonumber(amount) or 0)
    if not item or amount < 1 or amount > 500 then return false end
    if not nearFence(src) then return false, locale('fence_too_far') end
    if not Inv.remove(src, name, amount) then return false, locale('missing_item', item.label) end
    local total = price(item) * amount
    Inv.payMoney(src, total, Fence.account, 'heist-fence')
    Logs.send('Fence sale', ('%s sold %dx %s for $%s'):format(GetPlayerName(src), amount, item.label, Utils.money(total)))
    return true, locale('fence_sold', amount, item.label, Utils.money(total))
end)
