-- Scissors and clippers: consensual haircuts + forced buzz cuts

Tools = {}

local requests = {} -- [id] = { barber, client, tool, exp, stage }
local seq = 0

local function now() return os.time() end

local function toolCfg(tool)
    if tool == 'scissors' then return Config.Tools.Scissors, Config.Items.Scissors end
    if tool == 'clippers' then return Config.Tools.Clippers, Config.Items.Clippers end
end

local function release(r)
    local B, C = Players[r.barber], Players[r.client]
    if B then B.busy = false end
    if C then C.busy = false end
    requests[r.id] = nil
end

local function playSound(src, sound, duration)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local c = GetEntityCoords(ped)
    for _, s in ipairs(PlayersNear(c, Config.Tools.SoundRange)) do
        TriggerClientEvent('nz-wig:c:sound', s, { sound = sound, coords = { x = c.x, y = c.y, z = c.z },
            range = Config.Tools.SoundRange, duration = duration })
    end
end

-- runs the actual cut once both sides are locked in
local function run(r, onDone)
    local cfg = toolCfg(r.tool)
    r.stage = 'cutting'
    TriggerClientEvent('nz-wig:c:toolRun', r.barber, { role = 'barber', other = r.client, duration = Config.Tools.Duration, tool = r.tool })
    TriggerClientEvent('nz-wig:c:toolRun', r.client, { role = 'client', other = r.barber, duration = Config.Tools.Duration, tool = r.tool })
    playSound(r.barber, cfg.Sound, Config.Tools.Duration)
    SetTimeout(Config.Tools.Duration + 150, function()
        if requests[r.id] ~= r then return end
        local B, C = Players[r.barber], Players[r.client]
        release(r)
        if not B or not C then return end
        if PedDistance(r.barber, r.client) > Config.Tools.Range + 2.5 then
            Notify(r.barber, L('tool_cancelled'), 'error')
            return Notify(r.client, L('tool_cancelled'), 'error')
        end
        onDone(B, C)
    end)
end

local function validate(src, target, tool)
    local B, C = GetP(src), GetP(tonumber(target))
    if not B or not C or B == C then return nil end
    local cfg, item = toolCfg(tool)
    if not cfg or not cfg.Enabled then return nil end
    if B.busy or C.busy then Notify(src, L(B.busy and 'busy' or 'target_busy'), 'error') return nil end
    if Inv.Count(src, item) < 1 then Notify(src, L('tool_need', item), 'error') return nil end
    if PedDistance(src, C.src) > Config.Tools.Range + 1.0 then Notify(src, L('no_one_close'), 'error') return nil end
    if not Config.Snatch.AllowInVehicle and (InVehicle(src) or InVehicle(C.src)) then Notify(src, L('in_vehicle'), 'error') return nil end
    local m = Hair.PedModelKey(C.src)
    if not m or not ModelEnabled(m) then Notify(src, L('wrong_model'), 'error') return nil end
    if Hair.Layer(C) ~= 'natural' then Notify(src, L('already_bald'), 'error') return nil end
    return B, C, m
end

