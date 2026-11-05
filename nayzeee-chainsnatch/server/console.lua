-----------------------------------------------------------------
-- Console
--
-- Everything this script says while the server starts (dependencies,
-- inventory, the converter, what it restored, warnings) is collected and
-- printed as ONE block under the banner, instead of scattered through the
-- server log. After that every line goes out the same way:
--   [NayZeee Chain Snatch] WARN  something to look at
--
--   Console.wait(task)                     a startup step is still running
--   Console.done(task)                     ...and finished
--   Console.check(key, level, label, text) a row in the Server section
--   Console.log(level, text, ...)          anything else (format string)
-- levels: 'ok', 'info', 'warn', 'error'
-----------------------------------------------------------------

Console = {}

local RESOURCE = GetCurrentResourceName()
local NAME     = 'NayZeee Chain Snatch'
local VERSION  = GetResourceMetadata(RESOURCE, 'version', 0) or '1.0.0'
local ABOUT    = 'Chains you can buy, wear, flex, throw & snatch'

local LEVEL = {
    ok    = '^2 OK   ',
    info  = '^5 INFO ',
    warn  = '^3 WARN ',
    error = '^1 FAIL ',
}

-- the order rows appear in, whatever order the checks finish in
local ORDER = { 'ox_lib', 'framework', 'inventory', 'item', 'target', 'screenshot', 'converter', 'props', 'chains', 'store', 'drops' }
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
    local replaced = false
    for i, old in ipairs(rows) do
        if old.label == label then rows[i] = r; replaced = true break end
    end
    if not replaced then rows[#rows + 1] = r end
    -- after the block printed, a row that changes (a conversion finishing, say) prints as its own line
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

--- Debug lines: only with Config.Debug on.
function Console.debug(text, ...)
    if Config and Config.Debug then Console.log('info', text, ...) end
end

-- the JavaScript helpers (server/chainkit.js, server/icons.js) talk through this
AddEventHandler('nzc:console', function(level, text)
    if GetInvokingResource() and GetInvokingResource() ~= RESOURCE then return end
    Console.log(LEVEL[level] and level or 'info', tostring(text))
end)

-----------------------------------------------------------------
-- the checks that need nothing but the server itself
-----------------------------------------------------------------

local function up(res)
    local state = GetResourceState(res)
    return state == 'started' or state == 'starting'
end

if up('ox_lib') then
    Console.check('ox_lib', 'ok', 'ox_lib', 'started')
else
    Console.check('ox_lib', 'error', 'ox_lib', 'not running: the script cannot work without it. ensure ox_lib above this script')
end

if up('ox_target') then Console.check('target', 'ok', 'Target', 'ox_target')
elseif up('qb-target') then Console.check('target', 'ok', 'Target', 'qb-target')
else Console.check('target', 'info', 'Target', 'none: snatch / pick up use their commands and keys instead') end

if up('screenshot-basic') then
    Console.check('screenshot', 'ok', 'Icon studio', 'screenshot-basic started')
else
    Console.check('screenshot', 'info', 'Icon studio', 'screenshot-basic not running: chainkit icons only, no studio photos')
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
