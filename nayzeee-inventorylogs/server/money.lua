-- Money logging with the script that caused each change.
--   ESX Legacy:  esx:addAccountMoney / removeAccountMoney / setAccountMoney
--   QBCore/Qbox: QBCore:Server:OnMoneyChange
-- The framework bridge (framework_bridge/nayzeee.lua) supplies the calling script. Without it,
-- changes are credited to the framework. On ESX, cash that moves inside the inventory (drops,
-- gives, shop buys) never reaches the framework, so balances are also compared on a timer and
-- anything left unexplained is logged as "unattributed".
local NAMES = { cash = 'Cash', money = 'Cash', bank = 'Bank', black_money = 'Dirty money', crypto = 'Crypto' }
local bal = {}      -- charId -> { account -> last known balance }
local win = {}      -- charId -> spike window
local spikes = {}

function GetMoneySpikes() return spikes end

-- IsAccountItem(name) lives in server/inventory.lua: the inventory integration says which items are money

local function balanceOf(src)
    local id = NZ.CharId(src)
    if not id then return end
    bal[id] = bal[id] or {}
    return bal[id], id
end

--- Shift the remembered balance so the next comparison doesn't count a change we already explained.
function AdjustBaseline(src, account, delta)
    local b = balanceOf(src)
    if b and b[account] then b[account] = b[account] + delta end
end

function ResetMoneyBaseline(charId) if charId then bal[charId] = nil end end

