--[[ Loot rolls + completion payouts. Every reward in the pack is paid from here. ]]

Rewards = {}

local Fence = lib.load('config.fence')
local fenceValue = {}
for i = 1, #Fence.items do fenceValue[Fence.items[i].name] = Fence.items[i].price end

local function featuredMult(inst, field)
    if GlobalState['nzh:featured'] == inst.heistId then return Config.Featured[field] or 1.0 end
    return 1.0
end

--- Rolls a loot table for `src`. Returns a list of { label, amount } that was actually given.
function Rewards.roll(inst, src, key, rolls)
    local def = Heists.defs[inst.heistId]
    local tbl = def.loot[key]
    if not tbl then
        print(('^1[nzh] heist %s has no loot table "%s"^7'):format(inst.heistId, tostring(key)))
        return {}
    end
    local level = Profile.level(src)
    local mult = Utils.perks(level).loot * featuredMult(inst, 'money')
    local given = {}
    for _ = 1, rolls or 1 do
        for i = 1, #tbl do
            local row = tbl[i]
            if math.random() <= (row.chance or 1.0) then
                local amount = math.random(row.min or 1, row.max or row.min or 1)
                if row.item == 'money' then
                    amount = math.floor(amount * mult)
                    if Inv.payMoney(src, amount, nil, 'heist-loot') then
                        inst.earned[src] = (inst.earned[src] or 0) + amount
                        given[#given + 1] = { label = '$', amount = amount, money = true }
                    end
                else
                    if amount > 1 then amount = math.floor(amount * mult + 0.5) end
                    if Inv.canCarry(src, row.item, amount) and Inv.add(src, row.item, amount, row.metadata) then
                        inst.earned[src] = (inst.earned[src] or 0) + (fenceValue[row.item] or 0) * amount
                        given[#given + 1] = { label = Inv.label(row.item), amount = amount }
                    else
                        FW.notify(src, locale('inventory_full'), 'error')
                    end
                end
            end
        end
    end
    inst.lootCount = (inst.lootCount or 0) + 1
    return given
end

--- Completion bonus: XP to every member, money split per Config.Crew.payoutSplit
function Rewards.completion(inst, members)
    local def = Heists.defs[inst.heistId]
    local results = {}
    local n = #members
    if n == 0 then return results end

    local money = def.rewards.money
    local pot = 0
    if type(money) == 'table' then pot = math.random(money[1] or money.min, money[2] or money.max)
    elseif type(money) == 'number' then pot = money end
    pot = math.floor(pot * (1 + Config.Crew.crewBonus * (n - 1)) * featuredMult(inst, 'money'))

    local xp = math.floor((def.rewards.xp or 0) * featuredMult(inst, 'xp'))

    for i = 1, n do
        local src = members[i]
        local share = 0
        if pot > 0 then
            if Config.Crew.payoutSplit == 'leader' then
                share = (src == inst.leader) and pot or 0
            else
                share = math.floor(pot / n)
            end
        end
        if share > 0 then
            Inv.payMoney(src, share, nil, 'heist-completion')
            inst.earned[src] = (inst.earned[src] or 0) + share
        end
        local leveled, level = Profile.addXp(src, xp)
        results[src] = { xp = xp, money = share, leveled = leveled, level = level, earned = inst.earned[src] or 0 }
    end
    return results
end
