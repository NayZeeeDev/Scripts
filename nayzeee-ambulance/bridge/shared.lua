--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge (shared core)
    ═══════════════════════════════════════════════════════════════════════════

    This file is OPEN (escrow_ignore). It holds what both sides of the bridge
    share:

      Bridge.Framework            'esx' | 'qbcore' | 'qbox' | 'standalone'
      Bridge.Started(resource)    true while a resource is started/starting
      Bridge.Pick(kind, ...)      adapter detection (override → priority list)
      Bridge.Core()               ESX / QBCore shared object (cached)
      Bridge.Cfg(key, default)    read Config.Bridge safely
      Bridge.IsMedicJob(name) / Bridge.IsPoliceJob(name)
      Bridge.SplitDutyJob(name)   ESX 'offambulance' → 'ambulance', false
      Bridge.ItemKey(name) / Bridge.ItemDef(name) / Bridge.ItemLabel(name)
      Bridge.FaIcon(icon)         NAYZEEE icon name → Font Awesome class
      Bridge.Throttle(src, key, ms)
      Bridge.Debug(...) / Bridge.Warn(...)

    AUTO-DETECT ORDER
    Every kind of integration has a priority list and a resource map below.
    Reorder a list to prefer one script over another, or add your own entry
    (and an adapter with the same name in bridge/client or bridge/server).
    A resource value of true means "always available" (built in).
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge = Bridge or {}
Bridge.IsServer = IsDuplicityVersion()
Bridge.Version = '1.0.0'

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIG ACCESS
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.Cfg(key, default)
    local cfg = Config and Config.Bridge
    if cfg == nil then return default end
    local value = cfg[key]
    if value == nil then return default end
    return value
end

