-- Player preferences: colours, size, toast position, sounds, banners and minigame keys.
-- Saved on the player's own PC (client KVP). Server owners set the defaults in Config.UI.

Prefs = {}

local KVP = 'nzwig:prefs'
local CU = Config.UI

local DEFAULTS = {
    accent       = CU.Accent,
    alert        = CU.Alert,
    scale        = CU.Scale,
    toastPos     = CU.ToastPosition,
    sounds       = CU.Sounds,
    volume       = CU.Volume,
    reduceMotion = CU.ReduceMotion,
    banners      = 'all',          -- 'all' | 'city' (only citywide) | 'none'
    keyPull      = Config.Keys.Pull,
    keyMashL     = Config.Keys.MashLeft,
    keyMashR     = Config.Keys.MashRight,
}

local POSITIONS = { ['top-right'] = true, ['top-left'] = true, ['top-center'] = true, ['bottom-right'] = true, ['bottom-left'] = true }
local BANNERS = { all = true, city = true, none = true }

local function hex(v, fallback)
    if type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') then return v:lower() end
    return fallback
end

local function keycode(v, fallback)
    if type(v) == 'string' and #v <= 24 and v:match('^[%w]+$') then return v end
    return fallback
end

local function num(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then return fallback end
    return Clamp(v, lo, hi)
end

local function sanitize(t)
    t = type(t) == 'table' and t or {}
    return {
        accent       = hex(t.accent, DEFAULTS.accent),
        alert        = hex(t.alert, DEFAULTS.alert),
        scale        = num(t.scale, 0.8, 1.25, DEFAULTS.scale),
        toastPos     = POSITIONS[t.toastPos] and t.toastPos or DEFAULTS.toastPos,
        sounds       = t.sounds == nil and DEFAULTS.sounds or t.sounds == true,
        volume       = num(t.volume, 0, 1, DEFAULTS.volume),
        reduceMotion = t.reduceMotion == nil and DEFAULTS.reduceMotion or t.reduceMotion == true,
        banners      = BANNERS[t.banners] and t.banners or DEFAULTS.banners,
        keyPull      = keycode(t.keyPull, DEFAULTS.keyPull),
        keyMashL     = keycode(t.keyMashL, DEFAULTS.keyMashL),
        keyMashR     = keycode(t.keyMashR, DEFAULTS.keyMashR),
    }
end

local data
local function load()
    if not CU.PlayerPrefs then data = sanitize({}) return end
    local raw = GetResourceKvpString(KVP)
    local ok, t = pcall(json.decode, raw or '{}')
    data = sanitize(ok and t or {})
end
load()

function Prefs.All()
    local out = {}
    for k, v in pairs(data) do out[k] = v end
    out.editable = CU.PlayerPrefs == true
    out.presets = CU.Presets
    out.defaults = DEFAULTS
    return out
end

function Prefs.Get(key) return data[key] end

local function push()
    local all = Prefs.All()
    NUI.Send('prefs', all)
    PhoneBridge.Send({ type = 'prefs', prefs = all })
end

function Prefs.Save(t)
    if not CU.PlayerPrefs then return Prefs.All() end
    data = sanitize(t)
    SetResourceKvp(KVP, json.encode(data))
    push()
    return Prefs.All()
end

function Prefs.Reset()
    if not CU.PlayerPrefs then return Prefs.All() end
    DeleteResourceKvp(KVP)
    data = sanitize({})
    push()
    return Prefs.All()
end

RegisterNUICallback('prefs', function(_, cb) cb(Prefs.All()) end)
RegisterNUICallback('prefsSave', function(d, cb) cb(Prefs.Save(d)) end)
RegisterNUICallback('prefsReset', function(_, cb) cb(Prefs.Reset()) end)

if CU.SettingsCommand then
    RegisterCommand(CU.SettingsCommand, function()
        TriggerEvent('nz-wig:c:openVault', 'settings')
    end, false)
end
