if not NAYZEEE_LOCK_OK then return end

-- Per-player settings stored in client KVP
Settings = {}

local KEY = 'nzm:settings:v1'

local defaults = {
    fps      = false,
    bars     = false,
    sounds   = true,
    scale    = 1.0,
    distance = 'normal',
    scene    = 'auto',
    filter   = '',
    weather  = 'auto',
    hour     = -1,
    music    = { enabled = true, url = '', volume = Config.Music.volume },
}

local function merge(base, over)
    local out = NZ.Copy(base)
    if type(over) ~= 'table' then return out end
    for k, v in pairs(over) do
        if type(v) == 'table' and type(out[k]) == 'table' then out[k] = merge(out[k], v)
        elseif out[k] ~= nil and type(v) == type(out[k]) then out[k] = v end
    end
    return out
end

function Settings.Load()
    local raw = GetResourceKvpString(KEY)
    Settings.data = merge(defaults, raw and NZ.Decode(raw))
    return Settings.data
end

function Settings.Save(data)
    Settings.data = merge(defaults, data)
    SetResourceKvp(KEY, json.encode(Settings.data))
    return Settings.data
end

function Settings.Reset()
    DeleteResourceKvp(KEY)
    return Settings.Load()
end

function Settings.Get(k)
    if not Settings.data then Settings.Load() end
    return Settings.data[k]
end

Settings.Load()
