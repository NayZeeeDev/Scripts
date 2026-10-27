-- Small helpers both sides use.
NZ = NZ or {}

-- text in the server's language, then English, then the key itself
function NZ.L(key, ...)
    local s = (Locales[Config.Locale] or Locales.en)[key] or Locales.en[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

function NZ.Debug(...)
    if Config.Debug then print('^5[nayzeee-speaker]^7', ...) end
end

-- a number between lo and hi (anything that isn't one, NaN included, becomes lo)
function NZ.Clamp(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- a string without the spaces around it, cut to `max` characters ('' for anything that isn't a string)
function NZ.Trim(s, max)
    if type(s) ~= 'string' then return '' end
    s = s:sub(1, 2048):match('^%s*(.-)%s*$')
    return max and s:sub(1, max) or s
end

--[[
    A cache whose entries expire `ttl` seconds after they were stored. Expired entries are swept
    whenever it has doubled in size since the last sweep, so a long uptime doesn't keep growing it.
]]
function NZ.Cache(ttl)
    local life, items, size, sweepAt = ttl * 1000, {}, 0, 64
    local cache = {}

    function cache.get(key)
        local hit = items[key]
        if hit and GetGameTimer() - hit.at < life then return hit.value end
    end

    function cache.set(key, value)
        local now = GetGameTimer()
        if items[key] == nil then
            size = size + 1
            if size > sweepAt then
                for k, hit in pairs(items) do
                    if now - hit.at >= life then items[k], size = nil, size - 1 end
                end
                sweepAt = math.max(64, size * 2)
            end
        end
        items[key] = { value = value, at = now }
        return value
    end

    return cache
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

local AUDIO_EXT = { mp3 = true, ogg = true, opus = true, wav = true, webm = true, flac = true, m4a = true }

-- What the player pasted: 'yt', videoId | 'url', httpsAudioLink | nil
function NZ.ParseInput(input)
    input = NZ.Trim(input)
    if #input == 0 or #input > 500 then return nil end

    if #input == 11 and input:match('^[%w_%-]+$') then return 'yt', input end

    local host = input:match('^https?://([^/%?#]+)')
    if not host then return nil end
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
    -- a direct audio file; https only, the game's browser refuses mixed content
    local ext = input:match('^https?://[^%?#]+'):lower():match('%.(%w+)$')
    if ext and AUDIO_EXT[ext] and input:match('^https://') then return 'url', input end
    return nil
end
