-----------------------------------------------------------------
-- Console
--
-- Everything this script says while the server starts (dependencies,
-- database, what it restored, warnings) is collected and printed as ONE
-- block under the banner, instead of scattered through the server log.
-- After that every line goes out the same way:
--   [NayZeee Body Bag] WARN  something to look at
--
--   Console.wait(task)                     a startup step is still running
--   Console.done(task)                     ...and finished
--   Console.check(key, level, label, text) a row in the Server section
--   Console.log(level, text, ...)          anything else (format string)
-- levels: 'ok', 'info', 'warn', 'error'
-----------------------------------------------------------------

Console = {}

local RESOURCE = GetCurrentResourceName()
local NAME     = 'NayZeee Body Bag'
local VERSION  = GetResourceMetadata(RESOURCE, 'version', 0) or '1.0.0'
local ABOUT    = 'Body disposal, evidence, CK & the funeral home'

local LEVEL = {
    ok    = '^2 OK   ',
    info  = '^5 INFO ',
    warn  = '^3 WARN ',
    error = '^1 FAIL ',
}

-- the order rows appear in, whatever order the checks finish in
local ORDER = {
    'ox_lib', 'ox_target', 'ox_inventory', 'oxmysql', 'framework', 'onesync',
    'database', 'items', 'mode', 'logs', 'graves', 'funeral', 'funeraljob', 'morgue', 'memorials',
}
local rank = {}
for i, k in ipairs(ORDER) do rank[k] = i end

local started = GetGameTimer()
local rows, notes, pending = {}, {}, {}
local flushed = false
local nextRank = #ORDER

