-- Discord role sync: a role for being in a squad, for the squad's tier, and for the rank.
-- Every call goes through one queue so Discord's rate limits are respected.
Roles = {}

local R       = Config.Roles
local guild   = Config.Discord.GuildId
local API     = 'https://discord.com/api/v10'
local queue   = {}
local applied = {}   -- [src] = signature of the last sync
local running = false

local enabled = R.Enabled and guild ~= '' and Discord.Token() ~= ''

if R.Enabled then
    if guild == '' then
        print('^1[nayzeee-squads]^7 Role sync is on but Config.Discord.GuildId is empty.')
    elseif Discord.Token() == '' then
        print('^1[nayzeee-squads]^7 Role sync is on but nz_squads_bot_token is not set.')
    end
end

function Roles.Enabled() return enabled end

local managed
local function managedRoles()
    if managed then return managed end
    managed = {}
    local function add(id) if type(id) == 'string' and id ~= '' then managed[id] = true end end
    add(R.InSquad)
    add(R.Owner)
    for _, id in pairs(R.Tiers or {}) do add(id) end
    for _, id in pairs(R.Ranks or {}) do add(id) end
    return managed
end

local function push(method, url, cb)
    queue[#queue + 1] = { method = method, url = url, cb = cb }
    if running then return end
    running = true

    CreateThread(function()
        while #queue > 0 do
            local job = table.remove(queue, 1)
            local done, tries = false, 0

            while not done do
                local p = promise.new()
                PerformHttpRequest(job.url, function(status, body, headers)
                    p:resolve({ status = status, body = body, headers = headers })
                end, job.method, '', {
                    ['Authorization'] = 'Bot ' .. Discord.Token(),
                    ['Content-Type'] = 'application/json',
                })
                local res = Citizen.Await(p)

                if res.status == 429 and tries < 3 then
                    tries = tries + 1
                    local wait = 2000
                    local ok, data = pcall(json.decode, res.body or '')
                    if ok and type(data) == 'table' and data.retry_after then
                        wait = math.ceil(data.retry_after * 1000) + 150
                    end
                    Wait(wait)
                else
                    done = true
                    if job.cb then job.cb(res.status, res.body) end
                    if res.status == 403 then
                        print('^1[nayzeee-squads]^7 Discord refused a role change. The bot needs Manage Roles, and its own role must sit above the roles it assigns.')
                    end
                end
            end
            Wait(R.QueueDelay)
        end
        running = false
    end)
end

local function desiredFor(src)
    local want = {}
    local sq = SquadOf(src)
    if not sq then return want end
    if R.InSquad ~= '' then want[R.InSquad] = true end

    local identifier = sq.online[src]
    local rec = identifier and sq.roster[identifier]
    if not rec then return want end

    if R.Owner ~= '' and identifier == sq.owner then want[R.Owner] = true end

    local tierRole = R.Tiers and R.Tiers[Combat.Tier(sq.elo).name]
    if tierRole and tierRole ~= '' then want[tierRole] = true end

    local rankRole = R.Ranks and R.Ranks[Ranks.Name(sq, rec.rank)]
    if rankRole and rankRole ~= '' then want[rankRole] = true end
    return want
end

local function signature(want)
    local list = {}
    for id in pairs(want) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ',')
end

---@param src number
---@param force boolean|nil skip the "nothing changed" shortcut
function Roles.Sync(src, force)
    if not enabled then return end
    local user = Discord.UserId(src)
    if not user then return end

    local want = desiredFor(src)
    local sig = signature(want)
    if not force and applied[src] == sig then return end
    applied[src] = sig

    push('GET', ('%s/guilds/%s/members/%s'):format(API, guild, user), function(status, body)
        if status ~= 200 or not body then return end
        local ok, member = pcall(json.decode, body)
        if not ok or type(member) ~= 'table' or type(member.roles) ~= 'table' then return end

        local has = {}
        for i = 1, #member.roles do has[member.roles[i]] = true end

        for id in pairs(want) do
            if not has[id] then push('PUT', ('%s/guilds/%s/members/%s/roles/%s'):format(API, guild, user, id)) end
        end
        if R.RemoveOnLeave then
            for id in pairs(managedRoles()) do
                if has[id] and not want[id] then
                    push('DELETE', ('%s/guilds/%s/members/%s/roles/%s'):format(API, guild, user, id))
                end
            end
        end
    end)
end

function Roles.SyncSquad(sq, force)
    if not enabled or not sq then return end
    for src in pairs(sq.online) do Roles.Sync(src, force) end
end

function Roles.Clear(src)
    if not enabled then return end
    applied[src] = nil
    Roles.Sync(src, true)
end

function Roles.Forget(src)
    applied[src] = nil
end

-- /squadroles — re-syncs everyone, for after you change the config
RegisterCommand('squadroles', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Admin.Ace) then return end
    if not enabled then
        local msg = 'Role sync is off. Check Config.Roles.Enabled, Config.Discord.GuildId and nz_squads_bot_token.'
        if src == 0 then print('[nayzeee-squads] ' .. msg) else Notify(src, msg, 'error') end
        return
    end
    local n = 0
    for _, sq in pairs(Squads) do
        for s in pairs(sq.online) do
            Roles.Sync(s, true)
            n = n + 1
        end
    end
    local msg = ('Re-syncing Discord roles for %d players.'):format(n)
    if src == 0 then print('[nayzeee-squads] ' .. msg) else Notify(src, msg, 'inform') end
end, false)
