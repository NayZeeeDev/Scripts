NZ.Flags = {}          -- license -> { flagId = true }
NZ.Frozen = {}         -- src -> true
NZ.Cuffed = {}         -- src -> true
NZ.Calls  = {}         -- target src -> staff src
NZ.SpectateBucket = {} -- staff src -> original bucket

AddEventHandler('nzadmin:sv:booted', function()
    for _, r in ipairs(MySQL.query.await('SELECT license, flag FROM nz_admin_flags') or {}) do
        NZ.Flags[r.license] = NZ.Flags[r.license] or {}
        NZ.Flags[r.license][r.flag] = true
    end
end)

local function flagsOf(lic)
    local out = {}
    for f in pairs(NZ.Flags[lic] or {}) do out[#out + 1] = f end
    return out
end

local function coordsOf(id)
    local c = GetEntityCoords(GetPlayerPed(id))
    return { x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z), w = NZ.Round(GetEntityHeading(GetPlayerPed(id))) }
end
NZ.CoordsOf = coordsOf

-- ─── list ───────────────────────────────────────────────────────────────
function NZ.PlayerRow(id)
    local o = NZ.Online[id] or {}
    local s = NZ.Staff[id]
    local job = Bridge.GetJob(id)
    local ped = GetPlayerPed(id)
    return {
        id = id, name = GetPlayerName(id), char = Bridge.CharName(id), license = o.license,
        job = job.label, jobGrade = job.gradeLabel, ping = GetPlayerPing(id), joined = o.joined,
        staff = s and { label = s.group.label, color = s.group.color, duty = s.duty } or nil,
        flags = flagsOf(o.license), bucket = GetPlayerRoutingBucket(id),
        health = ped ~= 0 and GetEntityHealth(ped) or 0, armour = ped ~= 0 and GetPedArmour(ped) or 0,
        jailed = NZ.Jailed and NZ.Jailed[id] ~= nil, frozen = NZ.Frozen[id] == true, cuffed = NZ.Cuffed[id] == true,
        loaded = Bridge.IsLoaded(id),
    }
end

