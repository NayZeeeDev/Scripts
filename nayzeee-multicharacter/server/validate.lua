if not NAYZEEE_LOCK_OK then return end

Validate = {}

local R = Config.Registration

-- ── rate limits (ServerConfig.RateLimit, ms) ──────────────────────────────
local limits = {}

-- true when `action` was used by `src` less than `ms` (default from config) ago
function Validate.Limited(src, action, ms)
    ms = ms or ServerConfig.RateLimit[action] or 1000
    local l = limits[src]
    if not l then l = {} limits[src] = l end
    local now = GetGameTimer()
    if l[action] and now - l[action] < ms then return true end
    l[action] = now
    return false
end

function Validate.Forget(src) limits[src] = nil end

-- ── primitive checks ──────────────────────────────────────────────────────
-- Character / owner ids: ESX "char1:abc..." or QB citizenid
function Validate.Id(v)
    return type(v) == 'string' and #v > 0 and #v <= 64 and v:match('^[%w:_%-%.]+$') ~= nil
end

-- Link ids from multichar_squads
function Validate.LinkId(v)
    v = tonumber(v)
    if not v or v < 1 or v ~= math.floor(v) or v > 4294967295 then return nil end
    return v
end

-- Strip control chars + markup, trim, utf8-aware length cap. Returns clean string, or nil when invalid / empty.
function Validate.Text(v, max)
    if type(v) ~= 'string' then return nil end
    v = NZ.Trim((v:gsub('[%c<>\\{}]', ' '):gsub('%s+', ' ')))
    if v == '' then return nil end
    local len = utf8.len(v)
    if not len or len > max then return nil end
    return v
end

-- ── registration ──────────────────────────────────────────────────────────
local function blacklisted(s)
    local low = s:lower():gsub('[^%a]', '')
    for _, w in ipairs(R.name.blacklist or {}) do
        if low:find(w:lower(), 1, true) then return true end
    end
    return false
end

local function name(s)
    s = NZ.Trim(s)
    if s == '' then return nil, 'v_required' end
    if #s < R.name.min then return nil, 'v_min' end
    if #s > R.name.max then return nil, 'v_max' end
    if not s:match("^[%a][%a%s'%-]*$") then return nil, 'v_letters' end
    if blacklisted(s) then return nil, 'v_blacklist' end
    if R.name.autoCapitalize then s = NZ.Capitalize(s) end
    return s
end

local function isLeap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function age(y, m, d)
    local now = os.date('*t')
    local a = now.year - y
    if now.month < m or (now.month == m and now.day < d) then a = a - 1 end
    return a
end
Validate.Age = age

-- Accepts dobY/dobM/dobD or dob = 'YYYY-MM-DD'
local function dobParts(form)
    if form.dobY then return tonumber(form.dobY), tonumber(form.dobM), tonumber(form.dobD) end
    if type(form.dob) == 'string' then
        local y, m, d = form.dob:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$')
        return tonumber(y), tonumber(m), tonumber(d)
    end
end

-- Returns clean data table, or nil + { field = errorKey }
function Validate.Registration(form)
    if type(form) ~= 'table' then return nil, { form = 'v_required' } end
    local errors, out = {}, {}

    local f, e1 = name(form.firstname)
    local l, e2 = name(form.lastname)
    if e1 then errors.firstname = e1 else out.firstname = f end
    if e2 then errors.lastname = e2 else out.lastname = l end

    local y, m, d = dobParts(form)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or y < 1900 then
        errors.dob = 'v_date'
    else
        local maxd = (m == 2 and isLeap(y)) and 29 or mdays[m]
        if d > maxd then
            errors.dob = 'v_date'
        else
            local a = age(y, m, d)
            if a < R.dob.minAge then errors.dob = 'v_age_min'
            elseif a > R.dob.maxAge then errors.dob = 'v_age_max'
            else out.dobY, out.dobM, out.dobD = y, m, d end
        end
    end

    local g = form.gender
    local okGender = false
    for _, v in ipairs(R.genders) do if v == g then okGender = true end end
    if not okGender then errors.gender = 'v_gender' else out.gender = g end

    if R.height.enabled then
        local h = tonumber(form.height)
        if not h or h < R.height.min or h > R.height.max then errors.height = 'v_height' else out.height = math.floor(h) end
    else
        out.height = R.height.default
    end

    if R.nationality.enabled then
        local n = NZ.Trim(form.nationality)
        local found
        for _, v in ipairs(Config.Nationalities) do if v == n then found = v break end end
        if not found then
            if R.nationality.required then errors.nationality = 'v_nationality' else out.nationality = R.nationality.default end
        else
            out.nationality = found
        end
    else
        out.nationality = R.nationality.default
    end

    if R.backstory.enabled then
        local b = NZ.Trim(type(form.backstory) == 'string' and form.backstory or ''):gsub('[%c<>]', ' ')
        if b == '' then
            if R.backstory.required then errors.backstory = 'v_required' end
        elseif #b < R.backstory.min then errors.backstory = 'v_min'
        elseif #b > math.min(R.backstory.max, 600) then errors.backstory = 'v_max'
        else out.backstory = b end
    end

    if not errors.firstname and not errors.lastname and R.name.uniqueFullName and Bridge.NameTaken(out.firstname, out.lastname) then
        errors.lastname = 'v_taken'
    end

    if next(errors) then return nil, errors end
    return out
end

-- error keys -> localised messages with their numbers filled in
function Validate.Messages(errors)
    local T, msgs = NZ.T, {}
    for field, key in pairs(errors) do
        if key == 'v_min' then msgs[field] = T(key, field == 'backstory' and R.backstory.min or R.name.min)
        elseif key == 'v_max' then msgs[field] = T(key, field == 'backstory' and R.backstory.max or R.name.max)
        elseif key == 'v_age_min' then msgs[field] = T(key, R.dob.minAge)
        elseif key == 'v_age_max' then msgs[field] = T(key, R.dob.maxAge)
        elseif key == 'v_height' then msgs[field] = T(key, R.height.min, R.height.max)
        else msgs[field] = T(key) end
    end
    return msgs
end

-- Backstory edit from the lobby: '' clears, nil = invalid
function Validate.Backstory(b)
    if b == nil then return '' end
    if type(b) ~= 'string' then return nil end
    b = NZ.Trim(b):gsub('[%c<>]', ' ')
    if b == '' then return '' end
    local max = math.min(R.backstory.max or 600, 600)
    if #b > max then return nil end
    return b
end
