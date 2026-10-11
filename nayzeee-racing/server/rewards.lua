if not NAYZEEE_LOCK_OK then return end

--[[
    Rewards: wager pots, ranked payouts and loot, ELO + rank rewards, XP, crew race scoring
    and claiming rewards from the inbox.
]]

Rewards = {}

-- Pot split between the top finishers, weighted towards 1st (3 winners = 50% / 33% / 17%)
function Rewards.Wagers(lobby, finished)
    if not lobby.wager or lobby.wager <= 0 or lobby.paid <= 0 then return end
    local pot = lobby.wager * lobby.paid
    local winners = math.min(#finished, Config.Rewards.Winners)
    if winners == 0 then
        -- nobody finished: everyone who paid gets their wager back
        lobby:Each(function(part) if part.paid then lobby:Refund(part) end end)
        return
    end
    local weight = winners * (winners + 1) / 2
    local paidOut = 0
    for rank = 1, winners do
        local part = finished[rank]
        local amount = rank == winners and (pot - paidOut) or math.floor(pot * (winners - rank + 1) / weight)
        paidOut = paidOut + amount
        part.payout = amount
        Profiles.Message(part.id, MsgType.REWARD, L('MSG_WAGER_WON', lobby.name, rank), { rewardType = lobby.currency, amount = amount })
        DiscordLog('Wagers', L('LOG_WAGER_PAID'), { ('%s · %s'):format(part.profile.alias, lobby.name), ('%d %s'):format(amount, lobby.currency) })
    end
end

function Rewards.Ranked(lobby, finished)
    for _, part in ipairs(finished) do
        local src = Core.Online[part.id]
        local money = Config.Rewards.RacePayout and Config.Rewards.RacePayout(src, part.winnerStatus) or 0
        if money and money > 0 then
            Profiles.Message(part.id, MsgType.REWARD, L('MSG_RACE_PAYOUT', lobby.name), { rewardType = Config.Rewards.DefaultCurrency, amount = money })
        end
        local items = Config.Rewards.Loottable and Config.Rewards.Loottable(src, part.winnerStatus)
        if items and #items > 0 then
            Profiles.Message(part.id, MsgType.REWARD, L('MSG_RACE_LOOT', lobby.name), { rewardType = 'item', items = items })
        end
    end
end

function Rewards.Xp(lobby, finished)
    if not Config.Rewards.Xp or #lobby.order < 2 then return end
    for _, part in ipairs(finished) do
        local amount = Config.Rewards.Xp[part.winnerStatus]
        local src = Core.Online[part.id]
        if amount and src then pcall(Bridge.GiveXp, src, amount) end
    end
end

local function rankRewards(p, before)
    for _, rank in ipairs(Config.ELO.Ranks) do
        if rank.rewards and before < rank.min and p.elo >= rank.min and p.eloRewardMin < rank.min then
            for _, r in ipairs(rank.rewards) do
                local meta = r.type == 'item' and { rewardType = 'item', items = { { item = r.item, amount = r.amount or 1, metadata = r.metadata } } }
                    or { rewardType = r.type, amount = r.amount }
                Profiles.Message(p.id, MsgType.REWARD, L('MSG_RANK_REACHED', rank.name), meta)
            end
            p.eloRewardMin = rank.min
            MySQL.update('UPDATE nayzeee_racing_profiles SET elo_reward_min = ? WHERE id = ?', { rank.min, p.id })
        end
    end
end

-- Multiplayer ELO: each racer is scored against every other racer
function Rewards.Elo(lobby, ordered)
    local n = #ordered
    if n < 2 then return end
    local K = Config.ELO.K or 32
    local deltas = {}
    for i, a in ipairs(ordered) do
        local expected = 0
        for j, b in ipairs(ordered) do
            if i ~= j then expected = expected + 1 / (1 + 10 ^ ((b.profile.elo - a.profile.elo) / 400)) end
        end
        expected = expected / (n - 1)
        local actual = (n - a.position) / (n - 1)
        local delta = math.floor(K * (actual - expected) + 0.5)
        -- a real DNF never gains ELO (being eliminated is a placing, not a DNF)
        if a.status == PStatus.DISQUALIFIED and a.dqReason ~= 'eliminated' and delta >= 0 then delta = -1 end
        deltas[i] = delta
    end
    for i, part in ipairs(ordered) do
        local before = part.profile.elo
        part.eloDelta = deltas[i]
        if deltas[i] ~= 0 then Profiles.AddElo(part.profile, deltas[i]) end
        if part.profile.elo > before then rankRewards(part.profile, before) end
    end
end

-- Crew races: points per finisher (last place = 1 point), most points wins
function Rewards.CrewScore(lobby, ordered)
    local crews = lobby:Crews()
    if #crews ~= 2 then return nil end
    local finishers = 0
    for _, part in ipairs(ordered) do if part.status == PStatus.FINISHED then finishers = finishers + 1 end end
    local score = { [crews[1]] = 0, [crews[2]] = 0 }
    for _, part in ipairs(ordered) do
        if part.status == PStatus.FINISHED and score[part.profile.crewId] then
            score[part.profile.crewId] = score[part.profile.crewId] + (finishers - part.position + 1)
        end
    end
    local a, b = Crews.Brief(crews[1]), Crews.Brief(crews[2])
    local sa, sb = score[crews[1]], score[crews[2]]
    local winner = sa > sb and a or (sb > sa and b or nil)
    if winner and a and b then
        local loser = winner == a and b or a
        local ws, ls = math.max(sa, sb), math.min(sa, sb)
        Crews.Activity(winner.id, 'WON_RACE', L('ACT_WON_RACE', loser.name, ws, ls))
        Crews.Activity(loser.id, 'LOST_RACE', L('ACT_LOST_RACE', winner.name, ls, ws))
    elseif a and b then
        Crews.Activity(a.id, 'DRAW_RACE', L('ACT_DRAW_RACE', b.name, sa))
        Crews.Activity(b.id, 'DRAW_RACE', L('ACT_DRAW_RACE', a.name, sb))
    end
    return { list = { { crew = a, score = sa }, { crew = b, score = sb } }, winner = winner and winner.id or nil }
end

-- Pink slips: the winner takes the title of every other racer's car
function Rewards.PinkSlips(lobby, ordered)
    if not lobby.pinkSlip then return end
    local winner = ordered[1]
    if not winner or winner.status ~= PStatus.FINISHED then return end
    local wSrc = Core.Online[winner.id]
    local won = {}
    for i = 2, #ordered do
        local part = ordered[i]
        local lost = part.started and (part.status == PStatus.FINISHED or Config.PinkSlips.DnfLoses)
        if lost and part.vehicle then
            local lSrc = Core.Online[part.id]
            local ok = Bridge.TransferVehicle(part.profile.identifier, winner.profile.identifier, part.vehicle.plate)
            if ok then
                won[#won + 1] = part.vehicle.label
                part.pinkLost = part.vehicle.label
                pcall(Bridge.OnPinkSlip, wSrc, lSrc, part.vehicle.plate, part.netId)
                Profiles.Message(part.id, MsgType.STANDARD, L('MSG_PINK_LOST', part.vehicle.label, part.vehicle.plate, winner.profile.alias))
                Profiles.Message(winner.id, MsgType.STANDARD, L('MSG_PINK_WON', part.vehicle.label, part.vehicle.plate, part.profile.alias))
                if lSrc then Notify(lSrc, L('N_PINK_LOST', part.vehicle.label), 'error') end
                if wSrc then Notify(wSrc, L('N_PINK_WON', part.vehicle.label), 'success') end
                DiscordLog('PinkSlips', L('LOG_PINK'), { ('%s → %s'):format(part.profile.alias, winner.profile.alias), ('%s [%s] · %s'):format(part.vehicle.label, part.vehicle.plate, lobby.name) })
            else
                Log('warn', 'Pink slip transfer failed: %s (%s) -> %s', part.vehicle.plate, part.profile.alias, winner.profile.alias)
            end
        end
    end
    if #won > 0 then winner.pinkWon = table.concat(won, ', ') end
end

-- Bets: parimutuel pool on the winner, minus the house cut
function Rewards.Bets(lobby, ordered)
    if #lobby.bets == 0 then return end
    local cfg = Config.Betting
    local winner = ordered[1]
    local wid = winner and winner.status == PStatus.FINISHED and winner.id or nil
    local pool, stake = 0, 0
    for _, b in ipairs(lobby.bets) do
        pool = pool + b.amount
        if b.racer == wid then stake = stake + b.amount end
    end
    if stake == 0 then
        if cfg.RefundIfNoWinner then lobby:RefundBets(nil, 'MSG_BET_REFUND_NOWIN') else lobby.bets = {} end
        return
    end
    local payout = math.floor(pool * (1 - (cfg.HouseCut or 0)))
    for _, b in ipairs(lobby.bets) do
        if b.racer == wid then
            local amount = math.floor(payout * b.amount / stake)
            Profiles.Message(b.pid, MsgType.REWARD, L('MSG_BET_WON', winner.profile.alias, lobby.name), { rewardType = cfg.Currency, amount = amount })
            DiscordLog('Bets', L('LOG_BET_PAID'), { ('%s · %s'):format(b.alias, lobby.name), ('%d %s'):format(amount, cfg.Currency) })
        else
            Profiles.Message(b.pid, MsgType.STANDARD, L('MSG_BET_LOST', lobby.name))
        end
    end
    lobby.bets = {}
end

-- ── claiming ────────────────────────────────────────────────────────────
Handle('inbox:claim', function(src, p, d)
    local id = tonumber(d.id) or 0
    local msg = MySQL.single.await('SELECT id, metadata FROM nayzeee_racing_messages WHERE id = ? AND profile_id = ? AND type = ?', { id, p.id, MsgType.REWARD })
    if not msg then return nil, 'MSG_NOT_FOUND' end
    -- delete first so a double click can never pay twice
    local removed = MySQL.update.await('DELETE FROM nayzeee_racing_messages WHERE id = ? AND profile_id = ?', { id, p.id })
    if removed ~= 1 then return nil, 'MSG_NOT_FOUND' end
    local meta = DB.Decode(msg.metadata, {})
    local ok = false
    if meta.rewardType == 'item' then
        local failed = {}
        for _, it in ipairs(meta.items or {}) do
            if not Bridge.GiveItem(src, it.item, it.amount or 1, it.metadata) then failed[#failed + 1] = it end
        end
        ok = #failed == 0
        if not ok then meta.items = failed msg.metadata = json.encode(meta) end
    elseif meta.rewardType == 'money' or meta.rewardType == 'crypto' then
        ok = Bridge.AddMoney(src, math.floor(tonumber(meta.amount) or 0), meta.rewardType, 'race reward')
    end
    if not ok then
        MySQL.insert.await('INSERT INTO nayzeee_racing_messages (id, profile_id, type, message, metadata) VALUES (?, ?, ?, ?, ?)',
            { id, p.id, MsgType.REWARD, L('MSG_REWARD_RETRY'), msg.metadata })
        return nil, 'MSG_CLAIM_FAILED'
    end
    return true
end)
