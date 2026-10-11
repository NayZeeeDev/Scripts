if not NAYZEEE_LOCK_OK then return end

Logs = {}

local function ids(src)
    if not src or src <= 0 then return 'console' end
    local out = { ('**%s** (id %s)'):format(GetPlayerName(src) or '?', src) }
    for _, t in ipairs({ 'license', 'discord', 'fivem' }) do
        local v = GetPlayerIdentifierByType(src, t)
        if v then out[#out + 1] = '`' .. v .. '`' end
    end
    return table.concat(out, '\n')
end

-- fields: { { 'Name', 'value' }, ... }
function Logs.Send(event, src, fields)
    local cfg = ServerConfig.Logs
    if not cfg.enabled then return end
    local ev = cfg.events[event]
    if not ev or not ev.enabled then return end
    local url = GetConvar(cfg.convar, '')
    if url == '' then return end

    local embedFields = { { name = 'Player', value = ids(src), inline = false } }
    for _, f in ipairs(fields or {}) do
        embedFields[#embedFields + 1] = { name = f[1], value = tostring(f[2] or '-'), inline = f[3] ~= false }
    end

    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = cfg.name,
        embeds = { {
            title = ev.title,
            color = ev.color,
            fields = embedFields,
            footer = { text = 'nayzeee-multicharacter ' .. NZ.Version },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end
