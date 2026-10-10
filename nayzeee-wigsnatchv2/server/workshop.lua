-- Workshop: turn hair bundles into wigs, dye wigs, dye your own hair.
-- With wig tables on, making and dyeing wigs runs at a table in two calls, like the sneakers
-- crafting: tableStart checks everything and hands the client the stages, tableFinish (after the
-- stages played out) checks again, takes the materials and gives the result. Nothing is taken if
-- the player cancels or walks off part way.

Workshop = {}

local CW, CD, CT = Config.Workshop, Config.Dye, Config.Tables
local acting = {}
local useTables = CT.Enabled

local function maxHair(v) return Clamp(math.floor(tonumber(v) or 0), 0, 63) end

function Workshop.Info(src)
    local P = GetP(src)
    if not P then return nil end
    local bundles = {}
    for _, s in ipairs(Wigs.BundleStacks(src)) do
        local pub = Wigs.Public(s.meta, Wigs.Value(s.meta, 0))
        pub.key = s.key
        bundles[#bundles + 1] = pub
    end
    return {
        bundles = bundles,
        wigs = Wigs.List(src, 0),
        caps = Inv.Count(src, Config.Items.Cap),
        dyes = Inv.Count(src, Config.Items.Dye),
        need = CW.BundlesPerWig,
        needCap = CW.NeedCap,
        craft = CW.Enabled,
        dye = CD.Enabled,
        ownHair = CD.OwnHair,
        dyeBonus = CD.ValueBonus,
        hair = Hair.State(P),
        model = Hair.PedModelKey(src),
        needTable = useTables,
        capItem = Config.Items.Cap, capLabel = Crafting.ItemLabel(Config.Items.Cap),
        dyeItem = Config.Items.Dye, dyeLabel = Crafting.ItemLabel(Config.Items.Dye),
    }
end

-- everything the wig table window shows: your level, making from materials, from bundles, dyeing
lib.callback.register('nz-wig:bench', function(src)
    local P = GetP(src)
    if not P or not CT.Enabled then return false end
    local level = GetLevel(P.row.xp)
    local nextL = Config.Levels[level + 1]
    return {
        level = level, title = Config.Levels[level].title, xp = P.row.xp, from = Config.Levels[level].xp, to = nextL and nextL.xp or nil,
        make = Crafting.Info(src) or false,
        ws = Workshop.Info(src),
    }
end)

local function lowestGrade(list)
    local best
    for _, s in ipairs(list) do
        local i = GradeIndex[s.meta.grade] or 1
        if not best or i < best then best = i end
    end
    return Config.Bundles.Grades[best or 1]
end

-- the bundles picked for a wig, or nil + why not
local function pickBundles(src, keys)
    if type(keys) ~= 'table' or #keys ~= CW.BundlesPerWig then return nil, L('craft_need', CW.BundlesPerWig) end
    local byKey = {}
    for _, s in ipairs(Wigs.BundleStacks(src)) do byKey[s.key] = s end
    local picked, seen, model = {}, {}, nil
    for _, k in ipairs(keys) do
        local s = type(k) == 'string' and not seen[k] and byKey[k]
        if not s or s.generic or not s.meta.hair then return nil, L('craft_bad_bundle') end
        seen[k] = true
        model = model or s.meta.hair.m
        if s.meta.hair.m ~= model then return nil, L('craft_mixed') end
        picked[#picked + 1] = s
    end
    if CW.NeedCap and Inv.Count(src, Config.Items.Cap) < 1 then return nil, L('craft_need_cap') end
    return picked
end

-- make the wig. checks = { passed, failed } from a table job (nil without tables)
local function makeWig(src, P, picked, checks)
    -- everything still there?
    local still = {}
    for _, s in ipairs(Wigs.BundleStacks(src)) do still[s.key] = s end
    for _, s in ipairs(picked) do
        if not still[s.key] then return Notify(src, L('craft_bad_bundle'), 'error') end
    end
    if CW.NeedCap and Inv.Count(src, Config.Items.Cap) < 1 then return Notify(src, L('craft_need_cap'), 'error') end

    local passed, failed = checks and checks.passed or 0, checks and checks.failed or 0
    local grade = lowestGrade(picked)
    local tier = grade.tier
    if math.random() < CW.UpgradeChance + passed * CT.CheckUpgrade and TierIndex[tier] < #Config.Tiers then
        tier = Config.Tiers[TierIndex[tier] + 1].id
    end
    local len, from = 0, {}
    for _, s in ipairs(picked) do
        len = len + (s.meta.length or 14)
        if s.meta.from and #from < Config.Wig.ProvenanceSize then from[#from + 1] = s.meta.from end
    end
    len = math.floor(len / #picked)
    len = len - (len % 2)

    local first = picked[1].meta
    local meta = Wigs.Create(tier, first.hair, first.from or P.name, P.name, {
        crafted = P.name, grade = grade.id, length = len, owners = from,
    })
    if failed > 0 then
        meta.cond = math.max(20, (meta.cond or 100) - failed * CT.FailCondition)
        Wigs.Decorate(meta)
    end
    if not Wigs.CanCarry(src, meta) then return Notify(src, L('pockets_full'), 'error') end

    for _, s in ipairs(picked) do
        if not Wigs.Remove(src, still[s.key]) then return Notify(src, L('invalid'), 'error') end
    end
    if CW.NeedCap then Inv.Remove(src, Config.Items.Cap, 1) end
    Wigs.Give(src, meta)

    P.row.crafted = (P.row.crafted or 0) + 1
    local gain = Config.XP.Craft
    if checks and failed == 0 and passed > 0 then gain = gain + CT.PerfectXP end
    local xp = AddXP(P, gain)
    SaveP(P)
    Clash.CatalogCheck(P, meta)
    Notify(src, L('crafted', meta.label), 'success', 6000)
    TriggerClientEvent('nz-wig:c:crafted', src, { wig = Wigs.Public(meta, Wigs.Value(meta, 0)), xp = xp })
    TriggerClientEvent('nz-wig:c:refresh', src)
    Log('workshop', 'Wig crafted', ('**%s** made %s `%s` from %d bundles%s'):format(P.name, meta.label, meta.serial, #picked,
        checks and (' (%d/%d checks)'):format(passed, passed + failed) or ''))
    return meta
end

-- dye a wig
local function dyeWig(src, P, key, c, h, checks)
    local s = Wigs.Find(src, key)
    if not s or s.generic or not s.meta.hair then return Notify(src, L('invalid'), 'error') end
    if not Inv.Remove(src, Config.Items.Dye, 1) then return Notify(src, L('need_item', Config.Items.Dye), 'error') end
    s.meta.hair.c, s.meta.hair.h = c, h
    s.meta.dyed = true
    local failed = checks and checks.failed or 0
    if failed > 0 then s.meta.cond = math.max(5, (s.meta.cond or 100) - failed * math.floor(CT.FailCondition / 2)) end
    Wigs.Decorate(s.meta)
    Wigs.Update(src, s)
    Notify(src, L('dyed_wig'), 'success')
    TriggerClientEvent('nz-wig:c:refresh', src)
    Log('workshop', 'Wig dyed', ('**%s** dyed `%s` to %d / %d'):format(P.name, s.meta.serial or '-', c, h))
    return s.meta
end

RegisterNetEvent('nz-wig:s:craft', function(keys)
    local src = source
    local P = GetP(src)
    if not CW.Enabled or not P or acting[src] or P.busy then return end
    if useTables then return Notify(src, L('table_needed'), 'error') end
    local picked, why = pickBundles(src, keys)
    if not picked then return Notify(src, why, 'error') end

    acting[src] = true
    SetBusy(P, true)
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'craft', duration = CW.CraftTime, label = L('crafting') })
    SetTimeout(CW.CraftTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P then return end
        SetBusy(P, false)
        makeWig(src, P, picked)
    end)
end)

RegisterNetEvent('nz-wig:s:dye', function(key, c, h)
    local src = source
    local P = GetP(src)
    if not CD.Enabled or not P or acting[src] or P.busy or type(key) ~= 'string' then return end
    if useTables then return Notify(src, L('table_needed'), 'error') end
    local stack = Wigs.Find(src, key)
    if not stack or stack.generic or not stack.meta.hair or not Inv.HasMeta then return Notify(src, L('invalid'), 'error') end
    if Inv.Count(src, Config.Items.Dye) < 1 then return Notify(src, L('need_item', Config.Items.Dye), 'error') end
    c, h = maxHair(c), maxHair(h)

    acting[src] = true
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'dye', duration = CD.DyeTime, label = L('dyeing') })
    SetTimeout(CD.DyeTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P then return end
        dyeWig(src, P, key, c, h)
    end)
