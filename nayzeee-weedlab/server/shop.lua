--[[ Hardware stores: level-gated catalogue, paid from cash or bank ]]

Shop = {}

local byItem = {}
for _, row in ipairs(Config.Store.items) do byItem[row.item] = row end

local function nearStore(src)
    for i, s in ipairs(Config.Stores) do
        if Guard.near(src, s.ped, 4.0) then return i end
    end
end

Guard.callback('nzwl:shop:open', function(src)
    local P = Profile.get(src)
    if not P or not nearStore(src) then return false end
    local lvl = Profile.level(P)
    local items = {}
    for _, row in ipairs(Config.Store.items) do
        local need = Utils.itemLevel(row.item)
        local it = Config.Items[row.item]
        items[#items + 1] = {
            item = row.item, label = it[1], desc = it[3], price = row.price, cat = row.cat,
            level = need, locked = lvl < need,
        }
    end
    local money = {}
    for _, acc in ipairs(Config.Money.shopAccounts) do money[acc] = FW.getMoney(src, acc) end
    return { items = items, level = lvl, money = money, accounts = Config.Money.shopAccounts, max = Config.Store.maxQuantity }
end)

--- basket = { { item, n } }
Guard.callback('nzwl:shop:buy', function(src, basket, account)
    local P = Profile.get(src)
    if not P or type(basket) ~= 'table' or #basket == 0 or #basket > 40 then return false end
    if not nearStore(src) or not Guard.rate(src, 'shop', 1500) then return false end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    local lvl, total, list = Profile.level(P), 0, {}
    for _, b in ipairs(basket) do
        local row = type(b) == 'table' and byItem[b.item]
        local n = row and math.floor(tonumber(b.n) or 0) or 0
        if not row or n < 1 or n > Config.Store.maxQuantity then return false end
        if lvl < Utils.itemLevel(row.item) then return false, ('%s unlocks at level %d'):format(Utils.itemLabel(row.item), Utils.itemLevel(row.item)) end
        if not Inv.canCarry(src, row.item, n) then return false, ('You can\'t carry %dx %s'):format(n, Utils.itemLabel(row.item)) end
        total = total + row.price * n
        list[#list + 1] = { item = row.item, n = n }
    end
    if not FW.removeMoney(src, account, total, 'weedlab-store') then return false, 'Not enough money' end
    for _, b in ipairs(list) do Inv.add(src, b.item, b.n) end
    P.stats.spent = (P.stats.spent or 0) + total
    Profile.dirty(src)
    Story.progress(src, 'buy')
    return true, total
end)
