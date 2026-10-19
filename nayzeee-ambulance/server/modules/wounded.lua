--[[
    NAYZEEE AMBULANCE - Wounded (server): call EMS, give up, live status for the downed HUD

    The downed player's client sends intents; everything is validated here (state, time
    down, cooldowns, rate limits, server-side coords).

    Net events (C→S)
      nza:wounded:callEms ()       G on the wounded HUD / death screen. Cooldown
                                   Config.Wounded.callEms.cooldown. Creates a dispatch call
                                   (NZA.Dispatch.Create) with the triage priority; with no
                                   medic on duty asks NZA.AIMedic.Request(pid). Without the
                                   dispatch module: external dispatch via the bridge + a toast
                                   and blip for every on-duty medic ('nza:wounded:alert').
      nza:wounded:giveUp ()        held E. Needs Config.Wounded.giveUp.enabled, state wounded
                                   (or arrest when Config.WoundedUI.giveUpInArrest) and
                                   Config.Wounded.giveUp.minTime seconds down →
                                   NZA.Patients.SetState(pid, 'dead', 'gave_up')
    Net events (S→C)
      nza:wounded:called  { ok, kind, medics, ai, cooldown, left, text }   reply to a call
      nza:wounded:status  { cpr, cprBy, treating, onScene, called, callId } whenever it changes
                                   (1 s loop over downed players only)
      nza:wounded:help    { eta, unit, ai, status }   sent by dispatch / AI medic modules
                                   (or through NZA.Wounded.Help below)
      nza:wounded:alert   { title, code, priority, coords, name, street }  medics, fallback only
    Callbacks
      nza:wounded:info () → { state, downFor, giveUpIn, callLeft, medics, dead = {...} | nil }
    Server API (other modules)
      NZA.Wounded.Help(target, data)   target = src | pid. Show "medic on the way · ETA" etc. on
                                       that player's HUD. data = { eta = sec, unit = 'Unit 04 · J. Doe',
                                       ai = bool, status = 'enroute'|'onscene'|'cancelled' }
      NZA.Wounded.CauseLines(p)        plain-words cause of death lines (used by the death screen)
      NZA.Wounded.OnDuty()             on-duty medic sources
    Bus events emitted (server): wounded:called (src, p, callId), wounded:gaveUp (src, p)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Wounded = NZA.Wounded or {}
local W = NZA.Wounded

