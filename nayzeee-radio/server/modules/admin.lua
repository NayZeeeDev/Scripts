--[[
    NAYZEEE RADIO - Admin (server): /radioadmin data, save and live view

    The /radioadmin window (client/modules/admin.lua → html/apps/admin) reads and writes
    everything through these callbacks. Permission is NZR.Core.IsAdmin (ace
    Config.Admin.ace, then the framework's admin groups) and is checked on every call -
    the client opening the window proves nothing.

    Saving replaces the whole admin channel list and the whole admin vehicle list, after
    every field is checked: frequency valid and unique, access open / code / job, a code of
    exactly 4 digits for code channels, at least one job (≤ 16, grades 0..20) for job
    channels, labels ≤ 32 characters; vehicle models [A-Za-z0-9_] ≤ 32 characters and
    unique, labels ≤ 32, range multiplier 0.5..3. Up to 300 channels and 200 vehicles.

    PAYLOADS
      channel  { freq = '155.50', access = 'open' | 'code' | 'job', code = '1234' | nil,
                 jobs = { police = 0 } | nil, label = 'LSPD Dispatch' | nil, updatedBy }
               (save also takes jobs as a list { { name, grade } } or { 'police' })
      vehicle  { model = 'police3', label = 'Patrol' | nil, range_mult = 1.0 }
               (save also takes range or rangeMult for range_mult)
      jobs     { { name, label, grades = { { grade, label }, ... } }, ... }   (Bridge.GetJobs)
      live     { channels = { { freq, label, access, members = n, vehicles = n,
                                talkers = { { id, name, callsign, device } } } },
                 jammers = { { id, type, label, owner, ownerId, x, y, z, expires (s), e } },
                 radios = n powered radios }
      limits   { channels = 300, vehicles = 200, jobs = 16, grade = 20, label = 32,
                 min = Config.Channels.min, max = Config.Channels.max }
      restricted  Config.Channels.Restricted as { { from, to, label, jobs } } (read only)

    Callbacks
      nzr:admin:open ()                      → { ok, channels, vehicles, jobs, live, limits, restricted }
                                               | { ok = false, reason = 'denied' | 'busy' }
      nzr:admin:save ({ channels, vehicles }) → { ok = true, channels, vehicles } | { ok = false, error = 'text' }
                                               (a list left out is kept as it is)
      nzr:admin:jammerRemove (id)            → { ok }
      nzr:admin:live ()                      → { ok, live }     (refresh of the live tab)
      nzr:admin:check ()                     → { ok, admin }    (admin-only client tools such as /radiogrip)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Admin = NZR.Admin or {}
local AD = NZR.Admin
local Core = NZR.Core

local MAX_CHANNELS = 300
local MAX_VEHICLES = 200
local MAX_JOBS = 16
local MAX_GRADE = 20
local MAX_LABEL = 32
local MAX_MODEL = 32

local saving = false

local function L(key, ...) return NZR.L('server.' .. key, ...) end

local function by(src)
    if src == 0 then return 'console' end
    return ('%s (%s)'):format(Core.Name(src), Core.Identifier(src) or tostring(src))
end

-- ════════════════════════════════════════════════════════════════════════
-- LIVE VIEW
-- ════════════════════════════════════════════════════════════════════════

function AD.Live()
    local byFkey = {}
    local function entry(fkey)
        local e = byFkey[fkey]
        if not e then
            local label, access = NZR.Channels.Label(fkey)
            e = { freq = fkey, label = label, access = access, members = 0, vehicles = 0, talkers = {} }
            byFkey[fkey] = e
        end
        return e
    end

    local radios = 0
    for _, rec in pairs(NZR.Radio.players) do
        if rec.power then radios = radios + 1 end
    end
    for fkey, members in pairs(NZR.Radio.members) do
        entry(fkey).members = NZR.Util.Count(members)
    end
    for fkey, n in pairs(NZR.Vehicles.TunedCounts()) do
        entry(fkey).vehicles = n
    end
    for id, tx in pairs(NZR.Routing.active) do
        local t = entry(tx.fkey).talkers
        t[#t + 1] = { id = id, name = tx.name, callsign = tx.callsign, device = tx.device, emergency = tx.emergency == true }
    end

    local channels = {}
    for _, e in pairs(byFkey) do channels[#channels + 1] = e end
    table.sort(channels, function(a, b) return tonumber(a.freq) < tonumber(b.freq) end)
    return { channels = channels, jammers = NZR.Jammers.AdminList(), radios = radios }
end

local function limits()
    local band = Config.Channels or {}
    return {
        channels = MAX_CHANNELS, vehicles = MAX_VEHICLES, jobs = MAX_JOBS, grade = MAX_GRADE,
        label = MAX_LABEL, model = MAX_MODEL, min = band.min or 1.0, max = band.max or 999.99,
    }
end

local function restricted()
    local out = {}
    for _, r in ipairs((Config.Channels and Config.Channels.Restricted) or {}) do
        out[#out + 1] = { from = r.from, to = r.to, label = r.label, jobs = r.jobs }
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- VALIDATION
-- ════════════════════════════════════════════════════════════════════════

local function cleanLabel(v)
    if v == nil or v == false then return nil end
    if type(v) ~= 'string' then return nil end
    return Bridge.CleanText(v, MAX_LABEL)
end

local function isInt(n)
    return type(n) == 'number' and n == math.floor(n)
end

-- jobs as { police = 0 }, { { name = 'police', grade = 0 } } or { 'police' } → map | nil, err
local function validateJobs(raw, fkey)
    if type(raw) ~= 'table' then return nil, L('admin_err_jobs', fkey) end
    local out, n = {}, 0
    for k, v in pairs(raw) do
        local name, grade
        if type(k) == 'string' then
            name, grade = k, v
        elseif type(v) == 'string' then
            name, grade = v, 0
        elseif type(v) == 'table' then
            name, grade = v.name, v.grade
        else
            return nil, L('admin_err_jobs', fkey)
        end
        grade = tonumber(grade)
        if type(name) ~= 'string' or not name:match('^[%w_%-]+$') or #name > 32 then
            return nil, L('admin_err_job_name', fkey)
        end
        if not grade or not isInt(grade) or grade < 0 or grade > MAX_GRADE then
            return nil, L('admin_err_grade', fkey, name, MAX_GRADE)
        end
        if out[name] == nil then n = n + 1 end
        out[name] = grade
    end
    if n == 0 then return nil, L('admin_err_jobs', fkey) end
    if n > MAX_JOBS then return nil, L('admin_err_too_many_jobs', fkey, MAX_JOBS) end
    return out
end

local function validateChannels(list)
    if type(list) ~= 'table' then return nil, L('admin_err_list') end
    local n = #list
    if NZR.Util.Count(list) ~= n then return nil, L('admin_err_list') end
    if n > MAX_CHANNELS then return nil, L('admin_err_too_many_channels', MAX_CHANNELS) end
    local out, seen = {}, {}
    for i = 1, n do
        local c = list[i]
        if type(c) ~= 'table' then return nil, L('admin_err_row', i) end
        local f = NZR.Freq.Parse(c.freq)
        if not f or not NZR.Freq.Valid(f) then
            return nil, L('admin_err_freq', i, tostring(c.freq or '-'))
        end
        local fkey = NZR.Freq.Key(f)
        if seen[fkey] then return nil, L('admin_err_dup', fkey) end
        seen[fkey] = true

        local access = c.access
        if access ~= 'open' and access ~= 'code' and access ~= 'job' then
            return nil, L('admin_err_access', fkey)
        end
        local code, jobs
        if access == 'code' then
            code = c.code
            if isInt(code) and code >= 0 and code <= 9999 then code = ('%04d'):format(code) end
            if type(code) ~= 'string' or not code:match('^%d%d%d%d$') then
                return nil, L('admin_err_code', fkey)
            end
        elseif access == 'job' then
            local err
            jobs, err = validateJobs(c.jobs, fkey)
            if not jobs then return nil, err end
        end
        if c.label ~= nil and c.label ~= false and type(c.label) ~= 'string' then
            return nil, L('admin_err_label', fkey, MAX_LABEL)
        end
        out[#out + 1] = { freq = fkey, access = access, code = code, jobs = jobs, label = cleanLabel(c.label) }
    end
    return out
end

local function validateVehicles(list)
    if type(list) ~= 'table' then return nil, L('admin_err_list') end
    local n = #list
    if NZR.Util.Count(list) ~= n then return nil, L('admin_err_list') end
    if n > MAX_VEHICLES then return nil, L('admin_err_too_many_vehicles', MAX_VEHICLES) end
    local out, seen = {}, {}
    for i = 1, n do
        local v = list[i]
        if type(v) ~= 'table' then return nil, L('admin_err_row', i) end
        local model = type(v.model) == 'string' and v.model:gsub('^%s+', ''):gsub('%s+$', ''):lower() or nil
        if not model or model == '' or #model > MAX_MODEL or not model:match('^[%w_]+$') then
            return nil, L('admin_err_model', i, tostring(v.model or '-'))
        end
        if seen[model] then return nil, L('admin_err_dup_model', model) end
        seen[model] = true
        local mult = v.range_mult
        if mult == nil then mult = v.rangeMult end
        if mult == nil then mult = v.range end
        if mult == nil then mult = 1.0 end
        mult = tonumber(mult)
        if not mult or mult ~= mult or mult < 0.5 or mult > 3.0 then
            return nil, L('admin_err_range', model)
        end
        if v.label ~= nil and v.label ~= false and type(v.label) ~= 'string' then
            return nil, L('admin_err_label', model, MAX_LABEL)
        end
        out[#out + 1] = { model = model, label = cleanLabel(v.label), range_mult = math.floor(mult * 100 + 0.5) / 100 }
    end
    return out
end

AD.ValidateChannels = validateChannels
AD.ValidateVehicles = validateVehicles

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

NZR.Callback('nzr:admin:open', function(src)
    if not Core.IsAdmin(src) then return { ok = false, reason = 'denied' } end
    if not Core.Rate('nzr:admin:open', src, 6, 5000) then return { ok = false, reason = 'busy' } end
    return {
        ok = true,
        channels = NZR.Channels.AdminList(),
        vehicles = NZR.Vehicles.AdminList(),
        jobs = Core.B('GetJobs') or {},
        live = AD.Live(),
        limits = limits(),
        restricted = restricted(),
    }
end)

NZR.Callback('nzr:admin:live', function(src)
    if not Core.IsAdmin(src) then return { ok = false, reason = 'denied' } end
    if not Core.Rate('nzr:admin:live', src, 10, 5000) then return { ok = false, reason = 'busy' } end
    return { ok = true, live = AD.Live() }
end)

-- Admin-only client tools (/radiogrip) ask here: an ace checked on the client proves nothing.
NZR.Callback('nzr:admin:check', function(src)
    if not Core.Rate('nzr:admin:check', src, 6, 5000) then return { ok = false, reason = 'busy' } end
    return { ok = true, admin = Core.IsAdmin(src) == true }
end)

NZR.Callback('nzr:admin:save', function(src, data)
    if not Core.IsAdmin(src) then return { ok = false, error = L('admin_denied') } end
    if not Core.Rate('nzr:admin:save', src, 3, 5000) then return { ok = false, error = L('admin_busy') } end
    if type(data) ~= 'table' then return { ok = false, error = L('admin_err_list') } end
    if saving then return { ok = false, error = L('admin_busy') } end

    local channels, vehicles, err
    if data.channels ~= nil then
        channels, err = validateChannels(data.channels)
        if not channels then return { ok = false, error = err } end
    end
    if data.vehicles ~= nil then
        vehicles, err = validateVehicles(data.vehicles)
        if not vehicles then return { ok = false, error = err } end
    end
    if not channels and not vehicles then return { ok = false, error = L('admin_err_list') } end

    saving = true
    local ok = pcall(function()
        if channels and not NZR.DB.SaveChannels(channels, by(src)) then err = L('admin_err_db') end
        if not err and vehicles and not NZR.DB.SaveVehicles(vehicles) then err = L('admin_err_db') end
    end)
    saving = false
    if not ok or err then return { ok = false, error = err or L('admin_err_db') } end

    if channels then NZR.Channels.Reload() end
    if vehicles then NZR.Vehicles.Reload() end

    local codes, jobsOnly = 0, 0
    for _, c in ipairs(channels or {}) do
        if c.access == 'code' then codes = codes + 1 elseif c.access == 'job' then jobsOnly = jobsOnly + 1 end
    end
    Core.Webhook('admin', L('wh_admin_saved'), {
        Core.WebhookField(L('wh_admin'), by(src), false),
        Core.WebhookField(L('wh_channels'), channels and ('%d (%d code, %d job)'):format(#channels, codes, jobsOnly) or L('wh_unchanged')),
        Core.WebhookField(L('wh_vehicles'), vehicles and tostring(#vehicles) or L('wh_unchanged')),
    })
    return { ok = true, channels = NZR.Channels.AdminList(), vehicles = NZR.Vehicles.AdminList() }
end)

NZR.Callback('nzr:admin:jammerRemove', function(src, id)
    if not Core.IsAdmin(src) then return { ok = false, reason = 'denied' } end
    if not Core.Rate('nzr:admin:jammerRemove', src, 10, 5000) then return { ok = false, reason = 'busy' } end
    if type(id) ~= 'string' or #id > 24 then return { ok = false } end
    local j = NZR.Jammers.Get(id)
    if not j or not NZR.Jammers.Remove(id, 'admin', src) then return { ok = false } end
    local def = (Config.Jammers and Config.Jammers.Types and Config.Jammers.Types[j.t]) or {}
    Core.Webhook('jammers', L('wh_jammer_removed'), {
        Core.WebhookField(L('wh_admin'), by(src)),
        Core.WebhookField(L('wh_type'), def.label or j.t),
        Core.WebhookField(L('wh_owner'), j.ownerName or '-'),
    })
    return { ok = true }
end)
