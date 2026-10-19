--[[
    NAYZEEE AMBULANCE - Client core: guided care (NZA.Care)

    The server lists what every patient still needs (server/core/care.lua → state bag
    summary.plan). This file turns that list into something a medic can follow:

      · a short third eye (Config.Care.guided): Check patient, the next step by name
        ("Stop the bleeding"), moving the patient, and 'More...' for every other tool
      · NZA.Care.Run(entity, target, step): runs the right treatment for a step — an exam
        route when the step belongs to one wound, else the module's interaction option
      · a small steps card on the HUD while you stand near a patient you checked
      · the step list for the head-to-toe check ('Care steps' card, assess_exam.lua)

      NZA.Care.Steps(entity)               → plan from the state bag ({ c, r, i, w, u }, ...)
      NZA.Care.Visible(entity, steps)      → the steps this medic may see (check gating)
      NZA.Care.MarkChecked(target, pid)    → called by the head-to-toe check
      NZA.Care.IsChecked(entityOrTarget)   → bool
      NZA.Care.Describe(step)              → { code, title, why, where, urgent, region }
      NZA.Care.Resolve(entity, target, step, snap) → action | nil, reason
      NZA.Care.Run(entity, target, step, snap)     → bool
      NZA.Care.AlwaysShow(optionName)      → bool (guided third eye keeps it)
      NZA.Care.Actions[code]               = { routes = { exam route ids }, options = { option names } }
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Care = NZA.Care or {}
local Care = NZA.Care

local function cfg(key, default)
    local c = Config.Care
    if type(c) ~= 'table' or c[key] == nil then return default end
    return c[key]
end

local function L(key, ...) return NZA.L('care.' .. key, ...) end

-- ════════════════════════════════════════════════════════════════════════
-- WHAT RUNS EACH STEP (exam routes first: they know the wound; then options)
-- ════════════════════════════════════════════════════════════════════════

Care.Actions = {
    extricate = { routes = {},                                      options = { 'nza_calls_extricate' },                    icon = 'wrench' },
    release   = { routes = {},                                      options = { 'nza_calls_release' },                      icon = 'walk' },
    cpr       = { routes = { 'cpr' },                               options = { 'nza_cpr', 'nza_cpr_join' },                icon = 'heart' },
    bleed     = { routes = { 'tourniquet', 'stopbleed' },           options = { 'nza_fa_stopbleed', 'nza_fa_tq' },          icon = 'drop' },
    airway    = { routes = { 'airway_retube', 'airway_intubate', 'airway_bvm' }, options = { 'nza_airway_bvm', 'nza_airway_intubate' }, icon = 'wind' },
    recovery  = { routes = {},                                      options = { 'nza_fa_recovery' },                        icon = 'person' },
    infection = { routes = {},                                      options = { 'nza_fa_meds' },                            icon = 'pill' },
    breathing = { routes = { 'airway_bvm' },                        options = { 'nza_fa_oxygen', 'nza_airway_bvm' },        icon = 'lungs' },
    chest     = { routes = { 'us_decomp' },                         options = { 'nza_us_decomp' },                          icon = 'lungs' },
    overdose  = { routes = {},                                      options = { 'nza_fa_meds' },                            icon = 'pill' },
    binder    = { routes = { 'field_resus' },                       options = { 'nza_field_resus' },                        icon = 'cuff' },
    fluids    = { routes = { 'field_resus', 'field_iv', 'transfuse' }, options = { 'nza_field_resus', 'nza_field_iv', 'nza_blood_stand' }, icon = 'iv' },
    warm      = { routes = {},                                      options = { 'nza_fa_foil' },                            icon = 'blanket' },
    collar    = { routes = { 'collar' },                            options = { 'nza_fa_collar' },                          icon = 'collar' },
    splint    = { routes = { 'splint' },                            options = { 'nza_splint' },                             icon = 'bone' },
    burn      = { routes = { 'burn', 'burndressing' },              options = { 'nza_burn' },                               icon = 'flame' },
    wound     = { routes = { 'suture', 'stopbleed' },               options = { 'nza_suture', 'nza_fa_kit', 'nza_fa_stopbleed' }, icon = 'needle' },
    cool      = { routes = { 'ice' },                               options = { 'nza_fa_kit' },                             icon = 'snow' },
    pain      = { routes = { 'painrelief', 'morphine' },            options = { 'nza_fa_meds' },                            icon = 'pill' },
    standup   = { routes = {},                                      options = { 'nza_tr_helpup' },                          icon = 'walk' },
    scan      = { routes = { 'us_scan' },                           options = { 'nza_us_scan' },                            icon = 'scan' },
    internal  = { routes = { 'angio' },                             options = { 'nza_angio' },                              icon = 'scan' },
    drain     = { routes = { 'us_drain' },                          options = { 'nza_us_drain' },                           icon = 'lungs' },
    tamponade = { routes = { 'us_peri' },                           options = { 'nza_us_peri' },                            icon = 'heart' },
    bullet    = { routes = { 'bullet' },                            options = { 'nza_bullet' },                             icon = 'scalpel' },
    xray      = { routes = { 'xray_take', 'xray_reduce', 'xray_cast' }, options = { 'nza_xray_table', 'nza_xray_any', 'nza_xray_reduce', 'nza_xray_cast' }, icon = 'bone' },
    graft     = { routes = { 'graft' },                             options = { 'nza_graft' },                              icon = 'flame' },
    hospital  = { routes = {},                                      options = { 'nza_tr_tobed', 'nza_tr_onstretcher', 'nza_tr_carry' }, icon = 'ambulance' },
    bodybag   = { routes = {},                                      options = { 'nza_bodybag' },                            icon = 'bag' },
}

-- steps a medic sees without a check (you can see someone has no pulse or is bleeding out)
local OBVIOUS = { cpr = true, bodybag = true }

-- options the guided third eye keeps: checking, moving and handing over the patient
local ALWAYS = {
    nza_examine = true,
    nza_tr_carry = true, nza_tr_helpup = true, nza_tr_onstretcher = true, nza_tr_offstretcher = true,
    nza_tr_tobed = true, nza_tr_bedleave = true, nza_tr_outveh = true,
    nza_chair_seat = true, nza_chair_unseat = true,
    nza_calls_extricate = true, nza_calls_release = true,
    nza_askwalk = true, nza_stopwalk = true,
    nza_cpr_join = true, nza_bodybag = true, nza_xray_table = true, nza_pharmacy_bill = true,
}
local extraAlways = nil

function Care.AlwaysShow(name)
    if ALWAYS[name] then return true end
    if extraAlways == nil then
        extraAlways = {}
        for _, n in ipairs(cfg('alwaysShow', {}) or {}) do extraAlways[n] = true end
    end
    return extraAlways[name] == true
end

-- ════════════════════════════════════════════════════════════════════════
-- CHECKED PATIENTS (the steps show after a head-to-toe check)
-- ════════════════════════════════════════════════════════════════════════

local checked = {}      -- [target key] = { pid, at }
local CHECK_TTL = 30 * 60

function Care.MarkChecked(target, pid)
    local key = NZA.Target.Key(target)
    if key then checked[key] = { pid = pid, at = GetGameTimer() } end
end

function Care.IsChecked(x)
    if not cfg('needCheck', true) then return true end
    local target = type(x) == 'table' and x or NZA.Target.FromEntity(x)
    local key = target and NZA.Target.Key(target)
    local c = key and checked[key]
    if not c then return false end
    if GetGameTimer() - c.at > CHECK_TTL * 1000 then checked[key] = nil return false end
    local st = NZA.Target.State(target)
    if type(st) == 'table' and st.pid and c.pid and st.pid ~= c.pid then checked[key] = nil return false end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- STEPS
-- ════════════════════════════════════════════════════════════════════════

function Care.Steps(x)
    local st = NZA.Target.State(x)
    if type(st) ~= 'table' or type(st.plan) ~= 'table' then return {} end
    return st.plan
end

function Care.Visible(x, steps)
    steps = steps or Care.Steps(x)
    if Care.IsChecked(x) then return steps end
    local out = {}
    for _, s in ipairs(steps) do
        if OBVIOUS[s.c] or (s.c == 'bleed' and s.u) then out[#out + 1] = s end
    end
    return out
end

local function regionLabel(r)
    if not r then return nil end
    return NZA.Util and NZA.Util.RegionLabel and NZA.Util.RegionLabel(r) or r
end

function Care.Describe(s, steps)
    local region = regionLabel(s.r)
    local why
    if s.c == 'hospital' then
        why = L('why_hospital', tonumber(s.n) or 1)
    elseif region then
        -- 'inside the chest' mid-sentence, 'Chest is ...' at the start
        local tpl = NZA.L('care.why_' .. s.c)
        why = L('why_' .. s.c, (tpl:find('the %%s') or tpl:find('on the %%s')) and region:lower() or region)
    else
        why = L('why_' .. s.c, L('wound_generic'))
        if why:find('%%s') then why = why:gsub('%%s', '') end
    end
    local a = Care.Actions[s.c] or {}
    return {
        code = s.c, title = L('do_' .. s.c), why = why, region = region, injury = s.i,
        where = s.w == 'hospital' and 'hospital' or 'field', urgent = s.u == true, icon = a.icon,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- RESOLVE & RUN
-- ════════════════════════════════════════════════════════════════════════

local function has(list, v)
    if type(list) ~= 'table' then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function findRoute(id)
    for _, r in ipairs(NZA.ExamRoutes or {}) do
        if type(r) == 'table' and r.id == id then return r end
    end
    return nil
end

local function itemCount(name)
    if Bridge and Bridge.Inv then
        if Bridge.Inv.Count then
            local ok, n = pcall(Bridge.Inv.Count, name)
            if ok and tonumber(n) then return tonumber(n) end
        end
        if Bridge.Inv.Has then
            local ok, yes = pcall(Bridge.Inv.Has, name, 1)
            if ok then return yes and 1 or 0 end
        end
    end
    return 0
end

local function itemLabel(name)
    if NZA.Assess and NZA.Assess.ItemLabel then
        local ok, l = pcall(NZA.Assess.ItemLabel, name)
        if ok and l then return l end
    end
    return name
end

local function findInjury(snap, id)
    if type(snap) ~= 'table' or not id then return nil end
    for _, inj in ipairs(snap.injuries or {}) do
        if inj.id == id then return inj end
    end
    return nil
end

-- → { kind = 'route', route, inj } | { kind = 'option', opt } | nil, reason
function Care.Resolve(entity, target, step, snap)
    local A = Care.Actions[step.c]
    if not A then return nil, L('no_action') end
    local missing = nil
    local inj = findInjury(snap, step.i)
    local pseudo = inj or { id = 'care:' .. step.c, region = step.r or 'chest', type = 'care', severity = 2, treat = {} }
    for _, rid in ipairs(A.routes or {}) do
        local r = findRoute(rid)
        if r and r.run and (r.perm == nil or NZA.Perm(r.perm)) and snap then
            local fits = (r.types == nil or (inj and has(r.types, inj.type))) and (r.regions == nil or (inj and has(r.regions, inj.region)))
            if fits then
                local avail = true
                if type(r.available) == 'function' then
                    local ok, a = pcall(r.available, pseudo, snap)
                    avail = ok and a and true or false
                end
                if avail then
                    local lacking = nil
                    for name, need in pairs(type(r.items) == 'table' and r.items or {}) do
                        if itemCount(name) < (tonumber(need) or 1) then lacking = itemLabel(name) break end
                    end
                    if not lacking then return { kind = 'route', route = r, inj = pseudo } end
                    missing = missing or L('need_item', lacking)
                end
            end
        end
    end
    for _, name in ipairs(A.options or {}) do
        local opt = NZA.Interact.Get(name)
        if opt and entity and entity ~= 0 and NZA.Interact.Allowed(opt, entity, true) then
            return { kind = 'option', opt = opt }
        end
    end
    if step.w == 'hospital' then return nil, missing or L('at_hospital') end
    return nil, missing or L('no_action')
end

function Care.Run(entity, target, step, snap)
    if type(step) ~= 'table' or not step.c then return false end
    target = target or NZA.Target.FromEntity(entity)
    if not target then return false end
    entity = (entity and entity ~= 0) and entity or NZA.Target.Entity(target)
    if not snap and #((Care.Actions[step.c] or {}).routes or {}) > 0 then
        snap = NZA.Patient.Get(target)
    end
    local act, why = Care.Resolve(entity, target, step, snap)
    if not act then
        NZA.UI.Toast({ title = L('title'), message = why or L('no_action'), type = 'error' })
        return false
    end
    if act.kind == 'route' then
        local ok, err = pcall(act.route.run, target, act.inj, snap)
        if not ok then NZA.Warn(('care step "%s" (%s) failed: %s'):format(step.c, tostring(act.route.id), tostring(err))) end
        return ok
    end
    return NZA.Interact.Run(act.opt, entity)
end

-- ════════════════════════════════════════════════════════════════════════
-- GUIDED THIRD EYE: one option per step code, shown only when it is the next step
-- ════════════════════════════════════════════════════════════════════════

-- the step codes whose own option is already on the third eye (help up, stretcher, body bag)
local NO_STEP_OPTION = { standup = true, hospital = true, bodybag = true, extricate = true, release = true }

local function guided() return cfg('guided', true) ~= false end

local function nextSteps(entity, st)
    local plan = (type(st) == 'table' and type(st.plan) == 'table') and st.plan or {}
    if #plan == 0 then return {} end
    local vis = Care.Visible(entity, plan)
    local n = math.max(1, math.floor(tonumber(cfg('nextSteps', 1)) or 1))
    local out = {}
    for _, s in ipairs(vis) do
        -- hospital work starts from the hospital equipment (and the check's Care steps card)
        if not NO_STEP_OPTION[s.c] and s.w ~= 'hospital' then
            out[#out + 1] = s
            if #out >= n then break end
        end
    end
    return out
end

local function stepFor(entity, st, code)
    for _, s in ipairs(nextSteps(entity, st)) do
        if s.c == code then return s end
    end
    return nil
end

local function registerOptions()
    local order = 2
    for code in pairs(Care.Actions) do
        if not NO_STEP_OPTION[code] then
            local a = Care.Actions[code]
            NZA.Interact.Add({
                name = 'nza_care_' .. code, label = L('do_' .. code), icon = a.icon or 'medkit',
                order = order, guided = true, perm = 'assess', npc = true, player = true,
                states = { alive = true, wounded = true, arrest = true },
                distance = 2.5,
                canInteract = function(entity, _, st)
                    if not guided() then return false end
                    return stepFor(entity, st, code) ~= nil
                end,
                onSelect = function(entity, target)
                    local st = NZA.Target.State(entity)
                    local s = stepFor(entity, st, code)
                    if s then Care.Run(entity, target, s) end
                end,
            })
        end
    end
    if cfg('more', true) ~= false then
        NZA.Interact.Add({
            name = 'nza_care_more', label = L('more'), icon = 'menu', order = 95, guided = true,
            perm = 'assess', npc = true, player = true, distance = 2.5,
            canInteract = function() return guided() end,
            onSelect = function(entity) NZA.Interact.Open(entity, true) end,
        })
    end
end

CreateThread(function()
    Wait(0)
    if NZA.Interact and NZA.Interact.Add then registerOptions() end
end)

-- ════════════════════════════════════════════════════════════════════════
-- STEPS CARD (HUD, no focus)
-- ════════════════════════════════════════════════════════════════════════

local APP = 'care'
local card = { shown = false, key = nil, sig = nil, done = {} }

local function hideCard()
    if card.shown then NZA.UI.Close(APP) end
    card.shown, card.key, card.sig = false, nil, nil
end

local function nearestChecked(range)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestD = nil, range
    for key, c in pairs(checked) do
        local kind, id = key:match('^(%a+):(.+)$')
        local target = kind == 'player' and { kind = 'player', sid = tonumber(id) } or { kind = 'npc', net = tonumber(id) }
        local ent = NZA.Target.Entity(target)
        if ent ~= 0 and ent ~= me then
            local d = #(pos - GetEntityCoords(ent))
            if d < bestD and Care.IsChecked(target) then best, bestD = { target = target, entity = ent, key = key }, d end
        end
    end
    return best
end

local function cardData(n)
    local st = NZA.Target.State(n.entity)
    if type(st) ~= 'table' then return nil end
    local steps = st.plan or {}
    local list, codes = {}, {}
    for i, s in ipairs(steps) do
        if i > 6 then break end
        local d = Care.Describe(s)
        list[#list + 1] = d
        codes[s.c .. ':' .. tostring(s.i or '')] = d
    end
    -- steps that just went away were done: keep them ticked for a little while
    local now = GetGameTimer()
    local prev = card.done[n.key] or { last = {}, ticks = {} }
    for k, d in pairs(prev.last) do
        if not codes[k] then prev.ticks[k] = { d = d, at = now } end
    end
    prev.last = codes
    local doneList = {}
    for k, t in pairs(prev.ticks) do
        if now - t.at > 20000 or codes[k] then prev.ticks[k] = nil else doneList[#doneList + 1] = t.d end
    end
    card.done[n.key] = prev
    return {
        name = st.name, state = st.st, tri = st.tri, steps = list, done = doneList,
        locale = { title = L('title'), next = L('next'), field = L('field'), hospital = L('hospital'),
            hint = L('hint'), all_done = L('all_done'), done = L('done') },
    }
end

CreateThread(function()
    Wait(2500)
    while true do
        local wait = 600
        if cfg('card', true) ~= false and next(checked) ~= nil and NZA.Perm and NZA.Perm('assess') then
            local blocked = NZA.UI.Top() ~= nil or IsPauseMenuActive() or (NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown())
            local n = not blocked and nearestChecked(tonumber(cfg('cardRange', 4.0)) or 4.0) or nil
            if n then
                local data = cardData(n)
                if data then
                    local sig = json.encode(data)
                    if not card.shown or card.key ~= n.key then
                        NZA.UI.Open(APP, data, { focus = false })
                        card.shown, card.key, card.sig = true, n.key, sig
                    elseif sig ~= card.sig then
                        NZA.UI.Send(APP, 'update', data)
                        card.sig = sig
                    end
                else
                    hideCard()
                end
                wait = 400
            else
                hideCard()
            end
        else
            hideCard()
            wait = 1500
        end
        Wait(wait)
    end
end)
