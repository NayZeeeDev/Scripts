--[[ Admin / placement / media log: kept in memory for /tvadmin > Logs, optionally sent to Discord ]]

Logs = { list = {} }

local COLORS = { media = 0x08afa2, place = 0x58a6ff, admin = 0xe5a50a, danger = 0xe5484d }

local function webhook(entry)
    local url = ServerConfig.Webhook or ''
    if url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'NAYZEEE Television',
        embeds = { {
            title = entry.title, description = entry.text, color = COLORS[entry.kind] or COLORS.media,
            footer = { text = ('%s · %s'):format(entry.who or 'Server', entry.tv or '-') },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.at),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

--- kind: media | place | admin | danger
function Logs.add(kind, src, title, text, tv)
    local entry = {
        kind = kind, title = title, text = text or '', at = os.time(),
        who = src and src > 0 and ('%s (%d)'):format(Bridge.name(src), src) or 'Server',
        tv = tv and (tv.label .. ' · ' .. tv.id) or nil,
    }
    table.insert(Logs.list, 1, entry)
    while #Logs.list > Config.Logs.Keep do table.remove(Logs.list) end
    if Config.Debug then print(('^5[nayzeee-television]^7 %s — %s %s'):format(entry.who, title, entry.text)) end
    webhook(entry)
end