NZ.Route('players:list', false, function()
    local out = {}
    for _, id in ipairs(GetPlayers()) do out[#out + 1] = NZ.PlayerRow(tonumber(id)) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

-- ─── profile ────────────────────────────────────────────────────────────
NZ.Route('player:get', false, function(src, d)
    local id, err = NZ.Target(src, d.id, false); if not id then return false, err end
    local row = NZ.PlayerRow(id)
    local lic = row.license
    row.coords = coordsOf(id)
    row.gang = Bridge.GetGang(id)
    row.fwGroup = Bridge.GetGroup(id)
    row.charId = Bridge.CharId(id)
    row.vehicle = GetVehiclePedIsIn(GetPlayerPed(id), false) ~= 0
    if NZ.HasPerm(src, 'player.view_identifiers') then
        local ids = NZ.Ids(id)
        if not NZ.HasPerm(src, 'player.view_ip') then ids.ip = nil end
        row.identifiers = ids
        row.tokens = GetNumPlayerTokens(id)
    end
    if NZ.HasPerm(src, 'player.view_money_accounts') then row.accounts = Bridge.GetAccounts(id) end
    local seen = MySQL.single.await('SELECT UNIX_TIMESTAMP(first_seen) AS first, playtime, sessions FROM nz_admin_players WHERE license = ?', { lic }) or {}
    row.firstSeen, row.playtime, row.sessions = seen.first, (seen.playtime or 0) + (os.time() - (row.joined or os.time())), seen.sessions
    row.warnings = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_warnings WHERE license = ?', { lic }) or 0
    row.bans = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_bans WHERE license = ?', { lic }) or 0
    row.notesCount = MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_notes WHERE license = ?', { lic }) or 0
    row.jail = NZ.Jailed and NZ.Jailed[id] and NZ.JailInfo(id) or nil
    row.inCall = NZ.Calls[id] ~= nil
    return row
end)

NZ.Route('player:history', false, function(src, d)
    local lic = d.license; if not lic then return false end
    local out = {}
    if NZ.HasPerm(src, 'moderation.view.warnings') or NZ.HasPerm(src, 'player.warn') then
        out.warnings = MySQL.query.await('SELECT id, reason, staff_name, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_warnings WHERE license = ? ORDER BY id DESC', { lic })
    end
    if NZ.HasPerm(src, 'moderation.view.bans') or NZ.HasPerm(src, 'player.ban') then
        out.bans = MySQL.query.await('SELECT id, reason, staff_name, active, UNIX_TIMESTAMP(expires_at) AS expires, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_bans WHERE license = ? ORDER BY id DESC', { lic })
    end
    if NZ.HasPerm(src, 'player.view_notes') then
        out.notes = MySQL.query.await('SELECT id, text, staff_name, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_notes WHERE license = ? ORDER BY id DESC', { lic })
    end
    if NZ.HasPerm(src, 'logs.view') then
        out.timeline = MySQL.query.await('SELECT category, action, staff_name, message, UNIX_TIMESTAMP(created_at) AS time FROM nz_admin_logs WHERE target_license = ? ORDER BY id DESC LIMIT 60', { lic })
    end
    return out
end)

-- ─── notes / flags ──────────────────────────────────────────────────────
NZ.Route('player:note:add', 'player.create_notes', function(src, d)
    local text = NZ.Trim(d.text, 1000); if text == '' or not d.license then return false, 'Write something first.' end
    MySQL.insert.await('INSERT INTO nz_admin_notes (license, text, staff_name) VALUES (?, ?, ?)', { d.license, text, NZ.Name(src) })
    NZ.Log('staff', 'note_added', src, { name = d.name, license = d.license }, text)
    return true
end)

NZ.Route('player:note:delete', 'player.delete_notes', function(src, d)
    local id = tonumber(d.id); if not id then return false end
    local row = MySQL.single.await('SELECT license, text FROM nz_admin_notes WHERE id = ?', { id })
    if not row then return false, 'Note not found.' end
    MySQL.update.await('DELETE FROM nz_admin_notes WHERE id = ?', { id })
    NZ.Log('staff', 'note_deleted', src, { license = row.license }, row.text)
    return true
end)

NZ.Route('player:flag', 'player.flags', function(src, d)
    local lic, flag = d.license, d.flag
    local valid = false
    for _, f in ipairs(Config.Flags) do if f.id == flag then valid = true end end
    if not lic or not valid then return false end
    NZ.Flags[lic] = NZ.Flags[lic] or {}
    if NZ.Flags[lic][flag] then
        NZ.Flags[lic][flag] = nil
        MySQL.update.await('DELETE FROM nz_admin_flags WHERE license = ? AND flag = ?', { lic, flag })
    else
        NZ.Flags[lic][flag] = true
        MySQL.insert.await('INSERT IGNORE INTO nz_admin_flags (license, flag, staff_name) VALUES (?, ?, ?)', { lic, flag, NZ.Name(src) })
    end
    NZ.Log('staff', 'flag', src, { name = d.name, license = lic }, ('%s flag %s'):format(NZ.Flags[lic][flag] and 'added' or 'removed', flag))
    return flagsOf(lic)
end)

-- names overlay asks for this while it is on (every 10s), so flags never replicate to normal players
NZ.Route('names:meta', { 'self.player_names', 'self.player_ids' }, function()
    local out = {}
    for src, o in pairs(NZ.Online) do
        local f = flagsOf(o.license)
        local s = NZ.Staff[src]
        if #f > 0 or s then out[tostring(src)] = { flags = f, staff = s and s.group.color or nil } end
    end
    return out
end)

-- ─── actions ────────────────────────────────────────────────────────────
local simple = {
    revive  = { 'player.revive', function(id) Bridge.Revive(id) end },
    heal    = { 'player.heal', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'heal') end },
    armour  = { 'player.give_armor', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'armour') end },
    feed    = { 'player.give_food_and_water', function(id) Bridge.FeedPlayer(id) end },
    kill    = { 'player.kill', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'kill') end },
    slap    = { 'player.slap', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'slap') end },
    ragdoll = { 'player.ragdoll', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'ragdoll') end },
    burn    = { 'player.burn', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'burn') end },
    explode = { 'player.explode', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'explode') end },
    unarm   = { 'player.unarm', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'unarm') end },
    resetped= { 'player.change_ped', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'resetPed') end },
    clothing= { 'player.clothing_menu', function(id) TriggerClientEvent('nzadmin:cl:do', id, 'clothing') end },
    freeze  = { 'player.freeze', function(id)
        NZ.Frozen[id] = not NZ.Frozen[id] or nil
        TriggerClientEvent('nzadmin:cl:do', id, 'freeze', { state = NZ.Frozen[id] == true })
        return NZ.Frozen[id] and 'frozen' or 'unfrozen'
    end },
    cuff    = { 'player.handcuff', function(id)
        NZ.Cuffed[id] = not NZ.Cuffed[id] or nil
        TriggerClientEvent('nzadmin:cl:do', id, 'cuff', { state = NZ.Cuffed[id] == true })
        return NZ.Cuffed[id] and 'cuffed' or 'uncuffed'
    end },
}
NZ.SimpleActions = simple

