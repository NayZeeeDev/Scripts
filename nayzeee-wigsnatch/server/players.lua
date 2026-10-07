-- Player cache. Everything the server needs is in memory; the DB is written on change.

Players = {}   -- [src] = P
ById    = {}   -- [identifier] = src

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

-- Sends the small profile summary the client keeps (cooldowns, level, flags)
function SyncP(P)
    local lvl, data = GetLevel(P.row.xp)
    TriggerClientEvent('nz-wig:c:profile', P.src, {
        xp = P.row.xp,
        level = lvl,
        title = data.title,
        cooldownUntil = P.cooldownUntil or 0,
        now = os.time(),
        glueUntil = P.row.glue_until,
        passive = P.row.passive == 1 or P.row.passive == true,
        streak = P.row.streak,
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
    if type(row.hair) ~= 'table' then row.hair = {} end

    local P = {
        src = src,
        id = identifier,
        name = name,
        row = row,
        hair = row.hair,
        cooldownUntil = 0,
        immuneUntil = 0,
        busy = false,          -- in a clash, haircut, trade...
        protected = false,     -- set by the SetProtected export
    }
    Players[src] = P
    ById[identifier] = src

    Hair.OnLoad(P)
    Social.OnLoad(P)
    SyncP(P)
    Debug(('loaded %s (%s)'):format(name, identifier))
end

function UnloadPlayer(src)
    src = tonumber(src)
    local P = src and Players[src]
    if not P then return end
    Clash.OnDrop(src)
    Tools.OnDrop(src)
    Social.OnDrop(src)
    P.row.last_seen = os.time()
    SaveP(P)
    Hair.Unschedule(P)
    Players[src] = nil
    if ById[P.id] == src then ById[P.id] = nil end
end

function AddXP(P, amount)
    amount = math.floor(amount + 0.5)
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

function IsNewPlayer(P)
    local h = Config.Protection.NewPlayerHours
    return h > 0 and (os.time() - (P.row.first_seen or 0)) < h * 3600
end

function EndNewPlayer(P)
    if not IsNewPlayer(P) then return end
    P.row.first_seen = os.time() - Config.Protection.NewPlayerHours * 3600 - 1
    Notify(P.src, L('protection_ended'), 'warning')
end

local function onProtectedJob(src)
    local job, duty = Bridge.GetJob(src)
    if not job or not Config.Protection.Jobs[job] then return false end
    return (not Config.Protection.JobsOnDutyOnly) or duty
end

-- Can P be snatched right now? returns ok, localeKey
function CanBeTarget(P)
    if P.busy then return false, 'target_busy' end
    if IsPassive(P) or P.protected or stateFlag(P.src, Config.Protection.SafezoneStates) then return false, 'target_protected' end
    if os.time() < (P.immuneUntil or 0) then return false, 'target_immune' end
    if IsNewPlayer(P) then return false, 'target_new' end
    if onProtectedJob(P.src) then return false, 'target_job' end
    return true
end

-- Can P snatch right now? returns ok, localeKey, extra
function CanAttack(P)
    if P.busy then return false, 'busy' end
    if IsPassive(P) or P.protected or stateFlag(P.src, Config.Protection.SafezoneStates) then return false, 'self_protected' end
    if onProtectedJob(P.src) then return false, 'self_job' end
    local now = os.time()
    if now < (P.cooldownUntil or 0) then return false, 'cooldown', P.cooldownUntil - now end
    return true
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

function InVehicle(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0
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
