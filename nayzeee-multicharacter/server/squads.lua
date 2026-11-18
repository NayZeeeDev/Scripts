if not NAYZEEE_LOCK_OK then return end

--[[
    Persistent lobby squads & couples (CONTRACT §3 rules, §4.2 payload, §5 callbacks).

    multichar_squads row: sender / target charids, sender_slot = where TARGET stands in SENDER's lobby,
    target_slot = where SENDER stands in TARGET's lobby. Rules:
      * at most one accepted couple per character, couple partner always in slot 2
      * at most Config.Squad.maxLinks accepted links per character (slots 2..4)
      * type switches are asked (pending_type / pending_by) and accepted by the other side through respond
    Every mutation runs serialised so two players can never race the rules.
]]

Squads = {}

local T = NZ.T
local SQ = Config.Squad
local MAXL = math.max(0, math.min(math.floor(tonumber(SQ.maxLinks) or 3), 3))
local LAST = 1 + MAXL                       -- highest usable slot (4 with maxLinks = 3)
local TABLE = '`multichar_squads`'

local function fail(key, ...) return { ok = false, msg = T(key, ...) } end
local function label(kind) return T(kind == 'couple' and 'sq_couple' or 'sq_squad') end

-- ── serialisation ─────────────────────────────────────────────────────────
local busy = false
local function serial(fn, ...)
    while busy do Wait(10) end
    busy = true
    local res = table.pack(pcall(fn, ...))
    busy = false
    if not res[1] then
        print(('^1[nzm] squad error: %s^0'):format(res[2]))
        return fail('t_error')
    end
    return table.unpack(res, 2, res.n)
end

-- ── queries / row helpers ─────────────────────────────────────────────────
local function byId(id) return MySQL.single.await(('SELECT * FROM %s WHERE id = ?'):format(TABLE), { id }) end

local function linksOf(charId)
    return MySQL.query.await(('SELECT * FROM %s WHERE sender = ? OR target = ?'):format(TABLE), { charId, charId }) or {}
end

local function between(a, b)
    return MySQL.single.await(('SELECT * FROM %s WHERE (sender = ? AND target = ?) OR (sender = ? AND target = ?) LIMIT 1'):format(TABLE), { a, b, b, a })
end

-- 'sender' | 'target', other charid
local function side(row, charId)
    if row.sender == charId then return 'sender', row.target end
    if row.target == charId then return 'target', row.sender end
end

local function countAccepted(rows, exceptId)
    local n = 0
    for _, r in ipairs(rows) do if r.status == 'accepted' and r.id ~= exceptId then n = n + 1 end end
    return n
end

local function hasCouple(rows, exceptId)
    for _, r in ipairs(rows) do
        if r.status == 'accepted' and r.type == 'couple' and r.id ~= exceptId then return true end
    end
    return false
end

local function countOutgoing(rows, charId)
    local n = 0
    for _, r in ipairs(rows) do if r.status == 'pending' and r.sender == charId then n = n + 1 end end
    return n
end

-- map[slot] = row of accepted links on charId's side
local function slotMap(charId, rows, exceptId)
    local used = {}
    for _, r in ipairs(rows) do
        if r.status == 'accepted' and r.id ~= exceptId then
            local s = tonumber(r[side(r, charId) .. '_slot'])
            if s then used[s] = r end
        end
    end
    return used
end

local function freeSlot(used, from)
    for s = from or 2, LAST do if not used[s] then return s end end
end

