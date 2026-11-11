-- The salon (server side): doing someone's hair, step by step.
-- The stylist opens the Style Book on a client, picks a style, the hair and a price. The client says
-- yes (and the money is held). The stylist's client plays out every move and reports each one with a
-- score; the server checks the order and that no move was done faster than it can be, then decides
-- the quality, puts the style on the client and pays the stylist.

Salon = Salon or {}

local SC = Config.Salon
local sessions, bySrc, asks = {}, {}, {}
local seq = 0

local function now() return os.time() end

-- looks: which of the server's hairstyles each salon style shows as, per model -------------------------
-- Salon.Looks['box_braids'] = { f = { d = 132, t = 0 }, m = { d = 80, t = 2 } }
Salon.Looks = {}

local function cleanLooks(t)
    local out = {}
    for id, per in pairs(type(t) == 'table' and t or {}) do
        if type(id) == 'string' and type(per) == 'table' then
            for _, m in ipairs({ 'm', 'f' }) do
                local l = per[m]
                if type(l) == 'table' and tonumber(l.d) then
                    out[id] = out[id] or {}
                    out[id][m] = { d = math.floor(tonumber(l.d)), t = math.floor(tonumber(l.t) or 0), key = type(l.key) == 'string' and l.key or nil }
                end
            end
        end
    end
    return out
end

function Salon.Boot()
    Salon.Looks = cleanLooks(DB.GetKV('salon_looks'))
    TriggerClientEvent('nz-wig:c:salonLooks', -1, Salon.Looks)
end

RegisterNetEvent('nz-wig:s:salonLooks', function()
    TriggerClientEvent('nz-wig:c:salonLooks', source, Salon.Looks)
end)

