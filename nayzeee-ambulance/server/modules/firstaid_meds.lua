--[[
    NAYZEEE AMBULANCE - First aid (server): medic medication (dose panel)

      NZA.Treat 'fa_med'   perm Config.Firstaid.Meds.perm ('meds'), states alive / wounded / arrest
          payload { drug = 'morphine'|'adrenaline'|'naloxone'|'txa'|'antibiotics'|'painkillers',
                    dose = index into the drug's doses, route = 'iv'|'io'|'im'|'in'|'po' }
          checks  the drug is configured, the route is allowed for it, IV / TXA need IV, IO or a port,
                  oral drugs need a patient who can swallow, the medic carries the drug item
          effects NZA.Patients.GiveMed(pid, drug, { dose, route, by }); morphine pushed with a low
                  respiratory rate adds opioid load (breathing gets worse); naloxone that reverses an
                  opioid overdose wakes the patient up agitated (speech + NPC reaction)

      Callback 'nza:firstaid:meds' (target) → panel data { now, state, vitals, pain, access, meds, given,
                                               pupils, drugs = { id = { active = seconds left } } }
      Net event 'nza:firstaid:agitated' (S→C, netId, text) - the medic's client plays the NPC's reaction
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Firstaid = NZA.Firstaid or {}
local FA = NZA.Firstaid
local U = NZA.Util
local Core = NZA.Core

local function L(key, ...) return NZA.L('firstaid.' .. key, ...) end
local function fail(key, ...) return false, { err = key, msg = L('err_' .. key, ...) } end

local function medsCfg() return (Config.Firstaid or {}).Meds or {} end

local function drugDef(id)
    if type(id) ~= 'string' then return nil end
    for _, d in ipairs(medsCfg().drugs or {}) do
        if d.id == id then return d end
    end
    return nil
end
FA.DrugDef = drugDef

local function hasAccess(p)
    local d = p.devices or {}
    if type(d.iv) == 'table' or d.iv == true then return true, (type(d.iv) == 'table' and d.iv.kind) or 'iv' end
    if d.port then return true, 'port' end
    return false, nil
end
FA.HasAccess = hasAccess

local function routeAllowed(drug, route)
    for _, r in ipairs(drug.routes or {}) do
        if r == route then return true end
        if r == 'iv' and route == 'io' then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- NALOXONE WAKE-UP
-- ════════════════════════════════════════════════════════════════════════

local function agitatedLine(p)
    local lines = {}
    for i = 1, 8 do
        local key = ('firstaid.agitated_%s_%d'):format(p.sex == 'f' and 'f' or 'm', i)
        local s = NZA.L(key)
        if s ~= key then lines[#lines + 1] = s end
    end
    if #lines == 0 then return nil end
    return lines[math.random(#lines)]
end

local function wakeUp(src, pid)
    SetTimeout(2500, function()
        local p = NZA.Patients.Get(pid)
        if not p or p.state == 'dead' or p.state == 'arrest' then return end
        NZA.Physiology.Recompute(p)
        local od = p.conditions.overdose
        if od and od.drug == 'opioid' and (od.amount or 0) > 25 then
            if Core.Online(src) then Core.Notify(src, L('naloxone_partial'), 'warning', L('title_meds')) end
            return
        end
        if p.state == 'wounded' and NZA.Patients.CanStand(p.pid) then
            NZA.Patients.SetState(p.pid, 'alive', 'naloxone')
        end
        local avpu = p.vitals and p.vitals.avpu or 'A'
        if avpu ~= 'A' and avpu ~= 'V' then return end
        local line = agitatedLine(p)
        if line and Core.Online(src) then Core.Speech(src, p.name, line, 4500) end
        if p.kind == 'npc' and p.net and Core.Online(src) then
            TriggerClientEvent('nza:firstaid:agitated', src, p.net)
        elseif p.kind == 'player' and p.src then
            Core.Notify(p.src, L('naloxone_player'), 'warning', L('title_meds'))
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- TREATMENT
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('fa_med', {
    perm = medsCfg().perm or 'meds', self = false, maxDist = 3.0, cooldown = 1500,
    states = { alive = true, wounded = true, arrest = true },
    items = function(src, p, payload)
        local drug = drugDef(type(payload) == 'table' and payload.drug or nil)
        if not drug then return {} end
        return FA.ItemsOf({ [drug.item or drug.id] = 1 })
    end,
    handler = function(src, p, payload)
        payload = type(payload) == 'table' and payload or {}
        local c = medsCfg()
        local drug = drugDef(payload.drug)
        if not drug or drug.enabled == false then return fail('unknown_drug') end
        if not FA.Item(drug.item or drug.id) then return fail('unknown_drug') end
        local route = type(payload.route) == 'string' and payload.route or (drug.routes or {})[1]
        if not routeAllowed(drug, route) then return fail('bad_route') end
        local doses = drug.doses or { { dose = 1, mg = '' } }
        local idx = math.floor(tonumber(payload.dose) or drug.default or 1)
        local doseDef = doses[idx]
        if not doseDef then return fail('bad_dose') end
        -- easy mode (the department's easy flag) skips the IV / IO access requirement, supplies are still needed
        local access = hasAccess(p) or NZA.Staff.Easy(src, c.perm or 'meds')
        if (route == 'iv' or route == 'io' or drug.access) and not access then return fail('no_access') end
        local avpu = p.vitals and p.vitals.avpu or 'A'
        if route == 'po' and (p.state == 'arrest' or (avpu ~= 'A' and avpu ~= 'V')) then return fail('cant_swallow') end

        local id = drug.id
        local v = p.vitals or {}
        local wasOpioidOd = p.conditions.overdose ~= nil and p.conditions.overdose.drug == 'opioid'
        local ok, info = NZA.Patients.GiveMed(p.pid, id, { dose = doseDef.dose or 1, route = route, by = src })
        if not ok then
            local err = type(info) == 'table' and info.err or 'failed'
            return false, { err = err, msg = (type(info) == 'table' and info.msg) or L('err_failed') }
        end

        local extra = nil
        if id == 'morphine' then
            local rr = tonumber(v.rr) or 16
            if rr < (c.morphineRR or 10) and p.state ~= 'arrest' then
                local od = p.conditions.overdose
                local add = (c.lowRRDepression or 18) * (doseDef.dose or 1)
                if od and od.drug == 'opioid' then
                    local nv = {}
                    for k, val in pairs(od) do nv[k] = val end
                    nv.amount = math.min(100, (od.amount or 0) + add)
                    NZA.Patients.SetCondition(p.pid, 'overdose', nv)
                elseif not od then
                    NZA.Patients.SetCondition(p.pid, 'overdose', { drug = 'opioid', amount = math.min(100, add), since = os.time() })
                end
                extra = L('morphine_depressed')
            end
        elseif id == 'naloxone' and wasOpioidOd and c.naloxoneWake ~= false then
            wakeUp(src, p.pid)
        end

        FA.Bill(src, p, 'meds')
        local drugLabel = L('drug_' .. id)
        local routeLabel = L('route_' .. route)
        local msg = L('ok_med', drugLabel, doseDef.mg or '', routeLabel)
        if extra then msg = msg .. ' ' .. extra end
        if type(info) == 'table' and info.msg and info.msg ~= '' and id ~= 'naloxone' then msg = msg .. ' · ' .. info.msg end
        return true, { msg = msg, drug = id, record = L('rec_med', drugLabel, doseDef.mg or '', routeLabel) }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- PANEL DATA
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:firstaid:meds', function(src, target)
    if not Core.Rate('nza:firstaid:meds', src, 4, 1000) then return nil, 'rate' end
    if not NZA.Staff.Can(src, medsCfg().perm or 'meds') then return nil, 'no_perm' end
    local p = NZA.Patients.Resolve(target)
    if not p then return nil, 'no_patient' end
    if not (p.kind == 'player' and p.src == src) and Core.DistanceTo(src, p) > 4.5 then return nil, 'too_far' end
    local now = os.time()
    local active = {}
    for name, exp in pairs(p.meds or {}) do
        local left = (tonumber(exp) or 0) - now
        if left > 0 then active[name] = left end
    end
    local access, kind = hasAccess(p)
    local v = p.vitals or {}
    return {
        now = now, name = p.name, state = p.state, pain = math.floor(tonumber(p.pain) or 0),
        vitals = {
            hr = math.floor(tonumber(v.hr) or 0), sys = math.floor(tonumber(v.sys) or 0), dia = math.floor(tonumber(v.dia) or 0),
            rr = math.floor(tonumber(v.rr) or 0), spo2 = math.floor(tonumber(v.spo2) or 0), avpu = v.avpu or 'A',
            pupils = v.pupils, breathing = v.breathing,
        },
        access = access and kind or false, active = active, given = p.given or {},
        lastAdrenaline = p.meta and p.meta.lastAdrenaline and (now - p.meta.lastAdrenaline) or nil,
        bleeding = U.round(tonumber(p.bleedTotal) or 0, 1),
    }
end)