local function setSlot(q, row, charId, slot)
    q[#q + 1] = { query = ('UPDATE %s SET `%s_slot` = ?, updated_at = ? WHERE id = ?'):format(TABLE, side(row, charId)), values = { slot, os.time(), row.id } }
end

-- map[id] = normalised framework char
local function chars(ids)
    local map = {}
    if #ids == 0 then return map end
    for _, c in ipairs(Bridge.FetchByIds(ids)) do map[c.id] = c end
    return map
end

local function names(a, b)
    local m = chars({ a, b })
    return Characters.Name(m[a]), Characters.Name(m[b])
end

-- ── notifications ─────────────────────────────────────────────────────────
-- Every online player owning one of these chars (lobby list or currently playing it)
local function ownersOf(charId)
    local out = {}
    for src, s in pairs(Sessions) do
        if s.active == charId or (s.byId and s.byId[charId]) then out[#out + 1] = src end
    end
    return out
end

function Squads.Notify(...)
    for _, id in ipairs({ ... }) do
        for _, src in ipairs(ownersOf(id)) do TriggerClientEvent('nzm:client:squadChanged', src, id) end
    end
end

local function toast(charId, msg, kind)
    for _, src in ipairs(ownersOf(charId)) do TriggerClientEvent('nzm:client:notify', src, msg, kind or 'info') end
end

-- Ask the owner of charId: in-game prompt while that char is being PLAYED, lobby toast otherwise
local function invite(charId, fromName, kind, linkId)
    local src = Sessions.Playing(charId)
    if src and SQ.promptInGame and Sessions[src].stage == 'playing' then
        TriggerClientEvent('nzm:client:squadInvite', src, fromName, kind, linkId)
    else
        toast(charId, T('t_sq_got', fromName, label(kind)), 'info')
    end
end

local function log(src, action, a, b, extra)
    local fields = { { 'Action', action }, { 'Character', a or '-' }, { 'Other', b or '-' } }
    if extra then fields[#fields + 1] = { 'Type', extra } end
    Logs.Send('squad', src, fields)
end

-- ── read ──────────────────────────────────────────────────────────────────
function Squads.HasCouple(charId)
    return MySQL.scalar.await(("SELECT 1 FROM %s WHERE (sender = ? OR target = ?) AND status = 'accepted' AND type = 'couple' LIMIT 1"):format(TABLE), { charId, charId }) ~= nil
end

-- Squad payload (§4.2) for one character
function Squads.Get(charId)
    local out = { links = {}, incoming = {}, outgoing = {} }
    if not SQ.enabled or not charId then return out end
    local rows = linksOf(charId)
    if #rows == 0 then return out end

    local ids = {}
    for _, r in ipairs(rows) do local _, o = side(r, charId) ids[#ids + 1] = o end
    local others, meta, stale = chars(ids), DB.Prefs(ids), {}

    for _, r in ipairs(rows) do
        local sd, oid = side(r, charId)
        local o, m = others[oid], meta[oid] or {}
        if not o then
            stale[#stale + 1] = r.id                                -- character deleted outside of this resource
        elseif not NZ.Truthy(m.disabled) then
            local name = Characters.Name(o)
            if r.status == 'accepted' then
                local prefs = Characters.Prefs(m)
                out.links[#out.links + 1] = {
                    id          = r.id,
                    type        = r.type,
                    slot        = tonumber(r[sd .. '_slot']),
                    visible     = NZ.Truthy(r[sd .. '_visible']),
                    pendingType = r.pending_type,
                    pendingByMe = r.pending_by == charId,
                    other = {
                        id     = o.id,
                        name   = name,
                        job    = { label = o.job and o.job.label },
                        online = Sessions.Playing(o.id) ~= nil,
                        model  = o.model,
                        skin   = o.skin,
                        gender = o.gender,
                        prefs  = { pose = prefs.pose, couplePose = prefs.couplePose, weapon = prefs.weapon },
                        weapon = Weapons.Resolve(o.id, prefs.weapon, o.raw),
                    },
                }
            elseif sd == 'target' then
                out.incoming[#out.incoming + 1] = { id = r.id, type = r.type, from = { id = o.id, name = name }, at = tonumber(r.created_at) }
            else
                out.outgoing[#out.outgoing + 1] = { id = r.id, type = r.type, to = { id = o.id, name = name }, at = tonumber(r.created_at) }
            end
        end
    end

    if #stale > 0 then
        MySQL.update(('DELETE FROM %s WHERE id IN (%s)'):format(TABLE, Bridge.Marks(#stale)), stale)
    end
    table.sort(out.links, function(a, b) return (a.slot or 9) < (b.slot or 9) end)
    return out
end

-- ── search ────────────────────────────────────────────────────────────────
function Squads.Search(s, charId, query)
    query = Validate.Text(query, 64)
    if not query then return {} end

    local skip = { [charId] = true }
    for id in pairs(s.byId or {}) do skip[id] = true end
    for _, r in ipairs(linksOf(charId)) do local _, o = side(r, charId) skip[o] = true end

    local hits, seen = {}, {}
    local function add(list)
        for _, c in ipairs(list or {}) do
            if not skip[c.id] and not seen[c.id] then seen[c.id] = true hits[#hits + 1] = c end
        end
    end
    if SQ.searchBy.citizenid or SQ.searchBy.stateid then add(Bridge.Search(query, true)) end
    if SQ.searchBy.name and utf8.len(query) >= (SQ.searchMin or 3) then add(Bridge.Search(query, false)) end
    if #hits == 0 then return {} end

    -- drop disabled characters
    local ids = {}
    for _, c in ipairs(hits) do ids[#ids + 1] = c.id end
    local meta = DB.Prefs(ids)
    local out = {}
    for _, c in ipairs(hits) do
        if not NZ.Truthy(meta[c.id] and meta[c.id].disabled) then
            out[#out + 1] = { id = c.id, name = Characters.Name(c), online = Sessions.Playing(c.id) ~= nil }
            if #out >= 10 then break end
        end
    end
    return out
end

-- ── mutations ─────────────────────────────────────────────────────────────
-- Is this framework character owned by the player (any of their licenses)?
local function isMine(src, s, c)
    if not c.owner then return false end
    if c.owner == s.owner then return true end
    for _, t in ipairs({ 'license', 'license2' }) do
        local l = GetPlayerIdentifierByType(src, t)
        if l and (c.owner == l or 'license:' .. c.owner == l) then return true end
    end
    return false
end

local cooldowns = {}   -- [charId] = os.time() of the last request

function Squads.Request(src, s, charId, targetId, kind)
    if kind ~= 'squad' and kind ~= 'couple' then return fail('t_invalid') end
    if kind == 'couple' and not SQ.couples then return fail('t_invalid') end
    if not Validate.Id(targetId) then return fail('t_sq_not_found') end
    if targetId == charId or s.byId[targetId] then return fail('t_sq_self') end
    local last = cooldowns[charId]
    if last and os.time() - last < (SQ.cooldown or 0) then return fail('t_rate') end

    return serial(function()
        local target = chars({ targetId })[targetId]
        if not target then return fail('t_sq_not_found') end
        if isMine(src, s, target) then return fail('t_sq_self') end
        local tm = DB.Get(targetId)
        if tm and NZ.Truthy(tm.disabled) then return fail('t_sq_not_found') end
        if between(charId, targetId) then return fail('t_sq_exists') end

        local mine, theirs = linksOf(charId), linksOf(targetId)
        if countOutgoing(mine, charId) >= (SQ.maxPending or 5) then return fail('t_sq_pending_max') end
        if countAccepted(mine) >= MAXL then return fail('t_sq_full') end
        if countAccepted(theirs) >= MAXL then return fail('t_sq_target_full') end
        if kind == 'couple' and (hasCouple(mine) or hasCouple(theirs)) then return fail('t_sq_couple_taken') end

        local now = os.time()
        local id = MySQL.insert.await(('INSERT INTO %s (sender, target, type, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'):format(TABLE),
            { charId, targetId, kind, 'pending', now, now })
        if not id then return fail('t_error') end
        cooldowns[charId] = now

        local myName, theirName = Characters.Name(s.byId[charId]), Characters.Name(target)
        Squads.Notify(charId, targetId)
        invite(targetId, myName, kind, id)
        log(src, 'request', ('%s (%s)'):format(myName, charId), ('%s (%s)'):format(theirName, targetId), kind)
        return { ok = true, msg = T('t_sq_sent', theirName) }
    end)
end

-- slot for charId when `row` gets accepted (couple -> 2, pushing whoever stood there to a free slot)
local function place(charId, row, couple, rows, q)
    local used = slotMap(charId, rows, row.id)
    if couple then
        local holder = used[2]
        if holder then
            local free = freeSlot(used, 3)
            if not free then return nil end
            setSlot(q, holder, charId, free)
        end
        return 2
    end
    return freeSlot(used, 2)
end

local function acceptNew(row)
    local sRows, tRows = linksOf(row.sender), linksOf(row.target)
    if countAccepted(sRows, row.id) >= MAXL then return false, 't_sq_target_full' end
    if countAccepted(tRows, row.id) >= MAXL then return false, 't_sq_full' end
    local couple = row.type == 'couple'
    if couple and (hasCouple(sRows, row.id) or hasCouple(tRows, row.id)) then return false, 't_sq_couple_taken' end

    local q = {}
    local ss = place(row.sender, row, couple, sRows, q)
    local ts = place(row.target, row, couple, tRows, q)
    if not ss then return false, 't_sq_target_full' end
    if not ts then return false, 't_sq_full' end
    q[#q + 1] = { query = ("UPDATE %s SET status = 'accepted', sender_slot = ?, target_slot = ?, pending_type = NULL, pending_by = NULL, updated_at = ? WHERE id = ?"):format(TABLE),
                  values = { ss, ts, os.time(), row.id } }
    return MySQL.transaction.await(q) == true, 't_error'
end

local function applySwitch(row)
    local to = row.pending_type
    local q = {}
    if to == 'couple' then
        if not SQ.couples then return false, 't_invalid' end
        local rowsOf = { [row.sender] = linksOf(row.sender), [row.target] = linksOf(row.target) }
        if hasCouple(rowsOf[row.sender], row.id) or hasCouple(rowsOf[row.target], row.id) then return false, 't_sq_couple_taken' end
        for _, cid in ipairs({ row.sender, row.target }) do
            local cur = tonumber(row[side(row, cid) .. '_slot'])
            if cur ~= 2 then
                local used = slotMap(cid, rowsOf[cid], row.id)
                if used[2] then setSlot(q, used[2], cid, cur or freeSlot(used, 3)) end
            end
        end
        q[#q + 1] = { query = ("UPDATE %s SET type = 'couple', sender_slot = 2, target_slot = 2, pending_type = NULL, pending_by = NULL, updated_at = ? WHERE id = ?"):format(TABLE),
                      values = { os.time(), row.id } }
    else
        q[#q + 1] = { query = ('UPDATE %s SET type = ?, pending_type = NULL, pending_by = NULL, updated_at = ? WHERE id = ?'):format(TABLE),
                      values = { to, os.time(), row.id } }
    end
    return MySQL.transaction.await(q) == true, 't_error'
end

local function clearPending(row)
    MySQL.update.await(('UPDATE %s SET pending_type = NULL, pending_by = NULL, updated_at = ? WHERE id = ?'):format(TABLE), { os.time(), row.id })
end

-- accept / decline a new request (I am target) or a type switch (the other side asked)
function Squads.Respond(charId, linkId, accept, src)
    return serial(function()
        local row = byId(linkId)
        local sd, oid = row and side(row, charId)
        if not sd then return fail('t_invalid') end
        local myName, otherName = names(charId, oid)

        if row.status == 'pending' then
            if sd ~= 'target' then return fail('t_invalid') end
            if not accept then
                MySQL.update.await(('DELETE FROM %s WHERE id = ?'):format(TABLE), { row.id })
                Squads.Notify(charId, oid)
                toast(oid, T('t_sq_declined', myName), 'error')
                log(src, 'decline', myName, otherName, row.type)
                return { ok = true, msg = T('t_sq_removed') }
            end
            local ok, err = acceptNew(row)
            if not ok then return fail(err) end
            Squads.Notify(charId, oid)
            toast(oid, T('t_sq_accepted', myName), 'success')
            log(src, 'accept', myName, otherName, row.type)
            return { ok = true, msg = T('t_sq_accepted', otherName) }
        end

        if row.pending_type and row.pending_by and row.pending_by ~= charId then
            if not accept then
                clearPending(row)
                Squads.Notify(charId, oid)
                toast(oid, T('t_sq_declined', myName), 'error')
                log(src, 'switch declined', myName, otherName, row.pending_type)
                return { ok = true }
            end
            local ok, err = applySwitch(row)
            if not ok then return fail(err) end
            Squads.Notify(charId, oid)
            toast(oid, T('t_sq_switched', myName, label(row.pending_type)), 'success')
            log(src, 'switch', myName, otherName, row.pending_type)
            return { ok = true, msg = T('t_sq_switched', otherName, label(row.pending_type)) }
        end
        return fail('t_invalid')
    end)
end

-- cancel outgoing / decline incoming / remove accepted
function Squads.Remove(src, charId, linkId)
    return serial(function()
        local row = byId(linkId)
        local sd, oid = row and side(row, charId)
        if not sd then return { ok = false } end
        MySQL.update.await(('DELETE FROM %s WHERE id = ?'):format(TABLE), { row.id })
        local myName, otherName = names(charId, oid)
        Squads.Notify(charId, oid)
        if row.status == 'pending' and sd == 'target' then toast(oid, T('t_sq_declined', myName), 'error') end
        log(src, 'remove', myName, otherName, row.type)
        return { ok = true, msg = T('t_sq_removed') }
    end)
end

function Squads.Switch(src, charId, linkId, kind)
    if kind ~= 'squad' and kind ~= 'couple' then return fail('t_invalid') end
    if kind == 'couple' and not SQ.couples then return fail('t_invalid') end
    return serial(function()
        local row = byId(linkId)
        local sd, oid = row and side(row, charId)
        if not sd or row.status ~= 'accepted' or row.type == kind then return fail('t_invalid') end
        local myName, otherName = names(charId, oid)

        -- the other side already asked for exactly this: just apply it
        if row.pending_type == kind and row.pending_by == oid then
            local ok, err = applySwitch(row)
            if not ok then return fail(err) end
            Squads.Notify(charId, oid)
            toast(oid, T('t_sq_switched', myName, label(kind)), 'success')
            log(src, 'switch', myName, otherName, kind)
            return { ok = true, msg = T('t_sq_switched', otherName, label(kind)) }
        end

        if kind == 'couple' and (hasCouple(linksOf(charId), row.id) or hasCouple(linksOf(oid), row.id)) then
            return fail('t_sq_couple_taken')
        end
        MySQL.update.await(('UPDATE %s SET pending_type = ?, pending_by = ?, updated_at = ? WHERE id = ?'):format(TABLE), { kind, charId, os.time(), row.id })
        Squads.Notify(charId, oid)
        invite(oid, myName, kind, row.id)
        log(src, 'switch request', myName, otherName, kind)
        return { ok = true, msg = T('t_sq_switch_sent', otherName, label(kind)) }
    end)
end

-- move a link on MY side to `slot`, swapping with whoever stood there (couple stays in 2)
function Squads.Slot(charId, linkId, slot)
    slot = tonumber(slot)
    if not slot or slot ~= math.floor(slot) or slot < 2 or slot > LAST then return { ok = false } end
    return serial(function()
        local row = byId(linkId)
        local sd = row and side(row, charId)
        if not sd or row.status ~= 'accepted' then return { ok = false } end
        local cur = tonumber(row[sd .. '_slot'])
        if cur == slot then return { ok = true } end
        if row.type == 'couple' then return { ok = false, msg = T('t_invalid') } end

        local used = slotMap(charId, linksOf(charId), row.id)
        local holder = used[slot]
        if holder and holder.type == 'couple' then return { ok = false, msg = T('t_invalid') } end
        local q = {}
        if holder then setSlot(q, holder, charId, cur) end
        setSlot(q, row, charId, slot)
        if MySQL.transaction.await(q) ~= true then return { ok = false } end
        Squads.Notify(charId)
        return { ok = true }
    end)
end

function Squads.Visible(charId, linkId, visible)
    local row = byId(linkId)
    local sd = row and side(row, charId)
    if not sd or row.status ~= 'accepted' then return { ok = false } end
    MySQL.update.await(('UPDATE %s SET `%s_visible` = ?, updated_at = ? WHERE id = ?'):format(TABLE, sd), { visible and 1 or 0, os.time(), row.id })
    Squads.Notify(charId)
    return { ok = true }
end

-- Character deleted: drop every link and tell the other sides
function Squads.Purge(charId)
    local others = {}
    for _, r in ipairs(linksOf(charId)) do local _, o = side(r, charId) others[#others + 1] = o end
    MySQL.update.await(('DELETE FROM %s WHERE sender = ? OR target = ?'):format(TABLE), { charId, charId })
    cooldowns[charId] = nil
    if #others > 0 then Squads.Notify(table.unpack(others)) end
end

-- ── callbacks (lobby only, ownership checked on every charId) ─────────────
local function guard(src, charId, limit)
    if not SQ.enabled then return nil, fail('t_sq_disabled') end
    local s = Sessions[src]
    if not s or s.stage ~= 'select' or not Validate.Id(charId) or not s.byId or not s.byId[charId] then return nil, fail('t_error') end
    if limit and Validate.Limited(src, limit) then return nil, fail('t_rate') end
    return s
end

lib.callback.register('nzm:squad:get', function(src, charId)
    if not guard(src, charId) then return { links = {}, incoming = {}, outgoing = {} } end
    return Squads.Get(charId)
end)

lib.callback.register('nzm:squad:search', function(src, charId, query)
    local s = guard(src, charId, 'pref')
    if not s then return {} end
    return Squads.Search(s, charId, query)
end)

lib.callback.register('nzm:squad:request', function(src, charId, targetId, kind)
    local s, err = guard(src, charId, 'squad')
    if not s then return err end
    if s.byId[charId].disabled then return fail('t_disabled') end
    return Squads.Request(src, s, charId, targetId, kind)
end)

lib.callback.register('nzm:squad:respond', function(src, charId, linkId, accept)
    local s, err = guard(src, charId, 'squad')
    if not s then return err end
    linkId = Validate.LinkId(linkId)
    if not linkId then return fail('t_invalid') end
    if accept == true and s.byId[charId].disabled then return fail('t_disabled') end
    return Squads.Respond(charId, linkId, accept == true, src)
end)

lib.callback.register('nzm:squad:remove', function(src, charId, linkId)
    local s, err = guard(src, charId, 'squad')
    if not s then return err end
    linkId = Validate.LinkId(linkId)
    if not linkId then return { ok = false } end
    return Squads.Remove(src, charId, linkId)
end)

lib.callback.register('nzm:squad:switch', function(src, charId, linkId, kind)
    local s, err = guard(src, charId, 'squad')
    if not s then return err end
    linkId = Validate.LinkId(linkId)
    if not linkId then return fail('t_invalid') end
    return Squads.Switch(src, charId, linkId, kind)
end)

lib.callback.register('nzm:squad:slot', function(src, charId, linkId, slot)
    local s, err = guard(src, charId, 'pref')
    if not s then return err end
    linkId = Validate.LinkId(linkId)
    if not linkId then return { ok = false } end
    return Squads.Slot(charId, linkId, slot)
end)

lib.callback.register('nzm:squad:visible', function(src, charId, linkId, visible)
    local s, err = guard(src, charId, 'pref')
    if not s then return err end
    linkId = Validate.LinkId(linkId)
    if not linkId or type(visible) ~= 'boolean' then return { ok = false } end
    return Squads.Visible(charId, linkId, visible)
end)

-- In-game prompt answer (nzm:client:squadInvite -> lib.alertDialog)
RegisterNetEvent('nzm:server:squadAnswer', function(linkId, accept)
    local src = source
    if not SQ.enabled then return end
    local s = Sessions[src]
    if not s or s.stage ~= 'playing' or not s.active then return end
    linkId = Validate.LinkId(linkId)
    if not linkId or Validate.Limited(src, 'squad') then return end
    local res = Squads.Respond(s.active, linkId, accept == true, src)
    if res and res.msg then TriggerClientEvent('nzm:client:notify', src, res.msg, res.ok and 'success' or 'error') end
end)