-- from the Wig Studio: use the hairstyle on screen for a style (or clear it)
-- the hairstyles (hairkit keys) the salon shows: hairkit builds their slices
function Salon.SliceKeys()
    local out, seen = {}, {}
    for _, per in pairs(Salon.Looks) do
        for _, l in pairs(per) do
            if l.key and not seen[l.key] then seen[l.key] = true out[#out + 1] = l.key end
        end
    end
    return out
end

RegisterNetEvent('nz-wig:s:salonSetLook', function(id, m, d, t, key)
    local src = source
    if not IsPlayerAceAllowed(src, 'command.wigstudio') then return end
    if type(id) ~= 'string' or (not Salon.Style(id) and not SC.Looks[id]) or (m ~= 'm' and m ~= 'f') then return end
    Salon.Looks[id] = Salon.Looks[id] or {}
    d = SafeNumber(d)
    if d then
        Salon.Looks[id][m] = { d = math.floor(d), t = math.floor(SafeNumber(t) or 0),
                               key = type(key) == 'string' and key:match('^[mf]|[%w_%-%.]*|%d+$') and key or nil }
    else
        Salon.Looks[id][m] = nil
        if next(Salon.Looks[id]) == nil then Salon.Looks[id] = nil end
    end
    DB.SetKV('salon_looks', Salon.Looks)
    TriggerClientEvent('nz-wig:c:salonLooks', -1, Salon.Looks)
    Notify(src, d and L('salon_look_set', (Salon.Style(id) or {}).label or SC.Looks[id]) or L('salon_look_cleared'), 'success')
    -- build its slices (only what's missing is built)
    if d and HairProps and HairProps.kit and not HairProps.running then HairProps.Run('build', src) end
end)

local function lookFor(id, m)
    local l = Salon.Looks[id]
    return l and l[m] or nil
end

-- items ----------------------------------------------------------------------------------------------------

-- a hair pack's group: same shade, length and texture (packs carry them as metadata)
local function groupKey(meta)
    if type(meta) ~= 'table' or not meta.shade then return 'any' end
    return ('%s|%s|%s'):format(meta.shade, meta.length or '', meta.texture or '')
end
Salon.GroupKey = groupKey

local function packGroups(src, item)
    local groups, order = {}, {}
    for _, st in ipairs(Inv.Stacks(src, item)) do
        local k = groupKey(st.meta)
        if not groups[k] then
            local m = type(st.meta) == 'table' and st.meta or {}
            groups[k] = { key = k, shade = m.shade, length = m.length, texture = m.texture, count = 0 }
            order[#order + 1] = k
        end
        groups[k].count = groups[k].count + (st.count or 1)
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = groups[k] end
    return out
end

local function groupCount(src, item, key)
    for _, g in ipairs(packGroups(src, item)) do
        if g.key == key then return g.count, g end
    end
    return 0
end

local function removeGroup(src, item, key, n)
    local left = n
    for _, st in ipairs(Inv.Stacks(src, item)) do
        if left <= 0 then break end
        if groupKey(st.meta) == key then
            local take = math.min(left, st.count or 1)
            if Inv.Remove(src, item, take, st.slot) then left = left - take end
        end
    end
    return left <= 0
end

-- every item a stylist can need, with how many they have
local function itemCounts(src)
    local have, seen = {}, {}
    for _, t in pairs(SC.Tools) do
        if t.item and not seen[t.item] then seen[t.item] = true have[t.item] = Inv.Count(src, t.item) end
    end
    for _, s in ipairs(Config.SalonStyles) do
        for _, it in ipairs(s.uses or {}) do
            if not seen[it] then seen[it] = true have[it] = Inv.Count(src, it) end
        end
        for _, st in ipairs(s.steps) do
            for _, it in ipairs(st.uses or {}) do
                if not seen[it] then seen[it] = true have[it] = Inv.Count(src, it) end
            end
        end
    end
    return have
end

-- what's missing for a style: nil when everything is there
local function missing(src, style, opts, hairKey, extraKey)
    local need = Salon.Needs(style, opts)
    local out = {}
    for _, it in ipairs(need.tools) do
        if Inv.Count(src, it) < 1 then out[#out + 1] = it end
    end
    for _, it in ipairs(need.uses) do
        if Inv.Count(src, it) < 1 then out[#out + 1] = it end
    end
    if need.hair and groupCount(src, need.hair.item, hairKey) < need.hair.n then out[#out + 1] = need.hair.item end
    if need.extra and groupCount(src, need.extra.item, extraKey) < need.extra.n then out[#out + 1] = need.extra.item end
    return #out > 0 and out or nil, need
end

-- takes everything; returns a list to give back if the session is stopped before any work
local function takeItems(src, need, hairKey, extraKey)
    local taken = {}
    for _, it in ipairs(need.uses) do
        if not Inv.Remove(src, it, 1) then return false, taken end
        taken[#taken + 1] = { item = it, n = 1 }
    end
    local function packs(h, key)
        if not h then return true end
        local _, g = groupCount(src, h.item, key)
        if not removeGroup(src, h.item, key, h.n) then return false end
        taken[#taken + 1] = { item = h.item, n = h.n, meta = g and g.shade and Salon.PackMeta(h.item, g.shade, g.length, g.texture) or nil }
        return true
    end
    if not packs(need.hair, hairKey) then return false, taken end
    if not packs(need.extra, extraKey) then return false, taken end
    return true, taken
end

local function giveBack(src, taken)
    for _, t in ipairs(taken or {}) do Inv.Add(src, t.item, t.n, t.meta) end
end

-- the metadata on a pack of extension hair (the store hands these out)
function Salon.PackMeta(item, shade, length, texture)
    local h = SC.Hair[item]
    if not h then return nil end
    local sh
    for _, s in ipairs(SC.Shades) do if s.id == shade then sh = s break end end
    local parts = { sh and sh.label or shade }
    if length then parts[#parts + 1] = ('%d"'):format(length) end
    if texture then parts[#parts + 1] = texture end
    return {
        shade = shade, length = length, texture = texture,
        label = ('%s · %s'):format(h.label, table.concat(parts, ' · ')),
        description = ('%s. %s'):format(h.kind, table.concat(parts, ', ')),
    }
end

-- the Style Book --------------------------------------------------------------------------------------------

local function free(P) return P and not P.busy end

local function targetInfo(src, target)
    local C = GetP(target)
    if not C or C.src == src then return nil, 'invalid' end
    if PedDistance(src, C.src) > SC.Range + 1.0 then return nil, 'no_one_close' end
    local model = Hair.PedModelKey(C.src)
    if not model or not ModelEnabled(model) then return nil, 'wrong_model' end
    return C, nil, model
end

lib.callback.register('nz-wig:salonBook', function(src, target)
    local B = GetP(src)
    if not SC.Enabled or not B then return false end
    local C, err, model
    if target then
        C, err, model = targetInfo(src, tonumber(target))
        if not C then return { error = L(err) } end
    end
    local lvl = GetLevel(B.row.xp)
    local styles = {}
    for _, s in ipairs(Config.SalonStyles) do
        local look = model and lookFor(s.id, model) or nil
        styles[#styles + 1] = {
            id = s.id, look = look ~= nil,
            img = look and Wigs.ShotUrl({ m = model, d = look.d, t = look.t }) or nil,
            looks = { m = lookFor(s.id, 'm') ~= nil, f = lookFor(s.id, 'f') ~= nil },
            locked = lvl < (s.level or 1),
        }
    end
    local packs = {}
    for item in pairs(SC.Hair) do packs[item] = packGroups(src, item) end
    return {
        level = lvl, styles = styles, packs = packs, have = itemCounts(src), meta = Inv.HasMeta,
        target = C and { id = C.src, name = C.name, model = model, wig = C.hair.wig ~= nil, style = C.hair.style and C.hair.style.label or nil } or nil,
        maxPrice = SC.Payment.MaxPrice, account = SC.Payment.Account,
    }
end)

-- asking -------------------------------------------------------------------------------------------------

-- the work on the client's head, for everyone close by: slices of the style going on, the cornrow base,
-- the wig cap, clips and pins (client/salon.lua puts the props on)
local function workFx(s, op, data)
    local c = PedCoords(s.c)
    local seen = { [s.b] = true, [s.c] = true }
    TriggerClientEvent('nz-wig:c:salonWork', s.b, s.c, s.id, op, data)
    TriggerClientEvent('nz-wig:c:salonWork', s.c, s.c, s.id, op, data)
    if not c then return end
    for _, p in ipairs(PlayersNear(c, 60.0)) do
        if not seen[p] then seen[p] = true TriggerClientEvent('nz-wig:c:salonWork', p, s.c, s.id, op, data) end
    end
end

local function release(s)
    sessions[s.id] = nil
    asks[s.id] = nil
    for _, src in ipairs({ s.b, s.c }) do
        if bySrc[src] == s.id then bySrc[src] = nil end
        local P = Players[src]
        if P then SetBusy(P, false) end
    end
end

local function cancel(s, reason)
    if not sessions[s.id] then return end
    release(s)
    if s.stage == 'styling' then workFx(s, 'clear', {}) end
    if s.paid and Players[s.c] then Bridge.AddMoney(s.c, s.price, SC.Payment.Account, 'salon refund') end
    if s.idx == 1 and Players[s.b] then giveBack(s.b, s.taken) end
    TriggerClientEvent('nz-wig:c:salonEnd', s.b, { id = s.id, cancelled = true, reason = reason })
    TriggerClientEvent('nz-wig:c:salonEnd', s.c, { id = s.id, cancelled = true, reason = reason })
    if Players[s.b] then Notify(s.b, L('salon_cancelled'), 'error') end
    if Players[s.c] then Notify(s.c, L(s.paid and 'salon_cancelled_refund' or 'salon_cancelled'), 'info') end
end

local function cleanOpts(style, o)
    o = type(o) == 'table' and o or {}
    local out = {}
    if style.hair and style.hair.ext and o.ext == true then out.ext = true end
    for k in pairs(style.options or {}) do
        if o[k] == true then out[k] = true end
    end
    return out
end

RegisterNetEvent('nz-wig:s:salonRequest', function(target, styleId, opts, hairKey, extraKey, price)
    local src = source
    local B = GetP(src)
    local style = type(styleId) == 'string' and Salon.Style(styleId)
    if not SC.Enabled or not B or not style then return end
    if not free(B) then return Notify(src, L('busy'), 'error') end
    local C, err, model = targetInfo(src, tonumber(target))
    if not C then return Notify(src, L(err), 'error') end
    if not free(C) then return Notify(src, L('target_busy'), 'error') end
    if InVehicle(src) or InVehicle(C.src) then return Notify(src, L('in_vehicle'), 'error') end
    if C.hair.wig then return Notify(src, L('salon_wig_on', C.name), 'error') end
    if GetLevel(B.row.xp) < (style.level or 1) then return Notify(src, L('level_needed', style.level), 'error') end
    local look = lookFor(style.id, model)
    if not look then return Notify(src, L('salon_no_look', style.label), 'error') end

    opts = cleanOpts(style, opts)
    hairKey = type(hairKey) == 'string' and hairKey or 'any'
    extraKey = type(extraKey) == 'string' and extraKey or 'any'
    local miss, need = missing(src, style, opts, hairKey, extraKey)
    if miss then return Notify(src, L('salon_missing', #miss), 'error') end
    price = math.floor(SafeNumber(price) or 0)
    if price < 0 or price > SC.Payment.MaxPrice then return Notify(src, L('invalid'), 'error') end

    -- the shade of the style: the packs' shade (extension hair), else the client's own colour
    local shade
    if need.hair then
        local _, g = groupCount(src, need.hair.item, hairKey)
        shade = g and g.shade or nil
    end

    seq = seq + 1
    local moves = Salon.Moves(style, opts)
    local s = {
        id = seq, b = src, c = C.src, style = style, opts = opts, hairKey = hairKey, extraKey = extraKey,
        model = model, look = look, shade = shade, price = price, moves = moves, idx = 1, scores = {},
        effects = Salon.Effects(style, moves), revealed = 0, revealAt = 0,
        stage = 'asking',
    }
    sessions[s.id] = s
    asks[s.id] = s
    SetBusy(B, true)
    SetBusy(C, true)

    local shadeLabel
    for _, sh in ipairs(SC.Shades) do if sh.id == shade then shadeLabel = sh.label end end
    SendPrompt(C.src, {
        kind = 'salon', id = s.id, timeout = SC.RequestTimeout, price = price > 0 and price or nil,
        title = L('salon_prompt_title'),
        body = L(price > 0 and 'salon_prompt_paid' or 'salon_prompt_free', B.name, style.label, Salon.Minutes(style, opts), price)
            .. (shadeLabel and (' · ' .. shadeLabel) or ''),
    })
    Notify(src, L('prompt_sent', C.name), 'info')
    SetTimeout(SC.RequestTimeout * 1000 + 500, function()
        if asks[s.id] == s then
            release(s)
            ClosePrompt(s.c, s.id)
            if Players[src] then Notify(src, L('prompt_timeout'), 'warning') end
        end
    end)
end)

local function start(s)
    local B, C = Players[s.b], Players[s.c]
    if not B or not C then return release(s) end
    s.stage = 'styling'
    s.moveAt = GetGameTimer()
    s.startAt = s.moveAt
    bySrc[s.b], bySrc[s.c] = s.id, s.id
    local steps = {}
    for _, st in ipairs(s.style.steps) do steps[#steps + 1] = { text = st.text, phase = st.phase, opt = st.opt } end
    TriggerClientEvent('nz-wig:c:salonStart', s.b, {
        id = s.id, other = s.c, name = C.name, style = s.style.id, opts = s.opts, shade = s.shade, model = s.model,
        max = SC.MaxMinutes * 60,
    })
    TriggerClientEvent('nz-wig:c:salonSit', s.c, {
        id = s.id, other = s.b, name = B.name, style = s.style.id, opts = s.opts, label = s.style.label,
        total = #s.moves, price = s.price,
    })
    workFx(s, 'begin', { style = s.style.id, opts = s.opts, m = s.model, d = s.look.d, t = s.look.t })
    local id = s.id
    SetTimeout(SC.MaxMinutes * 60000 + 500, function()
        if sessions[id] == s then cancel(s, 'time') end
    end)
end

PromptHandlers.salon = function(src, id, accept)
    local s = asks[id]
    if not s or s.c ~= src then return end
    asks[id] = nil
    if not accept or not Players[s.b] then
        release(s)
        if Players[s.b] then Notify(s.b, L('prompt_declined', Players[src] and Players[src].name or '?'), 'warning') end
        return
    end
    -- everything again: time has passed
    local miss, need = missing(s.b, s.style, s.opts, s.hairKey, s.extraKey)
    if miss or PedDistance(s.b, s.c) > SC.Range + 1.0 then
        release(s)
        return Notify(s.b, L(miss and 'salon_missing' or 'no_one_close', miss and #miss or nil), 'error')
    end
    if s.price > 0 then
        if Bridge.GetMoney(src, SC.Payment.Account) < s.price or not Bridge.RemoveMoney(src, s.price, SC.Payment.Account, 'salon') then
            release(s)
            Notify(src, L('no_money'), 'error')
            return Notify(s.b, L('salon_client_broke', Players[src].name), 'error')
        end
        s.paid = true
    end
    local ok, taken = takeItems(s.b, need, s.hairKey, s.extraKey)
    s.taken = taken
    if not ok then
        giveBack(s.b, taken)
        s.idx = 0   -- nothing more to give back
        return cancel(s, 'items')
    end
    start(s)
end

-- playing it out ----------------------------------------------------------------------------------------

RegisterNetEvent('nz-wig:s:salonMove', function(id, idx, score)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if not s or s.b ~= src or s.stage ~= 'styling' then return end
    idx = tonumber(idx)
    if idx ~= s.idx then return end
    local t = GetGameTimer()
    local least = Salon.MoveTime(s.moves, idx) * SC.MinTime * 1000
    if t - s.moveAt < least then
        -- too fast: the move counts, but badly
        score = 0
    end
    if PedDistance(s.b, s.c) > SC.Range + 2.5 then return cancel(s, 'distance') end
    s.scores[idx] = math.max(0, math.min(100, math.floor(SafeNumber(score) or 0)))
    s.idx = idx + 1
    s.moveAt = t

    local m = s.moves[idx]
    local nextM = s.moves[idx + 1]
    TriggerClientEvent('nz-wig:c:salonProgress', s.c, { id = s.id, idx = s.idx, total = #s.moves, step = nextM and nextM.step or m.step })
    -- what it did to the head
    local e = s.effects[idx]
    if e then
        if e.base then
            -- the braid down: the client's hair goes to cornrows (a linked look wins over the config number)
            local look = lookFor(e.base, s.model) or (SC.Cornrows and SC.Cornrows[s.model])
            if look then TriggerClientEvent('nz-wig:c:salonLook', s.c, s.id, look) end
        end
        if e.cap then workFx(s, 'cap', {}) end
        if e.pieces then workFx(s, 'pieces', { kind = e.pieces, idx = idx }) end
        if e.reveal then
            s.revealed = e.reveal
            workFx(s, 'reveal', { f = e.reveal })
        end
    end
    if not nextM then Salon.Finish(s) end
end)

-- part way through a long move (rows of cornrows, a braid, a weft track): the style goes on as it's done
RegisterNetEvent('nz-wig:s:salonPart', function(id, idx, frac)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if not s or s.b ~= src or s.stage ~= 'styling' or tonumber(idx) ~= s.idx then return end
    local e = s.effects[s.idx]
    frac = SafeNumber(frac)
    if not e or not e.reveal or not frac then return end
    local f = (e.from or 0) + (e.reveal - (e.from or 0)) * math.max(0, math.min(0.95, frac))
    local t = GetGameTimer()
    if f > s.revealed + 0.03 and t - s.revealAt > 600 then
        s.revealed, s.revealAt = f, t
        workFx(s, 'reveal', { f = f })
    end
end)

-- the sound / spray / steam others see, at most a few times a second
RegisterNetEvent('nz-wig:s:salonFx', function(id, tool)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if not s or s.b ~= src or s.stage ~= 'styling' or type(tool) ~= 'string' then return end
    local def = SC.Tools[tool]
    if not def then return end
    local t = GetGameTimer()
    if t - (s.fxAt or 0) < 450 then return end
    s.fxAt = t
    local c = PedCoords(s.c)
    if not c then return end
    for _, p in ipairs(PlayersNear(c, 40.0)) do
        TriggerClientEvent('nz-wig:c:salonFx', p, s.c, tool)
    end
    if def.sound then
        for _, p in ipairs(PlayersNear(c, SC.SoundRange, s.b)) do
            TriggerClientEvent('nz-wig:c:sound', p, { sound = def.sound, coords = { x = c.x, y = c.y, z = c.z }, range = SC.SoundRange, duration = 900 })
        end
    end
end)

RegisterNetEvent('nz-wig:s:salonCancel', function(id)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if s and (s.b == src or s.c == src) then cancel(s, 'stopped') end
end)

function Salon.Finish(s)
    if not sessions[s.id] then return end
    local B, C = Players[s.b], Players[s.c]
    release(s)
    if not B or not C then
        if s.paid and C then Bridge.AddMoney(s.c, s.price, SC.Payment.Account, 'salon refund') end
        return
    end
    local total, n = 0, 0
    for i = 1, #s.moves do total = total + (s.scores[i] or 0) n = n + 1 end
    local q = n > 0 and math.floor(total / n + 0.5) or 0
    local style = s.style
    local minutes
    if SC.DayMinutes then minutes = math.floor((style.days or 7) * SC.DayMinutes * (0.5 + q / 200)) end
    Hair.SetStyle(C, {
        id = style.id, label = style.label, d = s.look.d, t = s.look.t, m = s.model, shade = s.shade,
        q = q, by = B.name, at = now(),
    }, minutes)

    if s.paid then Bridge.AddMoney(s.b, s.price, SC.Payment.Account, 'salon') end
    local xp = (style.level or 1) * SC.XP.PerLevel * (q / 100) + (q >= 95 and SC.XP.Perfect or 0)
    local gained = AddXP(B, xp)
    B.row.styled = (B.row.styled or 0) + 1
    React(C.src, 'cut_client', 600)
    SaveP(B) SaveP(C) SyncP(B)
    Hair.Push(C, 'style')
    -- the finished hairstyle is on the ped now: the pieces make way once it has streamed in
    workFx(s, 'reveal', { f = 1 })
    SetTimeout(1800, function() workFx(s, 'clear', {}) end)
    DB.AddFeed('style', B.id, B.name, C.id, C.name, nil, style.label, s.price)
    Social.PushFeed({ kind = 'style', actor_name = B.name, target_name = C.name, label = style.label, amount = s.price, created = now() })

    TriggerClientEvent('nz-wig:c:salonEnd', s.b, { id = s.id, done = true, q = q, label = style.label, xp = gained, paid = s.paid and s.price or 0, name = C.name })
    TriggerClientEvent('nz-wig:c:salonEnd', s.c, { id = s.id, done = true, q = q, label = style.label, by = B.name, minutes = minutes, style = style.id })
    Notify(s.b, L('salon_done_stylist', style.label, C.name, q), 'success', 6000)
    Log('haircut', 'Salon', ('**%s** did **%s** on **%s** (%d%%%s)'):format(B.name, style.label, C.name, q, s.paid and (', $' .. s.price) or ''))
end

-- taking a style down yourself ---------------------------------------------------------------------------

RegisterNetEvent('nz-wig:s:salonTakedown', function()
    local src = source
    local P = GetP(src)
    if not P or P.busy or not P.hair.style then return end
    local label = P.hair.style.label
    Hair.ClearStyle(P)
    SaveP(P)
    Hair.Push(P, 'takedown')
    Notify(src, L('salon_taken_down', label), 'info')
end)

OnPlayerDrop(function(src)
    local id = bySrc[src]
    local s = id and sessions[id]
    if s then cancel(s, 'left') end
    for aid, a in pairs(asks) do
        if a.b == src or a.c == src then
            release(a)
            ClosePrompt(a.b == src and a.c or a.b, aid)
        end
    end
end)

function Salon.InSession(src) return bySrc[src] ~= nil end

lib.callback.register('nz-wig:salonAdmin', function(src) return IsPlayerAceAllowed(src, 'command.wigstudio') end)

-- the rat-tail comb opens the Style Book on whoever is in front
function Salon.RegisterItems()
    if not SC.Enabled or not SC.Tools.rat_comb or not SC.Tools.rat_comb.item then return end
    Bridge.RegisterUsable(SC.Tools.rat_comb.item, function(src) TriggerClientEvent('nz-wig:c:salonUse', src) end)
end