function Bridge.Debug(...)
    if not (Bridge.Cfg('debug', false) or (Config and Config.Debug)) then return end
    local parts = {}
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        parts[#parts + 1] = type(v) == 'table' and json.encode(v) or tostring(v)
    end
    print('^5[nayzeee-ambulance:bridge]^7 ' .. table.concat(parts, ' '))
end

function Bridge.Warn(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('^3[nayzeee-ambulance:bridge]^7 ' .. table.concat(parts, ' '))
end

-- Run an adapter function; errors are logged instead of breaking the caller.
function Bridge.Try(label, fn, ...)
    if type(fn) ~= 'function' then return false end
    local results = table.pack(pcall(fn, ...))
    if not results[1] then
        Bridge.Debug(('adapter "%s" failed: %s'):format(tostring(label), tostring(results[2])))
        return false
    end
    return true, table.unpack(results, 2, results.n)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOURCE STATE
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.Started(resource)
    if resource == true then return true end
    if type(resource) ~= 'string' or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO-DETECT ORDER  (edit freely)
-- ═══════════════════════════════════════════════════════════════════════════

Bridge.Priority = {
    -- qbx_core provides 'qb-core', so Qbox is checked before QBCore
    framework = { 'qbox', 'esx', 'qbcore' },

    inventory = {
        'ox_inventory', 'qs-inventory', 'codem-inventory', 'origen_inventory', 'tgiann-inventory',
        'core_inventory', 'ps-inventory', 'lj-inventory', 'qb-inventory', 'framework',
    },

    -- sleepless_interact provides 'ox_target' and 'qtarget', so it goes first
    target = { 'sleepless_interact', 'ox_target', 'qb-target', 'qtarget', 'interact', 'builtin' },

    -- 'nza' is our own NUI toast and is always available
    notify = { 'nza', 'nayzeee', 'ox_lib', 'okok', 'codem', 'mythic', 'brutal', 't-notify', 'qb', 'esx', 'native' },

    phone = {
        'lb-phone', 'qs-smartphone-pro', 'qs-smartphone', 'yseries', 'npwd', 'gksphone',
        'okokPhone', 'roadphone', 'high-phone', 'renewed-phone',
    },

    dispatch = {
        'lb-tablet', 'cd_dispatch', 'ps-dispatch', 'qs-dispatch', 'rcore_dispatch', 'core_dispatch',
        'tk_dispatch', 'origen_police',
    },

    -- qbx_vehiclekeys provides 'qb-vehiclekeys', so it goes first
    keys = {
        'qbx_vehiclekeys', 'qb-vehiclekeys', 'qs-vehiclekeys', 'wasabi_carlock', 'MrNewbVehicleKeys',
        'Renewed-Vehiclekeys', 't1ger_keys', 'cd_garage', 'okokGarage', 'jaksam',
    },

    fuel = {
        'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'ps-fuel', 'lc_fuel', 'okokGasStation', 'Renewed-Fuel', 'native',
    },

    clothing = {
        'illenium-appearance', 'fivem-appearance', 'rcore_clothing', 'qb-clothing', 'esx_skin', 'native',
    },

    -- society money, per framework
    society = {
        esx        = { 'esx_addonaccount', 'okokBanking', 'fd_banking' },
        qbcore     = { 'Renewed-Banking', 'okokBanking', 'fd_banking', 'qb-banking', 'qb-management' },
        qbox       = { 'Renewed-Banking', 'okokBanking', 'fd_banking', 'qb-banking', 'qbx_management' },
        standalone = { 'Renewed-Banking', 'okokBanking', 'fd_banking' },
    },
}

-- adapter name → resource that must be started (true = built in)
Bridge.Resources = {
    framework = { qbox = 'qbx_core', esx = 'es_extended', qbcore = 'qb-core' },

    inventory = {
        ['ox_inventory']     = 'ox_inventory',
        ['qs-inventory']     = 'qs-inventory',
        ['codem-inventory']  = 'codem-inventory',
        ['origen_inventory'] = 'origen_inventory',
        ['tgiann-inventory'] = 'tgiann-inventory',
        ['core_inventory']   = 'core_inventory',
        ['ps-inventory']     = 'ps-inventory',
        ['lj-inventory']     = 'lj-inventory',
        ['qb-inventory']     = 'qb-inventory',
        ['framework']        = true,
    },

    target = {
        ['ox_target']          = 'ox_target',
        ['qb-target']          = 'qb-target',
        ['qtarget']            = 'qtarget',
        ['interact']           = 'interact',
        ['sleepless_interact'] = 'sleepless_interact',
        ['builtin']            = true,
    },

    notify = {
        ['nza']      = true,
        ['nayzeee']  = 'nayzeee-notify',
        ['ox_lib']   = 'ox_lib',
        ['okok']     = 'okokNotify',
        ['codem']    = 'codem-notification',
        ['mythic']   = 'mythic_notify',
        ['brutal']   = 'brutal_notify',
        ['t-notify'] = 't-notify',
        ['qb']       = 'qb-core',
        ['esx']      = 'es_extended',
        ['native']   = true,
    },

    phone = {
        ['lb-phone']          = 'lb-phone',
        ['qs-smartphone-pro'] = 'qs-smartphone-pro',
        ['qs-smartphone']     = 'qs-smartphone',
        ['yseries']           = 'yseries',
        ['npwd']              = 'npwd',
        ['gksphone']          = 'gksphone',
        ['okokPhone']         = 'okokPhone',
        ['roadphone']         = 'roadphone',
        ['high-phone']        = 'high-phone',
        ['renewed-phone']     = 'renewed-phone',
    },

    dispatch = {
        ['cd_dispatch']    = 'cd_dispatch',
        ['ps-dispatch']    = 'ps-dispatch',
        ['qs-dispatch']    = 'qs-dispatch',
        ['rcore_dispatch'] = 'rcore_dispatch',
        ['core_dispatch']  = 'core_dispatch',
        ['tk_dispatch']    = 'tk_dispatch',
        ['origen_police']  = 'origen_police',
        ['lb-tablet']      = 'lb-tablet',
    },

    keys = {
        ['qbx_vehiclekeys']     = 'qbx_vehiclekeys',
        ['qb-vehiclekeys']      = 'qb-vehiclekeys',
        ['qs-vehiclekeys']      = 'qs-vehiclekeys',
        ['wasabi_carlock']      = 'wasabi_carlock',
        ['MrNewbVehicleKeys']   = 'MrNewbVehicleKeys',
        ['cd_garage']           = 'cd_garage',
        ['Renewed-Vehiclekeys'] = 'Renewed-Vehiclekeys',
        ['t1ger_keys']          = 't1ger_keys',
        ['okokGarage']          = 'okokGarage',
        ['jaksam']              = 'vehicles_keys',
    },

    fuel = {
        ['ox_fuel']        = 'ox_fuel',
        ['LegacyFuel']     = 'LegacyFuel',
        ['cdn-fuel']       = 'cdn-fuel',
        ['ps-fuel']        = 'ps-fuel',
        ['lc_fuel']        = 'lc_fuel',
        ['okokGasStation'] = 'okokGasStation',
        ['Renewed-Fuel']   = 'Renewed-Fuel',
        ['native']         = true,
    },

    clothing = {
        ['illenium-appearance'] = 'illenium-appearance',
        ['fivem-appearance']    = 'fivem-appearance',
        ['rcore_clothing']      = 'rcore_clothing',
        ['qb-clothing']         = 'qb-clothing',
        ['esx_skin']            = 'esx_skin',
        ['native']              = true,
    },

    society = {
        ['esx_addonaccount'] = 'esx_addonaccount',
        ['Renewed-Banking']  = 'Renewed-Banking',
        ['okokBanking']      = 'okokBanking',
        ['fd_banking']       = 'fd_banking',
        ['qb-banking']       = 'qb-banking',
        ['qb-management']    = 'qb-management',
        ['qbx_management']   = 'qbx_management',
    },
}

-- Aliases people tend to type in the config
local ALIASES = {
    framework = { qb = 'qbcore', ['qb-core'] = 'qbcore', qbx = 'qbox', qbx_core = 'qbox', es_extended = 'esx', none = 'standalone' },
    notify    = { nayzeee_notify = 'nayzeee', ['nayzeee-notify'] = 'nayzeee', okokNotify = 'okok', mythic_notify = 'mythic',
                  brutal_notify = 'brutal', ['codem-notification'] = 'codem', ['qb-core'] = 'qb', es_extended = 'esx', ox = 'ox_lib' },
    keys      = { vehicles_keys = 'jaksam', mrnewbvehiclekeys = 'MrNewbVehicleKeys', ['renewed-vehiclekeys'] = 'Renewed-Vehiclekeys' },
    target    = { ox = 'ox_target', qb = 'qb-target', fallback = 'builtin', none = 'builtin' },
    inventory = { ox = 'ox_inventory', qb = 'qb-inventory', esx = 'framework', none = 'framework' },
}

local function resolveAlias(kind, name)
    local map = ALIASES[kind]
    if map and map[name] then return map[name] end
    -- also accept the resource name itself (e.g. 'okokNotify')
    local resources = Bridge.Resources[kind]
    if resources and resources[name] == nil then
        for adapter, res in pairs(resources) do
            if res == name then return adapter end
        end
    end
    return name
end

--- Pick the adapter for a kind of integration.
--- @param kind string           key of Bridge.Priority / Bridge.Resources
--- @param override any          the config value ('auto', a name, false)
--- @param opts table|nil        { priority = list, exclude = { name = true }, has = function(name) → bool }
--- @return string|nil
function Bridge.Pick(kind, override, opts)
    opts = opts or {}
    if override == false or override == 'none' or override == 'false' then return nil end

    local resources = Bridge.Resources[kind] or {}
    local has = opts.has

    local function available(name)
        if opts.exclude and opts.exclude[name] then return false end
        if has and not has(name) then return false end
        local res = resources[name]
        if res == nil then return false end
        return Bridge.Started(res)
    end

    if type(override) == 'string' and override ~= 'auto' and override ~= '' then
        local name = resolveAlias(kind, override)
        if available(name) then return name end
        Bridge.Warn(('%s "%s" is set in config/modules/bridge.lua but is not running - detecting automatically'):format(kind, tostring(override)))
    end

    for _, name in ipairs(opts.priority or Bridge.Priority[kind] or {}) do
        if available(name) then return name end
    end
    return nil
end

-- True when a resource that belongs to one of the kinds was started/stopped.
function Bridge.IsKnownResource(kind, resource)
    local resources = Bridge.Resources[kind]
    if not resources then return false end
    for _, res in pairs(resources) do
        if res == resource then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAMEWORK
-- ═══════════════════════════════════════════════════════════════════════════

local function detectFramework()
    local want = Bridge.Cfg('framework', 'auto')
    if want == 'auto' or want == nil then want = (Config and Config.Framework) or 'auto' end
    if type(want) == 'string' and want ~= 'auto' then
        local name = resolveAlias('framework', want)
        if name == 'standalone' then return 'standalone' end
        if Bridge.Resources.framework[name] then
            if Bridge.Started(Bridge.Resources.framework[name]) then return name end
            Bridge.Warn(('framework "%s" is set but %s is not running - detecting automatically'):format(want, Bridge.Resources.framework[name]))
        end
    end
    for _, name in ipairs(Bridge.Priority.framework) do
        if Bridge.Started(Bridge.Resources.framework[name]) then return name end
    end
    return 'standalone'
end

Bridge.Framework = detectFramework()

local coreObject = nil

--- ESX shared object, QBCore core object (QBCore and Qbox compat) or nil.
function Bridge.Core()
    if coreObject then return coreObject end
    local fw = Bridge.Framework
    local ok, obj = false, nil
    if fw == 'esx' then
        ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    elseif fw == 'qbcore' then
        ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    elseif fw == 'qbox' then
        ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    end
    if ok and obj then coreObject = obj end
    return coreObject
end

-- ═══════════════════════════════════════════════════════════════════════════
-- JOBS
-- ═══════════════════════════════════════════════════════════════════════════

local function inList(list, value)
    if type(list) == 'string' then return list == value end
    if type(list) ~= 'table' or value == nil then return false end
    for _, v in pairs(list) do
        if v == value then return true end
    end
    return false
end
Bridge.InList = inList

function Bridge.MedicJobs()
    return (Config and Config.Jobs and Config.Jobs.medic) or { 'ambulance' }
end

function Bridge.PoliceJobs()
    return (Config and Config.Jobs and Config.Jobs.police) or { 'police' }
end

function Bridge.IsMedicJob(name)
    return inList(Bridge.MedicJobs(), name)
end

function Bridge.IsPoliceJob(name)
    return inList(Bridge.PoliceJobs(), name)
end

--- ESX off-duty jobs: 'offambulance' → 'ambulance', false. Any other job → name, nil.
function Bridge.SplitDutyJob(name)
    if type(name) ~= 'string' then return name, nil end
    local prefix = Bridge.Cfg('offDutyPrefix', 'off')
    if type(prefix) == 'string' and prefix ~= '' and #name > #prefix and name:sub(1, #prefix) == prefix then
        local base = name:sub(#prefix + 1)
        if Bridge.IsMedicJob(base) or Bridge.IsPoliceJob(base) then
            return base, false
        end
    end
    return name, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ITEMS
-- ═══════════════════════════════════════════════════════════════════════════

local itemKeyByName = nil

function Bridge.ItemKey(name)
    if not itemKeyByName then
        itemKeyByName = {}
        for key, itemName in pairs((Config and Config.Items) or {}) do
            itemKeyByName[itemName] = key
        end
    end
    return itemKeyByName[name]
end

function Bridge.ItemDef(name)
    local key = Bridge.ItemKey(name)
    local defs = Config and Config.ItemDefs
    return key and defs and defs[key] or nil
end

--- Label from our own item definitions (inventories may have their own).
function Bridge.ItemLabel(name)
    local def = Bridge.ItemDef(name)
    return def and def.label or name
end

-- Does a metadata table contain every key/value of match? (nested tables compared shallowly by value)
function Bridge.MetaMatches(metadata, match)
    if match == nil then return true end
    if type(match) ~= 'table' then return false end
    if type(metadata) ~= 'table' then return next(match) == nil end
    for k, v in pairs(match) do
        local have = metadata[k]
        if type(v) == 'table' then
            if type(have) ~= 'table' then return false end
            for k2, v2 in pairs(v) do
                if have[k2] ~= v2 then return false end
            end
        elseif have ~= v then
            return false
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ICONS  (NAYZEEE icon names → Font Awesome 6 for third-party target menus)
-- ═══════════════════════════════════════════════════════════════════════════

Bridge.Icons = {
    heart = 'fa-solid fa-heart-pulse',   pulse = 'fa-solid fa-wave-square',   medkit = 'fa-solid fa-kit-medical',
    bandage = 'fa-solid fa-bandage',     pill = 'fa-solid fa-pills',          syringe = 'fa-solid fa-syringe',
    bottle = 'fa-solid fa-prescription-bottle', drop = 'fa-solid fa-droplet', hospital = 'fa-solid fa-hospital',
    user = 'fa-solid fa-user',           users = 'fa-solid fa-users',          person = 'fa-solid fa-person',
    hand = 'fa-solid fa-hand',           walk = 'fa-solid fa-person-walking',  sit = 'fa-solid fa-chair',
    brain = 'fa-solid fa-brain',         wind = 'fa-solid fa-lungs',           thermo = 'fa-solid fa-temperature-half',
    flame = 'fa-solid fa-fire',          bolt = 'fa-solid fa-bolt',            shield = 'fa-solid fa-shield-halved',
    ['shield-check'] = 'fa-solid fa-shield-heart', clipboard = 'fa-solid fa-clipboard-list', file = 'fa-solid fa-file-medical',
    note = 'fa-solid fa-note-sticky',    id = 'fa-solid fa-id-card',           badge = 'fa-solid fa-id-badge',
    car = 'fa-solid fa-car',             truck = 'fa-solid fa-truck-medical',  heli = 'fa-solid fa-helicopter',
    key = 'fa-solid fa-key',             fuel = 'fa-solid fa-gas-pump',        garage = 'fa-solid fa-warehouse',
    door = 'fa-solid fa-door-open',      trunk = 'fa-solid fa-car-rear',       siren = 'fa-solid fa-truck-medical',
    bag = 'fa-solid fa-briefcase-medical', backpack = 'fa-solid fa-suitcase-medical', briefcase = 'fa-solid fa-briefcase-medical',
    box = 'fa-solid fa-box',             crate = 'fa-solid fa-boxes-stacked',  store = 'fa-solid fa-store',
    cash = 'fa-solid fa-money-bill',     card = 'fa-solid fa-credit-card',     receipt = 'fa-solid fa-receipt',
    phone = 'fa-solid fa-mobile-screen', call = 'fa-solid fa-phone',          radio = 'fa-solid fa-walkie-talkie',
    clock = 'fa-solid fa-clock',         timer = 'fa-solid fa-stopwatch',      bell = 'fa-solid fa-bell',
    ['bell-ring'] = 'fa-solid fa-bell',  alert = 'fa-solid fa-triangle-exclamation', error = 'fa-solid fa-circle-xmark',
    info = 'fa-solid fa-circle-info',    check = 'fa-solid fa-check',          success = 'fa-solid fa-circle-check',
    x = 'fa-solid fa-xmark',             plus = 'fa-solid fa-plus',            minus = 'fa-solid fa-minus',
    eye = 'fa-solid fa-eye',             search = 'fa-solid fa-magnifying-glass', target = 'fa-solid fa-crosshairs',
    scan = 'fa-solid fa-x-ray',          camera = 'fa-solid fa-camera',        laptop = 'fa-solid fa-laptop-medical',
    terminal = 'fa-solid fa-desktop',    chart = 'fa-solid fa-chart-line',     gauge = 'fa-solid fa-gauge',
    cog = 'fa-solid fa-gear',            wrench = 'fa-solid fa-wrench',        hammer = 'fa-solid fa-hammer',
    scissors = 'fa-solid fa-scissors',   knife = 'fa-solid fa-scissors',        flask = 'fa-solid fa-flask',
    shirt = 'fa-solid fa-shirt',         hanger = 'fa-solid fa-shirt',         mask = 'fa-solid fa-mask-face',
    glove = 'fa-solid fa-mitten',        building = 'fa-solid fa-building',    map = 'fa-solid fa-map-location-dot',
    pin = 'fa-solid fa-location-dot',    nav = 'fa-solid fa-location-arrow',   route = 'fa-solid fa-route',
    mail = 'fa-solid fa-envelope',       message = 'fa-solid fa-comment',      send = 'fa-solid fa-paper-plane',
    lock = 'fa-solid fa-lock',           unlock = 'fa-solid fa-lock-open',     power = 'fa-solid fa-power-off',
    trash = 'fa-solid fa-trash',         edit = 'fa-solid fa-pen',             save = 'fa-solid fa-floppy-disk',
    teleport = 'fa-solid fa-person-walking-arrow-right', home = 'fa-solid fa-house', crown = 'fa-solid fa-crown',
    face = 'fa-solid fa-face-meh',       smile = 'fa-solid fa-face-smile',     star = 'fa-solid fa-star',
    light = 'fa-solid fa-lightbulb',     signal = 'fa-solid fa-signal',        food = 'fa-solid fa-utensils',
    coffee = 'fa-solid fa-mug-hot',      dice = 'fa-solid fa-dice',            history = 'fa-solid fa-clock-rotate-left',
    login = 'fa-solid fa-right-to-bracket', logout = 'fa-solid fa-right-from-bracket', refresh = 'fa-solid fa-rotate',
    seat = 'fa-solid fa-couch',          bed = 'fa-solid fa-bed-pulse',        stretcher = 'fa-solid fa-bed',
    skull = 'fa-solid fa-skull',         bone = 'fa-solid fa-bone',            lungs = 'fa-solid fa-lungs',
    stethoscope = 'fa-solid fa-stethoscope', xray = 'fa-solid fa-x-ray',       blood = 'fa-solid fa-droplet',
    wheelchair = 'fa-solid fa-wheelchair', crutch = 'fa-solid fa-crutch',      body = 'fa-solid fa-person',
}

function Bridge.FaIcon(icon)
    if type(icon) ~= 'string' or icon == '' then return 'fa-solid fa-circle' end
    if icon:find('fa%-') then return icon end
    return Bridge.Icons[icon] or ('fa-solid fa-' .. icon)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- THROTTLE  (per player / per key, used by every net event handler)
-- ═══════════════════════════════════════════════════════════════════════════

local throttles = {}

--- @return boolean true when allowed (and records the call)
function Bridge.Throttle(src, key, ms)
    src = src or 0
    local now = GetGameTimer()
    local bucket = throttles[src]
    if not bucket then
        bucket = {}
        throttles[src] = bucket
    end
    local last = bucket[key]
    if last and now - last < (ms or 1000) then return false end
    bucket[key] = now
    return true
end

function Bridge.ClearThrottle(src)
    throttles[src] = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.ToVec3(v)
    if v == nil then return nil end
    local t = type(v)
    if t == 'vector3' then return v end
    if t == 'vector4' then return vector3(v.x, v.y, v.z) end
    if t == 'table' then
        local x, y, z = tonumber(v.x or v[1]), tonumber(v.y or v[2]), tonumber(v.z or v[3])
        if x and y then return vector3(x + 0.0, y + 0.0, (z or 0.0) + 0.0) end
    end
    return nil
end

-- 'string' → string trimmed and capped; anything else → nil
function Bridge.CleanText(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    if max and #value > max then value = value:sub(1, max) end
    return value
end
