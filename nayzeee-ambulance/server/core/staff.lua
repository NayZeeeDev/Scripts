--[[
    NAYZEEE AMBULANCE - Staff & permissions (NZA.Staff)             ARCHITECTURE §7

    Who may do what. The default resolver uses the framework job through the bridge:
      medic job (Config.Jobs.medic) on duty → Config.DefaultPerms[grade] (highest lower
      grade when that grade is not listed) · police (Config.Jobs.police) on duty →
      Config.PolicePerms · everyone → Config.PublicPerms · admins → every permission.
    Config.Jobs.requireDuty = true strips job permissions while off duty.
    The hospital module installs the real resolver (departments / grades) with
    NZA.Staff.Provider(fn); fn(src, defaultRecord) returns a record or nil (= default).

    API
      NZA.Staff.Get(src)         → { hospital, dept, grade, gradeLabel, perms, easy, onDuty, medic, police, admin, job }
      NZA.Staff.Can(src, perm)   → bool
      NZA.Staff.Easy(src, perm)  → bool (easy mode for that permission)
      NZA.Staff.OnDuty()         → { src, ... } medics on duty
      NZA.Staff.Provider(fn)     install / replace the resolver (refreshes everyone)
      NZA.Staff.Refresh(src, force) / NZA.Staff.RefreshAll()   recompute + push 'nza:staff:update'

    Pushes 'nza:staff:update' (record) to the client on load, job change, duty change
    (polled every 30 s as a safety net), provider change, and resource start.
    Callback: 'nza:staff:get' () → record (client cold start / resource restart).
    Bus: staff:changed (src, record, old)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Staff = NZA.Staff or {}
NZA.Core = NZA.Core or {}
local S = NZA.Staff
local Core = NZA.Core

local cache = {}      -- src → record
local cacheStr = {}   -- src → last pushed json
local provider = nil

local function listHas(list, value)
    if type(list) ~= 'table' or value == nil then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return list[value] == true
end

local function addPerms(set, list)
    if type(list) ~= 'table' then return end
    for k, v in pairs(list) do
        if type(k) == 'number' and type(v) == 'string' then set[v] = true
        elseif type(k) == 'string' and v then set[k] = true end
    end
end

local function allPerms()
    local set = {}
    for _, p in ipairs(NZA.Const.Perms) do set[p.key] = true end
    set.builder = true
    return set
end

local function gradePerms(grade)
    local map = Config.DefaultPerms or {}
    grade = math.floor(tonumber(grade) or 0)
    local best, bestGrade
    for g, list in pairs(map) do
        g = tonumber(g)
        if g and g <= grade and (not bestGrade or g > bestGrade) then best, bestGrade = list, g end
    end
    if not best then
        -- grade below every listed one: use the lowest listed
        for g, list in pairs(map) do
            g = tonumber(g)
            if g and (not bestGrade or g < bestGrade) then best, bestGrade = list, g end
        end
    end
    return best or {}
end

local function requireDuty()
    return not (Config.Jobs and Config.Jobs.requireDuty == false)
end

local function defaultRecord(src)
    local job = Core.B('GetJob', src)
    job = type(job) == 'table' and job or {}
    local medic = Core.B('IsMedic', src)
    if medic == nil then medic = listHas(Config.Jobs and Config.Jobs.medic, job.name) end
    local police = Core.B('IsPolice', src)
    if police == nil then police = listHas(Config.Jobs and Config.Jobs.police, job.name) end
    local onDuty = job.onDuty
    if onDuty == nil then onDuty = Core.B('IsOnDuty', src) end
    if onDuty == nil then onDuty = true end

    local perms = {}
    addPerms(perms, Config.PublicPerms)
    if medic then addPerms(perms, gradePerms(job.grade)) end
    if police and not medic then addPerms(perms, Config.PolicePerms) end

    local easy = {}
    if Config.EasyMode and Config.EasyMode.default then easy = allPerms() end

    return {
        hospital = nil, dept = nil,
        grade = tonumber(job.grade) or 0,
        gradeLabel = job.gradeLabel or job.grade_label,
        perms = perms, easy = easy,
        onDuty = onDuty and true or false,
        medic = medic and true or false,
        police = police and true or false,
        job = job.name, jobLabel = job.label, isBoss = job.isBoss and true or false,
    }
end

-- duty rule + admin + public perms, applied to whatever the resolver returned
local function finalize(src, rec)
    rec.perms = type(rec.perms) == 'table' and rec.perms or {}
    rec.easy = type(rec.easy) == 'table' and rec.easy or {}
    local set = {}
    addPerms(set, rec.perms)
    if requireDuty() and not rec.onDuty and not rec.ignoreDuty then
        set = {}
    end
    addPerms(set, Config.PublicPerms)
    rec.admin = Core.IsAdmin(src)
    if rec.admin then
        for k in pairs(allPerms()) do set[k] = true end
    end
    rec.perms = set
    local easy = {}
    addPerms(easy, rec.easy)
    rec.easy = easy
    return rec
end

local function compute(src)
    local base = defaultRecord(src)
    local rec
    if provider then
        local ok, res = pcall(provider, src, NZA.Util.deepcopy(base))
        if ok and type(res) == 'table' then
            rec = res
            if rec.onDuty == nil then rec.onDuty = base.onDuty end
            if rec.medic == nil then rec.medic = base.medic end
            if rec.police == nil then rec.police = base.police end
            rec.job = rec.job or base.job
        elseif not ok then
            NZA.Warn('staff provider failed: ' .. tostring(res))
        end
    end
    return finalize(src, rec or base)
end

function S.Get(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local rec = cache[src]
    if not rec then
        rec = compute(src)
        cache[src] = rec
    end
    return rec
end

function S.Can(src, perm)
    src = tonumber(src)
    if src == 0 then return true end
    if not src then return false end
    if perm == nil then return true end
    local rec = S.Get(src)
    if not rec then return false end
    if rec.admin then return true end
    return rec.perms[perm] == true
end

function S.Easy(src, perm)
    local rec = S.Get(src)
    if rec and rec.easy[perm] ~= nil then return rec.easy[perm] == true end
    return (Config.EasyMode and Config.EasyMode.default) == true
end

function S.OnDuty()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local rec = src and S.Get(src)
        if rec and rec.medic and rec.onDuty then out[#out + 1] = src end
    end
    return out
end

function S.Refresh(src, force)
    src = tonumber(src)
    if not src or src <= 0 or not Core.Online(src) then return nil end
    local old = cache[src]
    local rec = compute(src)
    cache[src] = rec
    local ok, enc = pcall(json.encode, rec)
    enc = ok and enc or tostring(math.random())
    if force or enc ~= cacheStr[src] then
        cacheStr[src] = enc
        TriggerClientEvent('nza:staff:update', src, rec)
        NZA.Bus.Emit('staff:changed', src, rec, old)
    end
    return rec
end

function S.RefreshAll(force)
    for _, id in ipairs(GetPlayers()) do
        S.Refresh(tonumber(id), force)
    end
end

function S.Provider(fn)
    if fn ~= nil and type(fn) ~= 'function' then return false end
    provider = fn
    cache = {}
    S.RefreshAll()
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('player:loaded', function(src)
    SetTimeout(500, function() S.Refresh(src, true) end)
end)

NZA.Bus.On('player:job', function(src)
    S.Refresh(src)
end)

NZA.Bus.On('player:unloaded', function(src, reason)
    src = tonumber(src)
    if not src then return end
    cache[src] = nil
    cacheStr[src] = nil
    if reason ~= 'dropped' and Core.Online(src) then
        SetTimeout(250, function() S.Refresh(src, true) end)
    end
end)

lib.callback.register('nza:staff:get', function(src)
    -- a forced refresh hits the bridge and pushes an event; spammed calls get the cache
    if not Core.Rate('nza:staff:get', src, 2, 5000) then return S.Get(src) end
    return S.Refresh(src, true)
end)

-- safety net for duty toggles the framework doesn't announce
CreateThread(function()
    Wait(3000)
    S.RefreshAll(true)      -- resource (re)start: every client gets its record
    while true do
        Wait(30000)
        S.RefreshAll()
    end
end)
