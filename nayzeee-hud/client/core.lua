-- Shared client state + the diff-only NUI pipe.
-- Every value goes through NHUD.set(); only values that actually changed are sent on the next flush.

NHUD = {
    ready = false,   -- NUI page loaded
    visible = true,  -- /togglehud
    focus = false,   -- settings or control panel open
    hasBelt = false,
    settings = { minimap = Config.Defaults.minimap },
}

local SendNUIMessage = SendNUIMessage
local cache, pending, dirty = {}, {}, false

function NHUD.set(k, v)
    if cache[k] ~= v then
        cache[k] = v
        pending[k] = v
        dirty = true
    end
end

function NHUD.get(k)
    return cache[k]
end

function NHUD.flush()
    if not dirty or not NHUD.ready then return end
    SendNUIMessage({ t = 'u', d = pending })
    pending = {}
    dirty = false
end

-- Push the full state again (NUI just loaded / reloaded)
function NHUD.resend()
    pending = {}
    for k, v in pairs(cache) do pending[k] = v end
    dirty = true
    NHUD.flush()
end

function NHUD.send(t, data)
    data = data or {}
    data.t = t
    SendNUIMessage(data)
end
