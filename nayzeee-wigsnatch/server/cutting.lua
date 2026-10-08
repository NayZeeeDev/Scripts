-- First person haircuts and shaves (server side).
-- The barber's client reports work done on each region of the head with each tool. The server
-- caps how fast work can come in, tracks it per region / tool, and decides the result itself.

Cutting = {}

local CC = Config.Cutting
local HEAD = { 'top', 'back', 'left', 'right' }
local FACE = { 'brows', 'beard' }

local sessions, bySrc, asks = {}, {}, {}
local seq = 0

local function now() return os.time() end

-- pure: what the work adds up to. Exposed for tests / other scripts.
-- returns hairResult|nil, browsResult|nil, beardResult|nil, scissorRegions
function Cutting.Outcome(work)
    local function done(r, t) return ((work[r] or {})[t] or 0) >= 100 end
    local hair
    if done('top', 'razor') then hair = 'bald'
    elseif done('top', 'clippers') then hair = 'buzz'
    elseif done('left', 'clippers') or done('right', 'clippers') or done('back', 'clippers') then hair = 'fade'
    end
    local snipped = 0
    for _, r in ipairs(HEAD) do
        if done(r, 'scissors') then snipped = snipped + 1 end
    end
    if not hair and snipped > 0 then hair = 'trim' end
    local brows = done('brows', 'razor') and 'gone' or (done('brows', 'scissors') and 'thin' or nil)
    local beard = (done('beard', 'razor') or done('beard', 'clippers')) and 'gone' or (done('beard', 'scissors') and 'trim' or nil)
    return hair, brows, beard, snipped
end

local RANK = { thin = 1, trim = 1, gone = 2 }

local function toolsOwned(src)
    local out, any = {}, false
    for _, id in ipairs(ToolOrder) do
        local t = CC.Tools[id]
        if t and Inv.Count(src, t.Item) > 0 then out[id] = true any = true end
    end
    return any and out or nil
end

local function release(s)
    sessions[s.id] = nil
    for _, src in ipairs({ s.b, s.c }) do
        if bySrc[src] == s.id then bySrc[src] = nil end
        local P = Players[src]
        if P then SetBusy(P, false) end
    end
end

local function cancel(s, reason)
    if not sessions[s.id] then return end
    release(s)
    TriggerClientEvent('nz-wig:c:cutEnd', s.b, { id = s.id, cancelled = true, reason = reason })
    TriggerClientEvent('nz-wig:c:cutEnd', s.c, { id = s.id, cancelled = true, reason = reason })
    if Players[s.b] then Notify(s.b, L('cut_cancelled'), 'error') end
    if Players[s.c] then Notify(s.c, L('cut_cancelled'), 'info') end
end

local function snapshot(s)
    local out = {}
    for r, tools in pairs(s.work) do
        out[r] = {}
        for t, v in pairs(tools) do out[r][t] = math.floor(math.min(100, v)) end
    end
    return out
end

-- which regions this client actually has
local function regionsFor(C, q, model)
    local regions = {}
    local h = C.hair
    local hasHair = not h.wig and not h.bald and not IsBaldDrawable(model, h.cut and h.cut.d or q.d)
    for _, r in ipairs(HEAD) do regions[r] = hasHair end
    local face = h.face or {}
    regions.brows = q.bv ~= 255 and face.brows ~= 'gone'
    regions.beard = q.fv ~= 255 and face.beard ~= 'gone'
    return regions, hasHair
end

