-- Discord logs. Each log becomes one clean embed:
--   author   who did it (with their Discord picture when Config.Discord is set up)
--   title    what happened, description = the one-line summary
--   fields   player / staff / target cards, item, amount, from → to, where, script, item details
--   footer   server name + time
-- Embeds for the same channel are queued and sent together (up to 10 per message) so busy servers
-- stay under Discord's rate limit, and a 429 is retried after the wait Discord asks for.

local W = Config.Webhooks or {}
local L = Config.DiscordLogs or {}

-- ─── which channel ──────────────────────────────────────────────────────────
local GROUP = {
    give = 'players', take = 'players', drop = 'players', pickup = 'players',
    stash_put = 'storage', stash_take = 'storage', backpack_put = 'storage', backpack_take = 'storage',
    container_put = 'storage', container_take = 'storage', evidence_put = 'storage', evidence_take = 'storage',
    trunk_put = 'vehicles', trunk_take = 'vehicles', glovebox_put = 'vehicles', glovebox_take = 'vehicles',
    shop = 'shops', craft = 'shops',
    created = 'created',
    money = 'money',
    suspicious = 'security', dupe = 'security',
    admin_give = 'staff', admin_remove = 'staff', global = 'staff', rollback = 'staff', editor = 'staff',
}
WebhookGroups = GROUP

local function set(v) return type(v) == 'string' and v ~= '' and v or nil end

--- URL for a log type: its own URL, then (for weapons) the weapons channel, then its group, then everything.
--- Old flat configs (Config.Webhooks.drop = '...', default = '...') keep working.
local function resolve(kind, weapon)
    local types, groups = W.types or {}, W.groups or {}
    return set(types[kind]) or set(W[kind])
        or (weapon and (set(groups.weapons) or set(W.weapon)))
        or set(groups[GROUP[kind] or '']) or set(W[GROUP[kind] or ''])
        or set(W.everything) or set(W.default)
end

-- ─── formatting helpers ─────────────────────────────────────────────────────
local function clip(s, n) s = tostring(s or '') return #s > n and (s:sub(1, n - 1) .. '…') or s end
local function money(n) return ('$%s'):format(NZ.Comma(math.abs(tonumber(n) or 0))) end
local function serverName()
    return (GetConvar('sv_projectName', GetConvar('sv_hostname', 'FiveM server')):gsub('%^%d', ''))
end