RegisterNetEvent('nz-wig:s:toolRequest', function(target, tool, forced)
    local src = source
    local B, C, model = validate(src, target, tool)
    if not B then return end

    seq = seq + 1
    local r = { id = seq, barber = src, client = C.src, tool = tool, model = model, exp = now() + Config.Tools.RequestTimeout }

    if forced then
        if tool ~= 'clippers' or not Config.Tools.Clippers.AllowForced then return end
        local ok, key = CanBeTarget(C)
        if not ok then return Notify(src, L(key), 'error') end
        local okA, keyA, extra = CanAttack(B)
        if not okA then return Notify(src, keyA == 'cooldown' and L('cooldown', extra) or L(keyA), 'error') end

        B.busy, C.busy = true, true
        requests[r.id] = r
        local q = Clash.QueryHair(C.src, 2500)
        if requests[r.id] ~= r then return end
        local restrained = q and (q.restrained or q.handsUp or q.downed)
            or StateFlag(C.src, Config.RestrainedStates) or StateFlag(C.src, Config.DownedStates)
        if not restrained then
            release(r)
            return Notify(src, L('buzz_needs_restrain'), 'error')
        end
        StartCooldown(B)
        if Config.Protection.NewPlayerEndsOnAttack then EndNewPlayer(B) end
        SyncP(B)
        return run(r, function(Bn, Cn)
            Hair.SetBald(Cn, model)
            Cn.immuneUntil = now() + Config.Protection.VictimImmunity
            Bn.row.buzzes = Bn.row.buzzes + 1
            AddXP(Bn, Config.XP.Buzz)
            DB.AddFeed('buzz', Bn.id, Bn.name, Cn.id, Cn.name, nil, nil, 0)
            Social.PushFeed({ kind = 'buzz', actor_name = Bn.name, target_name = Cn.name, created = now() })
            Hair.Push(Cn, 'buzzed')
            Notify(Bn.src, L('buzz_forced', Cn.name), 'success')
            Notify(Cn.src, L('buzz_victim', Bn.name), 'error')
            Log('haircut', 'Forced buzz cut', ('**%s** buzzed **%s**'):format(Bn.name, Cn.name))
            SaveP(Bn) SaveP(Cn)
        end)
    end

    -- consensual: ask first
    r.stage = 'asking'
    requests[r.id] = r
    B.busy = true
    TriggerClientEvent('nz-wig:c:prompt', C.src, {
        kind = 'haircut', id = r.id, timeout = Config.Tools.RequestTimeout,
        title = L('tool_prompt_title'), body = L('tool_prompt_body', B.name), tool = tool,
    })
    Notify(src, L('tool_request_sent', C.name), 'info')
    SetTimeout(Config.Tools.RequestTimeout * 1000 + 500, function()
        if requests[r.id] == r and r.stage == 'asking' then
            release(r)
            TriggerClientEvent('nz-wig:c:promptClose', r.client, r.id)
            if Players[src] then Notify(src, L('tool_timeout', C.name), 'warning') end
        end
    end)
end)

function Tools.Reply(src, id, accept)
    local r = requests[id]
    if not r or r.client ~= src or r.stage ~= 'asking' then return end
    local B, C = Players[r.barber], Players[r.client]
    if not accept or not B or not C then
        release(r)
        if B then Notify(r.barber, L('tool_declined', C and C.name or '?'), 'warning') end
        return
    end
    if C.busy then release(r) return end
    C.busy = true
    r.stage = 'picking'
    local cuts = {}
    for i, cut in ipairs(Config.Tools.Cuts[GenderKey(r.model)] or {}) do
        local needsClippers = cut.clippers == true
        if (r.tool == 'clippers') == needsClippers then
            cuts[#cuts + 1] = { index = i, label = cut.label, drawable = cut.drawable }
        end
    end
    TriggerClientEvent('nz-wig:c:cutPicker', r.barber, { id = r.id, client = C.name, tool = r.tool, cuts = cuts, model = r.model })
end

RegisterNetEvent('nz-wig:s:toolPick', function(id, index)
    local src = source
    local r = requests[tonumber(id) or -1]
    if not r or r.barber ~= src or r.stage ~= 'picking' then return end
    local cut = (Config.Tools.Cuts[GenderKey(r.model)] or {})[tonumber(index) or -1]
    if not cut or ((r.tool == 'clippers') ~= (cut.clippers == true)) then return end
    local _, item = toolCfg(r.tool)
    if Inv.Count(src, item) < 1 then release(r) return Notify(src, L('tool_need', item), 'error') end
    run(r, function(B, C)
        C.hair.cut = { d = cut.drawable, t = 0, m = r.model }
        B.row.cuts = B.row.cuts + 1
        AddXP(B, Config.XP.Haircut)
        Hair.Push(C, 'cut')
        Notify(B.src, L('tool_done_barber'), 'success')
        Notify(C.src, L('tool_done_client'), 'success')
        Log('haircut', 'Haircut', ('**%s** gave **%s** a %s'):format(B.name, C.name, cut.label))
        SaveP(B) SaveP(C)
    end)
end)

RegisterNetEvent('nz-wig:s:toolCancel', function(id)
    local src = source
    local r = requests[tonumber(id) or -1]
    if not r or r.barber ~= src or r.stage == 'cutting' then return end
    release(r)
    Notify(r.client, L('tool_cancelled'), 'info')
end)

function Tools.OnDrop(src)
    for _, r in pairs(requests) do
        if r.barber == src or r.client == src then
            release(r)
            local other = r.barber == src and r.client or r.barber
            if Players[other] then
                Notify(other, L('tool_cancelled'), 'info')
                TriggerClientEvent('nz-wig:c:toolStop', other)
                TriggerClientEvent('nz-wig:c:promptClose', other, r.id)
            end
        end
    end
end
