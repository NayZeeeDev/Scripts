-- ═══════════════════════════════════════════════════════════════
--  SERVER HELPERS - shared by every server file
--  (notify, logging, player lookups, anti-exploit checks, props, DB setup)
-- ═══════════════════════════════════════════════════════════════
ESX = exports.es_extended:getSharedObject()

local RESOURCE = GetCurrentResourceName()

-- ═══════════════════════════════════════════════════════════════
--  NOTIFY - always goes through Config.Notify on the client so
--  every message has the same NAYZEEE look
-- ═══════════════════════════════════════════════════════════════
function Notify(target, msg, type, title)
    TriggerClientEvent('nayzeee-bodybag:client:notify', target, msg, type, title)
end

function Debug(...)
    if Config.Debug then print('[' .. RESOURCE .. ':debug]', ...) end
end

-- ═══════════════════════════════════════════════════════════════
--  LOGGING - console + optional Discord webhook
-- ═══════════════════════════════════════════════════════════════
local function hexToInt(hex)
    return tonumber((hex or '#08afa2'):gsub('#', ''), 16) or 569250
end

local function sendWebhook(url, title, description, color)
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Config.UI.Title,
        embeds = { {
            title = title,
            description = description,
            color = color or hexToInt(Config.UI.Accent),
            footer = { text = RESOURCE },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- Log(src, 'BAGGED', 'John Smith')       -> console + Config.Logs.Webhook
-- Log(src, 'CK', 'John Smith', true)     -> console + Config.Logs.CKWebhook
function Log(src, action, detail, isCK)
    local who = (src and src > 0) and ('%s [%s]'):format(GetPlayerName(src) or '?', src) or 'Server'
    print(('[%s] %s | %s | %s'):format(RESOURCE, who, action, detail or ''))

    local url = Config.Logs.Webhook
    if isCK and Config.Logs.CKWebhook ~= '' then url = Config.Logs.CKWebhook end
    if url and url ~= '' then
        sendWebhook(url, action, ('**Player:** %s\n**Details:** %s'):format(who, detail or '-'),
            isCK and 0xC0392B or nil)
    end
end

-- ═══════════════════════════════════════════════════════════════
--  PLAYER LOOKUPS
-- ═══════════════════════════════════════════════════════════════
function GetCharName(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getName() or GetPlayerName(src) or 'Unknown'
end

function GetIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier
end

function IsPolice(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.job and Config.Evidence.PoliceJobs[xPlayer.job.name] == true or false
end

function IsStaff(src)
    if src == 0 then return true end -- server console
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and Config.Admin.Groups[xPlayer.getGroup()] == true or false
end

function HasItem(src, item, amount)
    local count = exports.ox_inventory:Search(src, 'count', item)
    return (type(count) == 'number' and count or 0) >= (amount or 1)
end

-- ═══════════════════════════════════════════════════════════════
--  DEATH CHECK (server-side, so a modded client can't bag living players)
-- ═══════════════════════════════════════════════════════════════
local DeadPlayers = {} -- filled by ESX's own death/spawn events

RegisterNetEvent('esx:onPlayerDeath', function() DeadPlayers[source] = true end)
RegisterNetEvent('esx:onPlayerSpawn', function() DeadPlayers[source] = nil end)
AddEventHandler('esx:playerLoaded', function(playerId) DeadPlayers[playerId] = nil end)
AddEventHandler('playerDropped', function() DeadPlayers[source] = nil end)

function IsPlayerDeadServer(id)
    local hook = Config.Hooks.IsPlayerDead and Config.Hooks.IsPlayerDead(id)
    if hook ~= nil then return hook end

    local state = Player(id).state
    -- if the ambulance script uses a statebag, trust it (it's always up to date)
    if state.dead ~= nil then return state.dead == true end         -- wasabi
    if state.isDead ~= nil then return state.isDead == true end     -- most other ambulance jobs
    local ped = GetPlayerPed(id)
    if ped ~= 0 and GetEntityHealth(ped) <= 0 then return true end  -- plain GTA death
    return DeadPlayers[id] == true                                  -- esx_ambulancejob
end

-- ═══════════════════════════════════════════════════════════════
--  DISTANCE CHECKS
-- ═══════════════════════════════════════════════════════════════
function ToVec3(v)
    if type(v) ~= 'vector3' and type(v) ~= 'table' then return nil end
    if not tonumber(v.x) or not tonumber(v.y) or not tonumber(v.z) then return nil end
    return vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
end

function GetPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function IsNear(src, coords, maxDist)
    local me = GetPlayerCoords(src)
    coords = ToVec3(coords)
    return me ~= nil and coords ~= nil and #(me - coords) <= (maxDist or Config.MaxInteractDistance)
end

function IsNearEntity(src, entity, maxDist)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    return IsNear(src, GetEntityCoords(entity), maxDist)
end

-- network id -> server entity handle (nil if it doesn't exist)
function EntityFromNet(netId)
    netId = tonumber(netId)
    if not netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent
end

-- ═══════════════════════════════════════════════════════════════
--  PROPS - spawned SERVER-SIDE (anti-cheat safe, never culled)
--  settle = true -> the owning client drops it onto the ground
-- ═══════════════════════════════════════════════════════════════
function SpawnProp(propKey, coords, heading, settle)
    local model = Config.Props[propKey]
    coords = ToVec3(coords)
    if not model or not coords then
        print(('[%s] ^1SpawnProp: bad prop "%s" or coords^0'):format(RESOURCE, tostring(propKey)))
        return nil
    end
    if settle == nil then settle = true end

    local obj = CreateObjectNoOffset(model, coords.x, coords.y, coords.z - (settle and 0.2 or 0.0), true, true, false)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(obj) and GetGameTimer() < timeout do Wait(10) end
    if not DoesEntityExist(obj) then
        print(('[%s] ^1FAILED to spawn prop %s^0'):format(RESOURCE, propKey))
        return nil
    end

    -- keep it alive even when no player is nearby (default OneSync behaviour deletes it)
    if SetEntityOrphanMode then SetEntityOrphanMode(obj, 2) end
    SetEntityHeading(obj, (heading or 0.0) + 0.0)
    FreezeEntityPosition(obj, true)
    if settle then Entity(obj).state:set('nzInit', true, true) end
    return obj, NetworkGetNetworkIdFromEntity(obj)
end

-- client reports the prop has been placed on the ground -> stop re-settling it
RegisterNetEvent('nayzeee-bodybag:server:settled', function(netId)
    local ent = EntityFromNet(netId)
    if ent and Entity(ent).state.nzInit then Entity(ent).state:set('nzInit', nil, true) end
end)

-- ═══════════════════════════════════════════════════════════════
--  POLICE ALERTS
--  chanceKey = key in Config.Dispatch.Chances, or nil to always send
-- ═══════════════════════════════════════════════════════════════
function PoliceAlert(coords, title, message, chanceKey)
    if chanceKey then
        if not Config.Dispatch.Enabled then return end
        if math.random(100) > (Config.Dispatch.Chances[chanceKey] or 0) then return end
    end
    coords = ToVec3(coords)
    if not coords then return end
    if Config.Hooks.PoliceAlert and Config.Hooks.PoliceAlert(coords, title, message) then return end

    for _, id in ipairs(GetPlayers()) do
        local sid = tonumber(id)
        if IsPolice(sid) then
            TriggerClientEvent('nayzeee-bodybag:client:policeAlert', sid, coords, title, message)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  DNA / EVIDENCE HELPERS
-- ═══════════════════════════════════════════════════════════════
-- Each DNA trace survives with (100 - destroyedPct)% chance
function SurvivingDna(dna, destroyedPct)
    local left = {}
    for _, name in ipairs(dna or {}) do
        if math.random(100) > (destroyedPct or 0) then left[#left + 1] = name end
    end
    return left
end

function SaveEvidence(kind, coords, sourceName, details)
    if not Config.Evidence.Enabled then return end
    MySQL.insert('INSERT INTO nayzeee_bodybag_evidence (type, coords, source_name, details) VALUES (?, ?, ?, ?)',
        { kind, json.encode({ x = coords.x, y = coords.y, z = coords.z }), sourceName, details and json.encode(details) or nil })
end

-- ═══════════════════════════════════════════════════════════════
--  DATABASE - tables are created automatically on start
--  (running sql/install.sql by hand still works too)
-- ═══════════════════════════════════════════════════════════════
local function columnExists(tbl, column)
    return (MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]], { tbl, column }) or 0) > 0
end

DatabaseReady = false

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_cks` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `identifier` VARCHAR(60) NOT NULL,
        `char_name` VARCHAR(100) DEFAULT NULL,
        `reason` TEXT DEFAULT NULL,
        `requested_by` VARCHAR(100) DEFAULT NULL,
        `forced` TINYINT(1) DEFAULT 0,
        `created` DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_identifier` (`identifier`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_graves` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `coords` TEXT NOT NULL,
        `heading` FLOAT DEFAULT 0.0,
        `data` TEXT DEFAULT NULL,
        `cemetery` TINYINT(1) DEFAULT 0,
        `created` DATETIME DEFAULT CURRENT_TIMESTAMP)]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_evidence` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `type` VARCHAR(30) NOT NULL,
        `coords` TEXT NOT NULL,
        `source_name` VARCHAR(100) DEFAULT NULL,
        `details` TEXT DEFAULT NULL,
        `created` DATETIME DEFAULT CURRENT_TIMESTAMP)]])

    -- columns added in later versions (works on MySQL AND MariaDB)
    if not columnExists('nayzeee_bodybag_evidence', 'details') then
        MySQL.query.await('ALTER TABLE `nayzeee_bodybag_evidence` ADD COLUMN `details` TEXT DEFAULT NULL')
    end
    if not columnExists('users', 'ck_locked') then
        MySQL.query.await('ALTER TABLE `users` ADD COLUMN `ck_locked` TINYINT(1) DEFAULT 0')
    end

    DatabaseReady = true
    TriggerEvent('nayzeee-bodybag:databaseReady')
end)
