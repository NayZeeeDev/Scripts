-----------------------------------------------------------------
-- Logging
--
-- Console always, Discord webhook when one is configured.
-- Identifiers are included so a name change doesn't lose the trail.
-----------------------------------------------------------------

Logs = {}

local cfg = Config.Logs or { enabled = false, events = {} }
local ox = exports.ox_inventory

local function enabled(event)
    if not cfg.enabled then return false end
    if event and cfg.events and cfg.events[event] == false then return false end
    return true
end

--- Readable identity for a player, with their licence for auditing.
function Logs.who(src)
    if not src or src == 0 then return 'server', '-' end

    local name = GetPlayerName(src) or ('unknown (%s)'):format(src)
    local license = '-'

    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:find('^license:') then
            license = id
            break
        end
    end

    return ('%s [%s]'):format(name, src), license
end

--- Snapshot what's inside a bag, for rob and drop events.
function Logs.contents(metadata)
    if not cfg.events or not cfg.events.contents then return nil end

    local bagid = metadata and metadata.bagid
    if not bagid then return nil end

    local inv = ox:GetInventory(('backpack_%s'):format(bagid))
    if not inv or not inv.items then return 'empty' end

    local lines, count = {}, 0
    for _, item in pairs(inv.items) do
        if item and item.name then
            count = count + 1
            if count <= (cfg.maxContentLines or 12) then
                lines[#lines + 1] = ('%sx %s'):format(item.count or 1, item.name)
            end
        end
    end

    if count == 0 then return 'empty' end
    if count > (cfg.maxContentLines or 12) then
        lines[#lines + 1] = ('...and %d more'):format(count - (cfg.maxContentLines or 12))
    end

    return table.concat(lines, ', ')
end

local function send(event, title, fields, color)
    if not enabled(event) then return end

    -- console first, so there's a trail even with no webhook
    local flat = {}
    for _, f in ipairs(fields) do
        flat[#flat + 1] = ('%s: %s'):format(f.name, f.value)
    end
    print(('[nayzeee-backpack] %s | %s'):format(title, table.concat(flat, ' | ')))

    if not cfg.webhook or cfg.webhook == '' then return end

    local embed = {{
        title = title,
        color = color or (cfg.colors and cfg.colors.info) or 9807270,
        fields = fields,
        footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
    }}

    PerformHttpRequest(cfg.webhook, function() end, 'POST', json.encode({
        username = cfg.botName or 'Backpack',
        embeds = embed,
    }), { ['Content-Type'] = 'application/json' })
end

-----------------------------------------------------------------
-- events
-----------------------------------------------------------------

function Logs.rob(robber, victim, bagKey, metadata, droppedInstead)
    local rName, rLicense = Logs.who(robber)
    local vName, vLicense = Logs.who(victim)
    local bag = Config.Backpacks[bagKey]

    local fields = {
        { name = 'Robber', value = ('%s\n%s'):format(rName, rLicense), inline = true },
        { name = 'Victim', value = ('%s\n%s'):format(vName, vLicense), inline = true },
        { name = 'Bag',    value = (bag and bag.label or bagKey), inline = true },
        { name = 'Outcome', value = droppedInstead and 'Dropped on the ground' or 'Taken directly', inline = false },
    }

    local contents = Logs.contents(metadata)
    if contents then
        fields[#fields + 1] = { name = 'Contents', value = contents, inline = false }
    end

    send('rob', 'Backpack robbed', fields, cfg.colors and cfg.colors.rob)
end

function Logs.drop(src, bagKey, metadata, coords, reason)
    local name, license = Logs.who(src)
    local bag = Config.Backpacks[bagKey]

    local fields = {
        { name = 'Player', value = ('%s\n%s'):format(name, license), inline = true },
        { name = 'Bag',    value = (bag and bag.label or bagKey), inline = true },
        { name = 'Reason', value = reason or 'death', inline = true },
    }

    if coords then
        fields[#fields + 1] = { name = 'Location',
            value = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), inline = false }
    end

    local contents = Logs.contents(metadata)
    if contents then
        fields[#fields + 1] = { name = 'Contents', value = contents, inline = false }
    end

    send('drop', 'Backpack dropped', fields, cfg.colors and cfg.colors.drop)
end

function Logs.place(src, bagKey, coords, access, id)
    local name, license = Logs.who(src)
    local bag = Config.Backpacks[bagKey]

    send('place', 'Backpack placed', {
        { name = 'Player', value = ('%s\n%s'):format(name, license), inline = true },
        { name = 'Bag',    value = (bag and bag.label or bagKey), inline = true },
        { name = 'Access', value = access or 'private', inline = true },
        { name = 'Location', value = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), inline = false },
        { name = 'Id', value = tostring(id), inline = true },
    }, cfg.colors and cfg.colors.place)
end

function Logs.pickup(src, bagKey, coords, wasOwner, id)
    local name, license = Logs.who(src)
    local bag = Config.Backpacks[bagKey]

    send('pickup', 'Placed backpack picked up', {
        { name = 'Player', value = ('%s\n%s'):format(name, license), inline = true },
        { name = 'Bag',    value = (bag and bag.label or bagKey), inline = true },
        { name = 'Owner?', value = wasOwner and 'Own bag' or 'Someone else\'s', inline = true },
        { name = 'Location', value = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z), inline = false },
        { name = 'Id', value = tostring(id), inline = true },
    }, cfg.colors and cfg.colors.pickup)
end

function Logs.access(src, id, access)
    local name = Logs.who(src)
    send('access', 'Placed backpack access changed', {
        { name = 'Player', value = name, inline = true },
        { name = 'Id', value = tostring(id), inline = true },
        { name = 'Now', value = access, inline = true },
    }, cfg.colors and cfg.colors.info)
end

function Logs.simple(event, title, src, bagKey)
    local name = Logs.who(src)
    local bag = Config.Backpacks[bagKey]
    send(event, title, {
        { name = 'Player', value = name, inline = true },
        { name = 'Bag', value = (bag and bag.label or bagKey or '-'), inline = true },
    }, cfg.colors and cfg.colors.info)
end

function Logs.admin(src, bagKey, what)
    local name, license = Logs.who(src)
    local bag = Config.Backpacks[bagKey]
    send('admin', 'Backpack studio edit', {
        { name = 'Admin', value = ('%s\n%s'):format(name, license), inline = true },
        { name = 'Bag', value = (bag and bag.label or bagKey or '-'), inline = true },
        { name = 'Changed', value = what or '-', inline = false },
    }, cfg.colors and cfg.colors.info)
end

function Logs.search(officer, suspect, bagKey)
    local oName, oLicense = Logs.who(officer)
    local sName, sLicense = Logs.who(suspect)
    local bag = Config.Backpacks[bagKey]
    send('search', 'Backpack searched', {
        { name = 'Officer', value = ('%s\n%s'):format(oName, oLicense), inline = true },
        { name = 'Suspect', value = ('%s\n%s'):format(sName, sLicense), inline = true },
        { name = 'Bag', value = (bag and bag.label or bagKey or '-'), inline = true },
    }, cfg.colors and cfg.colors.info)
end
