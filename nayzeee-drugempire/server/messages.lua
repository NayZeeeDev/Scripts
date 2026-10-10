--[[ Message threads shown in the Empire app (and as phone notifications) ]]

Messages = {}

local MAX = 40

--- thread display info
function Messages.who(P, thread)
    if thread == 'benson' then
        local met = P.story.met
        return met and Config.Story.benson.name or Config.Story.unknownNumber, met and 'wheel' or 'unknown'
    end
    local c = Config.Customers[thread]
    if c then return c.name, 'user' end
    local d = Config.DealerList[thread]
    if d then return d.name .. ' (dealer)', 'crew' end
    return thread, 'user'
end

---@param msg { f: 'them'|'me', m: string, deal?: string, actions?: table }
function Messages.push(src, thread, msg, notify)
    local P = Profile.get(src)
    if not P then return end
    local list = P.threads[thread]
    if not list then list = {} P.threads[thread] = list end
    msg.t = os.time()
    list[#list + 1] = msg
    while #list > MAX do table.remove(list, 1) end
    if msg.f == 'them' then P.unread[thread] = (P.unread[thread] or 0) + 1 end
    Profile.dirty(src)
    if notify ~= false and msg.f == 'them' then
        local name = Messages.who(P, thread)
        TriggerClientEvent('nzde:text', src, { thread = thread, from = name, text = msg.m, app = P.story.app == true })
    end
    TriggerClientEvent('nzde:phone:refresh', src, 'messages')
end

function Messages.read(src, thread)
    local P = Profile.get(src)
    if not P or not P.unread[thread] then return end
    P.unread[thread] = nil
    Profile.dirty(src)
end

function Messages.view(P)
    local out = {}
    for thread, list in pairs(P.threads) do
        local name, icon = Messages.who(P, thread)
        local last = list[#list]
        out[#out + 1] = { id = thread, name = name, icon = icon, unread = P.unread[thread] or 0, last = last and last.m or '', t = last and last.t or 0, msgs = list }
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

function Messages.levelUp(src, level)
    local rank = Utils.rankLabel(level)
    local unlocks = {}
    for _, s in pairs(Config.Stations) do
        if s.unlock == level then unlocks[#unlocks + 1] = s.label end
    end
    for _, d in pairs(Config.Drugs) do
        if d.unlock == level then unlocks[#unlocks + 1] = d.label end
    end
    for _, r in ipairs(Config.Regions) do
        if r.unlock == level then unlocks[#unlocks + 1] = r.label end
    end
    local text = ('You hit %s.'):format(rank)
    if #unlocks > 0 then text = text .. ' Unlocked: ' .. table.concat(unlocks, ', ') .. '.' end
    TriggerClientEvent('nzde:levelup', src, { level = level, rank = rank, unlocks = unlocks })
    Messages.push(src, 'benson', { f = 'them', m = text }, false)
end