--- Run one action on one player. Returns ok, message.
function NZ.RunAction(src, id, action, d)
    local def = simple[action]
    if def then
        if not NZ.HasPerm(src, def[1]) then return false, 'No permission.' end
        local tid, err = NZ.Target(src, id, action ~= 'revive' and action ~= 'heal' and action ~= 'feed' and action ~= 'armour')
        if not tid then return false, err end
        local extra = def[2](tid)
        NZ.Log('staff', action, src, tid, ('%s %s'):format(action, extra or ''))
        return true
    end
    return false, 'Unknown action'
end

NZ.Route('player:action', false, function(src, d)
    local ok, err = NZ.RunAction(src, d.id, d.action, d)
    if not ok then return false, err end
    return true
end)

NZ.Route('players:bulk', false, function(src, d)
    local done, failed = 0, 0
    for _, id in ipairs(d.ids or {}) do
        local ok
        if d.action == 'kick' then ok = NZ.HasPerm(src, 'player.kick') and NZ.Kick(src, id, d.reason)
        elseif d.action == 'bring' then ok = NZ.HasPerm(src, 'player.teleport') and NZ.Bring(src, id)
        elseif d.action == 'notify' then ok = NZ.HasPerm(src, 'player.notify') and NZ.Message(src, id, d.message)
        elseif d.action == 'warn' then ok = NZ.HasPerm(src, 'player.warn') and NZ.Warn(src, id, d.reason)
        else ok = NZ.RunAction(src, id, d.action, d) end
        if ok then done = done + 1 else failed = failed + 1 end
    end
    return { done = done, failed = failed }
end)

-- revive everyone in a radius around the staff member
NZ.Route('player:revive_radius', 'player.revive', function(src, d)
    local me = GetEntityCoords(GetPlayerPed(src))
    local r, n = math.min(500.0, math.max(1.0, tonumber(d.radius) or 25.0)), 0
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if #(GetEntityCoords(GetPlayerPed(id)) - me) <= r then Bridge.Revive(id); n = n + 1 end
    end
    NZ.Log('staff', 'revive_radius', src, nil, ('revived %d players in %sm'):format(n, r), me)
    return n
end)

function NZ.Message(src, id, msg)
    id = tonumber(id); msg = NZ.Trim(msg, 300)
    if not id or not GetPlayerName(id) or msg == '' then return false end
    TriggerClientEvent('nzadmin:cl:staffMessage', id, { from = NZ.Name(src), message = msg })
    NZ.Log('staff', 'message', src, id, msg)
    return true
end

NZ.Route('player:message', 'player.notify', function(src, d) return NZ.Message(src, d.id, d.message) end)

-- ─── teleport ───────────────────────────────────────────────────────────
function NZ.Bring(src, id)
    local tid = NZ.Target(src, id); if not tid or tid == src then return false end
    SetPlayerRoutingBucket(tid, GetPlayerRoutingBucket(src))
    NZ.Teleport(tid, coordsOf(src))
    NZ.Log('staff', 'bring', src, tid, 'brought player', coordsOf(src))
    return true
end

NZ.Route('player:goto', 'player.teleport', function(src, d)
    local tid, err = NZ.Target(src, d.id, false); if not tid then return false, err end
    SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(tid))
    NZ.Teleport(src, coordsOf(tid))
    NZ.Log('staff', 'goto', src, tid, 'teleported to player')
    return true
end)

NZ.Route('player:bring', 'player.teleport', function(src, d) return NZ.Bring(src, d.id) or false, 'Could not bring' end)