end)

-- dye your own hair. With a wig on, it's the wig you see, so that's what gets dyed
local function wornWig(P)
    local w = P.hair.wig
    return w and not w.generic and w.hair and w or nil
end

RegisterNetEvent('nz-wig:s:dyeSelf', function(c, h)
    local src = source
    local P = GetP(src)
    if not CD.Enabled or not CD.OwnHair or not P or acting[src] or P.busy then return end
    if P.hair.bald and not wornWig(P) then return Notify(src, L('dye_bald'), 'error') end
    if Inv.Count(src, Config.Items.Dye) < 1 then return Notify(src, L('need_item', Config.Items.Dye), 'error') end
    c, h = maxHair(c), maxHair(h)

    acting[src] = true
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'dyeSelf', duration = CD.DyeTime, label = L('dyeing') })
    SetTimeout(CD.DyeTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P then return end
        local wig = wornWig(P)
        if not wig and P.hair.bald then return end
        if not Inv.Remove(src, Config.Items.Dye, 1) then return end
        if wig then
            wig.hair.c, wig.hair.h = c, h
            wig.dyed = true
            Wigs.Decorate(wig)
        else
            P.hair.dye = { c = c, h = h }
        end
        SaveP(P)
        Hair.Push(P, 'dye')
        Notify(src, wig and L('dyed_worn_wig') or L('dyed_self'), 'success')
        TriggerClientEvent('nz-wig:c:refresh', src)
    end)
