-- Server entry: online registry, profiles, run validation, leaderboards, admin.
Online = { src = {}, ident = {} }

function Online.Ident(src) return Online.src[tonumber(src) or -1] end
function Online.ByIdent(ident) return Online.ident[ident] end

local lastSubmit, lastBoard = {}, {}

local function identifierOf(src)
    local id = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license')
    if id then return id end
    for _, v in ipairs(GetPlayerIdentifiers(src)) do
        if v:sub(1, 8) == 'license:' then return v end
    end
    return 'src:' .. tostring(src)
end

local function cleanName(src)
    local n = (GetPlayerName(src) or ('Driver ' .. src)):gsub('[<>^~]', '')
    return n:sub(1, 32)
end

local function getPlayer(src)
    local ident = Online.Ident(src)
    if not ident then return nil end
    local p = DB.players[ident]
    if not p then
        p = { identifier = ident, name = cleanName(src), runs = 0, totalPoints = 0, totalDistance = 0 }
        DB.players[ident] = p
        DB.SavePlayer(p)
    end
    return p
end

local function sendProfile(src)
    local p = getPlayer(src)
    if not p then return end
    local crew = Crews.Get(p.crewId)
    local pos, total = Leaderboard.Position('solo', p.identifier)
    local cpos = Leaderboard.Position('crewruns', p.identifier)
    TriggerClientEvent('nayzeee-cutup:client:profile', src, {
        name = p.name,
        pbSolo = p.bestSolo and p.bestSolo.points or 0,
        pbCrew = p.bestCrew and p.bestCrew.points or 0,
        position = pos, crewPosition = cpos, totalPlayers = total,
        runs = p.runs or 0, totalPoints = p.totalPoints or 0, totalDistance = p.totalDistance or 0,
        crew = crew and { id = crew.id, name = crew.name, tag = crew.tag, color = crew.color, role = crew.members[p.identifier].role } or nil,
    })
end

