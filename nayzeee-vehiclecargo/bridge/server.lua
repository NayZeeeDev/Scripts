Bridge = {}

local FW, ESX, QB

local function detect()
    local want = Config.Framework
    if (want == 'auto' or want == 'qbx') and GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if (want == 'auto' or want == 'esx') and GetResourceState('es_extended') == 'started' then return 'esx' end
    if (want == 'auto' or want == 'qb') and GetResourceState('qb-core') == 'started' then return 'qb' end
    return nil
end

FW = detect()
if FW == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif FW == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
end
Bridge.Framework = FW

if not FW then
    print('^1[nayzeee-vehiclecargo] No supported framework found (ESX / QBCore / Qbox).^7')
end

local useOx = GetResourceState('ox_inventory') == 'started'

local function qbAccount(acc)
    if acc == 'money' then return 'cash' end
    return acc
end
local function esxAccount(acc)
    if acc == 'cash' then return 'money' end
    return acc
end

local function player(src)
    if FW == 'esx' then return ESX.GetPlayerFromId(src) end
    if FW == 'qb' then return QB.Functions.GetPlayer(src) end
    if FW == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end
Bridge.GetPlayer = player

function Bridge.GetIdentifier(src)
    local p = player(src)
    if not p then return nil end
    if FW == 'esx' then return p.identifier end
    return p.PlayerData and p.PlayerData.citizenid
end

function Bridge.GetName(src)
    local p = player(src)
    if not p then return GetPlayerName(src) or 'Unknown' end
    if FW == 'esx' then return p.getName and p.getName() or GetPlayerName(src) end
    local c = p.PlayerData and p.PlayerData.charinfo
    if c then return ('%s %s'):format(c.firstname or '', c.lastname or '') end
    return GetPlayerName(src)
end

function Bridge.GetMoney(src, account)
    local p = player(src)
    if not p then return 0 end
    if FW == 'esx' then
        local a = p.getAccount(esxAccount(account))
        return a and a.money or 0
    elseif FW == 'qbx' then
        return exports.qbx_core:GetMoney(src, qbAccount(account)) or 0
    else
        return p.Functions.GetMoney(qbAccount(account)) or 0
    end
end