end)

RegisterNetEvent('nz-wig:s:rinse', function()
    local P = GetP(source)
    if not P or not P.hair.dye then return end
    P.hair.dye = nil
    SaveP(P)
    Hair.Push(P, 'dye')
    Notify(P.src, L('rinsed'), 'info')
    TriggerClientEvent('nz-wig:c:refresh', P.src)
end)


-- what the result card shows when a job at the table is done
function Workshop.Result(meta, passed, failed, dyed)
    if not meta then return nil end
    local t = GetTier(meta.tier)
    return {
        name = meta.label, tier = t and t.label or meta.tier, color = t and t.color, cond = meta.cond or 100,
        passed = passed, checks = passed + failed, dyed = dyed or nil,
        hair = meta.hair and { m = meta.hair.m, d = meta.hair.d, t = meta.hair.t } or nil,
    }
end

-- jobs at a wig table ---------------------------------------------------------------------------------

local sessions = {}     -- [src] = { token, tableId, kind, req, stages, started, minTime }

local function release(src)
    local s = sessions[src]
    if not s then return end
    sessions[src] = nil
    acting[src] = nil
    local t = Tables.Get(s.tableId)
    if t and t.user == src then t.user = nil end
    local P = Players[src]
    if P then SetBusy(P, false) end
end

-- stages for a job, faster with level
local function stagesFor(kind, P)
    local level = GetLevel(P.row.xp)
    local speed = 1.0 - math.min(0.4, (level - 1) * CT.SpeedPerLevel)
    local out = {}
    for i, st in ipairs(CT.Stages[kind] or {}) do
        out[i] = {
            label = st.label, time = math.floor(st.time * speed), prop = st.prop or false,
            check = CT.SkillChecks and st.check or false,
        }
    end
    return out
end

