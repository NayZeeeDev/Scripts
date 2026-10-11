if not NAYZEEE_LOCK_OK then return end

--[[
    Daily and weekly challenges. Everyone gets the same picks for a period (seeded by the day / week
    number), progress is stored per racer and the reward is sent to the inbox when a goal is reached.
]]

Challenges = {}
local picked = {}   -- [periodKey] = { defs }

-- Deterministic shuffle so every server restart picks the same challenges for the period
local function pick(pool, count, seed)
    local list = {}
    for i, c in ipairs(pool) do list[i] = c end
    local s = (seed * 2654435761 + 97) % 2147483647
    for i = #list, 2, -1 do
        s = (s * 48271) % 2147483647
        local j = s % i + 1
        list[i], list[j] = list[j], list[i]
    end
    local out = {}
    for i = 1, math.min(count, #list) do out[i] = list[i] end
    return out
end

-- Active challenges: { def, period = 'd123' | 'w45', kind = 'daily' | 'weekly', ends = unix }
function Challenges.Active()
    local cfg = Config.Challenges
    if not cfg.Enabled then return {} end
    local now = os.time()
    local day, week = NZR.DayIndex(now), NZR.WeekIndex(now)
    local out = {}
    for _, g in ipairs({ { 'daily', cfg.Daily, 'd' .. day, day, (day + 1) * 86400 }, { 'weekly', cfg.Weekly, 'w' .. week, week + 100000, ((week + 1) * 7 - 3) * 86400 } }) do
        local kind, set, key, seed, ends = g[1], g[2], g[3], g[4], g[5]
        if set and set.Pool and #set.Pool > 0 then
            picked[key] = picked[key] or pick(set.Pool, set.Count or 3, seed)
            for _, def in ipairs(picked[key]) do out[#out + 1] = { def = def, period = key, kind = kind, ends = ends } end
        end
    end
    return out
end

local function label(def) return ((def.label or def.id):gsub('%%d', tostring(def.goal))) end

local function rewardMeta(r)
    if not r then return nil end
    if r.type == 'item' then return { rewardType = 'item', items = { { item = r.item, amount = r.amount or 1, metadata = r.metadata } } } end
    return { rewardType = r.type or 'money', amount = r.amount or 0 }
end

-- How much one race adds to a challenge for one racer
local function amountFor(def, lobby, part, racers)
    if lobby.practice then
        if not def.practice then return 0 end
    elseif def.practice then
        return 0
    elseif racers < (def.minRacers or Config.Challenges.MinRacers or 1) then
        return 0
    end
    if def.mode and def.mode ~= lobby.mode then return 0 end
    if def.type and def.type ~= lobby.type then return 0 end
    if def.track and def.track ~= (lobby.circuit and 'circuit' or 'sprint') then return 0 end
    local finished = part.status == PStatus.FINISHED
    local classified = finished or part.dqReason == 'eliminated'
    local e = def.event
    if e == 'race' then return 1 end
    if e == 'finish' then return finished and 1 or 0 end
    if e == 'win' then return (finished and part.position == 1) and 1 or 0 end
    if e == 'podium' then return (classified and part.position <= 3) and 1 or 0 end
    if e == 'distance' then return part.distance or 0 end
    return 0
end

-- Called once per finished race (in its own thread)
function Challenges.Record(lobby, ordered)
    if not Config.Challenges.Enabled then return end
    local active = Challenges.Active()
    if #active == 0 then return end
    local racers = 0
    for _, part in ipairs(ordered) do if part.started then racers = racers + 1 end end
    for _, part in ipairs(ordered) do
        if part.started then
            for _, a in ipairs(active) do
                local add = amountFor(a.def, lobby, part, racers)
                if add > 0 then
                    local goal = a.def.goal or 1
                    MySQL.update.await([[INSERT INTO nayzeee_racing_challenges (profile_id, period, challenge_id, progress) VALUES (?, ?, ?, LEAST(?, ?))
                        ON DUPLICATE KEY UPDATE progress = LEAST(?, progress + ?)]], { part.id, a.period, a.def.id, goal, add, goal, add })
                    -- only one call can flip done 0 -> 1, so the reward is sent once
                    local flipped = MySQL.update.await('UPDATE nayzeee_racing_challenges SET done = 1 WHERE profile_id = ? AND period = ? AND challenge_id = ? AND done = 0 AND progress >= ?',
                        { part.id, a.period, a.def.id, goal })
                    if flipped == 1 then
                        local text = label(a.def)
                        local meta = rewardMeta(a.def.reward)
                        if meta then Profiles.Message(part.id, MsgType.REWARD, L('MSG_CHALLENGE_DONE', text), meta) end
                        local src = Core.Online[part.id]
                        if src then Notify(src, L('N_CHALLENGE_DONE', text), 'success') end
                    end
                end
            end
        end
    end
end

Handle('challenges', function(_, p)
    local active = Challenges.Active()
    if #active == 0 then return {} end
    local keys = {}
    for _, a in ipairs(active) do keys[a.period] = true end
    local list = {}
    for k in pairs(keys) do list[#list + 1] = k end
    local rows = MySQL.query.await(('SELECT period, challenge_id, progress, done FROM nayzeee_racing_challenges WHERE profile_id = ? AND period IN (%s)')
        :format(('?,'):rep(#list):sub(1, -2)), { p.id, table.unpack(list) }) or {}
    local prog = {}
    for _, r in ipairs(rows) do prog[r.period .. ':' .. r.challenge_id] = r end
    local out = {}
    for _, a in ipairs(active) do
        local r = prog[a.period .. ':' .. a.def.id]
        out[#out + 1] = {
            id = a.def.id, kind = a.kind, label = label(a.def), goal = a.def.goal or 1, event = a.def.event,
            progress = r and r.progress or 0, done = r ~= nil and (r.done == true or r.done == 1), ends = a.ends,
            reward = a.def.reward,
        }
    end
    return out
end)
