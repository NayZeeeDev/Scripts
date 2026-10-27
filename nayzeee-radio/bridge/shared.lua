--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE RADIO - Bridge (shared core)
    ═══════════════════════════════════════════════════════════════════════════

    This file is OPEN (escrow_ignore). It holds what both sides of the bridge
    share:

      Bridge.Framework            'esx' | 'qbcore' | 'qbox' | 'standalone'
      Bridge.Started(resource)    true while a resource is started/starting
      Bridge.Pick(kind, ...)      adapter detection (override → priority list)
      Bridge.IsKnownResource(kind, resource)
      Bridge.Core()               ESX / QBCore shared object (cached; nil on standalone)
      Bridge.Cfg(key, default)    read Config.Bridge safely
      Bridge.Try(label, fn, ...)  run an adapter function, log instead of throwing
      Bridge.InList(list, value)
      Bridge.SplitDutyJob(name)   ESX 'offpolice' → 'police', false
      Bridge.JobMatches(job, rule, requireDuty)   rule = { police = 0, sheriff = 2 } (job → min grade)
      Bridge.ItemKey(name) / Bridge.ItemDef(name) / Bridge.ItemLabel(name)
      Bridge.MetaMatches(metadata, match)
      Bridge.FaIcon(icon)         NAYZEEE icon name → Font Awesome class (third-party target menus)
      Bridge.Throttle(src, key, ms) / Bridge.ClearThrottle(src)
      Bridge.ToVec3(v)            vector3 / vector4 / { x, y, z } / { 1, 2, 3 } → vector3 | nil
      Bridge.CleanText(value, max)
      Bridge.Debug(...) / Bridge.Warn(...)

    AUTO-DETECT ORDER
    Every kind of integration has a priority list and a resource map below.
    Reorder a list to prefer one script over another, or add your own entry
    (and an adapter with the same name in bridge/client or bridge/server).
    A resource value of true means "always available" (built in).

    ox_core is not supported by the radio: a server running it is treated as
    standalone (license identifier, ace jobs - see config/modules/bridge.lua).
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge = Bridge or {}
Bridge.IsServer = IsDuplicityVersion()
Bridge.Version = '1.0.0'

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG ACCESS
-- ════════════════════════════════════════════════════════════════════════

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
    print('^5[nayzeee-radio:bridge]^7 ' .. table.concat(parts, ' '))
end

