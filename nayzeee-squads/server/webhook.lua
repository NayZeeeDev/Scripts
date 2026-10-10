-- Discord webhook logging for staff. Silent when Config.Logs.Enabled is false.
Webhook = {}

local L = Config.Logs
local RED, AMBER = 15158332, 15844367

local function send(title, description, fields, color)
    if not L.Enabled or L.Webhook == '' then return end
    local embed = {
        title = title,
        description = description,
        color = color or L.Color,
        fields = fields,
        footer = { text = ('nayzeee-squads v%s'):format(Config.Version) },
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
        { { name = 'Owner', value = who(src), inline = true }, { name = 'ID', value = tostring(sq.id), inline = true },
          { name = 'Type', value = sq.temporary and 'Temporary' or 'Permanent', inline = true } })
end

function Webhook.Disband(sq, src, reason)
    if not L.Events.disband then return end
    send('Squad disbanded', ('**%s**'):format(sq.name),
        { { name = 'By', value = who(src), inline = true }, { name = 'Reason', value = reason or 'manual', inline = true } }, RED)
end

function Webhook.Join(sq, src)
    if not L.Events.join then return end
    send('Member joined', ('**%s** joined **%s**'):format(who(src), sq.name))
end

function Webhook.Leave(sq, src)
    if not L.Events.leave then return end
    send('Member left', ('**%s** left **%s**'):format(who(src), sq.name))
end

function Webhook.Kick(sq, src, name)
    if not L.Events.kick then return end
    send('Member removed', ('**%s** was removed from **%s**'):format(name, sq.name),
        { { name = 'By', value = who(src), inline = true } }, RED)
end

function Webhook.Rank(sq, src, name, rankName)
    if not L.Events.promote then return end
    send('Rank changed', ('**%s** is now **%s** in **%s**'):format(name, rankName, sq.name),
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
        ('**%s** and **%s**'):format(a.name, b.name), nil, kind == 'formed' and L.Color or RED)
end

function Webhook.Request(sq, src, accepted)
    if not L.Events.request then return end
    send(accepted and 'Join request accepted' or 'Join request',
        ('**%s** %s **%s**'):format(who(src), accepted and 'was accepted into' or 'asked to join', sq.name))
end

function Webhook.Admin(src, action, detail)
    if not L.Events.admin then return end
    send('Staff action', detail, { { name = 'Action', value = action, inline = true },
        { name = 'Staff', value = who(src), inline = true } }, AMBER)
end
