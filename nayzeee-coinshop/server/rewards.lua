if not NAYZEEE_LOCK_OK then return end

--[[
    Rewards: spend ranks (bonus coins on Tebex orders) and the daily login streak.
]]

Rewards = {}

local ranks = {}
for _, r in ipairs(Config.Ranks.List or {}) do ranks[#ranks + 1] = r end
table.sort(ranks, function(a, b) return (a.spent or 0) < (b.spent or 0) end)

function Rewards.List()
    local out = {}
    for i, r in ipairs(ranks) do
        out[i] = { name = r.name, spent = r.spent or 0, bonus = r.bonus or 0, color = r.color or '#08afa2', icon = r.icon or 'fa-medal' }
    end
    return out
end

function Rewards.Spent(id)
    return tonumber(MySQL.scalar.await('SELECT spent FROM nayzeee_coinshop_wallets WHERE identifier = ?', { id })) or 0
end

-- Rank for a total spent: name, bonus %, progress towards the next rank
function Rewards.Rank(spent)
    if not Config.Ranks.Enabled or #ranks == 0 then return nil end
    spent = math.max(0, tonumber(spent) or 0)
    local idx = 1
    for i, r in ipairs(ranks) do if spent >= (r.spent or 0) then idx = i end end
    local r, nx = ranks[idx], ranks[idx + 1]
    local min = r.spent or 0
    return {
        index = idx, count = #ranks, name = r.name, color = r.color or '#08afa2', icon = r.icon or 'fa-medal', bonus = r.bonus or 0, min = min, spent = spent,
        progress = nx and math.max(0, math.min(1, (spent - min) / math.max(1, nx.spent - min))) or 1,
        next = nx and { name = nx.name, min = nx.spent, bonus = nx.bonus or 0, color = nx.color, icon = nx.icon, need = nx.spent - spent } or nil,
    }
end

-- ── daily streak ────────────────────────────────────────────────────────
local function rewardsList() return Config.Daily.Rewards or {} end

function Rewards.Daily(id)
    local list = rewardsList()
    local n = #list
    if not Config.Daily.Enabled or n == 0 then return nil end
    local r = MySQL.single.await([[SELECT streak, claims, (last_claim = CURDATE()) AS today, DATEDIFF(CURDATE(), last_claim) AS gap,
        TIMESTAMPDIFF(SECOND, NOW(), CURDATE() + INTERVAL 1 DAY) AS reset FROM nayzeee_coinshop_daily WHERE identifier = ?]], { id })
    local reset = r and r.reset or MySQL.scalar.await('SELECT TIMESTAMPDIFF(SECOND, NOW(), CURDATE() + INTERVAL 1 DAY)')
    local streak = r and tonumber(r.streak) or 0
    local claimed = r and (r.today == 1 or r.today == true) or false
    local running = streak
    if not claimed and Config.Daily.ResetOnMiss and (not r or tonumber(r.gap) ~= 1) then running = 0 end
    local day = claimed and ((streak - 1) % n) + 1 or (running % n) + 1
    return {
        rewards = list, day = day, claimed = claimed, ready = not claimed, streak = claimed and streak or running,
        lost = not claimed and running == 0 and streak > 0, resetIn = tonumber(reset) or 0, claims = r and tonumber(r.claims) or 0,
        amount = list[day],
    }
end

function Rewards.DailyReady(id)
    local d = Rewards.Daily(id)
    return d and d.ready and d.amount or false
end

Handle('rewards', function(_, id)
    local spent = Rewards.Spent(id)
    return {
        rank = Rewards.Rank(spent), ranks = Config.Ranks.Enabled and Rewards.List() or nil, daily = Rewards.Daily(id),
        memberships = Members.ForPlayer(id), spent = spent,
        playtime = Config.Playtime.Enabled and { minutes = Config.Playtime.Minutes, coins = Config.Playtime.Coins, cap = Config.Playtime.DailyCap } or nil,
    }
end)

Handle('daily:claim', function(_, id)
    local list = rewardsList()
    if not Config.Daily.Enabled or #list == 0 then return nil, 'ERR_DISABLED' end
    MySQL.insert.await('INSERT IGNORE INTO nayzeee_coinshop_daily (identifier) VALUES (?)', { id })
    local streakSql = Config.Daily.ResetOnMiss and 'IF(last_claim = CURDATE() - INTERVAL 1 DAY, streak + 1, 1)' or 'streak + 1'
    -- one claim per server day, even with two requests at once
    local n = MySQL.update.await(([[UPDATE nayzeee_coinshop_daily SET streak = %s, last_claim = CURDATE(), claims = claims + 1
        WHERE identifier = ? AND (last_claim IS NULL OR last_claim < CURDATE())]]):format(streakSql), { id })
    if n ~= 1 then return nil, 'ERR_DAILY_CLAIMED' end
    local streak = tonumber(MySQL.scalar.await('SELECT streak FROM nayzeee_coinshop_daily WHERE identifier = ?', { id })) or 1
    local day = ((streak - 1) % #list) + 1
    local amount = math.max(0, math.floor(tonumber(list[day]) or 0))
    local balance = Wallet.Add(id, amount, 'daily', T('DAILY_DAY', day))
    return { coins = balance, amount = amount, day = day, streak = streak, daily = Rewards.Daily(id) }
end)

-- Let players know their reward is waiting once they have loaded in
if Config.Daily.Enabled and Config.Daily.NotifyOnJoin then
    Bridge.OnLoaded(function(src)
        SetTimeout(15000, function()
            if not DB.ready or not GetPlayerName(src) then return end
            local id = Identify(src)
            local amount = id and Rewards.DailyReady(id)
            if amount then Notify(src, T('N_DAILY_READY', amount, Config.General.CoinName, Config.General.Command or 'coinshop'), 'inform') end
        end)
    end)
end
