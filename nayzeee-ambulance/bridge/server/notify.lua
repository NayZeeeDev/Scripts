--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: notifications (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore).

      Bridge.Notify(src, { title, message, type = 'success'|'error'|'warning'|'info', duration })
          src = player id, or -1 for everyone

    With Config.Bridge.notify = 'auto' (or 'nza') the message becomes one of our
    own NUI toasts: event 'nza:ui:toast' (shown by client/core). Any other value
    sends 'nza:bridge:notify' to the client, which renders it through that
    notify resource (adapters in bridge/client/notify.lua).

    EVENTS SENT
      nza:ui:toast       (S→C) { title, message, type, duration }
      nza:bridge:notify  (S→C) { title, message, type, duration }
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

local TYPES = { success = true, error = true, warning = true, info = true }

local function useNza()
    local wanted = Bridge.Cfg('notify', 'auto')
    return wanted == nil or wanted == 'auto' or wanted == 'nza' or wanted == true
end

local function clean(data)
    if type(data) == 'string' then data = { message = data } end
    if type(data) ~= 'table' then return nil end
    local message = data.message or data.description or data.text
    if message == nil then return nil end
    return {
        title = data.title and tostring(data.title) or nil,
        message = tostring(message),
        type = TYPES[data.type] and data.type or (data.type == 'inform' and 'info') or (data.type == 'primary' and 'info') or 'info',
        duration = tonumber(data.duration) or 5000,
        icon = data.icon,
    }
end

function Bridge.Notify(src, data)
    src = tonumber(src)
    if not src or (src <= 0 and src ~= -1) then return false end
    data = clean(data)
    if not data then return false end
    if useNza() then
        TriggerClientEvent('nza:ui:toast', src, data)
    else
        TriggerClientEvent('nza:bridge:notify', src, data)
    end
    return true
end
