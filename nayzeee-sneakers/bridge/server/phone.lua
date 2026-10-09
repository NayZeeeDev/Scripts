--[[
    PHONE MESSAGES   Config.Phone.Messages
    Buyers text the player. Returns true when a phone resource took the message;
    otherwise the player gets an on-screen phone-style text (Config.Phone.Fallback).
]]

local P = Config.Phone

local function phoneSystem()
    local want = P.Messages
    if want ~= 'auto' then return want end
    for _, r in ipairs({ 'lb-phone', 'yseries', 'npwd', 'qs-smartphone', 'gksphone' }) do
        if GetResourceState(r) == 'started' then return r end
    end
    return 'none'
end

local phones = {
    -- lb-phone: SendMessage(from, to, message) needs a phone NUMBER as the sender
    ['lb-phone'] = function(src, text, from)
        local lb = exports['lb-phone']
        local number = lb:GetEquippedPhoneNumber(src)
        if not number then return false end
        lb:SendMessage(tostring(P.Number), number, text)
        if P.Notify then
            lb:SendNotification(src, { app = 'Messages', title = from, content = text })
        end
        return true
    end,
    ['npwd'] = function(src, text)
        local number = exports.npwd:getPhoneNumber(src)
        if not number then return false end
        exports.npwd:emitMessage({ senderNumber = tostring(P.Number), targetNumber = number, message = text })
        return true
    end,
    -- Fill these in from your phone's docs (export name + arguments), then return true.
    ['yseries'] = function(src, text, from) return false end,
    ['qs-smartphone'] = function(src, text, from) return false end,
    ['gksphone'] = function(src, text, from) return false end,
}

--- from = the name shown on the text
function Bridge.PhoneMessage(src, text, from)
    if not src or not text then return false end
    from = from or 'Unknown'
    local sys = phoneSystem()
    local fn = phones[sys]
    if fn and GetResourceState(sys) ~= 'started' then fn = nil end
    local ok, handled = false, false
    if fn then
        ok, handled = pcall(fn, src, text, from)
        if not ok then print(('^1[nayzeee-sneakers] %s text failed: %s^7'):format(sys, tostring(handled))) end
    end
    if not (ok and handled) and P.Fallback then
        TriggerClientEvent('nayzeee-sneakers:sms', src, { from = from, text = text })
    end
    return ok and handled
end