---------------------------------------------------------------------------
-- join / leave
---------------------------------------------------------------------------
RegisterNetEvent('nayzeee-cutup:server:init', function()
    local src = source
    local t = GetGameTimer() + 15000
    while not DB.ready and GetGameTimer() < t do Wait(100) end
    if not DB.ready then return end
    local ident = identifierOf(src)
    Online.src[src], Online.ident[ident] = ident, src
    local p = getPlayer(src)
    local name = cleanName(src)
    if p.name ~= name then
        p.name = name
        local crew = Crews.Get(p.crewId)
        if crew and crew.members[ident] then crew.members[ident].name = name DB.SaveCrew(crew) end
        DB.SavePlayer(p)
        Leaderboard.Dirty()
    end
    -- crew was deleted while they were away
    if p.crewId and not Crews.Get(p.crewId) then p.crewId = nil DB.SavePlayer(p) end
    Crews.SyncState(ident)
    Player(src).state:set('cutupActive', false, true)
    sendProfile(src)
    Crews.Send(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local ident = Online.src[src]
    if ident then Online.ident[ident] = nil end
    Online.src[src] = nil
    lastSubmit[src], lastBoard[src] = nil, nil
    Crews.Dropped(src)
end)

RegisterNetEvent('nayzeee-cutup:server:setActive', function(active)
    local src = source
    if not Online.Ident(src) then return end
    Player(src).state:set('cutupActive', active == true, true)
end)

---------------------------------------------------------------------------
-- runs
---------------------------------------------------------------------------
local function num(v, lo, hi)
    v = tonumber(v) or 0
    if v ~= v then v = 0 end   -- NaN
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function str(v, len) return (tostring(v or ''):gsub('[<>]', '')):sub(1, len) end

local function validate(run)
    local v = Config.Validation
    local time = num(run.time, 0, Config.Run.Duration + 10)
    if time < 20 then return nil, 'too short' end
    local points = math.floor(num(run.points, 0))
    if points < Config.Run.MinSubmit then return nil, 'too low' end
    if points / time > v.MaxPointsPerSecond then return nil, 'points rate' end
    local distance = math.floor(num(run.distance, 0))
    local avgSpeed = distance / time
    if avgSpeed > v.MaxAvgSpeed then return nil, 'speed' end
    local combo = math.floor(num(run.maxCombo, 0))
    if combo > v.MaxCombo then return nil, 'combo' end
    local trans = ({ auto = 'Automatic', sequential = 'Sequential', hpattern = 'H-Pattern' })[run.transmission] or 'Automatic'
    return {
        points = points, maxCombo = combo, time = math.floor(time), distance = distance, avgSpeed = avgSpeed,
        car = str(run.car, 40), map = str(run.map, 40), camera = str(run.camera, 20), density = str(run.density, 12),
        transmission = trans, carsPassed = math.floor(num(run.carsPassed, 0, 100000)),
        avgProximity = num(run.avgProximity, 0, 10), crashes = math.floor(num(run.crashes, 0, 99)),
        crewRun = run.crewRun == true, server = Config.ServerName, date = os.time(),
    }
end

RegisterNetEvent('nayzeee-cutup:server:submitRun', function(raw)
    local src = source
    local p = getPlayer(src)
    if not p or type(raw) ~= 'table' then return end
    local now = os.time()
    if lastSubmit[src] and now - lastSubmit[src] < Config.Validation.SubmitCooldown then
        return TriggerClientEvent('nayzeee-cutup:client:runResult', src, { ok = false, reason = 'cooldown' })
    end
    lastSubmit[src] = now

    local run, err = validate(raw)
    if not run then
        if Config.Debug then print(('[nayzeee-cutup] rejected run from %s: %s'):format(p.name, err)) end
        return TriggerClientEvent('nayzeee-cutup:client:runResult', src, { ok = false, reason = err })
    end
    if run.crewRun and not Crews.Get(p.crewId) then run.crewRun = false end

    local oldRank = Util.GetRank(math.max(p.bestSolo and p.bestSolo.points or 0, p.bestCrew and p.bestCrew.points or 0))
    p.runs = (p.runs or 0) + 1
    p.totalPoints = (p.totalPoints or 0) + run.points
    p.totalDistance = (p.totalDistance or 0) + run.distance

    local field = run.crewRun and 'bestCrew' or 'bestSolo'
    local board = run.crewRun and 'crewruns' or 'solo'
    local newPB = not p[field] or run.points > p[field].points
    if newPB then
        p[field] = run
        Leaderboard.Dirty()
        if run.crewRun then Crews.Recalc(p.crewId) end
    end
    DB.SavePlayer(p)
    DB.AddRun(p.identifier, run)

    local pos = Leaderboard.Position(board, p.identifier)
    local newRank = Util.GetRank(math.max(p.bestSolo and p.bestSolo.points or 0, p.bestCrew and p.bestCrew.points or 0))
    TriggerClientEvent('nayzeee-cutup:client:runResult', src, {
        ok = true, points = run.points, newPB = newPB, position = pos, board = board,
        rankUp = newRank.index > oldRank.index and newRank.name or nil,
    })
    sendProfile(src)

    local top = Config.Leaderboard.AnnounceTop
    if newPB and top and pos > 0 and pos <= top then
        local label = run.crewRun and 'CREW' or 'SOLO'
        TriggerClientEvent('nayzeee-cutup:client:toast', -1, 'LEADERBOARD',
            L('top_announce', p.name, pos, label, Util.FormatNumber(run.points)), 'success')
    end
end)

RegisterNetEvent('nayzeee-cutup:server:leaderboard', function(board)
    local src = source
    local p = getPlayer(src)
    if not p then return end
    local now = GetGameTimer()
    if lastBoard[src] and now - lastBoard[src] < 400 then return end
    lastBoard[src] = now
    Leaderboard.Send(src, board, p.identifier, p.crewId)
end)

RegisterNetEvent('nayzeee-cutup:server:crew', function(action, data)
    Crews.Handle(source, action, data)
end)

---------------------------------------------------------------------------
-- admin
---------------------------------------------------------------------------
RegisterCommand('cutupadmin', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.AdminAce) then return end
    local function reply(msg)
        if src == 0 then print(msg) else TriggerClientEvent('nayzeee-cutup:client:toast', src, 'ADMIN', msg, 'info') end
    end
    local sub = args[1]
    if sub == 'resetboards' then
        DB.ResetBoards()
        for _, c in pairs(DB.crews) do Crews.Recalc(c.id) end
        Leaderboard.Dirty()
        for s in pairs(Online.src) do sendProfile(s) end
        reply(L('admin_reset'))
    elseif sub == 'resetplayer' and tonumber(args[2]) then
        local ident = Online.Ident(tonumber(args[2]))
        local p = ident and DB.players[ident]
        if not p then return reply(L('crew_no_player')) end
        p.bestSolo, p.bestCrew = nil, nil
        DB.SavePlayer(p)
        if p.crewId then Crews.Recalc(p.crewId) end
        Leaderboard.Dirty()
        sendProfile(tonumber(args[2]))
        reply(L('admin_reset'))
    else
        reply(L('admin_usage'))
    end
end, false)

---------------------------------------------------------------------------
-- boot
---------------------------------------------------------------------------
CreateThread(function()
    math.randomseed(os.time())
    if GetResourceState('oxmysql') == 'starting' then
        local t = GetGameTimer() + 10000
        while GetResourceState('oxmysql') ~= 'started' and GetGameTimer() < t do Wait(100) end
    end
    DB.Init()
    -- restart-safe: re-register anyone already online
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ident = identifierOf(src)
        Online.src[src], Online.ident[ident] = ident, src
    end
end)
