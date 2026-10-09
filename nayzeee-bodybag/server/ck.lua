-- ═══════════════════════════════════════════════════════════════
--  CK (CHARACTER KILL) SYSTEM
--  Logs the CK, kicks the player, THEN deletes ONLY that character's
--  DB rows (or locks it). Other characters on the account survive.
-- ═══════════════════════════════════════════════════════════════
local pendingCKs = {}   -- victim id -> { requester, requesterName, reason, expires }
local lastRequest = {}  -- requester id -> os.time() of their last /ck

local function deleteCharacter(identifier)
    for _, t in ipairs(Config.CK.DeleteTables) do
        MySQL.update(('DELETE FROM `%s` WHERE `%s` = ?'):format(t.table, t.column), { identifier }, function(affected)
            Debug(('CK purge: %s.%s -> %s rows'):format(t.table, t.column, affected or 0))
        end)
    end
end

-- Global: called by DestroyBody (server/main.lua) on disposal, and by /ck /forceck
function PerformCK(identifier, charName, victimId, reason, requesterName, forced)
    if not identifier then return false end

    MySQL.insert('INSERT INTO nayzeee_bodybag_cks (identifier, char_name, reason, requested_by, forced) VALUES (?, ?, ?, ?, ?)',
        { identifier, charName or 'Unknown', reason or 'No reason given', requesterName or 'System', forced and 1 or 0 })

    if Config.CK.Obituary and charName then
        TriggerClientEvent('nayzeee-bodybag:client:notify', -1,
            ('%s has passed away. Rest in peace.'):format(charName), 'inform', 'OBITUARY')
    end

    -- kick FIRST so ESX saves the player before we wipe the rows (otherwise the save can race the delete)
    if victimId and GetPlayerName(victimId) then
        DropPlayer(victimId, Config.CK.KickMessage)
    end

    SetTimeout(3000, function()
        if Config.CK.DeleteCharacter then
            deleteCharacter(identifier)
        else
            MySQL.update('UPDATE users SET ck_locked = 1 WHERE identifier = ?', { identifier })
        end
    end)

    Log(nil, 'CHARACTER KILLED', ('%s [%s] | reason: %s | by: %s%s'):format(
        charName or '?', identifier, reason or 'n/a', requesterName or 'System', forced and ' (FORCED)' or ''), true)
    return true
end

-- ── /ck [id] [reason]  (player-to-player, victim must consent) ──
RegisterCommand('ck', function(src, args)
    if not Config.CK.Enabled or src == 0 then return end
    local targetId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not targetId then return Notify(src, 'Usage: /ck [id] [reason]', 'error', 'CK') end
    if targetId == src then return Notify(src, 'You can\'t CK yourself this way', 'error', 'CK') end

    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then return Notify(src, 'Player not found', 'error', 'CK') end

    local now = os.time()
    if now - (lastRequest[src] or 0) < (Config.CK.RequestCooldown or 0) then
        return Notify(src, 'Wait a moment before sending another CK request', 'error', 'CK')
    end
    lastRequest[src] = now

    if not Config.CK.VictimConsent then
        PerformCK(xTarget.identifier, xTarget.getName(), targetId, reason, GetCharName(src), false)
        return
    end

    if pendingCKs[targetId] and pendingCKs[targetId].expires > now then
        return Notify(src, 'They already have a CK request open', 'error', 'CK')
    end

    local timeout = Config.CK.RequestTimeout or 60
    pendingCKs[targetId] = { requester = src, requesterName = GetCharName(src), reason = reason, expires = now + timeout }
    TriggerClientEvent('nayzeee-bodybag:client:ckConsent', targetId, GetCharName(src), reason, timeout)
    Notify(src, 'Consent request sent...', 'inform', 'CK')

    SetTimeout(timeout * 1000, function()
        local p = pendingCKs[targetId]
        if p and p.requester == src and p.expires <= os.time() then
            pendingCKs[targetId] = nil
            TriggerClientEvent('nayzeee-bodybag:client:ckConsentExpired', targetId)
            Notify(src, 'The CK request expired.', 'error', 'CK')
        end
    end)
end, false)

RegisterNetEvent('nayzeee-bodybag:server:ckConsentResult', function(accepted)
    local victimId = source
    local pending = pendingCKs[victimId]
    if not pending or pending.expires < os.time() then return end
    pendingCKs[victimId] = nil

    if accepted == true then
        local xVictim = ESX.GetPlayerFromId(victimId)
        if xVictim then
            PerformCK(xVictim.identifier, xVictim.getName(), victimId, pending.reason, pending.requesterName, false)
            Notify(pending.requester, 'They accepted the CK.', 'success', 'CK')
        end
    else
        Notify(pending.requester, 'They declined the CK request.', 'error', 'CK')
    end
end)

-- ── /forceck [id] [reason]  (staff only) ──
RegisterCommand('forceck', function(src, args)
    if not Config.CK.Enabled or not Config.CK.StaffCanForce then return end
    if not IsStaff(src) then return Notify(src, 'No permission', 'error', 'CK') end

    local function reply(msg, type)
        if src == 0 then print('[nayzeee-bodybag] ' .. msg) else Notify(src, msg, type, 'CK') end
    end

    local targetId = tonumber(args[1])
    if not targetId then return reply('Usage: /forceck [id] [reason]', 'error') end
    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then return reply('Player not found', 'error') end

    local reason = table.concat(args, ' ', 2)
    PerformCK(xTarget.identifier, xTarget.getName(), targetId, reason ~= '' and reason or 'Staff CK',
        src == 0 and 'Console' or GetPlayerName(src), true)
    reply(('%s has been CKed.'):format(xTarget.getName()), 'success')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    pendingCKs[src] = nil
    lastRequest[src] = nil
end)

-- ── Exports ────────────────────────────────────────────────────
-- exports['nayzeee-bodybag']:IsCharacterCKd(identifier) -> true if locked (DeleteCharacter = false mode)
exports('IsCharacterCKd', function(identifier)
    local result = MySQL.scalar.await('SELECT ck_locked FROM users WHERE identifier = ?', { identifier })
    return result == 1 or result == true
end)

-- exports['nayzeee-bodybag']:GetCKHistory(identifier) -> rows from nayzeee_bodybag_cks
exports('GetCKHistory', function(identifier)
    return MySQL.query.await('SELECT * FROM nayzeee_bodybag_cks WHERE identifier = ? ORDER BY created DESC', { identifier })
end)
