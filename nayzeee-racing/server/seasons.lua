if not NAYZEEE_LOCK_OK then return end

--[[
    Seasons: ELO resets on a schedule. The top racers of the season get paid through the inbox
    and keep a badge on their profile.
]]

Seasons = { current = nil }

local function load()
    local r = MySQL.single.await('SELECT id, number, UNIX_TIMESTAMP(started) AS started, UNIX_TIMESTAMP(ends) AS ends FROM nayzeee_racing_seasons WHERE ended = 0 ORDER BY id DESC LIMIT 1')
    if not r then
        local n = (MySQL.scalar.await('SELECT MAX(number) FROM nayzeee_racing_seasons') or 0) + 1
        MySQL.insert.await('INSERT INTO nayzeee_racing_seasons (number, ends) VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY))', { n, Config.Seasons.LengthDays })
        r = MySQL.single.await('SELECT id, number, UNIX_TIMESTAMP(started) AS started, UNIX_TIMESTAMP(ends) AS ends FROM nayzeee_racing_seasons WHERE ended = 0 ORDER BY id DESC LIMIT 1')
    end
    Seasons.current = r
end

function Seasons.Public()
    local s = Seasons.current
    if not Config.Seasons.Enabled or not s then return nil end
    return { number = s.number, started = s.started, ends = s.ends }
end

-- Badges earned in past seasons, newest first
function Seasons.Badges(profileId)
    if not Config.Seasons.Enabled then return {} end
    return MySQL.query.await([[SELECT s.number AS season, r.position, r.badge FROM nayzeee_racing_season_results r
        JOIN nayzeee_racing_seasons s ON s.id = r.season_id WHERE r.profile_id = ? AND r.badge IS NOT NULL
        ORDER BY s.number DESC LIMIT 12]], { profileId }) or {}
end

local function tierFor(pos)
    for _, t in ipairs(Config.Seasons.Rewards) do
        if pos >= t.from and pos <= t.to then return t end
    end
end

function Seasons.End()
    local s = Seasons.current
    if not s then return end
    local cfg = Config.Seasons
    local places = 0
    for _, t in ipairs(cfg.Rewards) do places = math.max(places, t.to) end

    local top = MySQL.query.await([[SELECT p.id, p.alias, p.elo FROM nayzeee_racing_profiles p
        WHERE p.identifier <> 'SYSTEM' AND (SELECT COUNT(*) FROM nayzeee_racing_history h
            WHERE h.profile_id = p.id AND h.type = 'ranked' AND h.created >= FROM_UNIXTIME(?)) >= ?
        ORDER BY p.elo DESC LIMIT ?]], { s.started, cfg.MinRankedRaces, math.max(places, 1) }) or {}

    local lines = { L('LOG_SEASON', s.number) }
    for pos, r in ipairs(top) do
        local tier = tierFor(pos)
        MySQL.insert.await('INSERT INTO nayzeee_racing_season_results (season_id, profile_id, position, elo, badge) VALUES (?, ?, ?, ?, ?)',
            { s.id, r.id, pos, r.elo, tier and tier.badge or nil })
        if tier and tier.money and tier.money > 0 then
            Profiles.Message(r.id, MsgType.REWARD, L('MSG_SEASON_REWARD', s.number, pos), { rewardType = Config.Rewards.DefaultCurrency, amount = tier.money })
        end
        if tier and tier.items then
            Profiles.Message(r.id, MsgType.REWARD, L('MSG_SEASON_REWARD', s.number, pos), { rewardType = 'item', items = tier.items })
        end
        lines[#lines + 1] = ('`%d.` %s — %d ELO'):format(pos, r.alias, r.elo)
    end

    -- reset
    local start = Config.Profiles.StartingElo
    if cfg.Reset == 'hard' then
        MySQL.update.await("UPDATE nayzeee_racing_profiles SET elo = ? WHERE identifier <> 'SYSTEM'", { start })
    else
        MySQL.update.await("UPDATE nayzeee_racing_profiles SET elo = GREATEST(0, ROUND(? + (elo - ?) * ?)) WHERE identifier <> 'SYSTEM'",
            { start, start, cfg.SoftFactor })
    end
    if cfg.ResetRankRewards then MySQL.update.await('UPDATE nayzeee_racing_profiles SET elo_reward_min = 0') end
    MySQL.insert.await("INSERT INTO nayzeee_racing_elo_history (profile_id, elo) SELECT id, elo FROM nayzeee_racing_profiles WHERE identifier <> 'SYSTEM'")
    MySQL.update.await('UPDATE nayzeee_racing_seasons SET ended = 1 WHERE id = ?', { s.id })

    -- cached profiles pick up their new ELO
    local ids = {}
    for id in pairs(Profiles.cache) do ids[#ids + 1] = id end
    if #ids > 0 then
        local rows = MySQL.query.await(('SELECT id, elo, elo_reward_min FROM nayzeee_racing_profiles WHERE id IN (%s)'):format(('?,'):rep(#ids):sub(1, -2)), ids) or {}
        for _, r in ipairs(rows) do
            local p = Profiles.cache[r.id]
            if p then
                p.elo, p.eloRewardMin = r.elo, r.elo_reward_min
                if p.source then Push(p.source, 'profile', Profiles.Dto(p)) end
            end
        end
    end
    Profiles.stats = {}
    Profiles.InvalidateBoard()

    load()
    NotifyGroup('profiles', L('N_SEASON_ENDED', s.number, Seasons.current.number), 'inform')
    DiscordLog('Seasons', L('LOG_SEASON_ENDED'), lines)
    Log('info', 'Season %d ended, season %d started', s.number, Seasons.current.number)
end

local started = false
local function init()
    if started or not Config.Seasons.Enabled then return end
    started = true
    load()
    CreateThread(function()
        while true do
            if Seasons.current and os.time() >= (Seasons.current.ends or math.huge) then
                local ok, err = pcall(Seasons.End)
                if not ok then Log('error', 'Season end failed: %s', tostring(err)) end
            end
            Wait(5 * 60 * 1000)
        end
    end)
end
AddEventHandler('nzr:dbReady', init)
if DB.ready then CreateThread(init) end

-- Console / admin: racingseason end
RegisterCommand('racingseason', function(src, args)
    if src > 0 and not Bridge.IsAdmin(src) then return end
    if args[1] == 'end' and Config.Seasons.Enabled and Seasons.current then
        CreateThread(Seasons.End)
    else
        local s = Seasons.current
        print(s and ('Season %d, ends %s'):format(s.number, os.date('!%Y-%m-%d %H:%M UTC', s.ends)) or 'Seasons disabled')
    end
end, true)
