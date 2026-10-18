--[[
    NAYZEEE AMBULANCE - Shared bootstrap

    Creates the NZA namespace and the small pieces every other file relies on:
      NZA.Debug(...)            print when Config.Debug is on
      NZA.AddLocale(lang, map)  register strings (each module owns locales/en/<module>.lua)
      NZA.L(key, ...)           translated string, string.format'd with the extra args
      NZA.Bus.On / Emit         in-resource event bus (same API on client and server)
      NZA.IsServer              true on the server
]]

if not NAYZEEE_LOCK_OK then return end

NZA = NZA or {}
NZA.IsServer = IsDuplicityVersion()
NZA.Resource = GetCurrentResourceName()
NZA.Version = '1.0.0'

-- ════════════════════════════════════════════════════════════════════════
-- DEBUG
-- ════════════════════════════════════════════════════════════════════════

function NZA.Debug(...)
    if Config and Config.Debug then
        local parts = {}
        for i = 1, select('#', ...) do
            local v = select(i, ...)
            parts[#parts + 1] = type(v) == 'table' and json.encode(v) or tostring(v)
        end
        print('^5[nayzeee-ambulance]^7 ' .. table.concat(parts, ' '))
    end
end

function NZA.Warn(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('^3[nayzeee-ambulance]^7 ' .. table.concat(parts, ' '))
end

-- ════════════════════════════════════════════════════════════════════════
-- LOCALES
-- ════════════════════════════════════════════════════════════════════════

NZA.Locales = NZA.Locales or {}

function NZA.AddLocale(lang, map)
    local t = NZA.Locales[lang] or {}
    for k, v in pairs(map) do t[k] = v end
    NZA.Locales[lang] = t
end

function NZA.L(key, ...)
    local lang = (Config and Config.Locale) or 'en'
    local str = (NZA.Locales[lang] and NZA.Locales[lang][key])
        or (NZA.Locales.en and NZA.Locales.en[key])
        or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        if ok then return out end
    end
    return str
end

-- All strings of one module, for sending to the NUI in one go:
-- NZA.LocaleTable('exam') → { title = 'Head-to-toe check', ... } (prefix stripped)
function NZA.LocaleTable(prefix)
    local lang = (Config and Config.Locale) or 'en'
    local out = {}
    local p = prefix .. '.'
    for _, src in ipairs({ NZA.Locales.en or {}, NZA.Locales[lang] or {} }) do
        for k, v in pairs(src) do
            if k:sub(1, #p) == p then out[k:sub(#p + 1)] = v end
        end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- EVENT BUS (in-resource only, never crosses the network)
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus = NZA.Bus or { handlers = {} }

function NZA.Bus.On(name, fn)
    local list = NZA.Bus.handlers[name]
    if not list then
        list = {}
        NZA.Bus.handlers[name] = list
    end
    list[#list + 1] = fn
    return fn
end

function NZA.Bus.Off(name, fn)
    local list = NZA.Bus.handlers[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

function NZA.Bus.Emit(name, ...)
    local list = NZA.Bus.handlers[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            print(('^1[nayzeee-ambulance]^7 bus handler for "%s" failed: %s'):format(name, tostring(err)))
        end
    end
end
