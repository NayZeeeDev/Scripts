-- Hair state, persisted per character:
-- P.hair = {
--   bald   = { d, t, u }            hair lost (snatch / shave / remover), u = regrows at (0 = never)
--   wig    = meta                   wig being worn
--   cut    = { d, t, m, kind, u }   haircut from a first person cut
--   face   = { brows, beard, u }    'thin' | 'gone' / 'trim' | 'gone'
--   dye    = { c, h }               own hair dyed
--   status = { burn = u, lice = u, dirt = u }
-- }

Hair = {}

local function now() return os.time() end

function Hair.State(P)
    local h = P.hair
    local status = {}
    for k, u in pairs(h.status or {}) do
        if u > now() then status[k] = u end
    end
    return {
        bald   = h.bald and { d = h.bald.d, t = h.bald.t, u = h.bald.u } or nil,
        wig    = h.wig and { hair = h.wig.hair, label = h.wig.label, tier = h.wig.tier, serial = h.wig.serial, cond = h.wig.cond } or nil,
        cut    = h.cut and { d = h.cut.d, t = h.cut.t, m = h.cut.m, kind = h.cut.kind, u = h.cut.u } or nil,
        face   = h.face and { brows = h.face.brows, beard = h.face.beard, u = h.face.u } or nil,
        dye    = h.dye,
        status = status,
        now    = now(),
    }
end

-- statuses other players need to see (smoke, flies, mud)
local function syncFx(P)
    local fx, any = {}, false
    for k, u in pairs(P.hair.status or {}) do
        if u > now() then fx[k] = true any = true end
    end
    Player(P.src).state:set(ST.fx, any and fx or nil, true)
end

function Hair.Push(P, reason)
    syncFx(P)
    Player(P.src).state:set(ST.wig, P.hair.wig and true or nil, true)
    TriggerClientEvent('nz-wig:c:hair', P.src, Hair.State(P), reason)
end

-- visible layer: 'wig' | 'bald' | 'natural' (natural includes a haircut)
function Hair.Layer(P)
    if P.hair.wig then return 'wig' end
    if P.hair.bald then return 'bald' end
    return 'natural'
end

function Hair.HasStatus(P, kind)
    local s = P.hair.status
    return s ~= nil and (s[kind] or 0) > now()
end

-- one timer per player for whatever expires next ---------------------------------------------

