-- Player cache. Everything the server needs is in memory; the DB is written on change.

Players = {}   -- [src] = P
ById    = {}   -- [identifier] = src

-- modules hook into load / drop here (registered by each module)
local loadHooks, dropHooks = {}, {}
function OnPlayerLoad(fn) loadHooks[#loadHooks + 1] = fn end
function OnPlayerDrop(fn) dropHooks[#dropHooks + 1] = fn end

function GetP(src)
    return Players[tonumber(src) or -1]
end

function Notify(src, msg, kind, duration)
    TriggerClientEvent('nz-wig:c:notify', src, msg, kind or 'info', duration)
end

function SaveP(P)
    P.row.hair = P.hair
    DB.SavePlayer(P.row)
end

function SetBusy(P, on)
    P.busy = on == true
    Player(P.src).state:set(ST.busy, P.busy or nil, true)
end

-- Sends the small profile summary the client keeps (cooldowns, level, flags)
function SyncP(P)
    local lvl, data = GetLevel(P.row.xp)
    TriggerClientEvent('nz-wig:c:profile', P.src, {
        xp = P.row.xp,
        level = lvl,
        title = data.title,
        cooldownUntil = P.cooldownUntil or 0,
        tackleUntil = P.tackleUntil or 0,
        now = os.time(),
        glueUntil = P.row.glue_until,
        passive = P.row.passive == 1 or P.row.passive == true,
        streak = P.row.streak,
        stealBack = StealBack and StealBack.TargetsFor(P) or {},
    })
end

function LoadPlayer(src)
    src = tonumber(src)
    if not src or Players[src] then return end
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return end
    local name = Bridge.GetCharName(src)
    local row = DB.LoadPlayer(identifier, name)
    if not row then return end

    local P = {
        src = src,
        id = identifier,
        name = name,
        row = row,
        hair = row.hair,
        cooldownUntil = 0,
        immuneUntil = 0,
        busy = false,          -- in a minigame, cut, trade, tie...
        protected = false,     -- set by the SetProtected export
    }
    Players[src] = P
    ById[identifier] = src

    for _, fn in ipairs(loadHooks) do
        local ok, err = pcall(fn, P)
        if not ok then print(('^1[%s] load hook error: %s^7'):format(RESOURCE, err)) end
    end
    SyncP(P)
    Debug(('loaded %s (%s)'):format(name, identifier))
end

function UnloadPlayer(src)
    src = tonumber(src)
    local P = src and Players[src]
    if not P then return end
    for _, fn in ipairs(dropHooks) do
        local ok, err = pcall(fn, src, P)
        if not ok then print(('^1[%s] drop hook error: %s^7'):format(RESOURCE, err)) end
    end
    P.row.last_seen = os.time()
    SaveP(P)
    Players[src] = nil
    if ById[P.id] == src then ById[P.id] = nil end
end

function AddXP(P, amount)
    amount = math.floor((amount or 0) + 0.5)
    if amount <= 0 then return 0 end
    local before = GetLevel(P.row.xp)
    P.row.xp = P.row.xp + amount
    local after, data = GetLevel(P.row.xp)
    if after > before then
        Notify(P.src, L('level_up', data.title), 'success', 6000)
        TriggerClientEvent('nz-wig:c:levelUp', P.src, after, data.title)
    end
    return amount
end

function IsPassive(P)
    return Config.Protection.Passive.Enabled and (P.row.passive == 1 or P.row.passive == true)
end

local function stateFlag(src, keys)
    local st = Player(src).state
    for i = 1, #keys do
        if st[keys[i]] then return true end
    end
    return false
end
StateFlag = stateFlag

-- tied, held, tackled, cuffed or downed (server-visible state only)
function IsRestrainedSrc(src)
    return stateFlag(src, Config.RestrainedStates) or stateFlag(src, Config.DownedStates)
end

function IsNewPlayer(P)
    local h = Config.Protection.NewPlayerHours
    return h > 0 and (os.time() - (P.row.first_seen or 0)) < h * 3600
end

function EndNewPlayer(P)
    if not Config.Protection.NewPlayerEndsOnAttack or not IsNewPlayer(P) then return end
    P.row.first_seen = os.time() - Config.Protection.NewPlayerHours * 3600 - 1
    Notify(P.src, L('protection_ended'), 'warning')
end

local function onProtectedJob(src)
    local job, duty = Bridge.GetJob(src)
    if not job or not Config.Protection.Jobs[job] then return false end
    return (not Config.Protection.JobsOnDutyOnly) or duty
end

local function shielded(P)
    return IsPassive(P) or P.protected or stateFlag(P.src, Config.Protection.SafezoneStates)
end

-- Can P be targeted right now? returns ok, localeKey
--   opts.ignoreBusy   = holds / ties check busy themselves
--   opts.ignoreImmune = immunity only protects hair, not tackles / ties
function CanBeTarget(P, opts)
    opts = opts or {}
    if P.busy and not opts.ignoreBusy then return false, 'target_busy' end
    if shielded(P) then return false, 'target_protected' end
    if not opts.ignoreImmune and os.time() < (P.immuneUntil or 0) then return false, 'target_immune' end
    if IsNewPlayer(P) then return false, 'target_new' end
    if onProtectedJob(P.src) then return false, 'target_job' end
    return true
end

-- Can P act on someone right now? returns ok, localeKey, extra
--   opts.cooldown = also check the snatch cooldown
function CanAttack(P, opts)
    opts = opts or {}
    if P.busy and not opts.ignoreBusy then return false, 'busy' end
    -- tied up, held, cuffed or down: hands aren't free
    if Restrain.IsTied(P.src) or Restrain.HeldBy(P.src) or IsRestrainedSrc(P.src) then return false, 'self_restrained' end
    if shielded(P) then return false, 'self_protected' end
    if onProtectedJob(P.src) then return false, 'self_job' end
    if opts.cooldown then
        local now = os.time()
        if now < (P.cooldownUntil or 0) then return false, 'cooldown', P.cooldownUntil - now end
    end
    return true
end

function AttackError(src, key, extra)
    Notify(src, key == 'cooldown' and L('cooldown', extra) or L(key), 'error')
end

function StartCooldown(P)
    local perks = GetPerks(P.row.xp)
    local secs = math.floor(Config.Snatch.Cooldown * (1 - perks.cooldown))
    P.cooldownUntil = os.time() + secs
end

-- distance between two players' peds (server-side, OneSync)
function PedDistance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

function PedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

function InVehicle(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0
end

-- is attacker behind victim (within the blindside angle)?
function IsBehindSrc(attacker, victim, angle)
    local va, vv = GetPlayerPed(attacker), GetPlayerPed(victim)
    if va == 0 or vv == 0 then return false end
    local ca, cv = GetEntityCoords(va), GetEntityCoords(vv)
    local h = math.rad(GetEntityHeading(vv))
    local fx, fy = -math.sin(h), math.cos(h)
    local dx, dy = ca.x - cv.x, ca.y - cv.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return false end
    local dot = (fx * dx + fy * dy) / len
    return math.deg(math.acos(Clamp(dot, -1, 1))) >= 180 - (angle or 70)
end

function PlayersNear(coords, range, except)
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if s ~= except then
            local ped = GetPlayerPed(s)
            if ped ~= 0 and #(GetEntityCoords(ped) - coords) <= range then out[#out + 1] = s end
        end
    end
    return out
end

-- broadcast a positional sound to everyone close to src
function PlaySoundAt(src, sound, duration, range)
    local c = PedCoords(src)
    if not c then return end
    range = range or 12.0
    for _, s in ipairs(PlayersNear(c, range)) do
        TriggerClientEvent('nz-wig:c:sound', s, { sound = sound, coords = { x = c.x, y = c.y, z = c.z }, range = range, duration = duration })
    end
end

function React(src, kind, delay)
    TriggerClientEvent('nz-wig:c:react', src, kind, delay)
end

-- prompts: one accept / decline popup shared by trades, haircuts, wigs put on you...
PromptHandlers = {}   -- [kind] = fn(src, id, accept)

function SendPrompt(src, data)
    TriggerClientEvent('nz-wig:c:prompt', src, data)
end

function ClosePrompt(src, id)
    TriggerClientEvent('nz-wig:c:promptClose', src, id)
end

RegisterNetEvent('nz-wig:s:promptReply', function(kind, id, accept)
    local h = PromptHandlers[kind]
    if h then h(source, tonumber(id), accept == true) end
end)