-- ─── spike detection (net across all accounts, so moving bank -> cash never trips it) ─────────
local function spikeCheck(me, delta)
    local V = Config.MoneyLogs.velocity
    if not V or not V.enabled then return end
    local w = win[me.identifier]
    if not w then w = { list = {} } win[me.identifier] = w end
    w.list[#w.list + 1] = { t = os.time(), d = delta }
    if w.timer then return end
    w.timer = true
    -- wait for the other half of a transfer (e.g. bank -X then cash +X) before judging
    SetTimeout(3000, function()
        w.timer = nil
        local now = os.time()
        local cutoff = now - V.windowMinutes * 60
        local keep, total = {}, 0
        for _, e in ipairs(w.list) do
            if e.t >= cutoff then keep[#keep + 1] = e total = total + e.d end
        end
        w.list = keep
        if total >= V.amount and (not w.alerted or now - w.alerted > V.windowMinutes * 60) then
            w.alerted = now
            local details = ('%s gained $%s in under %d minutes'):format(me.name, NZ.Comma(total), V.windowMinutes)
            spikes[#spikes + 1] = { name = me.name, identifier = me.identifier, total = total, time = now }
            if #spikes > 20 then table.remove(spikes, 1) end
            InsertLog({ type = 'suspicious', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
                item_name = 'money', item_label = 'Money spike', item_count = total, coords = me.coords, details = details })
            SendWebhook('suspicious', 'Money spike', { player = me, details = details, coords = me.coords,
                money = { amount = total, account = 'All accounts together', reason = ('Net gain inside %d minutes'):format(V.windowMinutes) } })
            NZ.NotifyStaff(details, 'error', 'flags')
        end
    end)
end

--- Log a money change. resource = script that caused it (nil = unknown)
function LogMoneyChange(src, account, delta, reason, resource)
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 or not Config.MoneyLogs.enabled then return end
    if reason == 'nz-rollback' then return end
    local me = NZ.Actor(src)
    local isTransfer = resource == 'transfer'
    if not isTransfer then spikeCheck(me, delta) end
    if math.abs(delta) < (Config.MoneyLogs.minimumAmount or 0) then return end
    local label = NAMES[account] or account
    reason = reason and tostring(reason) ~= '' and tostring(reason):sub(1, 120) or nil
    local who = resource and resource ~= 'transfer' and (' via ' .. resource) or ''
    local details = ('%s %s $%s %s%s%s'):format(me.name, delta > 0 and 'received' or 'lost', NZ.Comma(delta), label:lower(), who, reason and (' · ' .. reason) or '')
    InsertLog({ type = 'money', source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        item_name = account, item_label = label, item_count = delta, inventory_from = reason, coords = me.coords,
        details = details, resource = resource })
    if math.abs(delta) >= (Config.MoneyLogs.webhookMinimum or 0) and not isTransfer then
        SendWebhook('money', delta > 0 and 'Money received' or 'Money removed', { player = me, resource = resource or 'unattributed', details = details, coords = me.coords,
            money = { amount = delta, account = label, reason = reason } })
    end
end

exports('LogMoneyEvent', function(src, account, amount, action, reason)
    amount = tonumber(amount) or 0
    if action == 'remove' then amount = -math.abs(amount) end
    AdjustBaseline(src, account, amount)
    LogMoneyChange(src, account, amount, reason, GetInvokingResource())
end)

-- ─── ESX ─────────────────────────────────────────────────────────────────────
local function esxBy(src, account) return AttrFor(src, 'money', account) or 'es_extended' end

AddEventHandler('esx:addAccountMoney', function(src, account, money, reason)
    if NZ.Framework ~= 'esx' then return end
    AdjustBaseline(src, account, money)
    LogMoneyChange(src, account, money, reason, esxBy(src, account))
end)

AddEventHandler('esx:removeAccountMoney', function(src, account, money, reason)
    if NZ.Framework ~= 'esx' then return end
    AdjustBaseline(src, account, -money)
    LogMoneyChange(src, account, -money, reason, esxBy(src, account))
end)

AddEventHandler('esx:setAccountMoney', function(src, account, money, reason)
    if NZ.Framework ~= 'esx' or type(src) ~= 'number' then return end
    local b = balanceOf(src)
    local prev = b and b[account]
    if b then b[account] = money end
    if prev then LogMoneyChange(src, account, money - prev, reason, esxBy(src, account)) end
end)

local ESX
local function accountsOf(src)
    ESX = ESX or exports.es_extended:getSharedObject()
    local x = ESX.GetPlayerFromId(src)
    if not x then return end
    local out = {}
    for _, acc in ipairs(x.getAccounts and x.getAccounts() or {}) do out[acc.name] = acc.money end
    return out, x.identifier
end

CreateThread(function()
    Wait(5000)
    if NZ.Framework ~= 'esx' or not Config.MoneyLogs.enabled then return end
    local every = math.max(5, Config.MoneyLogs.esxPollSeconds or 15) * 1000
    while true do
        Wait(every)
        local seen = {}
        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local acc, charId = accountsOf(src)
            if acc and charId then
                seen[charId] = true
                local b = bal[charId]
                if not b then
                    bal[charId] = acc
                else
                    for name, money in pairs(acc) do
                        if b[name] == nil then b[name] = money
                        else
                            local d = (money or 0) - b[name]
                            if d ~= 0 then
                                b[name] = money
                                LogMoneyChange(src, name, d, 'Changed outside the framework', nil)
                            end
                        end
                    end
                end
            end
        end
        for k in pairs(bal) do if not seen[k] then bal[k] = nil end end
    end
end)

AddEventHandler('esx:playerLogout', function(src)
    local id = NZ.CharId(src)
    if id then bal[id] = nil end
end)

-- ─── QBCore / Qbox ───────────────────────────────────────────────────────────
local function qbMoney(src)
    local p
    if NZ.Framework == 'qbx' then
        local ok, r = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        p = ok and r or nil
    elseif GetResourceState('qb-core') == 'started' then
        p = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
    end
    return p and p.PlayerData and p.PlayerData.money
end

AddEventHandler('QBCore:Server:OnMoneyChange', function(src, account, amount, action, reason)
    if NZ.Framework ~= 'qbcore' and NZ.Framework ~= 'qbx' then return end
    amount = tonumber(amount) or 0
    local by = AttrFor(src, 'money', account) or (NZ.Framework == 'qbx' and 'qbx_core' or 'qb-core')
    local r = tostring(reason or ''):lower()
    if r:find('sync') and r:find('inventory') then by = 'transfer' end
    local b = balanceOf(src)
    local prev = b and b[account]
    local now = qbMoney(src)
    if b and now and now[account] then b[account] = now[account] end
    if action == 'set' then
        if prev then LogMoneyChange(src, account, amount - prev, reason, by) end
        return
    end
    LogMoneyChange(src, account, action == 'remove' and -math.abs(amount) or amount, reason, by)
end)