local function expiries(P)
    local h, list = P.hair, {}
    if h.bald and (h.bald.u or 0) > 0 then list[#list + 1] = h.bald.u end
    if h.cut and (h.cut.u or 0) > 0 then list[#list + 1] = h.cut.u end
    if h.face and (h.face.u or 0) > 0 then list[#list + 1] = h.face.u end
    for _, u in pairs(h.status or {}) do list[#list + 1] = u end
    return list
end

-- clears everything that has expired, returns a list of what changed
local function expire(P)
    local h, t, changed = P.hair, now(), {}
    if h.bald and (h.bald.u or 0) > 0 and h.bald.u <= t then h.bald = nil changed[#changed + 1] = 'bald' end
    if h.cut and (h.cut.u or 0) > 0 and h.cut.u <= t then h.cut = nil changed[#changed + 1] = 'cut' end
    if h.face and (h.face.u or 0) > 0 and h.face.u <= t then h.face = nil changed[#changed + 1] = 'face' end
    if h.status then
        for k, u in pairs(h.status) do
            if u <= t then h.status[k] = nil changed[#changed + 1] = k end
        end
        if next(h.status) == nil then h.status = nil end
    end
    return changed
end

function Hair.Unschedule(P)
    P.hairToken = (P.hairToken or 0) + 1
end

function Hair.Schedule(P)
    Hair.Unschedule(P)
    local soonest
    for _, u in ipairs(expiries(P)) do
        if not soonest or u < soonest then soonest = u end
    end
    if not soonest then return end
    local token, src, id = P.hairToken, P.src, P.id
    SetTimeout(math.floor(math.max(1000, (soonest - now()) * 1000 + 250)), function()
        local cur = Players[src]
        if not cur or cur.id ~= id or cur.hairToken ~= token then return end
        local changed = expire(cur)
        if #changed > 0 then
            SaveP(cur)
            Hair.Push(cur, 'expired')
            for _, k in ipairs(changed) do
                if k == 'bald' then Notify(src, L('regrown'), 'success')
                elseif k == 'face' then Notify(src, L('face_regrown'), 'success')
                elseif k == 'cut' then Notify(src, L('cut_grown_out'), 'info')
                elseif Config.Products.Status[k] then Notify(src, L('status_gone', Config.Products.Status[k].Label), 'info') end
            end
        end
        Hair.Schedule(cur)
    end)
end

local function regrowAt(mins)
    mins = mins or 0
    return mins > 0 and (now() + mins * 60) or 0
end

function Hair.SetBald(P, modelKey, minutes)
    local style = Config.Snatch.BaldStyle[GenderKey(modelKey)] or { drawables = { 0 }, textures = { 0 } }
    P.hair.bald = {
        d = style.drawables[math.random(1, #style.drawables)],
        t = style.textures[math.random(1, #style.textures)],
        u = regrowAt(minutes or Config.Snatch.RegrowMinutes),
    }
    -- a haircut and dye go with the hair
    P.hair.cut = nil
    P.hair.dye = nil
    Hair.Schedule(P)
end

function Hair.ClearBald(P)
    P.hair.bald = nil
    Hair.Schedule(P)
end

function Hair.SetCut(P, model, kind, drawable, minutes)
    P.hair.cut = { d = drawable, t = 0, m = model, kind = kind, u = regrowAt(minutes or Config.Snatch.RegrowMinutes) }
    Hair.Schedule(P)
end

function Hair.SetFace(P, part, value)
    P.hair.face = P.hair.face or {}
    P.hair.face[part] = value
    P.hair.face.u = regrowAt(Config.Cutting.FaceRegrowMinutes)
    Hair.Schedule(P)
end

function Hair.SetStatus(P, kind, minutes)
    P.hair.status = P.hair.status or {}
    P.hair.status[kind] = now() + math.max(1, minutes or 10) * 60
    Hair.Schedule(P)
end

function Hair.ClearStatus(P, kind)
    if not P.hair.status then return false end
    local had = (P.hair.status[kind] or 0) > now()
    P.hair.status[kind] = nil
    if next(P.hair.status) == nil then P.hair.status = nil end
    Hair.Schedule(P)
    return had
end

-- Regrowth oil: everything grows back (or minutes come off every timer)
function Hair.Regrow(P, minutes)
    local h = P.hair
    if not h.bald and not h.cut and not h.face and not Hair.HasStatus(P, 'burn') then return false end
    if (minutes or 0) <= 0 then
        h.bald, h.cut, h.face = nil, nil, nil
        Hair.ClearStatus(P, 'burn')
    else
        local cut = minutes * 60
        for _, part in ipairs({ h.bald, h.cut, h.face }) do
            if part and (part.u or 0) > 0 then part.u = part.u - cut end
            if part and (part.u or 0) == 0 then part.u = now() + 1 end -- "never" timers start counting
        end
        if h.status and h.status.burn then h.status.burn = h.status.burn - cut end
        expire(P)
    end
    Hair.Schedule(P)
    return true
end

Hair.Expire = expire

OnPlayerLoad(function(P)
    expire(P)
    Hair.Schedule(P)
    Hair.Push(P, 'load')
end)

OnPlayerDrop(function(_, P)
    Hair.Unschedule(P)
end)

local function pedModelKey(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and ModelKey(GetEntityModel(ped)) or nil
end
Hair.PedModelKey = pedModelKey

-- wearing wigs -----------------------------------------------------------------------------------

local function putOnWig(P, meta)
    P.hair.wig = meta
    SaveP(P)
    TriggerClientEvent('nz-wig:c:anim', P.src, 'wear')
    SetTimeout(Config.Wig.WearAnim.duration or 1000, function()
        if Players[P.src] == P then Hair.Push(P, 'wear') end
    end)
end

local function wear(P, stack)
    if P.busy then return Notify(P.src, L('busy'), 'error') end
    if not stack or stack.generic or not stack.meta.hair then return Notify(P.src, L('invalid'), 'error') end
    if pedModelKey(P.src) ~= stack.meta.hair.m then return Notify(P.src, L('wig_wrong_model'), 'error') end

    local old = P.hair.wig
    if old and not Wigs.CanCarry(P.src, old) then return Notify(P.src, L('pockets_full'), 'error') end
    if not Wigs.Remove(P.src, stack) then return Notify(P.src, L('invalid'), 'error') end
    if old then Wigs.Give(P.src, old) end

    putOnWig(P, stack.meta)
    Notify(P.src, L('wig_on'), 'success')
end
Hair.Wear = wear

function Hair.Unwear(P)
    local wig = P.hair.wig
    if not wig then return Notify(P.src, L('no_wig_worn'), 'error') end
    if P.busy then return Notify(P.src, L('busy'), 'error') end
    if not Wigs.CanCarry(P.src, wig) then return Notify(P.src, L('pockets_full'), 'error') end
    if not Wigs.Give(P.src, wig) then return Notify(P.src, L('invalid'), 'error') end
    P.hair.wig = nil
    SaveP(P)
    TriggerClientEvent('nz-wig:c:anim', P.src, 'wear')
    SetTimeout(Config.Wig.WearAnim.duration or 1000, function()
        if Players[P.src] == P then Hair.Push(P, 'unwear') end
    end)
    Notify(P.src, L('wig_off'), 'info')
end

RegisterNetEvent('nz-wig:s:wear', function(key)
    local P = GetP(source)
    if not P or type(key) ~= 'string' then return end
    wear(P, Wigs.Find(P.src, key))
end)

RegisterNetEvent('nz-wig:s:unwear', function()
    local P = GetP(source)
    if P then Hair.Unwear(P) end
end)

-- putting a wig on someone else / taking one off them ---------------------------------------------

local pending, pseq = {}, 0 -- [id] = { kind, from, to, key, exp }

local function clearPending(id)
    local r = pending[id]
    if not r then return end
    pending[id] = nil
    local A, B = Players[r.from], Players[r.to]
    if A then SetBusy(A, false) end
    if B then SetBusy(B, false) end
end

local function newPending(kind, from, to, key)
    pseq = pseq + 1
    local r = { id = pseq, kind = kind, from = from, to = to, key = key }
    pending[r.id] = r
    SetTimeout(20500, function()
        if pending[r.id] == r then
            clearPending(r.id)
            ClosePrompt(r.to, r.id)
            if Players[from] then Notify(from, L('prompt_timeout'), 'warning') end
        end
    end)
    return r
end

-- give the wig in `key` to `target` and put it on their head
RegisterNetEvent('nz-wig:s:putOn', function(target, key)
    local src = source
    local A, B = GetP(src), GetP(tonumber(target))
    if not Config.Wig.PutOnOthers or not A or not B or A == B or type(key) ~= 'string' then return end
    if A.busy or B.busy then return Notify(src, L(A.busy and 'busy' or 'target_busy'), 'error') end
    if PedDistance(src, B.src) > 3.0 then return Notify(src, L('no_one_close'), 'error') end
    local stack = Wigs.Find(src, key)
    if not stack or stack.generic or not stack.meta.hair then return Notify(src, L('invalid'), 'error') end
    if pedModelKey(B.src) ~= stack.meta.hair.m then return Notify(src, L('wig_wrong_model_them'), 'error') end

    local r = newPending('puton', src, B.src, key)
    SetBusy(A, true)
    SetBusy(B, true)
    SendPrompt(B.src, {
        kind = 'puton', id = r.id, timeout = 20,
        title = L('puton_title'), body = L('puton_body', A.name),
        wig = Wigs.Public(stack.meta, Wigs.Value(stack.meta, 0)),
    })
    Notify(src, L('prompt_sent', B.name), 'info')
end)

PromptHandlers.puton = function(src, id, accept)
    local r = pending[id]
    if not r or r.to ~= src or r.kind ~= 'puton' then return end
    clearPending(id)
    local A, B = Players[r.from], Players[r.to]
    if not A or not B then return end
    if not accept then return Notify(A.src, L('prompt_declined', B.name), 'warning') end
    if PedDistance(A.src, B.src) > 3.5 then return Notify(A.src, L('no_one_close'), 'error') end

    local stack = Wigs.Find(A.src, r.key)
    if not stack or pedModelKey(B.src) ~= stack.meta.hair.m then return Notify(A.src, L('invalid'), 'error') end
    local old = B.hair.wig
    if old and not Wigs.CanCarry(B.src, old) then return Notify(A.src, L('their_pockets_full'), 'error') end
    if not Wigs.Remove(A.src, stack) then return Notify(A.src, L('invalid'), 'error') end
    if old then Wigs.Give(B.src, old) end

    TriggerClientEvent('nz-wig:c:anim', A.src, 'apply', B.src)
    putOnWig(B, stack.meta)
    Notify(A.src, L('puton_done', B.name), 'success')
    Notify(B.src, L('puton_got', A.name), 'success')
    Log('trade', 'Wig put on someone', ('**%s** put %s `%s` on **%s**'):format(A.name, stack.meta.label or 'a wig', stack.meta.serial or '-', B.name))
end

-- take the wig off someone (it goes back into THEIR pockets)
RegisterNetEvent('nz-wig:s:takeOff', function(target)
    local src = source
    local A, B = GetP(src), GetP(tonumber(target))
    if not Config.Wig.TakeOffOthers or not A or not B or A == B then return end
    if A.busy or B.busy then return Notify(src, L(A.busy and 'busy' or 'target_busy'), 'error') end
    if not B.hair.wig then return Notify(src, L('not_wearing_wig'), 'error') end
    if PedDistance(src, B.src) > 3.0 then return Notify(src, L('no_one_close'), 'error') end

    local r = newPending('takeoff', src, B.src)
    SetBusy(A, true)
    SetBusy(B, true)
    SendPrompt(B.src, { kind = 'takeoff', id = r.id, timeout = 20, title = L('takeoff_title'), body = L('takeoff_body', A.name) })
    Notify(src, L('prompt_sent', B.name), 'info')
end)

PromptHandlers.takeoff = function(src, id, accept)
    local r = pending[id]
    if not r or r.to ~= src or r.kind ~= 'takeoff' then return end
    clearPending(id)
    local A, B = Players[r.from], Players[r.to]
    if not A or not B then return end
    if not accept then return Notify(A.src, L('prompt_declined', B.name), 'warning') end
    if PedDistance(A.src, B.src) > 3.5 then return Notify(A.src, L('no_one_close'), 'error') end
    local wig = B.hair.wig
    if not wig then return end
    if not Wigs.CanCarry(B.src, wig) then return Notify(A.src, L('their_pockets_full'), 'error') end
    if not Wigs.Give(B.src, wig) then return end
    B.hair.wig = nil
    SaveP(B)
    TriggerClientEvent('nz-wig:c:anim', A.src, 'apply', B.src)
    SetTimeout(Config.Wig.WearAnim.duration or 1000, function()
        if Players[B.src] == B then Hair.Push(B, 'unwear') end
    end)
    Notify(A.src, L('takeoff_done', B.name), 'success')
    Notify(B.src, L('takeoff_got', A.name), 'info')
end

OnPlayerDrop(function(src)
    for id, r in pairs(pending) do
        if r.from == src or r.to == src then
            local other = r.from == src and r.to or r.from
            clearPending(id)
            ClosePrompt(other, id)
        end
    end
end)

-- glue + kits ---------------------------------------------------------------------------------------

local function useGlue(src)
    local P = GetP(src)
    if not P or P.busy then return end
    if Hair.Layer(P) == 'bald' then return Notify(src, L('glue_bald'), 'error') end
    if not Inv.Remove(src, Config.Items.Glue, 1) then return end
    P.row.glue_until = math.max(now(), P.row.glue_until or 0) + Config.Glue.Duration
    SaveP(P)
    SyncP(P)
    TriggerClientEvent('nz-wig:c:anim', src, 'glue')
    Notify(src, L('glue_on', math.floor((P.row.glue_until - now()) / 60)), 'success')
end

function Hair.IsGlued(P)
    return (P.row.glue_until or 0) > now()
end

RegisterNetEvent('nz-wig:s:repair', function(key)
    local P = GetP(source)
    if not P or type(key) ~= 'string' then return end
    local stack = Wigs.Find(P.src, key)
    if not stack or stack.generic or not Inv.HasMeta then return Notify(P.src, L('invalid'), 'error') end
    if (stack.meta.cond or 100) >= 100 then return Notify(P.src, L('kit_full'), 'error') end
    if Inv.Count(P.src, Config.Items.Kit) < 1 then return Notify(P.src, L('no_kit'), 'error') end
    if not Inv.Remove(P.src, Config.Items.Kit, 1) then return end
    stack.meta.cond = math.min(100, (stack.meta.cond or 100) + Config.Wig.KitRepair)
    Wigs.Update(P.src, stack)
    Notify(P.src, L('kit_used', stack.meta.cond), 'success')
    TriggerClientEvent('nz-wig:c:refresh', P.src)
end)

-- usable items ---------------------------------------------------------------------------------------

function Hair.RegisterItems()
    Bridge.RegisterUsable(Config.Items.Wig, function(src, data)
        local P = GetP(src)
        if not P then return end
        local meta = type(data) == 'table' and (data.metadata or data.info) or nil
        if meta and meta.serial then
            return wear(P, Wigs.Find(src, meta.serial))
        end
        TriggerClientEvent('nz-wig:c:openVault', src, 'wigs')
    end)
    Bridge.RegisterUsable(Config.Items.Glue, function(src) useGlue(src) end)
    for _, item in ipairs({ Config.Items.Kit }) do
        Bridge.RegisterUsable(item, function(src) TriggerClientEvent('nz-wig:c:openVault', src, 'wigs') end)
    end
    for _, item in ipairs({ Config.Items.Bundle, Config.Items.Cap, Config.Items.Dye }) do
        Bridge.RegisterUsable(item, function(src) TriggerClientEvent('nz-wig:c:openVault', src, 'workshop') end)
    end
end

-- my wigs (for the "put a wig on someone" picker)
lib.callback.register('nz-wig:myWigs', function(src)
    return GetP(src) and Wigs.List(src, 0) or {}
end)
