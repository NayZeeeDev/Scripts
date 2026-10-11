if not NAYZEEE_LOCK_OK then return end

Validate = {}

local R = Config.Registration

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

-- Returns clean data table, or nil + { field = errorKey }
function Validate.Registration(form)
    if type(form) ~= 'table' then return nil, { form = 'v_required' } end
    local errors, out = {}, {}

    local f, e1 = name(form.firstname)
    local l, e2 = name(form.lastname)
    if e1 then errors.firstname = e1 else out.firstname = f end
    if e2 then errors.lastname = e2 else out.lastname = l end

    local y, m, d = tonumber(form.dobY), tonumber(form.dobM), tonumber(form.dobD)
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
        local b = NZ.Trim(form.backstory):gsub('[%c]', ' ')
        if b == '' then
            if R.backstory.required then errors.backstory = 'v_required' end
        elseif #b < R.backstory.min then errors.backstory = 'v_min'
        elseif #b > R.backstory.max then errors.backstory = 'v_max'
        else out.backstory = b end
    end

    if not errors.firstname and not errors.lastname and R.name.uniqueFullName and Bridge.NameTaken(out.firstname, out.lastname) then
        errors.lastname = 'v_taken'
    end

    if next(errors) then return nil, errors end
    return out
end

function Validate.Backstory(b)
    b = NZ.Trim(b):gsub('[%c]', ' ')
    if b == '' then return '' end
    if #b > R.backstory.max then b = b:sub(1, R.backstory.max) end
    return b
end