NZ.Route('player:sendto', 'player.teleport', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local c = d.coords
    if d.to then local t2 = tonumber(d.to); if not t2 or not GetPlayerName(t2) then return false, 'Destination player is offline.' end; c = coordsOf(t2); SetPlayerRoutingBucket(tid, GetPlayerRoutingBucket(t2)) end
    if type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) then return false, 'Invalid coords.' end
    c = { x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z), w = tonumber(c.w) }
    TriggerClientEvent('nzadmin:cl:teleport', tid, c, c.z == nil)
    if Hooks and Hooks.AllowMovement then pcall(Hooks.AllowMovement, tid, 5) end
    NZ.Log('staff', 'send', src, tid, ('sent player to %.1f %.1f %.1f'):format(c.x, c.y, c.z or 0), c)
    return true
end)

NZ.Route('player:back', 'player.teleport', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    TriggerClientEvent('nzadmin:cl:do', tid, 'back')
    return true
end)

NZ.Route('player:seat', 'player.teleport', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    if d.mode == 'mine' then
        local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
        if veh == 0 then return false, 'You are not in a vehicle.' end
        TriggerClientEvent('nzadmin:cl:do', tid, 'seatIn', { net = NetworkGetNetworkIdFromEntity(veh) })
    else
        local veh = GetVehiclePedIsIn(GetPlayerPed(tid), false)
        if veh == 0 then return false, 'They are not in a vehicle.' end
        TriggerClientEvent('nzadmin:cl:do', src, 'seatIn', { net = NetworkGetNetworkIdFromEntity(veh) })
    end
    return true
end)

NZ.Route('self:bucket', 'self.teleport', function(src, d)
    local b = math.max(0, math.floor(tonumber(d.bucket) or 0))
    SetPlayerRoutingBucket(src, b)
    NZ.Log('staff', 'bucket', src, nil, 'own routing bucket set to ' .. b)
    return true
end)

NZ.Route('player:bucket', 'player.routing_bucket', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local b = math.max(0, math.floor(tonumber(d.bucket) or 0))
    SetPlayerRoutingBucket(tid, b)
    NZ.Log('staff', 'bucket', src, tid, 'routing bucket set to ' .. b)
    return true
end)

-- ─── spectate ───────────────────────────────────────────────────────────
NZ.Route('player:spectate', 'player.spectate', function(src, d)
    local tid, err = NZ.Target(src, d.id, false); if not tid then return false, err end
    if tid == src then return false, 'You cannot spectate yourself.' end
    if NZ.SpectateBucket[src] == nil then NZ.SpectateBucket[src] = GetPlayerRoutingBucket(src) end
    SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(tid))
    TriggerClientEvent('nzadmin:cl:spectate', src, { id = tid, name = GetPlayerName(tid), coords = coordsOf(tid) })
    NZ.Log('staff', 'spectate', src, tid, 'started spectating')
    return true
end)

RegisterNetEvent('nzadmin:sv:spectateStop', function()
    local src = source
    if NZ.SpectateBucket[src] ~= nil then SetPlayerRoutingBucket(src, NZ.SpectateBucket[src]); NZ.SpectateBucket[src] = nil end
end)

-- spectate target switched buckets or left
lib.callback.register('nzadmin:spectateInfo', function(src, tid)
    if not NZ.HasPerm(src, 'player.spectate') then return nil end
    tid = tonumber(tid)
    if not tid or not GetPlayerName(tid) then return nil end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(tid) then SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(tid)) end
    return { coords = coordsOf(tid), name = GetPlayerName(tid), health = GetEntityHealth(GetPlayerPed(tid)), armour = GetPedArmour(GetPlayerPed(tid)) }
end)

-- ─── ped / weapons ──────────────────────────────────────────────────────
NZ.Route('player:ped', 'player.change_ped', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local model = NZ.Trim(d.model, 64); if model == '' then return false, 'Enter a ped model.' end
    TriggerClientEvent('nzadmin:cl:do', tid, 'setPed', { model = model })
    NZ.Log('staff', 'change_ped', src, tid, 'ped set to ' .. model)
    return true
end)

