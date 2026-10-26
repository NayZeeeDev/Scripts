--[[
    NAYZEEE RADIO - Shared bootstrap

    Creates the NZR namespace and the small pieces every other file relies on:
      NZR.IsServer              true on the server
      NZR.Resource              'nayzeee-radio'
      NZR.Version               '1.0.0'
      NZR.Debug(...)            print when Config.Debug is on (tables are json encoded)
      NZR.Warn(...)             always prints, in yellow
      NZR.AddLocale(lang, map)  register strings (each module owns locales/en/<module>.lua)
      NZR.L(key, ...)           translated string, string.format'd with the extra args
      NZR.LocaleTable(prefix)   every '<prefix>.*' string with the prefix stripped (for the NUI)
      NZR.Bus.On / Off / Emit   in-resource event bus (same API on client and server)
]]

if not NAYZEEE_LOCK_OK then return end

NZR = NZR or {}
NZR.IsServer = IsDuplicityVersion()
NZR.Resource = GetCurrentResourceName()
NZR.Version = '1.0.0'

-- ════════════════════════════════════════════════════════════════════════
-- DEBUG
-- ════════════════════════════════════════════════════════════════════════

function NZR.Debug(...)
    if Config and Config.Debug then
        local parts = {}
        for i = 1, select('#', ...) do
            local v = select(i, ...)
            parts[#parts + 1] = type(v) == 'table' and json.encode(v) or tostring(v)
        end
        print('^5[nayzeee-radio]^7 ' .. table.concat(parts, ' '))
    end
end

function NZR.Warn(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('^3[nayzeee-radio]^7 ' .. table.concat(parts, ' '))
end

-- ════════════════════════════════════════════════════════════════════════
-- LOCALES
-- ════════════════════════════════════════════════════════════════════════

NZR.Locales = NZR.Locales or {}

function NZR.AddLocale(lang, map)
    local t = NZR.Locales[lang] or {}
    for k, v in pairs(map) do t[k] = v end
    NZR.Locales[lang] = t
end

function NZR.L(key, ...)
    local lang = (Config and Config.Locale) or 'en'
    local str = (NZR.Locales[lang] and NZR.Locales[lang][key])
        or (NZR.Locales.en and NZR.Locales.en[key])
        or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        if ok then return out end
    end
    return str
end

-- All strings of one module, for sending to the NUI in one go:
-- NZR.LocaleTable('roster') → { title = 'On this channel', ... } (prefix stripped).
-- English first, the configured language on top, so a half-translated file still works.
function NZR.LocaleTable(prefix)
    local lang = (Config and Config.Locale) or 'en'
    local out = {}
    local p = prefix .. '.'
    for _, src in ipairs({ NZR.Locales.en or {}, NZR.Locales[lang] or {} }) do
        for k, v in pairs(src) do
            if k:sub(1, #p) == p then out[k:sub(#p + 1)] = v end
        end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- EVENT BUS (in-resource only, never crosses the network)
-- ════════════════════════════════════════════════════════════════════════

NZR.Bus = NZR.Bus or { handlers = {} }

function NZR.Bus.On(name, fn)
    local list = NZR.Bus.handlers[name]
    if not list then
        list = {}
        NZR.Bus.handlers[name] = list
    end
    list[#list + 1] = fn
    return fn
end

function NZR.Bus.Off(name, fn)
    local list = NZR.Bus.handlers[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

-- A failing handler is logged and the others still run.
function NZR.Bus.Emit(name, ...)
    local list = NZR.Bus.handlers[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            print(('^1[nayzeee-radio]^7 bus handler for "%s" failed: %s'):format(name, tostring(err)))
        end
    end
end
