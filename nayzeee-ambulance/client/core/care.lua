--[[
    NAYZEEE AMBULANCE - Client core: guided care (NZA.Care)

    The server lists what every patient still needs (server/core/care.lua → state bag
    summary.plan, medic snapshot .care). This file turns that list into something a medic
    can act on:

      · the third eye on a patient (Config.Care.thirdEye):
          'check'  (default) only "Head-to-toe check" plus the options that move or hand over
                   the patient (carry, stretcher, bed, help up / walk, vehicle, cut free, release,
                   body bag, bill). Every treatment starts from the check: each body group shows
                   what to do there with a Start button (client/modules/assess_exam.lua)
          'guided' check, the next step by name ("Stop the bleeding"), moving, 'More...'
          'full'   every treatment option straight on the third eye (old style)
      · NZA.Care.Run(entity, target, step): runs the right treatment for a step — an exam
        route when the step belongs to one wound, else the module's interaction option
      · NZA.Care.Action(...): the same choice, described for the check (label, supplies)

      NZA.Care.Mode()                      → 'check' | 'guided' | 'full'
      NZA.Care.Hidden(opt)                 → bool (kept off the third eye on other people)
      NZA.Care.Handling(optionName)        → bool (moves / hands over the patient: stays on the third eye)
      NZA.Care.Steps(entity)               → plan from the state bag ({ c, r, i, w, u }, ...)
      NZA.Care.Visible(entity, steps)      → the steps this medic may see (guided mode: check gating)
      NZA.Care.MarkChecked(target, pid)    → called by the head-to-toe check
      NZA.Care.IsChecked(entityOrTarget)   → bool
      NZA.Care.Describe(step)              → { code, title, why, where, urgent, region, icon }
      NZA.Care.Resolve(entity, target, step, snap) → action | nil, reason
      NZA.Care.Action(entity, target, step, snap, counts)
                                           → { can, kind = 'route'|'option'|nil, id, label, icon,
                                               items = { { label, have, need, ok } }, reason }
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
    xray      = { routes = { 'xray_take' },                         options = { 'nza_xray_table', 'nza_xray_any' },         icon = 'xray' },
    xray_read = { routes = {},                                      options = {},                                           icon = 'xray' },
    reduce    = { routes = { 'xray_reduce' },                       options = { 'nza_xray_reduce' },                        icon = 'bone' },
    cast      = { routes = { 'xray_cast' },                         options = { 'nza_xray_cast' },                          icon = 'splint' },
    graft     = { routes = { 'graft' },                             options = { 'nza_graft' },                              icon = 'flame' },
    hospital  = { routes = {},                                      options = { 'nza_tr_tobed', 'nza_tr_onstretcher', 'nza_tr_carry', 'nza_askwalk' }, icon = 'ambulance' },
    bodybag   = { routes = {},                                      options = { 'nza_bodybag' },                            icon = 'bag' },
}

-- steps a medic sees without a check (you can see someone has no pulse or is bleeding out)
local OBVIOUS = { cpr = true, bodybag = true }

-- ════════════════════════════════════════════════════════════════════════
-- THIRD-EYE MODE
-- ════════════════════════════════════════════════════════════════════════

-- 'check' (default): the head-to-toe check and the options below are all the third eye shows
-- on another person; treatments start from the check. Moving / handing over the patient is
-- not a treatment, so it stays one click away.
local HANDLING = {
    nza_examine = true,                                                   -- the check itself
    nza_tr_carry = true, nza_tr_helpup = true, nza_tr_onstretcher = true, nza_tr_offstretcher = true,
    nza_tr_tobed = true, nza_tr_bedleave = true, nza_tr_outveh = true, nza_xray_off = true,
    nza_chair_seat = true, nza_chair_unseat = true,                       -- wheelchair
    nza_askwalk = true, nza_stopwalk = true,                              -- walk with me / wait here
    nza_calls_extricate = true, nza_calls_release = true,                 -- call scenes
    nza_bodybag = true, nza_pharmacy_bill = true,
}

-- 'guided' (round 1): the same, plus the next step by name, joining CPR, the X-ray table and 'More...'
local ALWAYS = {
    nza_cpr_join = true, nza_xray_table = true,
}
for name in pairs(HANDLING) do ALWAYS[name] = true end

local extraKeep = nil
local function extra(name)
    if extraKeep == nil then
        extraKeep = {}
        for _, n in ipairs(cfg('alwaysShow', {}) or {}) do extraKeep[n] = true end
    end
    return extraKeep[name] == true
end

function Care.Mode()
    local m = cfg('thirdEye', nil)
    if m == 'check' or m == 'guided' or m == 'full' then return m end
    if cfg('guided', true) == false then return 'full' end      -- configs from before thirdEye existed
    return 'check'
end

function Care.Handling(name)
    return HANDLING[name] == true or extra(name)
end

function Care.AlwaysShow(name)
    return ALWAYS[name] == true or extra(name)
end

-- Is this option kept off the third eye on another person? (target.lua asks; the self menu,
-- body bag props and 'all' listings - the check's tools, Care.Resolve - never hide anything)
function Care.Hidden(opt)
    if type(opt) ~= 'table' or opt.guided then return false end   -- step options hide themselves
    local mode = Care.Mode()
    if mode == 'full' then return false end
    -- only medics who can open the head-to-toe check get the short version (treatments start
    -- there): civilians, or a server with the check turned off (Config.Assess.Interact.examine
    -- = false), keep every option on the third eye
    local ex = NZA.Interact and NZA.Interact.Get and NZA.Interact.Get('nza_examine')
    if not ex or not (NZA.Perm and NZA.Perm(ex.perm or 'assess')) then return false end
    if mode == 'check' then return not Care.Handling(opt.name) end
    return not Care.AlwaysShow(opt.name)
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

-- the supplies a route needs: { { label, have, need, ok } }, all there?, first missing label
local function routeItems(r, counts)
    local items, all, missing = {}, true, nil
    for name, need in pairs(type(r.items) == 'table' and r.items or {}) do
        if counts[name] == nil then counts[name] = itemCount(name) end
        local haveN, needN = counts[name], tonumber(need) or 1
        local label = itemLabel(name)
        items[#items + 1] = { label = label, have = haveN, need = needN, ok = haveN >= needN }
        if haveN < needN then
            all = false
            missing = missing or label
        end
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    return items, all, missing
end

-- One pass over the step's exam routes (they know the wound), then its interaction options.
-- → act ({ kind = 'route', route, inj } | { kind = 'option', opt } | nil), info (what the check shows)
local function resolve(entity, step, snap, counts)
    local A = Care.Actions[step.c]
    if not A then return nil, { can = false, items = {}, reason = L('no_action') } end
    counts = counts or {}
    local inj = findInjury(snap, step.i)
    local pseudo = inj or { id = 'care:' .. step.c, region = step.r or 'chest', type = 'care', severity = 2, treat = {} }
    local short, blocked = nil, nil
    for _, rid in ipairs(A.routes or {}) do
        local r = findRoute(rid)
        if r and r.run and (r.perm == nil or NZA.Perm(r.perm)) and snap then
            local fits = (r.types == nil or (inj and has(r.types, inj.type))) and (r.regions == nil or (inj and has(r.regions, inj.region)))
            if fits then
                local avail, why = true, nil
                if type(r.available) == 'function' then
                    local ok, a, b = pcall(r.available, pseudo, snap)
                    avail = ok and a and true or false
                    if ok and not a and type(b) == 'string' then why = b end
                end
                if avail then
                    local items, all, missing = routeItems(r, counts)
                    local info = { can = all, kind = 'route', id = r.id, label = r.label or L('do_' .. step.c), icon = r.icon or A.icon, items = items }
                    if all then return { kind = 'route', route = r, inj = pseudo }, info end
                    info.reason = L('need_item', missing)
                    short = short or info
                elseif why then
                    blocked = blocked or why       -- e.g. "Put them on the X-ray table first"
                end
            end
        end
    end
    for _, name in ipairs(A.options or {}) do
        local opt = NZA.Interact.Get(name)
        if opt and entity and entity ~= 0 and NZA.Interact.Allowed(opt, entity, true) then
            return { kind = 'option', opt = opt }, { can = true, kind = 'option', id = name, label = opt.label, icon = opt.icon or A.icon, items = {} }
        end
    end
    if short then return nil, short end
    -- "bring a stretcher" only while they still lie free (not on a stretcher, bed, seat or in the bay)
    local tb = step.c == 'hospital' and entity and entity ~= 0 and NZA.Transport and NZA.Transport.Bag and NZA.Transport.Bag(entity)
    local st = step.c == 'hospital' and entity and entity ~= 0 and NZA.Target.State(entity)
    local placed = (type(tb) == 'table' and tb.m ~= nil and tb.m ~= 'free')
        or (type(st) == 'table' and (st.stretcher ~= nil or st.carried == true))
    local reason = blocked or (step.c == 'hospital' and not placed and L('hospital_how')) or (step.w == 'hospital' and L('at_hospital')) or L('no_action')
    return nil, { can = false, items = {}, reason = reason }
end

-- → { kind = 'route', route, inj } | { kind = 'option', opt } | nil, reason
function Care.Resolve(entity, target, step, snap)
    local act, info = resolve(entity, step, snap)
    if act then return act end
    return nil, info and info.reason or L('no_action')
end

-- What the head-to-toe check shows for one step (also when it cannot run: the supplies you lack,
-- or why not here). counts = shared item count cache for one view.
function Care.Action(entity, target, step, snap, counts)
    if type(step) ~= 'table' or not step.c then return { can = false, items = {}, reason = L('no_action') } end
    local _, info = resolve(entity, step, snap, counts)
    return info
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
-- GUIDED THIRD EYE (Config.Care.thirdEye = 'guided' only): one option per step code, shown
-- only when it is the next step, and 'More...' for every other tool
-- ════════════════════════════════════════════════════════════════════════

-- the step codes whose own option is already on the third eye (help up, stretcher, body bag)
-- (xray_read happens at the lightbox with the film, not on the patient)
local NO_STEP_OPTION = { standup = true, hospital = true, bodybag = true, extricate = true, release = true, xray_read = true }

local function guided() return Care.Mode() == 'guided' end

local function nextSteps(entity, st)
    local plan = (type(st) == 'table' and type(st.plan) == 'table') and st.plan or {}
    if #plan == 0 then return {} end
    local vis = Care.Visible(entity, plan)
    local n = math.max(1, math.floor(tonumber(cfg('nextSteps', 1)) or 1))
    local out = {}
    for _, s in ipairs(vis) do
        -- hospital work starts from the hospital equipment (and the check)
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
    NZA.Interact.Add({
        name = 'nza_care_more', label = L('more'), icon = 'menu', order = 95, guided = true,
        perm = 'assess', npc = true, player = true, distance = 2.5,
        canInteract = function() return guided() and cfg('more', true) ~= false end,
        onSelect = function(entity) NZA.Interact.Open(entity, true) end,
    })
end

CreateThread(function()
    Wait(0)
    if NZA.Interact and NZA.Interact.Add then registerOptions() end
end)
