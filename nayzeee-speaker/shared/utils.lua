NZ = NZ or {}

function NZ.L(key, ...)
    local pack = Locales[Config.Locale] or Locales['en']
    local s = pack[key] or Locales['en'][key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

function NZ.Debug(...)
    if Config.Debug then print('^5[nayzeee-speaker]^7', ...) end
end

function NZ.Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function NZ.InBlacklistedZone(coords)
    for _, z in ipairs(Config.BlacklistedZones or {}) do
        if #(coords - z.coords) <= z.radius then return true end
    end
    return false
end

function NZ.VehicleAllowed(model, class)
    local bl = Config.BlacklistedVehicles or {}
    if bl.models and bl.models[model] then return false end
    if bl.classes and bl.classes[class] then return false end
    return true
end

-- Parse whatever the player pasted. Returns kind ('yt' | 'url'), value
function NZ.ParseInput(input)
    if type(input) ~= 'string' then return nil end
    input = input:gsub('^%s+', ''):gsub('%s+$', '')
    if #input == 0 or #input > 500 then return nil end

    if input:match('^[%w_%-]+$') and #input == 11 then return 'yt', input end

    local host = input:match('^https?://([^/%?#]+)')
    if host then
        host = host:lower():gsub('^www%.', ''):gsub('^m%.', ''):gsub('^music%.', '')
        if host == 'youtu.be' then
            local id = input:match('youtu%.be/([%w_%-]+)')
            if id and #id == 11 then return 'yt', id end
        elseif host == 'youtube.com' or host == 'youtube-nocookie.com' then
            local id = input:match('[%?&]v=([%w_%-]+)')
                or input:match('/shorts/([%w_%-]+)')
                or input:match('/embed/([%w_%-]+)')
                or input:match('/live/([%w_%-]+)')
            if id and #id == 11 then return 'yt', id end
        end
        local path = input:match('^https?://[^%?#]+') or input
        local ext = path:lower():match('%.(%w+)$')
        if ext and (ext == 'mp3' or ext == 'ogg' or ext == 'opus' or ext == 'wav' or ext == 'webm' or ext == 'flac' or ext == 'm4a') then
            if input:match('^https://') then return 'url', input end
        end
    end
    return nil
end