local lastCall = {}      -- pid → os.time() of the last accepted call
local lastCallId = {}    -- pid → dispatch call id
local sentStatus = {}    -- src → json of the last status pushed
local nameCache = {}     -- src → { name, at }

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section, key, default)
    local s = Config[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function ui(key, default)
    return cfg('WoundedUI', key, default)
end

local function giveUpCfg(key, default)
    local g = cfg('Wounded', 'giveUp', nil)
    if type(g) ~= 'table' or g[key] == nil then return default end
    return g[key]
end

local function callCooldown()
    local c = cfg('Wounded', 'callEms', nil)
    return (type(c) == 'table' and tonumber(c.cooldown)) or 60
end

local function validSource(src)
    src = tonumber(src)
    return src and src > 0 and GetPlayerName(src) ~= nil
end

local function rate(src, bucket, n, ms)
    if NZA.Core and NZA.Core.Rate then
        return NZA.Core.Rate('wounded:' .. bucket, src, n, ms)
    end
    return true
end

local function notify(src, kind, key, ...)
    local msg = NZA.L(key, ...)
    if NZA.Core and NZA.Core.Notify then
        NZA.Core.Notify(src, msg, kind, NZA.L('wounded.title_toast'))
    else
        TriggerClientEvent('nza:ui:toast', src, { title = NZA.L('wounded.title_toast'), message = msg, type = kind })
    end
end

local function srcCoords(src)
    if NZA.Core and NZA.Core.SrcCoords then return NZA.Core.SrcCoords(src) end
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then return GetEntityCoords(ped) end
    return nil
end

local function playerName(src)
    local c = nameCache[src]
    local now = os.time()
    if c and now - c.at < 300 then return c.name end
    local name
    if NZA.Core and NZA.Core.Name then
        local ok, res = pcall(NZA.Core.Name, src)
        if ok then name = res end
    end
    name = name or GetPlayerName(src) or ('#' .. tostring(src))
    nameCache[src] = { name = name, at = now }
    return name
end

local function bridge(path, ...)
    if NZA.Core and NZA.Core.B then return NZA.Core.B(path, ...) end
    local node = Bridge
    for part in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    if type(node) ~= 'function' then return nil end
    local ok, res = pcall(node, ...)
    if ok then return res end
    return nil
end

local function fmtTime(sec)
    return NZA.Util.formatTime(sec)
end

-- On-duty medics (sources). Accepts the core list format or a bridge list.
function W.OnDuty()
    local list
    if NZA.Staff and NZA.Staff.OnDuty then
        local ok, res = pcall(NZA.Staff.OnDuty)
        if ok and type(res) == 'table' then list = res end
    end
    if not list then list = bridge('GetMedics', true) end
    local out = {}
    if type(list) ~= 'table' then return out end
    for k, v in pairs(list) do
        local s
        if type(v) == 'number' then
            s = v
        elseif type(v) == 'table' then
            s = tonumber(v.src or v.source)
        elseif v == true then
            s = tonumber(k)
        end
        if s and s > 0 then out[#out + 1] = s end
    end
    return out
end

local function isDown(p)
    return p and p.state ~= 'alive'
end

local function avpuOf(p)
    return (p.vitals and p.vitals.avpu) or 'A'
end

local function beingTreated(p)
    if p.watchers and next(p.watchers) ~= nil then return true end
    local win = tonumber(ui('cprWindow', 4)) or 4
    if p.lastCpr and os.time() - p.lastCpr <= win + 4 then return true end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- CAUSE OF DEATH (plain words)
-- ════════════════════════════════════════════════════════════════════════

local COND_ICON = {
    haemothorax = 'lungs', pneumothorax = 'lungs', tamponade = 'heart', concussion = 'brain',
    hypoxia = 'wind', airway = 'wind', overdose = 'pill', hypothermia = 'snow',
    infection = 'flask', spinal = 'bone',
}

local function injuryList(p)
    local arr = {}
    for _, inj in pairs(p.injuries or {}) do
        if type(inj) == 'table' and inj.type then arr[#arr + 1] = inj end
    end
    table.sort(arr, function(a, b)
        if (a.severity or 1) ~= (b.severity or 1) then return (a.severity or 1) > (b.severity or 1) end
        return (a.bleedBase or 0) > (b.bleedBase or 0)
    end)
    return arr
end

function W.CauseLines(p)
    local out = {}
    if not p then return out end
    local reason = type(p.cause) == 'table' and p.cause.reason or nil
    if reason then
        local key = 'wounded.cause_' .. tostring(reason)
        local txt = NZA.L(key)
        if txt ~= key then
            out[#out + 1] = { icon = reason == 'gave_up' and 'flag' or 'skull', text = txt, tone = 'red', lead = true }
        end
    end
    -- what stopped the heart, when an arrest ended in death (core keeps it in p.cause.arrestCause)
    local arrestCause = type(p.cause) == 'table' and p.cause.arrestCause or nil
    if arrestCause and arrestCause ~= reason then
        local key = 'wounded.cause_' .. tostring(arrestCause)
        local txt = NZA.L(key)
        if txt ~= key then
            out[#out + 1] = { icon = 'heart', text = txt, tone = 'red', lead = #out == 0 or nil }
        end
    end

    local inj = injuryList(p)
    for i = 1, math.min(3, #inj) do
        local it = inj[i]
        local sev = NZA.Const.SeverityLabel[it.severity or 1] or ''
        local t = NZA.Const.InjuryTypes[it.type]
        out[#out + 1] = {
            icon = (t and t.icon) or 'drop',
            text = NZA.L('wounded.cause_injury', sev, string.lower(NZA.Util.InjuryLabel(it.type)), NZA.Util.RegionLabel(it.region)),
            tone = (it.severity or 1) >= 3 and 'red' or 'amber',
        }
    end

    local max = tonumber(p.bloodMax) or 5000
    local loss
    if NZA.Patients.Loss then loss = NZA.Patients.Loss(p) else loss = 1 - (tonumber(p.blood) or max) / max end
    if loss >= 0.12 then
        local litres = math.max(0, max - (tonumber(p.blood) or max)) / 1000
        out[#out + 1] = {
            icon = 'drop',
            text = NZA.L('wounded.cause_blood', math.floor(loss * 100 + 0.5), string.format('%.1f', litres)),
            tone = loss >= 0.35 and 'red' or 'amber',
        }
    end

    local conds = 0
    for name in pairs(p.conditions or {}) do
        if name ~= 'arrest' and conds < 2 then
            local key = 'wounded.cond_' .. name
            local txt = NZA.L(key)
            if txt ~= key then
                conds = conds + 1
                out[#out + 1] = { icon = COND_ICON[name] or 'alert', text = txt, tone = 'amber' }
            end
        end
    end

    if p.arrestAt and p.deadAt and p.deadAt > p.arrestAt then
        out[#out + 1] = { icon = 'ecg', text = NZA.L('wounded.cause_arrest_time', fmtTime(p.deadAt - p.arrestAt)), tone = 'dim' }
    end

    if #inj > 3 then
        out[#out + 1] = { icon = 'plus', text = NZA.L('wounded.cause_more', #inj - 3), tone = 'dim' }
    end

    if #out == 0 then
        out[1] = { icon = 'skull', text = NZA.L('wounded.cause_unknown'), tone = 'dim' }
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- CALL EMS
-- ════════════════════════════════════════════════════════════════════════

local function worstType(p)
    local inj = injuryList(p)
    return inj[1] and inj[1].type or nil
end

local function reply(src, data)
    TriggerClientEvent('nza:wounded:called', src, data)
end

local function fallbackAlert(medics, call)
    local payload = {
        title = call.title, code = call.code, priority = call.priority, name = call.caller,
        coords = { x = call.coords.x, y = call.coords.y, z = call.coords.z },
    }
    for _, m in ipairs(medics) do
        TriggerClientEvent('nza:wounded:alert', m, payload)
    end
end

RegisterNetEvent('nza:wounded:callEms', function()
    local src = source
    if not validSource(src) then return end
    if not rate(src, 'call', 3, 4000) then return end
    local p = NZA.Patients.GetBySource(src)
    if not isDown(p) then return end

    local dead = p.state == 'dead'
    if dead and not ui('bodyRecoveryCall', true) then return end
    local avpu = avpuOf(p)
    if not dead and ui('callWhileUnconscious', true) == false
        and (p.state == 'arrest' or avpu == 'P' or avpu == 'U') then
        reply(src, { ok = false, kind = 'unconscious', text = NZA.L('wounded.call_unconscious') })
        return
    end

    local now = os.time()
    local cd = callCooldown()
    local last = lastCall[p.pid]
    if last and now - last < cd then
        local left = cd - (now - last)
        reply(src, { ok = false, kind = 'cooldown', left = left, cooldown = cd, text = NZA.L('wounded.call_cooldown', fmtTime(left)) })
        return
    end

    local coords = srcCoords(src)
    if not coords then
        reply(src, { ok = false, kind = 'failed', text = NZA.L('wounded.call_failed') })
        return
    end

    -- what kind of call
    local kind, ctype
    if dead then
        kind, ctype = 'dead', 'deceased'
    elseif p.state == 'arrest' then
        kind, ctype = 'arrest', 'arrest'
    else
        kind = 'injured'
        ctype = worstType(p) or ((avpu == 'P' or avpu == 'U') and 'unconscious') or 'unknown'
    end
    local titleKey = 'wounded.call_t_' .. (dead and 'dead' or (kind == 'arrest' and 'arrest' or ctype))
    local title = NZA.L(titleKey)
    if title == titleKey then title = NZA.L('wounded.call_t_unknown') end

    local priority = 3
    if not dead then
        local ok, lvl = pcall(NZA.Patients.Triage, p.pid)
        priority = (ok and tonumber(lvl)) or (kind == 'arrest' and 1 or 2)
    end

    local codes = ui('codes', {}) or {}
    local call = {
        code = codes[kind] or '10-52',
        priority = priority,
        title = title,
        type = ctype,
        coords = vector3(coords.x, coords.y, coords.z),
        caller = p.name,
        message = dead and NZA.L('wounded.call_msg_dead') or NZA.L('wounded.call_msg', p.name or '?'),
        patients = { p.pid },
        npc = false,
        source = 'player',
    }

    local medics = W.OnDuty()
    local callId
    if NZA.Dispatch and NZA.Dispatch.Create then
        local ok, res = pcall(NZA.Dispatch.Create, call)
        if ok then callId = res else NZA.Warn('wounded: NZA.Dispatch.Create failed: ' .. tostring(res)) end
    else
        bridge('Dispatch.External', call)
        fallbackAlert(medics, call)
        callId = NZA.Util.uid('W-')
    end
    if not callId then
        reply(src, { ok = false, kind = 'failed', text = NZA.L('wounded.call_failed') })
        return
    end

    lastCall[p.pid] = now
    lastCallId[p.pid] = callId
    if NZA.Patients.SetMeta then NZA.Patients.SetMeta(p.pid, 'callId', callId) end

    local ai = false
    if #medics == 0 and not dead and ui('aiMedic', true) and NZA.AIMedic and NZA.AIMedic.Request then
        local ok, res = pcall(NZA.AIMedic.Request, p.pid, { callId = callId, source = 'wounded' })
        ai = ok and res ~= false and res ~= nil
    end

    local text
    if dead then text = NZA.L('wounded.call_recovery')
    elseif ai then text = NZA.L('wounded.call_ai')
    elseif #medics == 0 then text = NZA.L('wounded.call_nomedic')
    else text = NZA.L('wounded.call_sent') end

    reply(src, { ok = true, kind = dead and 'recovery' or 'sent', medics = #medics, ai = ai, callId = callId, cooldown = cd, left = cd, text = text })
    NZA.Bus.Emit('wounded:called', src, p, callId)
    NZA.Debug('wounded: call', p.pid, title, 'P' .. tostring(priority), callId, 'medics', #medics, 'ai', ai)
end)

-- ════════════════════════════════════════════════════════════════════════
-- GIVE UP
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:wounded:giveUp', function()
    local src = source
    if not validSource(src) then return end
    if not rate(src, 'giveup', 2, 3000) then return end
    local p = NZA.Patients.GetBySource(src)
    if not p then return end

    if not giveUpCfg('enabled', true) then
        notify(src, 'error', 'wounded.giveup_disabled')
        return
    end
    local allowed = p.state == 'wounded' or (p.state == 'arrest' and ui('giveUpInArrest', true))
    if not allowed then return end

    local minTime = tonumber(giveUpCfg('minTime', 60)) or 60
    local downFor = os.time() - (tonumber(p.downAt) or os.time())
    if downFor < minTime - 1 then
        notify(src, 'error', 'wounded.giveup_early', fmtTime(minTime - downFor))
        return
    end
    if not ui('giveUpWhileTreated', false) and beingTreated(p) then
        notify(src, 'error', 'wounded.giveup_treated')
        return
    end

    NZA.Patients.SetState(p.pid, 'dead', 'gave_up')
    NZA.Bus.Emit('wounded:gaveUp', src, p)
end)

-- ════════════════════════════════════════════════════════════════════════
-- INFO (HUD / death screen open + relog re-entry)
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:wounded:info', function(src)
    if not rate(src, 'info', 12, 10000) then return nil end
    local p = NZA.Patients.GetBySource(src)
    if not p then return nil end
    local now = os.time()
    local downFor = p.downAt and math.max(0, now - p.downAt) or 0
    local minTime = tonumber(giveUpCfg('minTime', 60)) or 60
    local cd = callCooldown()
    local last = lastCall[p.pid]
    local out = {
        state = p.state,
        downFor = downFor,
        giveUp = giveUpCfg('enabled', true) and true or false,
        giveUpIn = math.max(0, minTime - downFor),
        giveUpHold = tonumber(giveUpCfg('hold', 3)) or 3,
        callLeft = last and math.max(0, cd - (now - last)) or 0,
        cooldown = cd,
        called = last ~= nil and now - last < 900,
        medics = #W.OnDuty(),
    }
    if p.state == 'dead' then
        local deadAt = tonumber(p.deadAt) or now
        local deadFor = math.max(0, now - deadAt)
        local timer = tonumber(cfg('Death', 'respawnTimer', 300)) or 300
        local respawn = W.RespawnPreview and W.RespawnPreview(src, p) or {}
        out.dead = {
            deadFor = deadFor,
            respawnIn = math.max(0, timer - deadFor),
            hold = tonumber(cfg('Death', 'respawnHold', 3)) or 3,
            tod = os.date(ui('timeFormat', '%H:%M'), deadAt),
            name = p.name,
            cause = W.CauseLines(p),
            bagged = (p.meta and p.meta.bodybag) and true or false,
            respawn = respawn,
        }
    end
    return out
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIVE STATUS (CPR, medic examining you, medic on scene)
-- ════════════════════════════════════════════════════════════════════════

local function nearestMedic(p, medics)
    local c = srcCoords(p.src)
    if not c then return nil end
    local best, bestD = nil, (tonumber(ui('onSceneDistance', 15.0)) or 15.0)
    for _, m in ipairs(medics) do
        if m ~= p.src then
            local mc = srcCoords(m)
            if mc then
                local d = #(mc - c)
                if d <= bestD then best, bestD = m, d end
            end
        end
    end
    return best
end

local function statusOf(p, medics)
    local now = os.time()
    local win = tonumber(ui('cprWindow', 4)) or 4
    local cpr = p.state == 'arrest' and p.lastCpr ~= nil and now - p.lastCpr <= win
    local cprBy = nil
    if cpr and p.meta and tonumber(p.meta.cprBy) then cprBy = playerName(tonumber(p.meta.cprBy)) end
    local onScene = nearestMedic(p, medics)
    local last = lastCall[p.pid]
    return {
        cpr = cpr or false,
        cprBy = cprBy,
        treating = (p.watchers and next(p.watchers) ~= nil) or false,
        onScene = onScene and playerName(onScene) or nil,
        called = last ~= nil and now - last < 900,
        callId = lastCallId[p.pid],
    }
end

local function pushStatus(p, medics)
    local st = statusOf(p, medics)
    local ok, enc = pcall(json.encode, st)
    if not ok then return end
    if sentStatus[p.src] == enc then return end
    sentStatus[p.src] = enc
    TriggerClientEvent('nza:wounded:status', p.src, st)
end

CreateThread(function()
    while true do
        local any = false
        local medics = nil
        local seen = {}
        for _, p in pairs(NZA.Patients.All()) do
            if p.kind == 'player' and p.src and p.state ~= 'alive' then
                any = true
                medics = medics or W.OnDuty()
                seen[p.src] = true
                pushStatus(p, medics)
            end
        end
        for s in pairs(sentStatus) do
            if not seen[s] then sentStatus[s] = nil end
        end
        Wait(any and 1000 or 2500)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- HELP (dispatch / AI medic modules → downed player's HUD)
-- ════════════════════════════════════════════════════════════════════════

function W.Help(target, data)
    local src = tonumber(target)
    if not src and type(target) == 'string' then
        local p = NZA.Patients.Get(target)
        src = p and p.src
    end
    if not src or type(data) ~= 'table' then return false end
    TriggerClientEvent('nza:wounded:help', src, {
        eta = tonumber(data.eta),
        unit = type(data.unit) == 'string' and data.unit or nil,
        ai = data.ai == true,
        status = type(data.status) == 'string' and data.status or 'enroute',
    })
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('state:changed', function(p, _, new)
    if type(p) ~= 'table' or p.kind ~= 'player' then return end
    if new == 'alive' then
        lastCallId[p.pid] = nil
        if p.src then sentStatus[p.src] = nil end
    end
end)

NZA.Bus.On('player:unloaded', function(src)
    if src then
        sentStatus[src] = nil
        nameCache[src] = nil
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    sentStatus[src] = nil
    nameCache[src] = nil
end)