function Bridge.Warn(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('^3[nayzeee-radio:bridge]^7 ' .. table.concat(parts, ' '))
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

-- ════════════════════════════════════════════════════════════════════════
-- RESOURCE STATE
-- ════════════════════════════════════════════════════════════════════════

function Bridge.Started(resource)
    if resource == true then return true end
    if type(resource) ~= 'string' or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

-- ════════════════════════════════════════════════════════════════════════
-- AUTO-DETECT ORDER  (edit freely)
-- ════════════════════════════════════════════════════════════════════════

Bridge.Priority = {
    -- qbx_core provides 'qb-core', so Qbox is checked before QBCore
    framework = { 'qbox', 'esx', 'qbcore' },

    inventory = {
        'ox_inventory', 'qs-inventory', 'codem-inventory', 'origen_inventory', 'tgiann-inventory',
        'core_inventory', 'ps-inventory', 'lj-inventory', 'qb-inventory', 'framework',
    },

    -- sleepless_interact provides 'ox_target' and 'qtarget', so it goes first
    target = { 'sleepless_interact', 'ox_target', 'qb-target', 'qtarget', 'interact', 'builtin' },

    -- 'nzr' is our own NUI toast and is always available
    notify = { 'nzr', 'nayzeee', 'ox_lib', 'okok', 'codem', 'mythic', 'brutal', 't-notify', 'qb', 'esx', 'native' },
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
        ['nzr']      = true,
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
}

-- Aliases people tend to type in the config
local ALIASES = {
    framework = { qb = 'qbcore', ['qb-core'] = 'qbcore', qbx = 'qbox', qbx_core = 'qbox', es_extended = 'esx',
                  none = 'standalone' },
    notify    = { nayzeee_notify = 'nayzeee', ['nayzeee-notify'] = 'nayzeee', okokNotify = 'okok', mythic_notify = 'mythic',
                  brutal_notify = 'brutal', ['codem-notification'] = 'codem', ['qb-core'] = 'qb', es_extended = 'esx', ox = 'ox_lib' },
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

-- ════════════════════════════════════════════════════════════════════════
-- FRAMEWORK
-- ════════════════════════════════════════════════════════════════════════

local function detectFramework()
    local want = Bridge.Cfg('framework', 'auto')
    if want == 'auto' or want == nil then want = (Config and Config.Framework) or 'auto' end
    if type(want) == 'string' and want ~= 'auto' then
        local name = resolveAlias('framework', want)
        if name == 'standalone' then return 'standalone' end
        if Bridge.Resources.framework[name] then
            if Bridge.Started(Bridge.Resources.framework[name]) then return name end
            Bridge.Warn(('framework "%s" is set but %s is not running - detecting automatically'):format(want, Bridge.Resources.framework[name]))
        else
            Bridge.Warn(('framework "%s" is not supported - detecting automatically'):format(tostring(want)))
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
    elseif fw == 'qbcore' or fw == 'qbox' then
        ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    end
    if ok and obj then coreObject = obj end
    return coreObject
end

-- ════════════════════════════════════════════════════════════════════════
-- JOBS
-- ════════════════════════════════════════════════════════════════════════

local function inList(list, value)
    if type(list) == 'string' then return list == value end
    if type(list) ~= 'table' or value == nil then return false end
    for _, v in pairs(list) do
        if v == value then return true end
    end
    return false
end
Bridge.InList = inList

--- ESX off-duty jobs: 'offpolice' → 'police', false. Any other job → name, nil.
--- Only jobs in Config.Bridge.offDutyJobs are split ('office' must stay 'office').
function Bridge.SplitDutyJob(name)
    if type(name) ~= 'string' then return name, nil end
    local prefix = Bridge.Cfg('offDutyPrefix', 'off')
    if type(prefix) == 'string' and prefix ~= '' and #name > #prefix and name:sub(1, #prefix) == prefix then
        local base = name:sub(#prefix + 1)
        local jobs = Bridge.Cfg('offDutyJobs', { 'police', 'sheriff', 'ambulance' })
        if jobs == true or inList(jobs, base) then
            return base, false
        end
    end
    return name, nil
end

--- Does a bridge job pass a job rule?
---   job   { name, grade, onDuty } (Bridge.GetJob)
---   rule  { police = 0, sheriff = 2 }: job name → minimum grade. A list { 'police' } means grade 0.
---         false / nil = nobody passes (callers treat "no rule" themselves).
---   requireDuty  the job must also be on duty
function Bridge.JobMatches(job, rule, requireDuty)
    if type(job) ~= 'table' or type(job.name) ~= 'string' or type(rule) ~= 'table' then return false end
    local minGrade = rule[job.name]
    if minGrade == nil and inList(rule, job.name) then minGrade = 0 end
    if minGrade == nil or minGrade == false then return false end
    minGrade = tonumber(minGrade) or 0
    if (tonumber(job.grade) or 0) < minGrade then return false end
    if requireDuty and job.onDuty ~= true then return false end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- ITEMS
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- ICONS  (NAYZEEE icon names → Font Awesome 6 for third-party target menus)
-- ════════════════════════════════════════════════════════════════════════

Bridge.Icons = {
    radio = 'fa-solid fa-walkie-talkie',   walkie = 'fa-solid fa-walkie-talkie',  headunit = 'fa-solid fa-radio',
    signal = 'fa-solid fa-signal',          antenna = 'fa-solid fa-tower-cell',    broadcast = 'fa-solid fa-tower-broadcast',
    jammer = 'fa-solid fa-tower-broadcast', frequency = 'fa-solid fa-wave-square', dial = 'fa-solid fa-sliders',
    headset = 'fa-solid fa-headset',        speaker = 'fa-solid fa-volume-high',   volume = 'fa-solid fa-volume-high',
    mute = 'fa-solid fa-volume-xmark',      mic = 'fa-solid fa-microphone',        ['mic-off'] = 'fa-solid fa-microphone-slash',
    chip = 'fa-solid fa-microchip',         hack = 'fa-solid fa-microchip',        terminal = 'fa-solid fa-terminal',
    hand = 'fa-solid fa-hand',              pickup = 'fa-solid fa-hand-holding',   box = 'fa-solid fa-box',
    lock = 'fa-solid fa-lock',              unlock = 'fa-solid fa-lock-open',      key = 'fa-solid fa-key',
    power = 'fa-solid fa-power-off',        bolt = 'fa-solid fa-bolt',             battery = 'fa-solid fa-battery-three-quarters',
    car = 'fa-solid fa-car',                siren = 'fa-solid fa-bell',            alert = 'fa-solid fa-triangle-exclamation',
    user = 'fa-solid fa-user',              users = 'fa-solid fa-users',           badge = 'fa-solid fa-id-badge',
    shield = 'fa-solid fa-shield-halved',   eye = 'fa-solid fa-eye',               search = 'fa-solid fa-magnifying-glass',
    target = 'fa-solid fa-crosshairs',      wrench = 'fa-solid fa-wrench',         cog = 'fa-solid fa-gear',
    trash = 'fa-solid fa-trash',            check = 'fa-solid fa-check',           x = 'fa-solid fa-xmark',
    info = 'fa-solid fa-circle-info',       timer = 'fa-solid fa-stopwatch',       history = 'fa-solid fa-clock-rotate-left',
}

function Bridge.FaIcon(icon)
    if type(icon) ~= 'string' or icon == '' then return 'fa-solid fa-circle' end
    if icon:find('fa%-') then return icon end
    return Bridge.Icons[icon] or ('fa-solid fa-' .. icon)
end

-- ════════════════════════════════════════════════════════════════════════
-- THROTTLE  (per player / per key, a minimum gap between two calls)
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

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
