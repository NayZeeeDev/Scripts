--[[
    NAYZEEE AMBULANCE - Instant treatments (NZA.Treat)             ARCHITECTURE §5.1

    Server registry of one-shot treatments. Modules register at their file top level:
      NZA.Treat.Register('bandage', {
          perm = 'basic',          -- §7 permission ; nil = anyone
          self = true,             -- may be used on yourself
          items = { [Config.Items.bandage] = 1 } | function(src, patient, payload) return itemsTable end,
          maxDist = 3.0,           -- metres, server-side coords (default 3.0)
          states = { wounded = true, ... },  -- optional: patient states allowed (default: all but dead)
          npc = true, player = true,         -- optional: patient kinds allowed (default both)
          cooldown = 500,          -- optional ms between uses by the same medic (default 400)
          record = false,          -- optional: don't write a treatment record
          handler = function(src, patient, payload) return true, { msg = 'Bleeding slowed' } end,
      })

    Callback 'nza:treat' (action, target, payload) → ok, result
      Checks: action exists → rate limit → patient → self / kind / state → permission →
      distance → items present → handler (pcall) → items consumed only when the handler
      returned true → bus 'treat:done' (src, p, action, result) → NZA.Records.Add.
      Failures return false, { err = code, msg = localized text, item? }.
      Error codes: unknown_action rate no_patient no_self kind state no_perm too_far missing_item failed

    Server API
      NZA.Treat.Register(name, def)   NZA.Treat.Get(name)   NZA.Treat.List()
      NZA.Treat.Run(src, action, target, payload) → ok, result   (same checks, for server-side use)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Treat = NZA.Treat or {}
NZA.Core = NZA.Core or {}
local T = NZA.Treat
local Core = NZA.Core

T.registry = T.registry or {}

function T.Register(name, def)
    if type(name) ~= 'string' or type(def) ~= 'table' or type(def.handler) ~= 'function' then
        NZA.Warn('NZA.Treat.Register: bad definition for ' .. tostring(name))
        return false
    end
    def.name = name
    def.maxDist = tonumber(def.maxDist) or 3.0
    T.registry[name] = def
    return true
end

function T.Get(name) return T.registry[name] end

function T.List()
    local out = {}
    for name, def in pairs(T.registry) do out[#out + 1] = { name = name, perm = def.perm, self = def.self == true } end
    return out
end

local function fail(code, extra)
    local r = { err = code, msg = NZA.L('core.err_' .. code) }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    if r.item then
        local label = Core.B('Inv.Label', r.item) or r.item
        r.msg = NZA.L('core.err_missing_item', label)
    end
    return false, r
end

-- shared by treat & proc
function Core.TargetChecks(src, def, target, opts)
    opts = opts or {}
    local p = NZA.Patients.Resolve(target)
    if not p then return nil, 'no_patient' end
    local isSelf = p.kind == 'player' and p.src == src
    if isSelf and not def.self then return nil, 'no_self' end
    if (p.kind == 'npc' and def.npc == false) or (p.kind == 'player' and def.player == false) then return nil, 'kind' end
    if type(def.states) == 'table' then
        if not def.states[p.state] then return nil, 'state' end
    elseif p.state == 'dead' then
        return nil, 'state'
    end
    if def.perm and not NZA.Staff.Can(src, def.perm) then return nil, 'no_perm' end
    if not isSelf and src > 0 then
        local maxD = (def.maxDist or 3.0) + (opts.slack or 1.0)   -- 1 m for latency / ped origin offsets
        if Core.DistanceTo(src, p) > maxD then return nil, 'too_far' end
    end
    return p, nil, isSelf
end

function Core.ResolveItems(def, src, p, payload)
    local items = def.items
    if type(items) == 'function' then
        local ok, res = pcall(items, src, p, payload)
        if not ok then
            NZA.Warn(('items() for %s failed: %s'):format(tostring(def.name), tostring(res)))
            return nil
        end
        items = res
    end
    return Core.NormalizeItems(items)
end

local busy = {}

function T.Run(src, action, target, payload)
    src = tonumber(src)
    local def = T.registry[action]
    if not def then return fail('unknown_action') end
    if not src then return fail('no_perm') end
    if src > 0 and not Core.Rate('nza:treat', src, 1, def.cooldown or 400) then return fail('rate') end
    if busy[src] then return fail('rate') end

    payload = type(payload) == 'table' and payload or {}
    local p, err, isSelf = Core.TargetChecks(src, def, target)
    if not p then return fail(err) end

    local items = Core.ResolveItems(def, src, p, payload)
    if not items then return fail('failed') end
    local okItems, missing = true, nil
    if src > 0 then okItems, missing = Core.CheckItems(src, items) end
    if not okItems then return fail('missing_item', { item = missing }) end

    busy[src] = true
    local ok, res1, res2 = pcall(def.handler, src, p, payload, { self = isSelf, items = items })
    busy[src] = nil
    if not ok then
        NZA.Warn(('treatment %s failed: %s'):format(action, tostring(res1)))
        return fail('failed')
    end
    local success, result = res1, res2
    if type(result) ~= 'table' then result = { msg = type(result) == 'string' and result or nil } end
    if not success then
        result.err = result.err or 'failed'
        result.msg = result.msg or NZA.L('core.err_failed')
        return false, result
    end

    if src > 0 and next(items) then Core.TakeItems(src, items) end
    NZA.Patients.Touch(p, true)
    NZA.Bus.Emit('treat:done', src, p, action, result)
    if def.record ~= false then
        NZA.Records.Add(p, { medic = src, action = action, summary = result.record or result.msg or action })
    end
    return true, result
end

lib.callback.register('nza:treat', function(src, action, target, payload)
    if type(action) ~= 'string' then return fail('unknown_action') end
    return T.Run(src, action, target, payload)
end)
