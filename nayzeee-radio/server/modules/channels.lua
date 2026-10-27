--[[
    NAYZEEE RADIO - Channels (server): who may tune which frequency

    Every frequency between Config.Channels.min and max is open unless a rule says otherwise.
    A rule comes from one of three places, checked in this order (first match wins):

      runtime  addChannelRule(freq, rule) from another resource (kept until it is removed or
               the radio restarts; never saved)
      admin    the entries saved with /radioadmin (database, NZR.DB.LoadChannels)
      range    Config.Channels.Restricted ({ from, to, label, jobs }) - whole bands

    A rule = { access = 'open' | 'code' | 'job', code = '1234', jobs = { police = 0 },
    label = 'LSPD Dispatch', requireDuty = true|false|nil }. Job rules use
    Bridge.JobMatches (job name → minimum grade; requireDuty falls back to
    Config.Channels.requireDuty). A code channel stays unlocked for the rest of the session
    once the right code is entered; codeAttempts wrong codes lock that frequency for that
    player for codeLockout seconds. Changing a channel's code or access in /radioadmin
    throws every session unlock of it away.

    Codes never leave the server, except to admins in the admin panel. GlobalState
    'nzr_labels' carries labels and the access type only.

    API
      NZR.Channels.Rule(freq)                     → rule | nil (open)
      NZR.Channels.Check(src, freq, code?, opts?) → ok, reason, rule
            reason ∈ 'invalid' | 'denied' | 'code' (a code is needed) | 'badcode' | 'locked'
            opts = { noCode = true }   re-checks: an unlocked session passes, no attempt is used
      NZR.Channels.Allowed(src, freq)             → bool (Check with noCode)
      NZR.Channels.Label(freq)                    → label | nil, access ('open' | 'code' | 'job')
      NZR.Channels.Labels()                       → the 'nzr_labels' table
      NZR.Channels.AdminList()                    → admin entries WITH codes, sorted by frequency
      NZR.Channels.Reload()                       re-read the admin entries (after a save) and
                                                  take every channel away from players who lost it
      NZR.Channels.AddRule(freq, rule) → ok, err  NZR.Channels.RemoveRule(freq) → ok
      NZR.Channels.RecheckPlayer(src)             after a job change
      NZR.Channels.TakeSession(src)               unlocks / code fails gathered before the player
                                                  had a radio record (radio.lua adopts them)

    Exports
      addChannelRule(freq, rule) → ok, err        removeChannelRule(freq) → ok

    GlobalState
      nzr_labels = { ['155.50'] = { label, access }, ..., ranges = { { from, to, label, access }, ... } }
                   one entry per runtime / admin rule; Config.Channels.Restricted bands go in
                   'ranges' (a band is too many frequencies to list one by one)

    Bus (listens): player:job (src), player:dropped (src)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Channels = NZR.Channels or {}
local C = NZR.Channels
local Core = NZR.Core

C.admin = C.admin or {}       -- [fkey] = rule
C.runtime = C.runtime or {}   -- [fkey] = rule

local sessions = {}           -- [src] = { unlocked = {}, codeFails = {} } for players without a radio record
local rangeCache = nil

local ACCESS = { open = true, code = true, job = true }
local MAX_JOBS = 16

local function cfg()
    return Config.Channels or {}
end

-- ════════════════════════════════════════════════════════════════════════
-- RULES
-- ════════════════════════════════════════════════════════════════════════

-- { police = 0 } or { 'police', 'sheriff' } or { { name = 'police', grade = 2 } } → { police = 0, ... }
local function cleanJobs(raw)
    if type(raw) ~= 'table' then return nil end
    local out, n = {}, 0
    for k, v in pairs(raw) do
        local name, grade
        if type(k) == 'string' then
            name, grade = k, v
        elseif type(v) == 'string' then
            name, grade = v, 0
        elseif type(v) == 'table' then
            name, grade = v.name, v.grade
        end
        grade = math.floor(tonumber(grade) or 0)
        if type(name) == 'string' and name:match('^[%w_%-]+$') and #name <= 32 and grade >= 0 then
            if not out[name] then n = n + 1 end
            out[name] = grade
            if n >= MAX_JOBS then break end
        end
    end
    if n == 0 then return nil end
    return out
end
C.CleanJobs = cleanJobs

local function cleanCode(code)
    if type(code) == 'number' and code >= 0 and code <= 9999 and code == math.floor(code) then
        code = ('%04d'):format(code)
    end
    if type(code) == 'string' and code:match('^%d%d%d%d$') then return code end
    return nil
end

--- Normalise a rule from any source. → rule | nil, err
local function normalize(raw, origin)
    if type(raw) ~= 'table' then return nil, 'rule' end
    local jobs = cleanJobs(raw.jobs)
    local code = cleanCode(raw.code)
    local access = raw.access
    if not ACCESS[access] then
        access = (jobs and 'job') or (code and 'code') or 'open'
    end
    if access == 'code' and not code then return nil, 'code' end
    if access == 'job' and not jobs then return nil, 'jobs' end
    local label = Bridge.CleanText(raw.label, 32)
    local duty = raw.requireDuty
    if duty ~= nil then duty = duty == true end
    return {
        access = access,
        code = access == 'code' and code or nil,
        jobs = access == 'job' and jobs or nil,
        label = label,
        requireDuty = duty,
        origin = origin,
    }
end

local function ranges()
    if rangeCache then return rangeCache end
    local out = {}
    for _, r in ipairs(cfg().Restricted or {}) do
        local from, to = NZR.Freq.Parse(r.from), NZR.Freq.Parse(r.to)
        local rule = from and to and normalize(r, 'range')
        if rule then
            rule.from, rule.to = math.min(from, to), math.max(from, to)
            out[#out + 1] = rule
        end
    end
    rangeCache = out
    return out
end

function C.Rule(freq)
    local fkey = NZR.Freq.Key(freq)
    if not fkey then return nil end
    local r = C.runtime[fkey] or C.admin[fkey]
    if r then return r end
    local f = tonumber(fkey)
    for _, range in ipairs(ranges()) do
        if f >= range.from and f <= range.to then return range end
    end
    return nil
end

function C.Label(freq)
    local r = C.Rule(freq)
    if not r then return nil, 'open' end
    return r.label, r.access
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSIONS (code unlocks and failed attempts)
-- They belong to the radio record (SPEC §4: unlocked, codeFails). A player who
-- tunes a head unit without ever having had a handheld has no record, so they
-- get a small session table here until one exists.
-- ════════════════════════════════════════════════════════════════════════

local function session(src)
    local rec = NZR.Radio and NZR.Radio.players and NZR.Radio.players[src]
    if rec then
        rec.unlocked = rec.unlocked or {}
        rec.codeFails = rec.codeFails or {}
        return rec
    end
    local s = sessions[src]
    if not s then
        s = { unlocked = {}, codeFails = {} }
        sessions[src] = s
    end
    return s
end

function C.TakeSession(src)
    local s = sessions[src]
    sessions[src] = nil
    return s
end

local function clearUnlocks(fkey)
    for _, s in pairs(sessions) do
        s.unlocked[fkey] = nil
        s.codeFails[fkey] = nil
    end
    for _, rec in pairs((NZR.Radio and NZR.Radio.players) or {}) do
        if rec.unlocked then rec.unlocked[fkey] = nil end
        if rec.codeFails then rec.codeFails[fkey] = nil end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- ACCESS CHECK
-- ════════════════════════════════════════════════════════════════════════

local function jobAllowed(src, rule)
    local job = Core.B('GetJob', src)
    local duty = rule.requireDuty
    if duty == nil then duty = cfg().requireDuty == true end
    return Bridge.JobMatches(job, rule.jobs, duty)
end

function C.Check(src, freq, code, opts)
    src = tonumber(src)
    local f = NZR.Freq.Parse(freq)
    if not src or not f or not NZR.Freq.Valid(f) then return false, 'invalid' end
    local fkey = NZR.Freq.Key(f)
    local rule = C.Rule(fkey)
    if not rule or rule.access == 'open' then return true, nil, rule end

    if rule.access == 'job' then
        if jobAllowed(src, rule) then return true, nil, rule end
        return false, 'denied', rule
    end

    -- code channel
    local s = session(src)
    if s.unlocked[fkey] then return true, nil, rule end
    if opts and opts.noCode then return false, 'code', rule end

    local now = GetGameTimer()
    local fail = s.codeFails[fkey]
    if fail and fail.lockedUntil then
        if fail.lockedUntil > now then return false, 'locked', rule end
        fail = nil   -- the lockout ran out: a fresh set of attempts
        s.codeFails[fkey] = nil
    end
    if code == nil or code == false or code == '' then return false, 'code', rule end

    if cleanCode(code) == rule.code then
        s.unlocked[fkey] = true
        s.codeFails[fkey] = nil
        return true, nil, rule
    end

    fail = fail or { n = 0 }
    fail.n = fail.n + 1
    s.codeFails[fkey] = fail
    local attempts = math.max(1, math.floor(tonumber(cfg().codeAttempts) or 3))
    if fail.n >= attempts then
        fail.n = 0
        fail.lockedUntil = now + math.max(1, tonumber(cfg().codeLockout) or 30) * 1000
        return false, 'locked', rule
    end
    return false, 'badcode', rule
end

function C.Allowed(src, freq)
    local ok = C.Check(src, freq, nil, { noCode = true })
    return ok == true
end

-- ════════════════════════════════════════════════════════════════════════
-- LABELS (GlobalState nzr_labels)
-- ════════════════════════════════════════════════════════════════════════

function C.Labels()
    local out = {}
    for fkey, r in pairs(C.admin) do out[fkey] = { label = r.label, access = r.access } end
    for fkey, r in pairs(C.runtime) do out[fkey] = { label = r.label, access = r.access } end
    local list = {}
    for _, r in ipairs(ranges()) do
        list[#list + 1] = { from = r.from, to = r.to, label = r.label, access = r.access }
    end
    out.ranges = list
    return out
end

function C.Publish()
    local labels = C.Labels()
    local ok, err = pcall(function() GlobalState:set('nzr_labels', labels, true) end)
    if not ok then NZR.Warn('could not publish channel labels: ' .. tostring(err)) end
end

-- ════════════════════════════════════════════════════════════════════════
-- RE-CHECKS (someone lost access to a channel they are on)
-- ════════════════════════════════════════════════════════════════════════

function C.RecheckPlayer(src, onlyFkey)
    local rec = NZR.Radio and NZR.Radio.players and NZR.Radio.players[src]
    if not rec then return end
    for slot, f in pairs(rec.slots) do
        local fkey = NZR.Freq.Key(f)
        if fkey and (not onlyFkey or onlyFkey == fkey) and not C.Allowed(src, fkey) then
            NZR.Radio.Kick(src, slot, fkey)
        end
    end
end

function C.Recheck(onlyFkey)
    local ids = {}
    for src in pairs((NZR.Radio and NZR.Radio.players) or {}) do ids[#ids + 1] = src end
    for _, src in ipairs(ids) do C.RecheckPlayer(src, onlyFkey) end
end

-- ════════════════════════════════════════════════════════════════════════
-- ADMIN ENTRIES (database)
-- ════════════════════════════════════════════════════════════════════════

local function signature(r)
    if not r then return 'none' end
    return ('%s|%s'):format(r.access, r.code or '')
end

function C.Reload()
    local rows = NZR.DB.LoadChannels()
    local fresh = {}
    for _, row in ipairs(rows) do
        local fkey = NZR.Freq.Key(row.freq)
        local rule = fkey and NZR.Freq.Valid(fkey) and normalize(row, 'admin')
        if rule then
            rule.updatedBy = row.updated_by
            fresh[fkey] = rule
        end
    end
    local old = C.admin
    C.admin = fresh
    for fkey, r in pairs(old) do
        if signature(r) ~= signature(fresh[fkey]) then clearUnlocks(fkey) end
    end
    for fkey, r in pairs(fresh) do
        if not old[fkey] and r.access == 'code' then clearUnlocks(fkey) end
    end
    C.Publish()
    C.Recheck()
    NZR.Debug('channel rules loaded:', NZR.Util.Count(fresh))
end

function C.AdminList()
    local out = {}
    for fkey, r in pairs(C.admin) do
        local jobs = nil
        if r.jobs then
            jobs = {}
            for name, grade in pairs(r.jobs) do jobs[name] = grade end
        end
        out[#out + 1] = { freq = fkey, access = r.access, code = r.code, jobs = jobs, label = r.label, updatedBy = r.updatedBy }
    end
    table.sort(out, function(a, b) return tonumber(a.freq) < tonumber(b.freq) end)
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- RUNTIME RULES (exports, not saved)
-- ════════════════════════════════════════════════════════════════════════

function C.AddRule(freq, raw)
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return false, 'invalid' end
    local rule, err = normalize(raw, 'runtime')
    if not rule then return false, err end
    local fkey = NZR.Freq.Key(f)
    local before = C.runtime[fkey]
    C.runtime[fkey] = rule
    if signature(before) ~= signature(rule) then clearUnlocks(fkey) end
    C.Publish()
    C.Recheck(fkey)
    return true
end

function C.RemoveRule(freq)
    local fkey = NZR.Freq.Key(freq)
    if not fkey or not C.runtime[fkey] then return false end
    C.runtime[fkey] = nil
    clearUnlocks(fkey)
    C.Publish()
    C.Recheck(fkey)
    return true
end

exports('addChannelRule', function(freq, rule) return C.AddRule(freq, rule) end)
exports('removeChannelRule', function(freq) return C.RemoveRule(freq) end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZR.Bus.On('player:job', function(src)
    -- defer: radio.lua updates the record's job in the same bus round
    SetTimeout(0, function() C.RecheckPlayer(src) end)
end)

NZR.Bus.On('player:dropped', function(src)
    sessions[src] = nil
end)

CreateThread(function()
    Wait(0)
    C.Publish()      -- the configured bands straight away, admin entries once the database answers
    C.Reload()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    pcall(function() GlobalState:set('nzr_labels', nil, true) end)
end)
