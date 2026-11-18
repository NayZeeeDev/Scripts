if not NAYZEEE_LOCK_OK then return end

-- Per-player lobby settings stored in client KVP (contract §7 Settings)
Settings = {}

local KEY = 'nzm:settings:v2'

local function defaults()
    local vol = Config.Audio.volume or {}
    return {
        scale         = Config.UI.scale or 1.0,
        muted         = false,
        uiVolume      = vol.ui or 0.6,
        ambientVolume = vol.ambience or 0.35,
        sway          = true,
        dof           = true,
        plates        = Config.UI.nameplates ~= false,
        perf          = false,
        bars          = true,
    }
end

-- Only known keys with the same type survive (old / tampered KVP can't break anything)
local function merge(base, over)
    local out = NZ.Copy(base)
    if type(over) ~= 'table' then return out end
    for k, v in pairs(over) do
        if out[k] ~= nil and type(v) == type(out[k]) then out[k] = v end
    end
    out.scale = math.min(math.max(tonumber(out.scale) or 1.0, 0.7), 1.4)
    out.uiVolume = math.min(math.max(tonumber(out.uiVolume) or 0.6, 0.0), 1.0)
    out.ambientVolume = math.min(math.max(tonumber(out.ambientVolume) or 0.35, 0.0), 1.0)
    return out
end

function Settings.Load()
    local raw = GetResourceKvpString(KEY)
    Settings.data = merge(defaults(), raw and NZ.Decode(raw))
    return Settings.data
end

-- Partial updates are fine: missing keys keep their current value
function Settings.Save(data)
    local cur = Settings.data or Settings.Load()
    local nextData = NZ.Copy(cur)
    if type(data) == 'table' then
        for k, v in pairs(data) do nextData[k] = v end
    end
    Settings.data = merge(defaults(), nextData)
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
