-- Server side commands (they work from the server console too).
local C = Config.Commands

local function reply(src, msg, kind)
    if src == 0 then print('[nayzeee-admin] ' .. msg) else NZ.Notify(src, msg, kind or 'info') end
end

--- perm: a permission, a list (any of) or false (any staff member)
local function allowed(src, perm)
    if src == 0 then return true end
    if not NZ.Staff[src] then return false end
    if perm == false then return true end
    if type(perm) == 'table' then
        for _, p in ipairs(perm) do if NZ.HasPerm(src, p) then return true end end
        return false
    end
    return NZ.HasPerm(src, perm)
end

local function register(key, perm, fn)
    local c = C[key]
    if not c or not c.enabled then return end
    RegisterCommand(c.name, function(src, args)
        if not allowed(src, perm) then return reply(src, 'You do not have permission.', 'error') end
        fn(src, args)
    end, false)
end

local function rest(args, from) return table.concat(args, ' ', from) end

register('kick', 'player.kick', function(src, a)
    if not tonumber(a[1]) then return reply(src, 'Usage: /' .. C.kick.name .. ' id reason', 'error') end
    local ok, err = NZ.Kick(src, a[1], rest(a, 2))
    if ok then reply(src, 'Player kicked.', 'success') else reply(src, err or 'Could not kick that player.', 'error') end
end)

register('ban', 'player.ban', function(src, a)
    local dur = NZ.ParseDuration(a[2])
    if not tonumber(a[1]) or not a[2] or dur == false then return reply(src, 'Usage: /' .. C.ban.name .. ' id 1d2h|perm reason', 'error') end
    local id, err = NZ.Ban(src, a[1], rest(a, 3), dur)
    if id then reply(src, 'Ban #' .. id .. ' created.', 'success') else reply(src, err or 'Could not ban that player.', 'error') end
end)

register('warn', 'player.warn', function(src, a)
    if not tonumber(a[1]) or not a[2] then return reply(src, 'Usage: /' .. C.warn.name .. ' id reason', 'error') end
    local ok, err = NZ.Warn(src, a[1], rest(a, 2))
    if ok then reply(src, 'Warning sent.', 'success') else reply(src, err or 'Could not warn that player.', 'error') end
end)

register('jail', 'player.jail', function(src, a)
    local dur = NZ.ParseDuration(a[2])
    if not tonumber(a[1]) or not dur then return reply(src, 'Usage: /' .. C.jail.name .. ' id 30m reason', 'error') end
    local ok, err = NZ.Jail(src, a[1], dur, rest(a, 3))
    reply(src, ok and 'Player jailed.' or err, ok and 'success' or 'error')
end)

register('unjail', 'player.jail_remove', function(src, a)
    local ok = NZ.Release(tonumber(a[1]) or -1, src ~= 0 and src or nil)
    reply(src, ok and 'Player released.' or 'That player is not jailed.', ok and 'success' or 'error')
end)

register('bring', 'player.teleport', function(src, a)
    if src == 0 then return end
    if not NZ.Bring(src, a[1]) then reply(src, 'Could not bring that player.', 'error') end
end)

register('goto', 'player.teleport', function(src, a)
    if src == 0 then return end
    local tid = tonumber(a[1])
    if not tid or not GetPlayerName(tid) then return reply(src, 'Player not found.', 'error') end
    SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(tid))
    NZ.Teleport(src, NZ.CoordsOf(tid))
    NZ.Log('staff', 'goto', src, tid, 'teleported to player')
end)

-- /revive [id] and /heal [id], no id = yourself
local function selfOrTarget(src, a, selfPerm, otherPerm, action)
    local tid = tonumber(a[1])
    if not tid then
        if src == 0 then return reply(src, 'Usage: /' .. C[action].name .. ' id') end
        tid = src
    end
    if tid == src and not NZ.HasPerm(src, selfPerm) and not NZ.HasPerm(src, otherPerm) then return reply(src, 'You do not have permission.', 'error') end
    if tid ~= src and not NZ.HasPerm(src, otherPerm) then return reply(src, 'You do not have permission.', 'error') end
    if tid == src then
        if action == 'revive' then Bridge.Revive(src) else TriggerClientEvent('nzadmin:cl:do', src, 'heal') end
        NZ.Log('staff', 'self_' .. action, src, nil, action .. 'd themselves')
        return reply(src, action == 'revive' and 'Revived.' or 'Healed.', 'success')
    end
    local ok, err = NZ.RunAction(src, tid, action)
    reply(src, ok and (action == 'revive' and 'Player revived.' or 'Player healed.') or err, ok and 'success' or 'error')
end
register('revive', { 'player.revive', 'self.revive' }, function(src, a) selfOrTarget(src, a, 'self.revive', 'player.revive', 'revive') end)
register('heal', { 'player.heal', 'self.revive' }, function(src, a) selfOrTarget(src, a, 'self.revive', 'player.heal', 'heal') end)

-- /sc message · reaches every staff member online, on or off duty
register('staffchat', false, function(src, a)
    local msg = NZ.Trim(rest(a, 1), 300)
    if msg == '' then return reply(src, 'Usage: /' .. C.staffchat.name .. ' message', 'error') end
    local from = NZ.Name(src)
    NZ.ToStaff('nzadmin:cl:staffChat', { { from = from, id = src, message = msg, color = src ~= 0 and NZ.Staff[src] and NZ.Staff[src].group.color or nil } })
    if src == 0 then print(('[staff] %s: %s'):format(from, msg)) end
    NZ.Log('staff', 'staff_chat', src, nil, msg)
end)

register('announce', 'announcements.create', function(src, a)
    local msg = rest(a, 1)
    if msg == '' then return reply(src, 'Usage: /' .. C.announce.name .. ' message', 'error') end
    NZ.Announce(src, { message = msg })
end)

-- /tp id | /tp x y z
register('tp', 'self.teleport', function(src, a)
    if src == 0 then return end
    if #a >= 3 then
        local x, y, z = tonumber((a[1]:gsub(',', ''))), tonumber((a[2]:gsub(',', ''))), tonumber((a[3]:gsub(',', '')))
        if x and y and z then return NZ.Teleport(src, { x = x, y = y, z = z }) end
    end
    local tid = tonumber(a[1])
    if tid and GetPlayerName(tid) and NZ.HasPerm(src, 'player.teleport') then
        SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(tid))
        return NZ.Teleport(src, NZ.CoordsOf(tid))
    end
    reply(src, 'Usage: /' .. C.tp.name .. ' id  or  /' .. C.tp.name .. ' x y z', 'error')
end)

if C.staff.enabled then
    RegisterCommand(C.staff.name, function(src)
        local list = {}
        for id, s in pairs(NZ.Staff) do
            if s.duty then list[#list + 1] = ('%s (%s)'):format(NZ.Name(id), s.group.label) end
        end
        reply(src, #list > 0 and ('On duty: ' .. table.concat(list, ', ')) or 'No staff on duty right now.')
    end, false)
end

if C.duty.enabled then
    RegisterCommand(C.duty.name, function(src)
        if not NZ.Staff[src] then return end
        local s = NZ.Staff[src]
        NZ.SetDuty(src, not s.duty)
        reply(src, s.duty and 'You are on duty.' or 'You are off duty.', 'success')
    end, false)
end
