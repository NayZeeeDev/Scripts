-- Client notifications. Every adapter is here so you can tweak one for your version.
-- kind is always one of: 'success' | 'error' | 'info' | 'warning'

Notifier = {}

local function started(res) return GetResourceState(res) == 'started' end

local FW = nil
local function fw()
    if FW then return FW end
    if started('qbx_core') then FW = { name = 'qbx' }
    elseif started('es_extended') then FW = { name = 'esx', obj = exports.es_extended:getSharedObject() }
    elseif started('qb-core') then FW = { name = 'qb', obj = exports['qb-core']:GetCoreObject() }
    else FW = { name = 'none' } end
    return FW
end

local ADAPTERS = {}

ADAPTERS.nui = function(title, msg, kind, duration)
    NUI.Send('toast', { title = title, message = msg, kind = kind, duration = duration })
end

ADAPTERS.ox_lib = function(title, msg, kind, duration)
    lib.notify({ title = title, description = msg, type = kind == 'info' and 'inform' or kind,
        duration = duration, position = Prefs and Prefs.Get('toastPos') or Config.UI.ToastPosition })
end

ADAPTERS.esx = function(_, msg, kind, duration)
    local f = fw()
    if f.name ~= 'esx' then return ADAPTERS.nui(L('title'), msg, kind, duration) end
    f.obj.ShowNotification(msg, kind, duration)
end

ADAPTERS.qb = function(_, msg, kind, duration)
    local f = fw()
    if f.name ~= 'qb' then return ADAPTERS.nui(L('title'), msg, kind, duration) end
    local map = { info = 'primary', success = 'success', error = 'error', warning = 'error' }
    f.obj.Functions.Notify(msg, map[kind] or 'primary', duration)
end

ADAPTERS.qbx = function(title, msg, kind, duration)
    exports.qbx_core:Notify(msg, kind == 'info' and 'inform' or kind, duration, title)
end

ADAPTERS.okok = function(title, msg, kind, duration)
    exports['okokNotify']:Alert(title, msg, duration, kind, true)
end

ADAPTERS.mythic = function(_, msg, kind, duration)
    local map = { info = 'inform', success = 'success', error = 'error', warning = 'error' }
    exports['mythic_notify']:SendAlert(map[kind] or 'inform', msg, duration)
end

ADAPTERS.pnotify = function(_, msg, kind, duration)
    local map = { info = 'info', success = 'success', error = 'error', warning = 'warning' }
    exports['pNotify']:SendNotification({ text = msg, type = map[kind] or 'info', timeout = duration, layout = 'centerRight' })
end

ADAPTERS.tnotify = function(title, msg, kind, duration)
    exports['t-notify']:Alert({ style = kind, title = title, message = msg, duration = duration })
end

ADAPTERS.brutal = function(title, msg, kind, duration)
    exports['brutal_notify']:SendAlert(title, msg, duration, kind, true)
end

ADAPTERS.wasabi = function(title, msg, kind, duration)
    exports.wasabi_notify:notify(title, msg, duration, kind)
end

ADAPTERS.lation = function(title, msg, kind, duration)
    exports.lation_ui:notify({ title = title, message = msg, type = kind, duration = duration })
end

ADAPTERS.custom = function(title, msg, kind, duration)
    Config.CustomNotify(title, msg, kind, duration)
end

-- framework = whatever framework is running
ADAPTERS.framework = function(title, msg, kind, duration)
    local f = fw()
    if f.name == 'esx' then return ADAPTERS.esx(title, msg, kind, duration) end
    if f.name == 'qb' then return ADAPTERS.qb(title, msg, kind, duration) end
    if f.name == 'qbx' then return ADAPTERS.qbx(title, msg, kind, duration) end
    return ADAPTERS.nui(title, msg, kind, duration)
end

local AUTO_ORDER = {
    { res = 'okokNotify',    id = 'okok' },
    { res = 'brutal_notify', id = 'brutal' },
    { res = 'wasabi_notify', id = 'wasabi' },
    { res = 'lation_ui',     id = 'lation' },
    { res = 't-notify',      id = 'tnotify' },
    { res = 'pNotify',       id = 'pnotify' },
    { res = 'mythic_notify', id = 'mythic' },
    { res = 'ox_lib',        id = 'ox_lib' },
}

local mode
local function resolve()
    if mode then return mode end
    mode = Config.Notify
    if mode == 'auto' then
        mode = 'nui'
        for _, a in ipairs(AUTO_ORDER) do
            if started(a.res) then mode = a.id break end
        end
    end
    if not ADAPTERS[mode] then mode = 'nui' end
    Debug('notifications:', mode)
    return mode
end

function Notifier.Send(msg, kind, duration)
    kind = (kind == 'success' or kind == 'error' or kind == 'warning') and kind or 'info'
    duration = duration or 4200
    local m = resolve()
    local ok, err = pcall(ADAPTERS[m], L('title'), msg, kind, duration)
    if not ok then
        Debug('notify adapter failed:', m, err)
        ADAPTERS.nui(L('title'), msg, kind, duration)
    end
end
