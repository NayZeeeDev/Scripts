if not NAYZEEE_LOCK_OK then return end

--[[
    Core: players, the request router used by the UI, wallets + ledger, admin check,
    Discord profiles, webhooks, exports and commands.
]]

Core = { Ids = {}, Online = {}, Open = {} }   -- [src] = identifier, [identifier] = src, [src] = shop open

-- ── players ─────────────────────────────────────────────────────────────
function Identify(src)
    local id = Core.Ids[src]
    if id then return id end
    id = Bridge.GetIdentifier(src)
    if id then Core.Ids[src], Core.Online[id] = id, src end
    return id
end

local function forget(src)
    local id = Core.Ids[src]
    if id and Core.Online[id] == src then Core.Online[id] = nil end
    Core.Ids[src], Core.Open[src] = nil, nil
end

function Push(src, channel, data) TriggerClientEvent('nzc:push', src, channel, data) end

function Notify(src, message, kind) Bridge.Notify(src, message, kind) end

-- ── admin ───────────────────────────────────────────────────────────────
function IsAdmin(src)
    src = tonumber(src)
    if not src or src <= 0 then return src == 0 end
    if IsPlayerAceAllowed(src, ServerConfig.AcePermission) then return true end
    local list = ServerConfig.Admins or {}
    if #list > 0 then
        local mine = {}
        for _, v in ipairs(GetPlayerIdentifiers(src)) do mine[v] = true end
        local fid = Identify(src)
        if fid then mine[fid] = true end
        for _, v in ipairs(list) do if mine[v] then return true end end
    end
    return Bridge.IsFrameworkAdmin(src)
end

-- ── router ──────────────────────────────────────────────────────────────
local Handlers, rate = {}, {}

-- opts.admin = admin only
function Handle(name, fn, opts)
    Handlers[name] = { fn = fn, admin = opts and opts.admin or false }
end

lib.callback.register('nzc:req', function(src, name, data)
    local h = Handlers[name]
    if not h then return { error = 'ERR_UNKNOWN' } end
    if not DB.ready then return { error = 'ERR_NOT_READY' } end
    local now = GetGameTimer()
    local r = rate[src]
    if not r or now - r.t > 1000 then rate[src] = { t = now, n = 1 } else
        r.n = r.n + 1
        if r.n > 20 then return { error = 'ERR_RATE' } end
    end
    local id = Identify(src)
    if not id then return { error = 'ERR_NO_CHARACTER' } end
    if h.admin and not IsAdmin(src) then return { error = 'ERR_NO_PERMISSION' } end
    local ok, res, err, extra = pcall(h.fn, src, id, type(data) == 'table' and data or {})
    if not ok then
        Log('^1Request %s failed: %s^0', name, tostring(res))
        return { error = 'ERR_GENERIC' }
    end
    if err then return { error = err, extra = extra } end
    return { data = res }
end)

-- ── wallets ─────────────────────────────────────────────────────────────
Wallet = {}

function Wallet.Ensure(id)
    MySQL.insert.await('INSERT IGNORE INTO nayzeee_coinshop_wallets (identifier, coins) VALUES (?, 0)', { id })
end

function Wallet.Get(id)
    local c = MySQL.scalar.await('SELECT coins FROM nayzeee_coinshop_wallets WHERE identifier = ?', { id })
    if c == nil then Wallet.Ensure(id) return 0 end
    return c
end

local function changed(id, delta, balance, reason, note)
    MySQL.insert('INSERT INTO nayzeee_coinshop_ledger (identifier, delta, balance, reason, note) VALUES (?, ?, ?, ?, ?)',
        { id, delta, balance, reason, note and tostring(note):sub(1, 160) or nil })
    local src = Core.Online[id]
    if src then Push(src, 'coins', balance) end
    TriggerEvent('nayzeee-coinshop:coinsChanged', src, id, balance - delta, balance, reason)
    return balance
end

-- Add coins. Returns the new balance.
function Wallet.Add(id, amount, reason, note)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return Wallet.Get(id) end
    MySQL.insert.await([[INSERT INTO nayzeee_coinshop_wallets (identifier, coins) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE coins = coins + VALUES(coins)]], { id, amount })
    return changed(id, amount, Wallet.Get(id), reason or 'add', note)
end

-- Take coins only if the balance covers it (atomic). Returns ok, newBalance.
function Wallet.Take(id, amount, reason, note, countAsSpent)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true, Wallet.Get(id) end
    Wallet.Ensure(id)
    local n = MySQL.update.await('UPDATE nayzeee_coinshop_wallets SET coins = coins - ?, spent = spent + ? WHERE identifier = ? AND coins >= ?',
        { amount, countAsSpent and amount or 0, id, amount })
    if n ~= 1 then return false, Wallet.Get(id) end
    return true, changed(id, -amount, Wallet.Get(id), reason or 'remove', note)