NZ.Route('player:weapon', { 'player.give_weapon', 'self.give_weapon' }, function(src, d)
    local tid = tonumber(d.id) or src
    if tid ~= src and not NZ.HasPerm(src, 'player.give_weapon') then return false, 'No permission.' end
    if tid == src and not NZ.HasPerm(src, 'self.give_weapon') then return false, 'No permission.' end
    local tgt, err = NZ.Target(src, tid); if not tgt then return false, err end
    local weapon = NZ.Trim(d.weapon, 48):upper()
    if not weapon:find('^WEAPON_') then weapon = 'WEAPON_' .. weapon end
    if Bridge.inv == 'ox_inventory' then
        local ok = exports.ox_inventory:AddItem(tgt, weapon, 1)
        if ok and (tonumber(d.ammo) or 0) > 0 then
            local ammo = exports.ox_inventory:Items(weapon)
            ammo = ammo and ammo.ammoname
            if ammo then exports.ox_inventory:AddItem(tgt, ammo, math.floor(d.ammo)) end
        end
        if not ok then return false, 'Could not give that weapon.' end
    else
        TriggerClientEvent('nzadmin:cl:do', tgt, 'giveWeapon', { weapon = weapon, ammo = tonumber(d.ammo) or 250 })
    end
    NZ.Log('staff', 'give_weapon', src, tgt, weapon)
    return true
end)

-- ─── job / group / money ────────────────────────────────────────────────
NZ.Route('jobs:list', false, function() return { jobs = Bridge.GetJobs(), gangs = Bridge.GetGangs() } end)

NZ.Route('player:job', 'player.update_job', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local name = NZ.Trim(d.name, 50); if name == '' then return false, 'Pick a job.' end
    d.name = name
    local ok
    if d.gang then ok = Bridge.SetGang(tid, name, tonumber(d.grade) or 0)
    else ok = Bridge.SetJob(tid, name, tonumber(d.grade) or 0) end
    if not ok then return false, d.gang and 'That gang or grade does not exist.' or 'That job or grade does not exist.' end
    NZ.Log('staff', d.gang and 'set_gang' or 'set_job', src, tid, ('%s %s grade %s'):format(d.gang and 'gang' or 'job', d.name, d.grade))
    return true
end)

NZ.Route('player:group', 'player.set_group', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local group = NZ.Trim(d.group, 32); if group == '' then return false, 'Enter a group.' end
    if not Bridge.SetGroup(tid, group) then return false, 'Not supported on this framework.' end
    NZ.Log('staff', 'set_group', src, tid, 'framework group set to ' .. group)
    return true
end)

NZ.Route('player:account', 'player.manage_accounts', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local amount = tonumber(d.amount); if not amount or amount < 0 then return false, 'Invalid amount.' end
    local before
    for _, a in ipairs(Bridge.GetAccounts(tid)) do if a.name == d.account then before = a.money end end
    if before == nil then return false, 'Unknown account.' end
    if not Bridge.SetAccount(tid, d.account, amount) then return false, 'Could not update that account.' end
    NZ.Log('money', 'set_account', src, tid, ('%s: %s -> %s'):format(d.account, before or '?', math.floor(amount)))
    return Bridge.GetAccounts(tid)
end)

-- ─── inventory ──────────────────────────────────────────────────────────
NZ.Route('player:inventory', 'inventory.view', function(src, d)
    local tid, err = NZ.Target(src, d.id, false); if not tid then return false, err end
    return { items = Bridge.GetItems(tid), images = Config.ItemImages }
end)

NZ.Route('player:inventory:open', 'inventory.view', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    if not Bridge.OpenInventory(src, tid) then return false, 'Your inventory resource does not support this.' end
    NZ.Log('staff', 'open_inventory', src, tid, 'opened inventory')
    return true
end)

NZ.Route('player:item:give', 'inventory.give', function(src, d)
    local tid, err = NZ.Target(src, d.id or src); if not tid then return false, err end
    d.item = NZ.Trim(d.item, 64); if d.item == '' then return false, 'Pick an item.' end
    d.count = math.max(1, math.floor(tonumber(d.count) or 1))
    local ok, why = Bridge.AddItem(tid, d.item, d.count)
    if not ok then return false, why == 'cannot_carry' and 'They cannot carry that.' or 'Could not give the item.' end
    NZ.Log('staff', 'give_item', src, tid, ('%sx %s'):format(d.count, d.item))
    return Bridge.GetItems(tid)
end)

NZ.Route('player:item:remove', 'inventory.remove', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    d.item = NZ.Trim(d.item, 64); if d.item == '' then return false, 'Pick an item.' end
    d.count = math.max(1, math.floor(tonumber(d.count) or 1))
    if not Bridge.RemoveItem(tid, d.item, d.count, d.slot) then return false, 'Could not remove the item.' end
    NZ.Log('staff', 'remove_item', src, tid, ('%sx %s'):format(d.count, d.item))
    return Bridge.GetItems(tid)
end)