function Bridge.RemoveMoney(src, account, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    if Bridge.GetMoney(src, account) < amount then return false end
    local p = player(src)
    if not p then return false end
    if FW == 'esx' then
        p.removeAccountMoney(esxAccount(account), amount, reason)
        return true
    elseif FW == 'qbx' then
        return exports.qbx_core:RemoveMoney(src, qbAccount(account), amount, reason) ~= false
    else
        return p.Functions.RemoveMoney(qbAccount(account), amount, reason) ~= false
    end
end

function Bridge.AddMoney(src, account, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return end
    local p = player(src)
    if not p then return end
    if FW == 'esx' then
        p.addAccountMoney(esxAccount(account), amount, reason)
    elseif FW == 'qbx' then
        exports.qbx_core:AddMoney(src, qbAccount(account), amount, reason)
    else
        p.Functions.AddMoney(qbAccount(account), amount, reason)
    end
end

-- returns job name, on duty
function Bridge.GetJob(src)
    local p = player(src)
    if not p then return nil, false end
    if FW == 'esx' then
        return p.job and p.job.name, true
    end
    local j = p.PlayerData and p.PlayerData.job
    return j and j.name, j and j.onduty
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.Admin.Ace) then return true end
    local p = player(src)
    if not p then return false end
    if FW == 'esx' then
        local g = p.getGroup and p.getGroup()
        for _, v in ipairs(Config.Admin.Groups) do if v == g then return true end end
    elseif FW == 'qb' then
        for _, v in ipairs(Config.Admin.Groups) do
            if QB.Functions.HasPermission(src, v) then return true end
        end
    elseif FW == 'qbx' then
        for _, v in ipairs(Config.Admin.Groups) do
            if IsPlayerAceAllowed(src, 'group.' .. v) then return true end
        end
    end
    return false
end

function Bridge.HasItem(src, item, count)
    count = count or 1
    if useOx then return (exports.ox_inventory:Search(src, 'count', item) or 0) >= count end
    local p = player(src)
    if not p then return false end
    if FW == 'esx' then
        local i = p.getInventoryItem(item)
        return i and (i.count or 0) >= count
    end
    local i = p.Functions.GetItemByName(item)
    return i and (i.amount or i.count or 0) >= count
end

function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if useOx then return exports.ox_inventory:RemoveItem(src, item, count) end
    local p = player(src)
    if not p then return false end
    if FW == 'esx' then p.removeInventoryItem(item, count) return true end
    return p.Functions.RemoveItem(item, count)
end

function Bridge.Notify(src, message, ntype, title)
    -- shown by the client bridge with whatever Config.Notify picks
    TriggerClientEvent('nz_cargo:notify', src, message, ntype or 'info', title)
end

-----------------------------------------------------------------
-- PHONE MESSAGES (texts from an unknown number)   Config.Phone
-- Returns true when a phone resource took the message. Otherwise the
-- player gets an on-screen phone-style message (Config.Phone.Fallback).
-----------------------------------------------------------------
local function phoneSystem()
    local want = Config.Phone.System
    if want ~= 'auto' then return want end
    for _, r in ipairs({ 'lb-phone', 'yseries', 'npwd', 'qs-smartphone', 'gksphone' }) do
        if GetResourceState(r) == 'started' then return r end
    end
    return 'none'
end

local function dbg(msg) if Config.Debug then print(('^3[nayzeee-vehiclecargo] %s^7'):format(msg)) end end

local phones = {
    -- lb-phone: SendMessage(from, to, message) needs a phone NUMBER as the sender.
    ['lb-phone'] = function(src, text)
        local lb = exports['lb-phone']
        local number = lb:GetEquippedPhoneNumber(src)
        if not number then dbg(('lb-phone: player %s has no phone equipped'):format(src)) return false end
        lb:SendMessage(tostring(Config.Phone.Number), number, text)
        if Config.Phone.Notify then
            lb:SendNotification(src, { app = 'Messages', title = Config.Phone.Sender, content = text })
        end
        dbg(('lb-phone: text sent %s -> %s'):format(Config.Phone.Number, number))
        return true
    end,
    ['npwd'] = function(src, text)
        local number = exports.npwd:getPhoneNumber(src)
        if not number then return false end
        exports.npwd:emitMessage({ senderNumber = tostring(Config.Phone.Number), targetNumber = number, message = text })
        return true
    end,
    -- Fill these in from your phone's docs (export name + arguments), then return true.
    ['yseries'] = function(src, text) return false end,
    ['qs-smartphone'] = function(src, text) return false end,
    ['gksphone'] = function(src, text) return false end,
}

function Bridge.PhoneMessage(src, text)
    if not src or not text then return end
    local sys = phoneSystem()
    local fn = phones[sys]
    local ok, handled = false, false
    if fn and GetResourceState(sys) ~= 'started' then
        dbg(('Config.Phone.System is %s but that resource is not running'):format(sys))
        fn = nil
    end
    if fn then
        ok, handled = pcall(fn, src, text)
        if not ok then print(('^1[nayzeee-vehiclecargo] %s text failed: %s^7'):format(sys, tostring(handled))) end
    end
    if not (ok and handled) and Config.Phone.Fallback then
        TriggerClientEvent('nz_cargo:sms', src, { from = Config.Phone.Sender, text = text })
    end
    return ok and handled
end

function Bridge.CountPolice()
    local count = 0
    local jobs = {}
    for _, j in ipairs(Config.Sourcing.PoliceJobs) do jobs[j] = true end
    for _, id in ipairs(GetPlayers()) do
        local job, duty = Bridge.GetJob(tonumber(id))
        if job and jobs[job] and duty then count = count + 1 end
    end
    return count
end

-----------------------------------------------------------------
-- DISPATCH   Config.Dispatch
-- data = { title, message, coords = vector3, code, blip = { sprite, colour }, plate, src }
-- src is the player the alert is about (client-side dispatch
-- resources raise the alert from that player's client).
-----------------------------------------------------------------
local function policeJobs()
    local set = {}
    for _, j in ipairs(Config.Sourcing.PoliceJobs) do set[j] = true end
    return set
end

local function dispatchSystem()
    local want = Config.Dispatch and Config.Dispatch.System or 'builtin'
    if want ~= 'auto' then return want end
    for _, r in ipairs({ 'ps-dispatch', 'cd_dispatch', 'rcore_dispatch', 'qs-dispatch' }) do
        if GetResourceState(r) == 'started' then return r end
    end
    return 'builtin'
end

local function builtin(data)
    local jobs = policeJobs()
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local job, duty = Bridge.GetJob(id)
        if job and jobs[job] and duty then TriggerClientEvent('nz_cargo:dispatch', id, data) end
    end
end

-- Server-side systems. Client-side ones go through nz_cargo:dispatchOut.
local serverSide = {
    ['rcore_dispatch'] = function(data)
        local c = data.coords
        TriggerEvent('rcore_dispatch:server:sendAlert', {
            code = data.code or '10-60', default_priority = 'high', coords = c, job = Config.Sourcing.PoliceJobs,
            text = ('%s - %s'):format(data.title or 'Alert', data.message or ''), type = 'alerts',
            blip_time = math.floor((Config.Dispatch.BlipTime or 60) / 60),
            blip = { sprite = data.blip and data.blip.sprite or 225, colour = data.blip and data.blip.colour or 1, scale = 1.0, text = data.title or 'Alert', flashes = true, radius = 0 },
        })
        return true
    end,
}
local clientSide = { ['ps-dispatch'] = true, ['cd_dispatch'] = true, ['qs-dispatch'] = true }

-- Your own dispatch. Return true when handled.
function Bridge.CustomDispatch(data)
    return false
end

function Bridge.Dispatch(data)
    local c = data.coords
    if c then data.coords = vector3(c.x, c.y, c.z) end
    data.jobs = Config.Sourcing.PoliceJobs
    data.blipTime = Config.Dispatch and Config.Dispatch.BlipTime or 60
    local sys = dispatchSystem()
    local handled = false
    if sys == 'custom' then
        local ok, r = pcall(Bridge.CustomDispatch, data)
        handled = ok and r
    elseif serverSide[sys] then
        local ok, r = pcall(serverSide[sys], data)
        handled = ok and r
    elseif clientSide[sys] then
        -- needs a player to raise it from; any online player works when nobody is tied to it
        local from = data.src or tonumber(GetPlayers()[1])
        if from then
            TriggerClientEvent('nz_cargo:dispatchOut', from, sys, data)
            handled = true
        end
    end
    if not handled then builtin(data) end
end

-- Character unload / logout hook so missions get cleaned up.
function Bridge.OnUnload(cb)
    AddEventHandler('playerDropped', function() cb(source) end)
    if FW == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) cb(src or source) end)
    else
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src or source) end)
    end
end

-----------------------------------------------------------------
-- CREW RADIO (server side)
-- Return true when you handled it here. Anything else is sent to
-- the client bridge (pma-voice, tokovoip, custom).
-----------------------------------------------------------------
local function radioSystem()
    local s = Config.Radio.System
    if s ~= 'auto' then return s end
    if GetResourceState('saltychat') == 'started' then return 'saltychat' end
    return 'client'
end

function Bridge.RadioServer(src, channel, join)
    if radioSystem() == 'saltychat' then
        local ok = pcall(function()
            if join then exports.saltychat:SetPlayerRadioChannel(src, tostring(channel), true)
            else exports.saltychat:RemovePlayerRadioChannel(src, tostring(channel)) end
        end)
        return ok
    end
    return false
end
