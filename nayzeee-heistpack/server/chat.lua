--[[ Underground chat. Only players with the tablet open receive live messages (no global broadcasts). ]]

Chat = { subscribers = {} }

local history = {}
local MAX_HISTORY = 40
local MAX_LENGTH = 180

function Chat.subscribe(src, state)
    Chat.subscribers[src] = state and true or nil
end

Guard.callback('nzh:chat:history', function(src)
    Chat.subscribe(src, true)
    return history
end)

Guard.callback('nzh:chat:send', function(src, text)
    if type(text) ~= 'string' then return false end
    if not Guard.rate(src, 'chat', 1200) then return false, locale('slow_down') end
    text = text:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #text == 0 then return false end
    if #text > MAX_LENGTH then text = text:sub(1, MAX_LENGTH) end
    local p = Profile.public(src)
    if not p then return false end
    local msg = { source = src, nickname = p.nickname, avatar = p.avatar, level = p.level, text = text, time = os.time() }
    history[#history + 1] = msg
    if #history > MAX_HISTORY then table.remove(history, 1) end
    for target in pairs(Chat.subscribers) do
        TriggerClientEvent('nzh:chat:message', target, msg)
    end
    return true
end)

RegisterNetEvent('nzh:menu:closed', function()
    Chat.subscribe(source, false)
end)

AddEventHandler('playerDropped', function()
    Chat.subscribers[source] = nil
end)