end

-- Give back coins from a failed purchase (also undoes the "spent" counter)
function Wallet.Refund(id, amount, note)
    MySQL.update.await('UPDATE nayzeee_coinshop_wallets SET coins = coins + ?, spent = GREATEST(spent - ?, 0) WHERE identifier = ?', { amount, amount, id })
    return changed(id, amount, Wallet.Get(id), 'refund', note)
end

function Wallet.Set(id, amount, reason, note)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local before = Wallet.Get(id)
    MySQL.update.await('UPDATE nayzeee_coinshop_wallets SET coins = ? WHERE identifier = ?', { amount, id })
    return changed(id, amount - before, amount, reason or 'set', note)
end

-- ── webhooks ────────────────────────────────────────────────────────────
function Webhook(kind, title, fields, description)
    local url = ServerConfig.Webhooks and ServerConfig.Webhooks[kind]
    if not url or url == '' then return end
    local list = {}
    for i = 1, 16 do   -- fields may contain nil holes (optional rows)
        local f = fields and fields[i]
        if f then list[#list + 1] = { name = f[1], value = tostring(f[2]), inline = f[3] ~= false } end
    end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = ServerConfig.WebhookName, avatar_url = ServerConfig.WebhookAvatar ~= '' and ServerConfig.WebhookAvatar or nil,
        embeds = { {
            title = title, description = description, color = ServerConfig.WebhookColors[kind] or 0x08afa2, fields = list,
            footer = { text = 'nayzeee-coinshop' }, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function Who(src)
    if not src or src == 0 then return 'Console' end
    return ('%s (ID %d)'):format(Bridge.GetName(src), src)
end

-- ── Discord profile ─────────────────────────────────────────────────────
local discord = {}

function DiscordProfile(src, cb)
    local did = Bridge.GetDiscord(src)
    local token = ServerConfig.DiscordBotToken
    if not did or not token or token == '' then return cb(nil) end
    if discord[did] then return cb(discord[did]) end
    PerformHttpRequest(('https://discord.com/api/v10/users/%s'):format(did), function(status, body)
        if status ~= 200 or not body then return cb(nil) end
        local d = DB.Decode(body)
        if not d then return cb(nil) end
        local avatar
        if d.avatar then
            avatar = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=128'):format(did, d.avatar, d.avatar:sub(1, 2) == 'a_' and 'gif' or 'png')
        else
            avatar = ('https://cdn.discordapp.com/embed/avatars/%d.png'):format((tonumber(did) >> 22) % 6)
        end
        discord[did] = { name = d.global_name or d.username, avatar = avatar }
        cb(discord[did])
    end, 'GET', '', { Authorization = 'Bot ' .. token })
end

-- ── exports ─────────────────────────────────────────────────────────────
local function idOf(src) return Identify(tonumber(src) or -1) end

exports('GetCoins', function(src) local id = idOf(src) return id and Wallet.Get(id) or 0 end)
exports('AddCoins', function(src, amount, note) local id = idOf(src) return id and Wallet.Add(id, amount, 'export', note) or false end)
exports('RemoveCoins', function(src, amount, note) local id = idOf(src) if not id then return false end return (Wallet.Take(id, amount, 'export', note)) end)
exports('SetCoins', function(src, amount, note) local id = idOf(src) return id and Wallet.Set(id, amount, 'export', note) or false end)
exports('GetCoinsByIdentifier', function(identifier) return Wallet.Get(identifier) end)
exports('AddCoinsByIdentifier', function(identifier, amount, note) return Wallet.Add(identifier, amount, 'export', note) end)

-- ── commands ────────────────────────────────────────────────────────────
local function reply(src, msg)
    if src > 0 then Notify(src, msg, 'inform') else print(msg) end
end

-- Tebex: coinshop_addcode {transaction} <coins>
RegisterCommand(ServerConfig.TebexCommand or 'coinshop_addcode', function(src, args)
    if src > 0 and not IsAdmin(src) then return end
    local code, coins = NZC.Trim(args[1]), tonumber(args[2])
    if code == '' or not coins or coins <= 0 then return print(T('USAGE_ADDCODE')) end
    CreateThread(function()
        for attempt = 1, 3 do
            local ok, err = pcall(MySQL.insert.await, 'INSERT IGNORE INTO nayzeee_coinshop_codes (tbx_id, coins, status) VALUES (?, ?, ?)', { code, math.floor(coins), 'pending' })
            if ok then Log('Code added | %s | %d coins', code, coins) return end
            Log('^3Adding code %s failed (attempt %d): %s^0', code, attempt, tostring(err))
            Wait(2000)
        end
    end)
end, true)

local function coinCommand(kind)
    return function(src, args)
        if src > 0 and not IsAdmin(src) then return Notify(src, T('ERR_NO_PERMISSION'), 'error') end
        local target, amount = tonumber(args[1]), tonumber(args[2])
        if not target or not amount or amount < 0 or (kind ~= 'set' and amount == 0) then return reply(src, T('USAGE_' .. kind:upper())) end
        local id = Identify(target)
        if not id then return reply(src, T('ERR_PLAYER_NOT_FOUND')) end
        local before = Wallet.Get(id)
        local after
        if kind == 'give' then after = Wallet.Add(id, amount, 'admin_give', Who(src))
        elseif kind == 'set' then after = Wallet.Set(id, amount, 'admin_set', Who(src))
        else
            local ok
            ok, after = Wallet.Take(id, math.min(amount, before), 'admin_remove', Who(src))
        end
        Notify(target, T('N_COINS_NOW', after), 'inform')
        Webhook('admin', T('LOG_CMD_' .. kind:upper()), { { 'By', Who(src) }, { 'Target', Who(target) }, { 'Balance', ('%d → %d'):format(before, after) } })
        reply(src, T('N_ADMIN_BALANCE', Bridge.GetName(target), after))
    end
end

RegisterCommand('givecoins', coinCommand('give'), false)
RegisterCommand('setcoins', coinCommand('set'), false)
RegisterCommand('removecoins', coinCommand('remove'), false)

-- ── playtime rewards (one thread, once a minute) ────────────────────────
if Config.Playtime.Enabled then
    local minutes = {}
    CreateThread(function()
        while true do
            Wait(60000)
            if DB.ready then
                for _, s in ipairs(GetPlayers()) do
                    local src = tonumber(s)
                    minutes[src] = (minutes[src] or 0) + 1
                    if minutes[src] >= Config.Playtime.Minutes then
                        minutes[src] = 0
                        local id = Identify(src)
                        if id then
                            local amount = Config.Playtime.Coins
                            if Config.Playtime.DailyCap > 0 then
                                MySQL.update.await([[UPDATE nayzeee_coinshop_wallets SET playtime_coins = IF(playtime_day = CURDATE(), playtime_coins, 0),
                                    playtime_day = CURDATE() WHERE identifier = ?]], { id })
                                local got = MySQL.scalar.await('SELECT playtime_coins FROM nayzeee_coinshop_wallets WHERE identifier = ?', { id }) or 0
                                amount = math.min(amount, Config.Playtime.DailyCap - got)
                            end
                            if amount > 0 then
                                Wallet.Add(id, amount, 'playtime')
                                MySQL.update('UPDATE nayzeee_coinshop_wallets SET playtime_coins = playtime_coins + ? WHERE identifier = ?', { amount, id })
                                Notify(src, T('N_PLAYTIME', amount, Config.General.CoinName), 'success')
                            end
                        end
                    end
                end
            end
        end
    end)
    AddEventHandler('playerDropped', function() minutes[source] = nil end)
end

-- ── lifecycle ───────────────────────────────────────────────────────────
if Config.General.Item then
    Bridge.RegisterUsableItem(Config.General.Item, function(src) TriggerClientEvent('nzc:open', src) end)
end

AddEventHandler('playerDropped', function()
    local src = source
    rate[src] = nil
    TestDriveEnd(src)
    forget(src)
end)
Bridge.OnLogout(function(src) forget(src) end)

-- ── test drive buckets ──────────────────────────────────────────────────
local driving, lastDrive = {}, {}

function TestDriveEnd(src)
    if not driving[src] then return end
    driving[src] = nil
    SetPlayerRoutingBucket(src, 0)
end

Handle('testdrive:start', function(src, _, d)
    if not Config.TestDrive.Enabled then return nil, 'ERR_DISABLED' end
    local item = Catalog.Get(d.id)
    if not item or item.category ~= Categories.VEHICLE or not item.enabled then return nil, 'ERR_ITEM_NOT_FOUND' end
    local now = os.time()
    if lastDrive[src] and now - lastDrive[src] < Config.TestDrive.Cooldown then
        return nil, 'ERR_TD_COOLDOWN', { Config.TestDrive.Cooldown - (now - lastDrive[src]) }
    end
    lastDrive[src] = now
    if Config.TestDrive.Isolate then
        local bucket = 7000 + src
        SetRoutingBucketPopulationEnabled(bucket, false)
        SetPlayerRoutingBucket(src, bucket)
        driving[src] = true
    end
    return { model = item.spawnName, duration = Config.TestDrive.Duration }
end)

RegisterNetEvent('nzc:testdrive:end', function() TestDriveEnd(source) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZC.Resource then return end
    for src in pairs(driving) do SetPlayerRoutingBucket(src, 0) end
end)
