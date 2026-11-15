-- Boards: solo (best solo run), crewruns (best crew run per driver), crews (crew points)
Leaderboard = { cache = {} }

function Leaderboard.Dirty() Leaderboard.cache = {} end

local function crewChip(crewId)
    local c = crewId and DB.crews[crewId]
    if not c then return nil end
    return { tag = c.tag, name = c.name, color = c.color }
end

local function runRow(p, run)
    return {
        name = p.name, crew = crewChip(p.crewId),
        points = run.points, combo = run.maxCombo, car = run.car, avgSpeed = run.avgSpeed,
        distance = run.distance, time = run.time, map = run.map, server = run.server,
        density = run.density, transmission = run.transmission, avgProximity = run.avgProximity,
        carsPassed = run.carsPassed, camera = run.camera, crashes = run.crashes, date = run.date,
    }
end

local function build(board)
    local c = Leaderboard.cache[board]
    if c and os.time() - c.at < Config.Leaderboard.Cache then return c end

    local list, keys = {}, {}
    if board == 'crews' then
        for id, crew in pairs(DB.crews) do
            local members, bestName, bestPts = 0, nil, 0
            for ident in pairs(crew.members) do
                members = members + 1
                local p = DB.players[ident]
                local pts = p and p.bestCrew and p.bestCrew.points or 0
                if pts > bestPts then bestName, bestPts = p.name, pts end
            end
            if (crew.points or 0) > 0 then
                list[#list + 1] = {
                    key = id, name = crew.name, tag = crew.tag, color = crew.color,
                    points = crew.points or 0, members = members, bestName = bestName, bestPoints = bestPts,
                }
            end
        end
    else
        local field = board == 'crewruns' and 'bestCrew' or 'bestSolo'
        for ident, p in pairs(DB.players) do
            local run = p[field]
            if run then
                local row = runRow(p, run)
                row.key = ident
                list[#list + 1] = row
            end
        end
    end
    table.sort(list, function(a, b) return a.points > b.points end)
    for i, row in ipairs(list) do
        row.pos = i
        keys[row.key] = i
    end
    c = { at = os.time(), list = list, keys = keys }
    Leaderboard.cache[board] = c
    return c
end

function Leaderboard.Position(board, key)
    local c = build(board)
    return c.keys[key] or 0, #c.list
end

-- strips internal keys before anything goes to a client
local function public(row)
    local out = {}
    for k, v in pairs(row) do if k ~= 'key' then out[k] = v end end
    return out
end

function Leaderboard.Send(src, board, identifier, crewId)
    if board ~= 'solo' and board ~= 'crewruns' and board ~= 'crews' then board = 'solo' end
    local c = build(board)
    local rows = {}
    for i = 1, math.min(#c.list, Config.Leaderboard.Size) do rows[i] = public(c.list[i]) end
    local myKey = board == 'crews' and crewId or identifier
    local myPos = myKey and c.keys[myKey] or 0
    TriggerClientEvent('nayzeee-cutup:client:leaderboard', src, {
        board = board, rows = rows, total = #c.list,
        me = myPos > 0 and public(c.list[myPos]) or nil, myPos = myPos,
    })
end