local function pad(s, n)
    s = tostring(s)
    return s .. string.rep(' ', math.max(0, n - #s))
end

local WIDTH = 66 -- where every rule line ends

--- '   ┌─ Title ───────' padded with ─ out to WIDTH (colour codes don't count)
local function rule(corner, title)
    local head = ('^5   %s─ %s ^5'):format(corner, title)
    local visible = utf8.len((head:gsub('%^%d', ''))) or #head
    return head .. string.rep('─', math.max(3, WIDTH - visible))
end

local function line(level, text)
    return ('^5[%s]^7%s^7%s^0'):format(NAME, LEVEL[level] or LEVEL.info, text)
end

local function flush()
    if flushed then return end
    flushed = true

    table.sort(rows, function(a, b) return a.rank < b.rank end)
    local worst = 'ok'
    for _, r in ipairs(rows) do
        if r.level == 'error' then worst = 'error' elseif r.level == 'warn' and worst ~= 'error' then worst = 'warn' end
    end
    for _, n in ipairs(notes) do
        if n.level == 'error' then worst = 'error' elseif n.level == 'warn' and worst ~= 'error' then worst = 'warn' end
    end

    local out = {
        '',
        '^5   ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗',
        '^5   ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝',
        '^5   ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗',
        '^5   ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝',
        '^5   ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗',
        '^5   ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝',
        ('^7   %s ^5v%s  ^7%s'):format(NAME, VERSION, ABOUT),
        '',
        rule('┌', '^7About'),
        ('^5   │ ^7%s^5NayZeee Development'):format(pad('Developer', 13)),
        ('^5   │ ^7%s^5discord.gg/nayzeeedev'):format(pad('Discord', 13)),
        ('^5   │ ^7%s^5%s'):format(pad('Resource', 13), RESOURCE),
        rule('├', '^7Server'),
    }
    for _, r in ipairs(rows) do
        out[#out + 1] = ('^5   │%s^7%s^7%s'):format(LEVEL[r.level] or LEVEL.info, pad(r.label, 15), r.text)
    end
    if #notes > 0 then
        out[#out + 1] = rule('├', '^7Notes')
        for _, n in ipairs(notes) do
            out[#out + 1] = ('^5   │%s^7%s'):format(LEVEL[n.level] or LEVEL.info, n.text)
        end
    end
    local took = (GetGameTimer() - started) / 1000
    local status = ({ ok = '^2Ready', warn = '^3Ready, with warnings', error = '^1Started with errors' })[worst]
    out[#out + 1] = rule('└', ('%s ^7in %.1fs'):format(status, took))
    out[#out + 1] = '^0'
    print(table.concat(out, '\n'))
end

--- A startup step that has to finish before the block prints.
function Console.wait(task) pending[task] = true end

--- That step is done; prints the block once nothing is left running.
function Console.done(task)
    pending[task] = nil
    if not flushed and next(pending) == nil then SetTimeout(0, flush) end
end

--- A row in the Server section. `key` places it (see ORDER); text is plain.
function Console.check(key, level, label, text)
    local r = { rank = rank[key], level = level, label = label, text = text or '' }
    if not r.rank then nextRank = nextRank + 1; r.rank = nextRank end
    for i, old in ipairs(rows) do
        if old.label == label then rows[i] = r return end
    end
    rows[#rows + 1] = r
    if flushed then print(line(level, ('%s: %s'):format(label, text or ''))) end
end

--- Anything else. Before the block prints it lands under Notes, after
--- that it prints straight away with the script's prefix.
function Console.log(level, text, ...)
    if select('#', ...) > 0 then text = text:format(...) end
    if flushed then
        print(line(level, text))
    else
        notes[#notes + 1] = { level = level, text = text }
    end
end

-----------------------------------------------------------------
-- the checks that need nothing but the server itself
-----------------------------------------------------------------

local function dep(key, res, required, missingText)
    local state = GetResourceState(res)
    if state == 'started' or state == 'starting' then
        Console.check(key, 'ok', res, 'started')
    else
        Console.check(key, required and 'error' or 'warn', res, missingText or state)
    end
    return state == 'started' or state == 'starting'
end

dep('ox_lib', 'ox_lib', true, 'not running: the script cannot work without it')
dep('ox_target', 'ox_target', true, 'not running: nothing can be third-eyed. Ensure it before this script')
local hasInventory = dep('ox_inventory', 'ox_inventory', true, 'not running: no items can be used. Ensure it before this script')
dep('oxmysql', 'oxmysql', true, 'not running: graves, CKs and the morgue cannot be saved')

if GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
    Console.check('framework', 'ok', 'Framework', 'es_extended')
else
    Console.check('framework', 'error', 'Framework', 'es_extended not running: this script needs ESX Legacy')
end

if GetConvar('onesync', 'off') ~= 'off' then
    Console.check('onesync', 'ok', 'OneSync', 'on')
else
    Console.check('onesync', 'error', 'OneSync', 'off: add "set onesync on" to server.cfg')
end

-- every item this script hands out or needs must exist in ox_inventory
if hasInventory then
    local ok, all = pcall(function() return exports.ox_inventory:Items() end)
    if ok and type(all) == 'table' then
        local funeralOnly = { flowers = true, urn = true, deathCertificate = true }
        local missing = {}
        for key, name in pairs(Config.Items) do
            if not all[name] and (not funeralOnly[key] or (Config.Funeral and Config.Funeral.Enabled)) then
                missing[#missing + 1] = name
            end
        end
        table.sort(missing)
        if #missing == 0 then
            Console.check('items', 'ok', 'Items', 'all items found in ox_inventory')
        else
            Console.check('items', 'warn', 'Items', ('%d item(s) missing: copy them from README.md into ox_inventory/data/items.lua'):format(#missing))
            Console.log('warn', 'no item yet: %s', table.concat(missing, ', '))
        end
    else
        Console.check('items', 'warn', 'Items', 'could not read the ox_inventory item list')
    end
end

-- what happens when a body is destroyed
local mode = Config.CK.OnDisposal
if mode ~= 'ck' and mode ~= 'respawn' then
    Console.check('mode', 'warn', 'Disposal', ('Config.CK.OnDisposal = "%s" is not valid: use \'ck\' or \'respawn\''):format(tostring(mode)))
elseif Config.CK.Enabled and mode == 'ck' then
    Console.check('mode', 'info', 'Disposal', 'CK: a destroyed body permanently kills the character')
else
    Console.check('mode', 'info', 'Disposal', 'respawn: victims wake up in hospital (NLR)')
end

-- decomposition stages must be in order or bodies skip stages
local lastAfter = -1
for _, s in ipairs(Config.Decomposition.Stages) do
    if s.after <= lastAfter then
        Console.log('warn', 'Config.Decomposition.Stages are not in ascending order: sort them by "after"')
        break
    end
    lastAfter = s.after
end

if Config.Logs.Webhook ~= '' or Config.Logs.CKWebhook ~= '' then
    Console.check('logs', 'ok', 'Logs', 'console + Discord webhook')
else
    Console.check('logs', 'info', 'Logs', 'console only (set Config.Logs.Webhook for Discord)')
end

-- nothing left waiting (or something hung): print anyway after 15s
CreateThread(function()
    Wait(0)
    if next(pending) == nil then return flush() end
    Wait(15000)
    if not flushed then
        for task in pairs(pending) do Console.log('warn', 'startup step "%s" took too long', task) end
        flush()
    end
end)
