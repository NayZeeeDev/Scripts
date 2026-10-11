NZ = NZ or {}
NZ.Resource = GetCurrentResourceName()
NZ.Version  = GetResourceMetadata(NZ.Resource, 'version', 0) or '1.0.0'

local units = { y = 31536000, w = 604800, d = 86400, h = 3600, m = 60, s = 1 }

--- "1y2d3h4m" -> seconds. "perm", "0" or "" -> nil (permanent). Bad input -> false.
function NZ.ParseDuration(str)
    if str == nil then return nil end
    if type(str) == 'number' then return str > 0 and math.floor(str) or nil end
    str = tostring(str):lower():gsub('%s+', '')
    if str == '' or str == 'perm' or str == 'permanent' or str == '0' then return nil end
    if str:match('^%d+$') then return tonumber(str) * 60 end -- bare number = minutes
    local total, matched = 0, false
    for num, unit in str:gmatch('(%d+)([ywdhms])') do
        total = total + tonumber(num) * units[unit]
        matched = true
    end
    if not matched or total <= 0 then return false end
    return total
end

function NZ.FormatDuration(sec)
    if not sec then return 'Permanent' end
    sec = math.max(0, math.floor(sec))
    local d = sec // 86400; sec = sec % 86400
    local h = sec // 3600;  sec = sec % 3600
    local m = sec // 60;    local s = sec % 60
    local out = {}
    if d > 0 then out[#out + 1] = d .. 'd' end
    if h > 0 then out[#out + 1] = h .. 'h' end
    if m > 0 then out[#out + 1] = m .. 'm' end
    if d == 0 and h == 0 and m < 5 and (s > 0 or #out == 0) then out[#out + 1] = s .. 's' end
    return table.concat(out, ' ')
end

function NZ.Round(n, dp)
    local m = 10 ^ (dp or 2)
    return math.floor(n * m + 0.5) / m
end

function NZ.Trim(s, max)
    s = tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if max and #s > max then s = s:sub(1, max) end
    return s
end

function NZ.IsTrue(v) return v == true or v == 1 or v == '1' or v == 'true' end

function NZ.Debug(...)
    if Config.Debug then print('^6[nayzeee-admin]^7', ...) end
end

function NZ.L(key, ...)
    local str = (Locales and Locales[key]) or key
    if select('#', ...) > 0 then return str:format(...) end
    return str
end
