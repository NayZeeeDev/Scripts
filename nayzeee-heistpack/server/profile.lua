--[[ Player heist profiles: nickname, avatar, xp/level, stats. Cached per session, saved on change. ]]

Profile = {}

local cache = {}      -- src -> profile
local dirty = {}      -- src -> true
local AVATARS = 12

local function defaultNick(src)
    return ('Ghost%04d'):format(math.random(0, 9999)) .. (src % 10)
end

function Profile.get(src)
    local p = cache[src]
    if p then return p end
    local identifier = FW.identifier(src)
    if not identifier then return nil end
    local row = DB.getProfile(identifier)
    if not row then
        DB.createProfile(identifier, defaultNick(src))
        row = DB.getProfile(identifier)
    end
    if not row then return nil end
    row.stats = row.stats and json.decode(row.stats) or {}
    row.identifier = identifier
    cache[src] = row
    return row
end

function Profile.cached(src)
    return cache[src]
end

local function markDirty(src)
    if dirty[src] then return end
    dirty[src] = true
    SetTimeout(5000, function()
        dirty[src] = nil
        if cache[src] then DB.saveProfile(cache[src]) end
    end)
end

function Profile.level(src)
    local p = Profile.get(src)
    return p and Utils.levelFromXp(p.xp) or 1
end

function Profile.public(src)
    local p = Profile.get(src)
    if not p then return nil end
    local level, into, need = Utils.levelFromXp(p.xp)
    local perks = Utils.perks(level)
    return {
        source = src,
        nickname = p.nickname,
        avatar = p.avatar,
        xp = p.xp,
        level = level,
        levelXp = into,
        levelNeed = need,
        completed = p.completed,
        failed = p.failed,
        earned = p.earned,
        stats = p.stats,
        perks = { loot = perks.loot, speed = perks.speed },
    }
end

--- @return boolean leveledUp, number newLevel
function Profile.addXp(src, amount)
    local p = Profile.get(src)
    if not p or amount <= 0 then return false, 1 end
    local before = Utils.levelFromXp(p.xp)
    p.xp = p.xp + math.floor(amount)
    markDirty(src)
    local after = Utils.levelFromXp(p.xp)
    return after > before, after
end

function Profile.setXp(src, xp)
    local p = Profile.get(src)
    if not p then return end
    p.xp = math.max(0, math.floor(xp))
    markDirty(src)
end

function Profile.record(src, heistId, success, earned, duration)
    local p = Profile.get(src)
    if not p then return end
    if success then p.completed = p.completed + 1 else p.failed = p.failed + 1 end
    p.earned = p.earned + math.floor(earned or 0)
    local s = p.stats[heistId] or { done = 0, best = 0 }
    if success then
        s.done = s.done + 1
        if duration and (s.best == 0 or duration < s.best) then s.best = duration end
    end
    p.stats[heistId] = s
    markDirty(src)
end

function Profile.addEarned(src, amount)
    local p = Profile.get(src)
    if not p then return end
    p.earned = p.earned + math.floor(amount)
    markDirty(src)
end

Guard.callback('nzh:profile:nickname', function(src, nickname)
    if not Guard.rate(src, 'nick', 3000) then return false, locale('slow_down') end
    if type(nickname) ~= 'string' then return false end
    nickname = nickname:gsub('^%s+', ''):gsub('%s+$', '')
    if #nickname < 3 or #nickname > 20 or not nickname:match('^[%w_%-%. ]+$') then
        return false, locale('nickname_invalid')
    end
    local p = Profile.get(src)
    if not p then return false end
    if DB.nicknameTaken(nickname, p.identifier) then return false, locale('nickname_taken') end
    p.nickname = nickname
    markDirty(src)
    Crew.refreshFor(src)
    return true, Profile.public(src)
end)

Guard.callback('nzh:profile:avatar', function(src, avatar)
    avatar = tonumber(avatar)
    if not avatar or avatar < 1 or avatar > AVATARS then return false end
    local p = Profile.get(src)
    if not p then return false end
    p.avatar = math.floor(avatar)
    markDirty(src)
    Crew.refreshFor(src)
    return true, Profile.public(src)
end)

local board, boardAt = {}, 0
Guard.callback('nzh:profile:leaderboard', function()
    if os.time() - boardAt > 60 then
        board = DB.leaderboard(15)
        for i = 1, #board do
            board[i].level = Utils.levelFromXp(board[i].xp)
        end
        boardAt = os.time()
    end
    return board
end)

Guard.callback('nzh:profile:history', function(src)
    local p = Profile.get(src)
    if not p then return {} end
    local rows = DB.history(p.identifier, 15)
    for i = 1, #rows do
        local def = Heists.defs[rows[i].heist]
        rows[i].label = def and def.label or rows[i].heist
    end
    return rows
end)

AddEventHandler('playerDropped', function()
    local src = source
    if cache[src] then DB.saveProfile(cache[src]) end
    cache[src] = nil
    dirty[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, p in pairs(cache) do DB.saveProfile(p) end
end)