NZ.Route('items:list', { 'inventory.give', 'items_database.view' }, function()
    return { items = Bridge.GetItemList(), images = Config.ItemImages }
end)

NZ.Route('items:holders', 'items_database.view', function(src, d)
    if type(d.item) ~= 'string' or d.item == '' then return false, 'Pick an item.' end
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local n = Bridge.CountItem(id, d.item)
        if n > 0 then out[#out + 1] = { id = id, name = GetPlayerName(id), char = Bridge.CharName(id), count = n } end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end)

-- ─── screenshot / call / character ──────────────────────────────────────
NZ.Route('player:screenshot', 'player.screenshot', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    if Config.Integrations.Screenshot == 'none' or GetResourceState('screenshot-basic') ~= 'started' then return false, 'screenshot-basic is not running.' end
    exports['screenshot-basic']:requestClientScreenshot(tid, { encoding = 'jpg', quality = 0.7 }, function(e, data)
        if e or not data then NZ.Notify(src, 'Screenshot failed.', 'error'); return end
        TriggerClientEvent('nzadmin:cl:push', src, 'screenshot', { id = tid, name = GetPlayerName(tid), image = data, time = os.time() })
    end)
    NZ.Log('screenshots', 'screenshot', src, tid, 'took a screenshot')
    return true
end)

NZ.Route('player:call', 'player.staff_call', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    if Config.Integrations.Voice ~= 'pma-voice' or GetResourceState('pma-voice') ~= 'started' then return false, 'pma-voice is not running.' end
    if NZ.Calls[tid] then
        local staff = NZ.Calls[tid]
        NZ.Calls[tid] = nil
        exports['pma-voice']:setPlayerCall(tid, 0)
        local busy = false -- keep the staff member in the channel while they still have someone else in it
        for _, s in pairs(NZ.Calls) do if s == staff then busy = true end end
        if not busy and GetPlayerName(staff) then exports['pma-voice']:setPlayerCall(staff, 0) end
        TriggerClientEvent('nzadmin:cl:staffMessage', tid, { from = NZ.Name(src), message = 'Staff call ended.' })
        NZ.Log('staff', 'staff_call_end', src, tid, 'ended a staff call')
        return 'ended'
    end
    local channel = Config.Integrations.StaffCallChannel + src
    exports['pma-voice']:setPlayerCall(src, channel)
    exports['pma-voice']:setPlayerCall(tid, channel)
    NZ.Calls[tid] = src
    TriggerClientEvent('nzadmin:cl:staffMessage', tid, { from = NZ.Name(src), message = 'You have been pulled into a private call with staff.' })
    NZ.Log('staff', 'staff_call', src, tid, 'started a staff call')
    return 'started'
end)

NZ.Route('player:delete_character', 'player.delete_character', function(src, d)
    local tid, err = NZ.Target(src, d.id); if not tid then return false, err end
    local name, charId = Bridge.CharName(tid), Bridge.CharId(tid)
    NZ.Log('moderation', 'delete_character', src, tid, ('deleted character %s (%s)'):format(name, charId))
    Bridge.DeleteCharacter(tid)
    return true
end)

AddEventHandler('nzadmin:sv:dropped', function(src)
    NZ.Frozen[src], NZ.Cuffed[src], NZ.SpectateBucket[src] = nil, nil, nil
    local ended = {}
    for t, s in pairs(NZ.Calls) do
        if t == src or s == src then ended[#ended + 1] = t end
    end
    for _, t in ipairs(ended) do
        local s = NZ.Calls[t]
        NZ.Calls[t] = nil
        pcall(function()
            if GetPlayerName(t) then exports['pma-voice']:setPlayerCall(t, 0) end
            if GetPlayerName(s) then exports['pma-voice']:setPlayerCall(s, 0) end
        end)
    end
end)

-- ─── self helpers that need the server ──────────────────────────────────
NZ.Route('self:revive', 'self.revive', function(src) Bridge.Revive(src); return true end)
NZ.Route('self:feed', 'self.revive', function(src) Bridge.FeedPlayer(src); return true end)

RegisterNetEvent('nzadmin:sv:movement', function(seconds)
    local src = source
    if NZ.Staff[src] and Hooks and Hooks.AllowMovement then Hooks.AllowMovement(src, tonumber(seconds) or 5) end
end)

lib.callback.register('nzadmin:ownedPlate', function(_, plate)
    return Bridge.PlateTaken(plate)
end)
