-- ═══════════════════════════════════════════════════════════
--  ADMIN
-- ═══════════════════════════════════════════════════════════

local function isAdmin(src)
    return MDT.isStaff(src)
end

local function say(src, text)
    if src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'MDT', text } })
    else
        print(text)
    end
end

RegisterCommand('mdtadmin', function(src, args)
    if not isAdmin(src) then
        if src > 0 then MDT.notify(src, 'MDT', 'You do not have access to that.', 'error') end
        return
    end

    local action = (args[1] or ''):lower()

    -- /mdtadmin duty <playerId> — force someone off duty
    if action == 'duty' then
        local target = ESX.GetPlayerFromId(tonumber(args[2]))
        if not target then return say(src, 'No player online with that ID.') end
        MDT.clockOut(target.identifier)
        TriggerClientEvent('nz_mdt:dutyChanged', target.source, false, 'break')
        say(src, ('%s was taken off duty.'):format(MDT.fullName(target)))

    -- /mdtadmin callsign <playerId> <callsign>
    elseif action == 'callsign' then
        local target = ESX.GetPlayerFromId(tonumber(args[2]))
        local sign = (args[3] or ''):upper():gsub('[^%w%-]', ''):sub(1, 12)
        if not target or sign == '' then return say(src, 'Usage: /mdtadmin callsign <id> <callsign>') end
        MySQL.update.await('UPDATE nz_mdt_officers SET callsign = NULL WHERE callsign = ? AND identifier != ?', { sign, target.identifier })
        MySQL.update.await('UPDATE nz_mdt_officers SET callsign = ? WHERE identifier = ?', { sign, target.identifier })
        local info = MDT.online[target.source]
        if info then info.callsign = sign end
        MDT.push('roster:update', MDT.activeOfficers())
        say(src, ('Callsign set to %s.'):format(sign))

    -- /mdtadmin clear — close every open dispatch call
    elseif action == 'clear' then
        local n = MySQL.update.await([[
            UPDATE nz_mdt_dispatch SET status = 'closed', closed_by = 'Admin', closed_at = NOW()
            WHERE status != 'closed'
        ]]) or 0
        MySQL.update.await("UPDATE nz_mdt_officers SET status = 'available' WHERE on_duty = 1")
        for _, info in pairs(MDT.online) do if info.onDuty then info.status = 'available' end end
        MDT.broadcast('dispatch:closed', { all = true })
        MDT.audit(nil, 'admin.clear', 'dispatch', nil, ('%s calls closed'):format(n))
        say(src, ('Closed %s open calls.'):format(n))

    -- /mdtadmin import — pull every ESX user into the citizen registry
    elseif action == 'import' then
        CreateThread(function()
            local users = MySQL.query.await([[
                SELECT u.identifier FROM users u
                LEFT JOIN nz_mdt_citizens c ON c.identifier = u.identifier
                WHERE c.id IS NULL LIMIT 5000
            ]]) or {}
            local made = 0
            for _, u in ipairs(users) do
                if MDT.importCitizen(u.identifier, true) then made = made + 1 end
                Wait(5)
            end
            say(src, ('Imported %s citizen records.'):format(made))
        end)
        say(src, 'Import running in the background...')

    -- /mdtadmin perms <playerId>
    elseif action == 'perms' then
        local target = tonumber(args[2]) or src
        local session = MDT.getSession(target)
        if not session then return say(src, 'That player is not on a department roster.') end
        local list = {}
        for k in pairs(session.perms) do list[#list + 1] = k end
        table.sort(list)
        say(src, ('^5%s^7 · %s / %s'):format(session.name, session.department, session.rank))
        say(src, table.concat(list, ', '))

    -- /mdtadmin stats
    elseif action == 'stats' then
        local rows = {
            { 'Citizens',  MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_citizens') or 0 },
            { 'Vehicles',  MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_vehicles') or 0 },
            { 'Weapons',   MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_weapons') or 0 },
            { 'Incidents', MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_incidents') or 0 },
            { 'Evidence',  MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_evidence') or 0 },
            { 'Open calls',MySQL.scalar.await("SELECT COUNT(*) FROM nz_mdt_dispatch WHERE status != 'closed'") or 0 },
            { 'On duty',   MySQL.scalar.await('SELECT COUNT(*) FROM nz_mdt_officers WHERE on_duty = 1') or 0 }
        }
        for _, r in ipairs(rows) do say(src, ('%s: %s'):format(r[1], r[2])) end

    else
        say(src, 'Commands: /mdtadmin duty <id> · callsign <id> <sign> · clear · import · perms [id] · stats')
    end
end, false)
