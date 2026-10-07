-- Hair state: bald (with regrow timer), worn wig, haircut. Persisted per character.
-- P.hair = { bald = { u = unix, d, t } | nil, wig = meta | nil, cut = { d, t } | nil }

Hair = {}

local function now() return os.time() end

function Hair.State(P)
    local h = P.hair
    return {
        bald = h.bald and { d = h.bald.d, t = h.bald.t, u = h.bald.u } or nil,
        wig  = h.wig and { hair = h.wig.hair, label = h.wig.label, tier = h.wig.tier, serial = h.wig.serial, cond = h.wig.cond } or nil,
        cut  = h.cut and { d = h.cut.d, t = h.cut.t, m = h.cut.m } or nil,
        now  = now(),
    }
end

function Hair.Push(P, reason)
    TriggerClientEvent('nz-wig:c:hair', P.src, Hair.State(P), reason)
end

-- visible layer: 'wig' | 'bald' | 'natural' (natural includes a haircut)
function Hair.Layer(P)
    if P.hair.wig then return 'wig' end
    if P.hair.bald then return 'bald' end
    return 'natural'
end

function Hair.Unschedule(P)
    P.hairToken = (P.hairToken or 0) + 1
end

function Hair.Schedule(P)
    Hair.Unschedule(P)
    local b = P.hair.bald
    if not b or (b.u or 0) <= 0 then return end
    local token, src, id = P.hairToken, P.src, P.id
    local ms = math.max(1000, (b.u - now()) * 1000)
    SetTimeout(math.floor(ms), function()
        local cur = Players[src]
        if not cur or cur.id ~= id or cur.hairToken ~= token or not cur.hair.bald then return end
        cur.hair.bald = nil
        SaveP(cur)
        Hair.Push(cur, 'regrown')
        Notify(src, L('regrown'), 'success')
    end)
end

function Hair.SetBald(P, modelKey)
    local style = Config.Snatch.BaldStyle[GenderKey(modelKey)] or { drawables = { 0 }, textures = { 0 } }
    local mins = Config.Snatch.RegrowMinutes or 0
    P.hair.bald = {
        d = style.drawables[math.random(1, #style.drawables)],
        t = style.textures[math.random(1, #style.textures)],
        u = mins > 0 and (now() + mins * 60) or 0,
    }
    -- a haircut someone gave you is gone with the hair
    P.hair.cut = nil
    Hair.Schedule(P)
end

function Hair.ClearBald(P)
    P.hair.bald = nil
    Hair.Unschedule(P)
end

function Hair.OnLoad(P)
    local b = P.hair.bald
    if b and (b.u or 0) > 0 and b.u <= now() then P.hair.bald = nil end
    Hair.Schedule(P)
    Hair.Push(P, 'load')
end

local function pedModelKey(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and ModelKey(GetEntityModel(ped)) or nil
end
Hair.PedModelKey = pedModelKey

-- wearing wigs -----------------------------------------------------------------

local function wear(P, stack)
    if P.busy then return Notify(P.src, L('busy'), 'error') end
    if not stack or stack.generic or not stack.meta.hair then return Notify(P.src, L('invalid'), 'error') end
    if pedModelKey(P.src) ~= stack.meta.hair.m then return Notify(P.src, L('wig_wrong_model'), 'error') end

    local old = P.hair.wig
    if old and not Wigs.CanCarry(P.src, old) then return Notify(P.src, L('pockets_full'), 'error') end
    if not Wigs.Remove(P.src, stack) then return Notify(P.src, L('invalid'), 'error') end
    if old then Wigs.Give(P.src, old) end

    P.hair.wig = stack.meta
    SaveP(P)
    TriggerClientEvent('nz-wig:c:anim', P.src, 'wear')
    SetTimeout(Config.Wig.WearAnim.duration or 1000, function()
        if Players[P.src] == P then Hair.Push(P, 'wear') end
    end)
    Notify(P.src, L('wig_on'), 'success')
end

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

-- glue + kits --------------------------------------------------------------------

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
    Wigs.Decorate(stack.meta)
    Inv.SetMeta(P.src, stack.slot, stack.meta)
    Notify(P.src, L('kit_used', stack.meta.cond), 'success')
    TriggerClientEvent('nz-wig:c:refresh', P.src)
end)

-- barber ---------------------------------------------------------------------------

local function nearBarber(src)
    if not Config.Barber.Enabled then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local c = GetEntityCoords(ped)
    for _, loc in ipairs(Config.Barber.Locations) do
        if #(c - loc) <= Config.Barber.Radius + 3.0 then return true end
    end
    return false
end

lib.callback.register('nz-wig:barber', function(src)
    local P = GetP(src)
    if not P or not nearBarber(src) then return nil end
    local wigs = {}
    for _, w in ipairs(Wigs.List(src, 0)) do
        if not w.generic and w.cond < 100 then
            w.repair = math.floor((100 - w.cond) * Config.Barber.RepairPerPoint)
            wigs[#wigs + 1] = w
        end
    end
    return {
        state = Hair.State(P),
        restorePrice = Config.Barber.RestorePrice,
        resetPrice = Config.Barber.ResetCutPrice,
        wigs = wigs,
        money = Bridge.GetMoney(src, Config.Barber.Account),
    }
end)

RegisterNetEvent('nz-wig:s:barberRestore', function()
    local src = source
    local P = GetP(src)
    if not P or P.busy or not nearBarber(src) then return end
    local price, what
    if P.hair.bald then price, what = Config.Barber.RestorePrice, 'bald'
    elseif P.hair.cut then price, what = Config.Barber.ResetCutPrice, 'cut'
    else return Notify(src, L('barber_not_needed'), 'info') end

    if price > 0 and not Bridge.RemoveMoney(src, price, Config.Barber.Account, 'wig-barber') then
        return Notify(src, L('no_money'), 'error')
    end
    if what == 'bald' then Hair.ClearBald(P) else P.hair.cut = nil end
    SaveP(P)
    Hair.Push(P, 'barber')
    Notify(src, what == 'bald' and L('restored') or L('cut_reset'), 'success')
    TriggerClientEvent('nz-wig:c:refresh', src)
end)

RegisterNetEvent('nz-wig:s:barberRepair', function(key)
    local src = source
    local P = GetP(src)
    if not P or type(key) ~= 'string' or not nearBarber(src) or not Inv.HasMeta then return end
    local stack = Wigs.Find(src, key)
    if not stack or stack.generic then return end
    local cond = stack.meta.cond or 100
    if cond >= 100 then return Notify(src, L('kit_full'), 'error') end
    local cost = math.floor((100 - cond) * Config.Barber.RepairPerPoint)
    if not Bridge.RemoveMoney(src, cost, Config.Barber.Account, 'wig-repair') then
        return Notify(src, L('no_money'), 'error')
    end
    stack.meta.cond = 100
    Wigs.Decorate(stack.meta)
    Inv.SetMeta(src, stack.slot, stack.meta)
    Notify(src, L('repaired', cost), 'success')
    TriggerClientEvent('nz-wig:c:refresh', src)
end)

-- usable items -----------------------------------------------------------------------

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
    Bridge.RegisterUsable(Config.Items.Kit, function(src)
        TriggerClientEvent('nz-wig:c:openVault', src, 'wigs')
    end)
end
