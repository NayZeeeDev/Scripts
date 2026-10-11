-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Discord webhook logging for staff. Silent when SquadsConfig.Logs.Enabled is false.
Webhook = {}

local L = SquadsConfig.Logs

local function send(title, description, fields, color)
    if not L.Enabled or L.Webhook == '' then return end
    local embed = {
        title = title,
        description = description,
        color = color or L.Color,
        fields = fields,
        footer = { text = ('nayzeee-squads v%s'):format(SquadsConfig.Version) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    PerformHttpRequest(L.Webhook, function() end, 'POST',
        json.encode({ username = L.Name, embeds = { embed } }), { ['Content-Type'] = 'application/json' })
end

local function who(src)
    if not src then return 'Unknown' end
    return ('%s (%s)'):format(GetPlayerName(src) or 'Unknown', src)
end

function Webhook.Create(sq, src)
    if not L.Events.create then return end
    send('Squad created', ('**%s**%s'):format(sq.name, sq.tag and (' [%s]'):format(sq.tag) or ''),
        { { name = 'Owner', value = who(src), inline = true }, { name = 'ID', value = tostring(sq.id), inline = true } })
end

function Webhook.Disband(sq, src, reason)
    if not L.Events.disband then return end
    send('Squad disbanded', ('**%s**'):format(sq.name),
        { { name = 'By', value = who(src), inline = true }, { name = 'Reason', value = reason or 'manual', inline = true } }, 15158332)
end

function Webhook.Join(sq, src)
    if not L.Events.join then return end
    send('Member joined', ('**%s** joined **%s**'):format(who(src), sq.name))
end

function Webhook.Leave(sq, src)
    if not L.Events.leave then return end
    send('Member left', ('**%s** left **%s**'):format(who(src), sq.name))
end

function Webhook.Kick(sq, src, target)
    if not L.Events.kick then return end
    send('Member removed', ('**%s** was removed from **%s**'):format(who(target), sq.name),
        { { name = 'By', value = who(src), inline = true } }, 15158332)
end

function Webhook.Rank(sq, src, target, rankName)
    if not L.Events.promote then return end
    send('Rank changed', ('**%s** is now **%s** in **%s**'):format(who(target), rankName, sq.name),
        { { name = 'By', value = who(src), inline = true } })
end

function Webhook.Match(a, b, eng, deltaA, deltaB)
    if not L.Events.match then return end
    send('Squad fight scored', ('**%s** %d - %d **%s**'):format(a.name, eng.killsA, eng.killsB, b.name), {
        { name = a.name, value = ('%d ELO (%+d)'):format(a.elo, deltaA), inline = true },
        { name = b.name, value = ('%d ELO (%+d)'):format(b.elo, deltaB), inline = true },
    })
end

function Webhook.Ally(a, b, kind)
    if not L.Events.ally then return end
    send(kind == 'formed' and 'Alliance formed' or 'Alliance ended',
        ('**%s** and **%s**'):format(a.name, b.name), nil, kind == 'formed' and L.Color or 15158332)
end

function Webhook.Admin(src, action, detail)
    if not L.Events.admin then return end
    send('Staff action', detail, { { name = 'Action', value = action, inline = true },
        { name = 'Staff', value = who(src), inline = true } }, 15844367)
end