lib.callback.register('nz-wig:tableStart', function(src, tableId, kind, req)
    local P = GetP(src)
    if not CT.Enabled or not P or P.busy or acting[src] or type(req) ~= 'table' then return false end
    local t = Tables.Get(tableId)
    if not t or not Tables.Near(src, t) then return false end
    if not Tables.CanUse(src, t) then return false, L('table_not_yours') end
    local user = Tables.InUseBy(t)
    if user and user ~= src then return false, L('table_busy') end

    local job, show
    if kind == 'make' then
        local why
        job, why = Crafting.Check(src, P, req)
        if not job then return false, why end
        show = { m = job.m, d = job.d, t = job.t, c = job.c, h = job.h, wefts = job.recipe[Config.Crafting.WeftItem] }
    elseif kind == 'craft' then
        if not CW.Enabled then return false end
        local picked, why = pickBundles(src, req.keys)
        if not picked then return false, why end
        job = { keys = req.keys, model = picked[1].meta.hair.m }
        show = picked[1].meta.hair and { m = picked[1].meta.hair.m, d = picked[1].meta.hair.d, t = picked[1].meta.hair.t,
            c = picked[1].meta.hair.c, h = picked[1].meta.hair.h, wefts = #picked } or nil
    elseif kind == 'dye' then
        if not CD.Enabled or not Inv.HasMeta or type(req.key) ~= 'string' then return false end
        local stack = Wigs.Find(src, req.key)
        if not stack or stack.generic or not stack.meta.hair then return false, L('invalid') end
        if Inv.Count(src, Config.Items.Dye) < 1 then return false, L('need_item', Config.Items.Dye) end
        job = { key = req.key, c = maxHair(req.c), h = maxHair(req.h), hair = stack.meta.hair }
        local hr = stack.meta.hair
        show = { m = hr.m, d = hr.d, t = hr.t, c = hr.c, h = hr.h, toC = job.c, toH = job.h }
    else
        return false
    end

    release(src)
    local stages = stagesFor(kind, P)
    local total = 0
    for _, st in ipairs(stages) do total = total + st.time end
    local token = ('%d-%d'):format(src, math.random(100000, 999999))
    sessions[src] = { token = token, tableId = tableId, kind = kind, job = job, stages = stages, started = GetGameTimer(), minTime = total }
    acting[src] = true
    SetBusy(P, true)
    t.user = src
    return true, token, stages, show
end)

lib.callback.register('nz-wig:tableCancel', function(src)
    release(src)
    return true
end)

lib.callback.register('nz-wig:tableFinish', function(src, token, results)
    local s = sessions[src]
    if not s or s.token ~= token then return false end
    release(src)
    local P = GetP(src)
    if not P then return false end

    local t = Tables.Get(s.tableId)
    if not t or not Tables.Near(src, t, 3.0) then return false end
    if GetGameTimer() - s.started < s.minTime * 0.85 then return false end

    local passed, failed = 0, 0
    results = type(results) == 'table' and results or {}
    for i, st in ipairs(s.stages) do
        if st.check then
            if results[i] == true or results[tostring(i)] == true then passed = passed + 1 else failed = failed + 1 end
        end
    end
    local checks = { passed = passed, failed = failed }

    if s.kind == 'make' then
        local meta = Crafting.Make(src, P, s.job, checks)
        return meta ~= nil, Workshop.Result(meta, passed, failed)
    end
    if s.kind == 'craft' then
        local picked, why = pickBundles(src, s.job.keys)
        if not picked then Notify(src, why, 'error') return false end
        local meta = makeWig(src, P, picked, checks)
        return meta ~= nil, Workshop.Result(meta, passed, failed)
    end
    local meta = dyeWig(src, P, s.job.key, s.job.c, s.job.h, checks)
    if meta then
        local gain = AddXP(P, failed == 0 and passed > 0 and CT.PerfectXP or 0)
        if gain > 0 then SaveP(P) end
    end
    return meta ~= nil, Workshop.Result(meta, passed, failed, true)
end)

OnPlayerDrop(function(src)
    release(src)
    acting[src] = nil
end)