local function start(s)
    local B, C = Players[s.b], Players[s.c]
    if not B or not C then return release(s) end
    s.stage = 'cutting'
    s.started = GetGameTimer()
    s.lastAt = s.started
    s.budget = 0
    bySrc[s.b], bySrc[s.c] = s.id, s.id

    local tools = {}
    for _, id in ipairs(ToolOrder) do
        if s.tools[id] then tools[#tools + 1] = id end
    end
    TriggerClientEvent('nz-wig:c:cutStart', s.b, {
        id = s.id, other = s.c, name = C.name, tools = tools, regions = s.regions, forced = s.forced,
        max = CC.MaxSeconds, short = s.short, work = snapshot(s),
    })
    TriggerClientEvent('nz-wig:c:cutSit', s.c, { id = s.id, other = s.b, name = B.name, forced = s.forced })

    local id = s.id
    SetTimeout(CC.MaxSeconds * 1000 + 500, function()
        if sessions[id] == s then Cutting.Finish(s, 'time') end
    end)
end

RegisterNetEvent('nz-wig:s:cutRequest', function(target, forced)
    local src = source
    local B, C = GetP(src), GetP(tonumber(target))
    if not CC.Enabled or not B or not C or B == C then return end
    forced = forced == true
    if B.busy or C.busy then return Notify(src, L(B.busy and 'busy' or 'target_busy'), 'error') end
    local owned = toolsOwned(src)
    if not owned then return Notify(src, L('cut_need_tool'), 'error') end
    if PedDistance(src, C.src) > CC.Range + 1.0 then return Notify(src, L('no_one_close'), 'error') end
    if InVehicle(src) or InVehicle(C.src) then return Notify(src, L('in_vehicle'), 'error') end
    local model = Hair.PedModelKey(C.src)
    if not model or not ModelEnabled(model) then return Notify(src, L('wrong_model'), 'error') end

    if forced then
        local ok, key, extra = CanAttack(B, { cooldown = true })
        if not ok then return AttackError(src, key, extra) end
        local okT, keyT = CanBeTarget(C)
        if not okT then return Notify(src, L(keyT), 'error') end
    end

    SetBusy(B, true)
    SetBusy(C, true)
    local q = Clash.QueryHair(C.src, 2500)
    if Players[src] ~= B or Players[C.src] ~= C or not q then
        if Players[src] then SetBusy(B, false) end
        if Players[C.src] then SetBusy(C, false) end
        return Players[src] and Notify(src, L('invalid'), 'error')
    end

    local helpless = q.restrained or q.handsUp or q.downed or IsRestrainedSrc(C.src)
    if forced and not helpless then
        SetBusy(B, false) SetBusy(C, false)
        return Notify(src, L('cut_needs_restrain'), 'error')
    end

    local regions, hasHair = regionsFor(C, q, model)
    local anything = false
    for _, v in pairs(regions) do anything = anything or v end
    if not anything then
        SetBusy(B, false) SetBusy(C, false)
        return Notify(src, L('cut_nothing'), 'error')
    end

    seq = seq + 1
    local d = C.hair.cut and C.hair.cut.d or q.d
    local s = {
        id = seq, b = src, c = C.src, model = model, forced = forced, tools = owned, regions = regions,
        hair = { m = model, d = d, t = C.hair.cut and C.hair.cut.t or q.t, c = q.c, h = q.h },
        short = not hasHair or IsShortDrawable(model, d),
        work = {}, stage = 'asking', soundAt = 0, fxAt = 0,
    }
    for r in pairs(regions) do s.work[r] = { scissors = 0, clippers = 0, razor = 0 } end
    sessions[s.id] = s

    if forced then
        StartCooldown(B)
        EndNewPlayer(B)
        SyncP(B)
        return start(s)
    end

    asks[s.id] = s
    SendPrompt(C.src, {
        kind = 'cut', id = s.id, timeout = CC.RequestTimeout,
        title = L('cut_prompt_title'), body = L('cut_prompt_body', B.name), tool = 'scissors',
    })
    Notify(src, L('prompt_sent', C.name), 'info')
    SetTimeout(CC.RequestTimeout * 1000 + 500, function()
        if asks[s.id] == s then
            asks[s.id] = nil
            release(s)
            ClosePrompt(s.c, s.id)
            if Players[src] then Notify(src, L('prompt_timeout'), 'warning') end
        end
    end)
end)

PromptHandlers.cut = function(src, id, accept)
    local s = asks[id]
    if not s or s.c ~= src then return end
    asks[id] = nil
    if not accept or not Players[s.b] then
        release(s)
        if Players[s.b] then Notify(s.b, L('prompt_declined', Players[src] and Players[src].name or '?'), 'warning') end
        return
    end
    start(s)
end

-- work coming in from the barber, batched: { { r = 'top', t = 'clippers', w = 12 }, ... }
RegisterNetEvent('nz-wig:s:cutWork', function(id, batch)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if not s or s.b ~= src or s.stage ~= 'cutting' or type(batch) ~= 'table' then return end

    local t = GetGameTimer()
    s.budget = math.min(CC.MaxWorkPerSecond, s.budget + (t - s.lastAt) * CC.MaxWorkPerSecond / 1000)
    s.lastAt = t

    if PedDistance(s.b, s.c) > CC.Range + 2.5 then return cancel(s, 'distance') end

    local soundTool, region
    for i = 1, math.min(#batch, 8) do
        local e = batch[i]
        local r, tool, w = type(e) == 'table' and e.r, type(e) == 'table' and e.t, tonumber(type(e) == 'table' and e.w)
        local def = CC.Tools[tool]
        if s.regions[r] and def and s.tools[tool] and def.Regions[r] and w and w > 0 then
            -- razor on the top only after the clippers (or on hair that's already short)
            local allowed = not (tool == 'razor' and r == 'top' and not s.short and (s.work.top.clippers or 0) < 100)
            if allowed then
                local grant = math.min(w, s.budget)
                if grant > 0 then
                    s.budget = s.budget - grant
                    s.work[r][tool] = math.min(100, s.work[r][tool] + grant)
                    soundTool, region = tool, r
                end
            end
        end
    end

    TriggerClientEvent('nz-wig:c:cutProgress', src, s.id, snapshot(s))

    if soundTool then
        local c = PedCoords(s.c)
        if c and t - s.soundAt > 650 then
            s.soundAt = t
            for _, p in ipairs(PlayersNear(c, CC.SoundRange, s.b)) do
                TriggerClientEvent('nz-wig:c:sound', p, { sound = CC.Tools[soundTool].Sound, coords = { x = c.x, y = c.y, z = c.z },
                    range = CC.SoundRange, duration = 700 })
            end
        end
        if c and t - s.fxAt > 450 then
            s.fxAt = t
            for _, p in ipairs(PlayersNear(c, 40.0)) do
                TriggerClientEvent('nz-wig:c:cutFx', p, s.c, region, soundTool)
            end
        end
    end
end)

RegisterNetEvent('nz-wig:s:cutFinish', function(id)
    local s = sessions[tonumber(id) or -1]
    if s and s.b == source and s.stage == 'cutting' then Cutting.Finish(s, 'done') end
end)

RegisterNetEvent('nz-wig:s:cutCancel', function(id)
    local src = source
    local s = sessions[tonumber(id) or -1]
    if not s then return end
    -- the barber can always stop; a client can only walk out of a cut they agreed to
    if s.b == src or (s.c == src and not s.forced) then cancel(s, 'stopped') end
end)

local function pick(list)
    if not list or #list == 0 then return 0 end
    return list[math.random(1, #list)]
end

function Cutting.Finish(s, why)
    if not sessions[s.id] then return end
    local B, C = Players[s.b], Players[s.c]
    release(s)
    if not B or not C then return end
    if PedDistance(s.b, s.c) > CC.Range + 2.5 then
        TriggerClientEvent('nz-wig:c:cutEnd', s.b, { id = s.id, cancelled = true })
        TriggerClientEvent('nz-wig:c:cutEnd', s.c, { id = s.id, cancelled = true })
        return Notify(s.b, L('cut_cancelled'), 'error')
    end

    local hair, brows, beard, snipped = Cutting.Outcome(s.work)
    if not s.regions.top then hair = nil end
    local g = GenderKey(s.model)
    local changed = {}

    if hair == 'bald' then
        Hair.SetBald(C, s.model, CC.BuzzMinutes > 0 and CC.BuzzMinutes or nil)
        changed[#changed + 1] = L('cut_res_bald')
    elseif hair then
        Hair.SetCut(C, s.model, hair, pick(CC.Results[hair][g]), (hair == 'buzz' and CC.BuzzMinutes > 0) and CC.BuzzMinutes or nil)
        changed[#changed + 1] = L('cut_res_' .. hair)
    end

    local face = C.hair.face or {}
    if brows and s.regions.brows and (RANK[brows] or 0) > (RANK[face.brows] or 0) then
        Hair.SetFace(C, 'brows', brows)
        changed[#changed + 1] = L('cut_res_brows_' .. brows)
    end
    if beard and s.regions.beard and (RANK[beard] or 0) > (RANK[face.beard] or 0) then
        Hair.SetFace(C, 'beard', beard)
        changed[#changed + 1] = L('cut_res_beard_' .. beard)
    end

    -- bundles from long hair that was snipped
    local bundles = 0
    if CC.Bundles.Enabled and not s.short and snipped > 0 then
        local n = math.min(CC.Bundles.Max, snipped * CC.Bundles.PerRegion)
        for _ = 1, n do
            local meta = Wigs.CreateBundle(s.hair, C.name)
            if Wigs.CanCarry(s.b, meta) and Wigs.Give(s.b, meta) then bundles = bundles + 1 end
        end
    end

    local result = { id = s.id, changes = changed, bundles = bundles }
    if #changed == 0 then
        TriggerClientEvent('nz-wig:c:cutEnd', s.b, result)
        TriggerClientEvent('nz-wig:c:cutEnd', s.c, result)
        return Notify(s.b, L('cut_no_change'), 'info')
    end

    local xp = s.forced and CC.XP.Forced or CC.XP.Cut
    if brows or beard then xp = xp + CC.XP.Face end
    result.xp = AddXP(B, xp)
    if s.forced then
        B.row.buzzes = B.row.buzzes + 1
        if hair then C.immuneUntil = now() + Config.Protection.VictimImmunity end
        DB.AddFeed('buzz', B.id, B.name, C.id, C.name, nil, hair or 'face', 0)
        Social.PushFeed({ kind = 'buzz', actor_name = B.name, target_name = C.name, label = hair or 'face', created = now() })
        React(C.src, 'cut_victim', 400)
    else
        B.row.cuts = B.row.cuts + 1
        React(C.src, 'cut_client', 400)
    end
    Products.Spread(C, B)

    SaveP(B) SaveP(C) SyncP(B)
    Hair.Push(C, 'cut')
    TriggerClientEvent('nz-wig:c:cutEnd', s.b, result)
    TriggerClientEvent('nz-wig:c:cutEnd', s.c, result)
    local summary = table.concat(changed, ', ')
    Notify(s.b, L('cut_done_barber', C.name, summary) .. (bundles > 0 and (' · ' .. L('cut_bundles', bundles)) or ''), 'success', 6000)
    Notify(s.c, L(s.forced and 'cut_done_forced' or 'cut_done_client', B.name, summary), s.forced and 'error' or 'success', 6000)
    Log('haircut', s.forced and 'Forced cut' or 'Haircut', ('**%s** → **%s**: %s%s'):format(
        B.name, C.name, summary, bundles > 0 and (' (+%d bundles)'):format(bundles) or ''))
end

OnPlayerDrop(function(src)
    local id = bySrc[src]
    local s = id and sessions[id]
    if s then cancel(s, 'left') end
    for aid, a in pairs(asks) do
        if a.b == src or a.c == src then
            asks[aid] = nil
            release(a)
            ClosePrompt(a.b == src and a.c or a.b, aid)
        end
    end
end)

function Cutting.InSession(src) return bySrc[src] ~= nil end

-- usable tools: offer a cut to whoever is closest in front
function Cutting.RegisterItems()
    if not CC.Enabled then return end
    local seen = {}
    for _, id in ipairs(ToolOrder) do
        local t = CC.Tools[id]
        if t and not seen[t.Item] then
            seen[t.Item] = true
            Bridge.RegisterUsable(t.Item, function(src) TriggerClientEvent('nz-wig:c:useTool', src) end)
        end
    end
end