--- A player/staff card: handle + server id, character + job, Discord mention, ids
local function person(p)
    if type(p) ~= 'table' then return nil end
    local lines = {}
    local head = ('**%s**'):format(p.name or 'Unknown')
    if p.id and p.id ~= 0 then head = head .. (' · ID %s'):format(p.id) end
    lines[1] = head
    if p.id and p.id ~= 0 and GetPlayerName(p.id) then
        local ok, info = pcall(NZ.CharInfo, p.id)
        if ok and info then
            local who = {}
            if info.char and NZ.Trim(info.char) ~= '' then who[#who + 1] = NZ.Trim(info.char) end
            if info.job then who[#who + 1] = info.grade and ('%s (%s)'):format(info.job, info.grade) or info.job end
            if #who > 0 then lines[#lines + 1] = table.concat(who, ' · ') end
        end
    end
    if L.showIdentifiers ~= false then
        if p.discord then lines[#lines + 1] = ('<@%s>'):format((tostring(p.discord):gsub('discord:', ''))) end
        if p.identifier and p.identifier ~= 'console' then lines[#lines + 1] = ('`%s`'):format(p.identifier) end
        if p.license and p.license ~= p.identifier then lines[#lines + 1] = ('`%s`'):format(p.license) end
    end
    return table.concat(lines, '\n')
end

--- Inventory ids in plain words: 3 → Player 3 (name), trunkABC → Trunk ABC, ground → Ground
local function place(inv)
    if inv == nil or inv == '' then return nil end
    inv = tostring(inv)
    local id = tonumber(inv)
    if id then
        local n = GetPlayerName(id)
        return n and ('Player %d (%s)'):format(id, n) or ('Player %d'):format(id)
    end
    if inv == 'ground' then return 'Ground' end
    local plate = inv:match('^trunk%-?(.+)$')
    if plate then return ('Trunk `%s`'):format(plate) end
    plate = inv:match('^glove%-?(.+)$') or inv:match('^glovebox%-?(.+)$')
    if plate then return ('Glovebox `%s`'):format(plate) end
    local bench = inv:match('^bench:(.+)$')
    if bench then return ('Crafting bench `%s`'):format(bench) end
    if inv:match('^drop%-') or inv:match('^drop_') then return ('Drop `%s`'):format(inv) end
    if inv:find('[%s#]') then return inv end         -- already readable, e.g. "General #3"
    return ('Stash `%s`'):format(inv)
end

-- item details worth reading at a glance, in this order
local META_KEYS = {
    { 'serial', 'Serial' }, { 'serie', 'Serial' }, { 'registered', 'Registered to' }, { 'durability', 'Durability', '%' },
    { 'quality', 'Quality', '%' }, { 'ammo', 'Ammo' }, { 'label', 'Custom label' }, { 'description', 'Note' },
}
local function metaText(m)
    if type(m) ~= 'table' or next(m) == nil or L.showMetadata == false then return nil end
    local lines, used = {}, {}
    for _, k in ipairs(META_KEYS) do
        local v = m[k[1]]
        if v ~= nil and v ~= '' and type(v) ~= 'table' then
            if type(v) == 'number' and k[3] then v = ('%s%s'):format(math.floor(v + 0.5), k[3]) end
            lines[#lines + 1] = ('%s: `%s`'):format(k[2], clip(v, 80))
            used[k[1]] = true
        end
    end
    local rest = {}
    for k, v in pairs(m) do
        if not used[k] and k ~= 'components' and k ~= 'image' and k ~= 'weight' then rest[k] = v end
    end
    if type(m.components) == 'table' and #m.components > 0 then lines[#lines + 1] = ('Attachments: %s'):format(clip(table.concat(m.components, ', '), 200)) end
    if next(rest) then
        local ok, enc = pcall(json.encode, rest)
        if ok and enc and enc ~= '{}' and enc ~= '[]' then lines[#lines + 1] = '```json\n' .. clip(enc, 500) .. '\n```' end
    end
    return #lines > 0 and table.concat(lines, '\n') or nil
end

local function itemText(item, isMoney)
    if type(item) ~= 'table' then return nil end
    if isMoney then return nil end
    local label = item.label or item.name or '?'
    local s = ('**%s**'):format(label)
    if item.name and item.name ~= label then s = s .. (' `%s`'):format(item.name) end
    return s .. (' × **%s**'):format(NZ.Comma(item.count or 1))
end

local function thumb(item)
    if not item or not item.name then return nil end
    local base = set(L.itemImages)
    if not base then
        local p = Inv and Inv.ImagePath and Inv.ImagePath() or ''
        if not p:match('^https://') then return nil end
        base = p:gsub('/$', '') .. '/%s.png'
    end
    local info = Inv and Inv.Item and Inv.Item(item.name)
    local file = info and type(info.image) == 'string' and info.image:gsub('%.png$', '') or item.name
    return { url = base:find('%%s') and base:format(file) or (base .. file .. '.png') }
end

local function avatarOf(p)
    if type(p) ~= 'table' or not p.discord or not GetDiscordAvatar then return nil end
    return GetDiscordAvatar((tostring(p.discord):gsub('discord:', '')))
end

local function color(kind, p)
    local C = L.colors or Config.WebhookColors or {}
    if kind == 'money' and p.money then return (p.money.amount or 0) >= 0 and (C.money_in or 0x46A758) or (C.money_out or 0xE5484D) end
    if p.weapon and C.weapon and not C[kind] then return C.weapon end
    return C[kind] or C[GROUP[kind] or ''] or 0x08AFA2
end

-- ─── sending (queued, batched, rate-limit aware) ────────────────────────────
local queues, busy = {}, {}

local function flush(url)
    local q = queues[url]
    if busy[url] or not q or #q == 0 then return end
    busy[url] = true
    local batch, size, mention = {}, 0, {}
    while #q > 0 and #batch < 10 do
        local e = q[1]
        local len = #json.encode(e.embed)
        if #batch > 0 and size + len > 5800 then break end
        table.remove(q, 1)
        batch[#batch + 1] = e.embed
        size = size + len
        if e.mention then mention[e.mention] = true end
    end
    local pings = {}
    for m in pairs(mention) do pings[#pings + 1] = m end
    local body = json.encode({
        username = set(L.name) or Config.WebhookName or 'Inventory Manager',
        avatar_url = set(L.avatar) or set(Config.WebhookAvatar),
        content = #pings > 0 and table.concat(pings, ' ') or nil,
        embeds = batch,
        allowed_mentions = { parse = { 'roles', 'users', 'everyone' } },
    })
    PerformHttpRequest(url, function(code, _, headers)
        busy[url] = false
        if code == 429 then
            -- put them back in front and wait as long as Discord asks
            for i = #batch, 1, -1 do table.insert(q, 1, { embed = batch[i], mention = i == 1 and pings[1] or nil }) end
            local wait = 2000
            local h = type(headers) == 'table' and (headers['retry-after'] or headers['Retry-After'])
            if tonumber(h) then wait = math.floor(tonumber(h) * 1000) + 250 end
            SetTimeout(wait, function() flush(url) end)
            return
        end
        if code and code >= 400 and code ~= 429 then
            NZ.Debug(('Discord webhook returned %s (check the URL in Config.Webhooks)'):format(code))
        end
        if #q > 0 then SetTimeout(1000, function() flush(url) end) end
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

local function enqueue(url, embed, mention)
    queues[url] = queues[url] or {}
    local q = queues[url]
    q[#q + 1] = { embed = embed, mention = mention }
    if #q > 300 then table.remove(q, 1) end -- never let a dead webhook eat memory
    if #q == 1 then SetTimeout(math.floor((tonumber(L.batchSeconds) or 2) * 1000), function() flush(url) end) end
end

--- SendWebhook(kind, title, {
---   player, target, admin      actor tables from NZ.Actor (or { name, identifier, id })
---   item = { name, label, count }, metadata,
---   money = { amount, account, reason },
---   from, to, coords, resource, details, weapon = bool,
---   extra = { { name, value, inline }, ... }   any additional fields
--- })
function SendWebhook(kind, title, p)
    p = p or {}
    local url = resolve(kind, p.weapon)
    if not url then return end
    local isMoney = p.money ~= nil
    local fields = {}
    local function add(name, value, inline)
        if value == nil or value == '' then return end
        fields[#fields + 1] = { name = name, value = clip(value, 1024), inline = inline == true }
    end

    local actor = p.admin or p.player
    add(p.admin and 'Staff' or 'Player', person(actor), true)
    if p.admin and p.player then add('Player', person(p.player), true) end
    add('Target', person(p.target), true)

    if isMoney then
        local m = p.money
        add('Amount', ('%s **%s**'):format((m.amount or 0) >= 0 and '+' or '−', money(m.amount)), true)
        add('Account', m.account, true)
        add('Reason', m.reason, true)
    else
        add('Item', itemText(p.item), true)
    end
    local from, to = place(p.from), place(p.to)
    if from and to then add('Moved', ('%s → %s'):format(from, to), false)
    else add('From', from, true) add('To', to, true) end
    add('Script', p.resource and ('`%s`'):format(p.resource) or nil, true)
    if L.showCoords ~= false and p.coords then add('Location', ('`%s`'):format(p.coords), true) end
    add('Item details', metaText(p.metadata), false)
    for _, f in ipairs(p.extra or {}) do add(f[1] or f.name, f[2] or f.value, f[3] or f.inline) end

    local embed = {
        title = clip(title, 250),
        description = p.details and clip(p.details, 2000) or nil,
        color = color(kind, p),
        fields = fields,
        thumbnail = not isMoney and thumb(p.item) or nil,
        footer = { text = clip(table.concat({ set(L.footer) or set(Config.WebhookFooter) or 'Inventory Manager', L.showServerName ~= false and serverName() or nil }, ' · '), 200) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    if actor and actor.name then
        embed.author = { name = clip(actor.id and actor.id ~= 0 and ('%s (ID %s)'):format(actor.name, actor.id) or actor.name, 250), icon_url = avatarOf(actor) }
    end
    local ping = L.mentions and (set(L.mentions[kind]) or set(L.mentions[GROUP[kind] or '']))
    enqueue(url, embed, ping)
end

-- send whatever is still queued when the resource stops
AddEventHandler('onResourceStop', function(r)
    if r ~= NZ.Resource then return end
    for url in pairs(queues) do busy[url] = false flush(url) end
end)
