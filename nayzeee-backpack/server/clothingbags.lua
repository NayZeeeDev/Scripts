-----------------------------------------------------------------
-- Clothing bags
--
-- bagkit (tools/bagkit, run by server/bagkit.js) turns bag clothing
--   bags/<Bag Name>/hand_000_u.ydd + hand_diff_000_a_*.ytd ...
-- (and, if Config.ClothingBags.scanResources says so, bags other
-- resources stream as clothing) into props in nayzeee-bagprops: one
-- prop per colour, a picture of each, and bagmap.json saying which
-- bone the clothing was skinned to and where it sat. Only what's new
-- or changed is rebuilt.
--
-- This file starts that resource once the start-up conversion is done,
-- then turns bagmap.json into Config.Backpacks entries (key nzb_...,
-- `converted = {...}`) on the server and every client. They all live
-- in the one ox_inventory item Config.ClothingBags.item.
-----------------------------------------------------------------

ClothingBags = { kit = false, platform = nil, running = false, list = {}, problems = {} }

local CC = Config.ClothingBags
if not CC or not CC.enabled then
    Console.check('clothing', 'info', 'Clothing bags', 'off (Config.ClothingBags.enabled = false)')
    return
end

local RES = CC.resource or 'nayzeee-bagprops'
local SELF = GetCurrentResourceName()
local FOLDER = CC.folder or 'bags'
local bootPhase = true   -- until the start-up scan is done, the props resource waits
local bootBuild = false  -- ...and while the start-up build runs
local autoBuild = false

-----------------------------------------------------------------
-- registry: bagmap.json -> Config.Backpacks
-----------------------------------------------------------------

local function vec(t)
    if type(t) ~= 'table' then return nil end
    local x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function bagmap()
    if GetResourceState(RES) == 'missing' then return {} end
    local raw = LoadResourceFile(RES, 'bagmap.json')
    local ok, data = pcall(json.decode, raw or '{}')
    return ok and type(data) == 'table' and type(data.bags) == 'table' and data.bags or {}
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- Read bagmap.json again and (re)register every clothing bag, here and on every client.
function ClothingBags.reload()
    for key, bag in pairs(Config.Backpacks) do
        if type(bag) == 'table' and bag.converted then Config.Backpacks[key] = nil end
    end
    Bags.cache = {}

    local list = {}
    local d = CC.defaults or {}
    for source, e in pairs(bagmap()) do
        if type(e) == 'table' and type(e.id) == 'string' and type(e.variants) == 'table' and #e.variants > 0 then
            local vars = {}
            for i, v in ipairs(e.variants) do
                if type(v.prop) == 'string' then
                    vars[#vars + 1] = { label = ('Colour %s'):format(string.upper(tostring(v.letter or string.char(96 + i)))), model = v.prop }
                end
            end
            if #vars > 0 then
                local def = {
                    label = e.label or e.id, model = vars[1].model,
                    category = d.category or 'backpack', theme = d.theme or 'realistic',
                    price = d.price, slots = d.slots, weight = d.weight,
                    variants = #vars > 1 and vars or nil,
                    converted = { resource = RES, source = source, bone = tonumber(e.bone), centre = vec(e.centre) },
                }
                for k, v in pairs(type(CC.bags) == 'table' and CC.bags[e.label] or {}) do
                    if k ~= 'converted' then def[k] = v end
                end
                if Config.Backpacks[e.id] and not Config.Backpacks[e.id].converted then
                    Console.log('warn', 'clothing bag %s clashes with a Config.Backpacks key, skipped', e.id)
                else
                    Config.Backpacks[e.id] = def
                    list[e.id] = def
                end
            end
        end
    end
    ClothingBags.list = list
    TriggerLatentClientEvent('nayzeee-backpack:clothingBags', -1, 200000, list)
    for _, id in ipairs(GetPlayers()) do RefreshBagState(tonumber(id)) end
    return count(list)
end

RegisterNetEvent('nayzeee-backpack:clothingBags:get', function()
    TriggerLatentClientEvent('nayzeee-backpack:clothingBags', source, 200000, ClothingBags.list)
end)

AddEventHandler('onResourceStart', function(res)
    if res == RES then SetTimeout(500, ClothingBags.reload) end
end)

-----------------------------------------------------------------
-- running the converter
-----------------------------------------------------------------

local function outDir()
    if GetResourceState(RES) ~= 'missing' then return GetResourcePath(RES) end
    local mine = GetResourcePath(SELF):gsub('[/\\]+$', '')
    return (mine:match('^(.*)[/\\][^/\\]+$') or mine) .. '/' .. RES
end

local function roots()
    local out = {}
    local want = CC.scanResources
    if want == 'all' then
        local skip = { [SELF] = true, [RES] = true }
        for i = 0, GetNumResources() - 1 do
            local name = GetResourceByFindIndex(i)
            if name and not skip[name] and GetResourceState(name) == 'started' then
                local p = GetResourcePath(name)
                if p and p ~= '' then out[#out + 1] = p end
            end
        end
    elseif type(want) == 'table' then
        for _, name in ipairs(want) do
            if GetResourceState(name) ~= 'missing' then
                local p = GetResourcePath(name)
                if p and p ~= '' then out[#out + 1] = p end
            else
                Console.log('warn', 'Config.ClothingBags.scanResources: no resource called %s', name)
            end
        end
    end
    return out
end

local function notify(src, text, kind)
    if src and src > 0 then TriggerClientEvent('nayzeee-backpack:notify', src, text, kind or 'inform') end
end

--- newer FXServer builds sandbox resources: say exactly which server.cfg line is missing
local function sandboxHelp(text)
    text = tostring(text or '')
    if text:find('child', 1, true) and (text:find('restricted', 1, true) or text:find('not allowed', 1, true)) then
        return ('the server blocks the converter: add  add_unsafe_child_process_permission "%s"  to server.cfg and restart'):format(SELF)
    end
    return nil
end

--- mode: 'scan' | 'build' (new + changed) | 'rebuild' (everything) | 'icons' | 'prune' (also delete bags whose files are gone)
function ClothingBags.run(mode, src)
    if ClothingBags.running then return false end
    if not ClothingBags.kit then
        notify(src, 'bagkit is missing for this server (tools/bagkit, in the release zip).', 'error')
        return false
    end
    ClothingBags.running = mode
    if mode ~= 'scan' then ClothingBags.problems = {} end
    TriggerEvent('nayzeee-backpack:bagkit:run', {
        mode = mode, src = src or 0, kits = CC.kit, roots = roots(), drops = { FOLDER }, out = outDir(),
        tex = CC.textureSize, icons = CC.iconSize, lod = CC.lodDistance, tris = CC.maxTriangles,
    })
    return true
end

local function aceOk(cmd)
    local ok, yes = pcall(IsPrincipalAceAllowed, 'resource.' .. SELF, 'command.' .. cmd)
    return not ok or yes -- old builds without the native: assume yes
end

--- why the props resource didn't start, and what to do (one line)
local function whyNotStarted(state)
    local missing = {}
    for _, c in ipairs({ 'refresh', 'ensure', 'restart' }) do
        if not aceOk(c) then missing[#missing + 1] = ('add_ace resource.%s command.%s allow'):format(SELF, c) end
    end
    if #missing > 0 then return 'this script may not run those commands, add to server.cfg: ' .. table.concat(missing, ' / ') end
    if state == 'missing' then return ('the server can\'t see the folder, it should be at %s'):format(outDir()) end
    return ('type  ensure %s  in this console: the error it prints is why'):format(RES)
end

local function startProps()
    local st = GetResourceState(RES)
    if st == 'started' or st == 'starting' then return end
    ExecuteCommand('refresh')
    ExecuteCommand('ensure ' .. RES)
end

--- once the props resource is up: its rows, and the start-up block may print
local function reportProps(done)
    CreateThread(function()
        local state
        for _ = 1, 20 do
            state = GetResourceState(RES)
            if state == 'started' then break end
            Wait(500)
        end
        local n = 0
        if state == 'started' then
            n = ClothingBags.reload()
            Console.check('bagprops', 'ok', 'Bag props', ('%s started'):format(RES))
        else
            Console.check('bagprops', state == 'missing' and 'info' or 'error', 'Bag props', state == 'missing'
                and ('no %s yet: it is made the first time a bag is converted'):format(RES)
                or ('%s didn\'t start (it is "%s"): %s'):format(RES, tostring(state), whyNotStarted(state)))
        end
        Console.check('clothing', n > 0 and 'ok' or 'info', 'Clothing bags', n > 0 and ('%d ready'):format(n)
            or ('none yet: put bag clothing in %s/%s/ and restart'):format(SELF, FOLDER))
        if done then Console.done('converter') end
    end)
end

local function restartProps()
    ExecuteCommand('refresh')
    if GetResourceState(RES) == 'started' then ExecuteCommand('restart ' .. RES) else ExecuteCommand('ensure ' .. RES) end
    -- restarting re-hashes every streamed model first, which can take a while on a slow disk: wait for it
    CreateThread(function()
        local state
        for _ = 1, 60 do
            Wait(1000)
            state = GetResourceState(RES)
            if state == 'started' then break end
        end
        if state ~= 'started' then
            Console.check('bagprops', 'error', 'Bag props', ('%s didn\'t start (it is "%s"): %s'):format(RES, tostring(state), whyNotStarted(state)))
        else
            local n = ClothingBags.reload()
            Console.check('bagprops', 'ok', 'Bag props', ('%s started, %d clothing bag(s) ready'):format(RES, n))
        end
    end)
end

AddEventHandler('nayzeee-backpack:bagkit:line', function(l)
    if Config.Debug then Console.log('info', 'bagkit: %s', tostring(l)) end
end)

AddEventHandler('nayzeee-backpack:bagkit:kit', function(ok, platform)
    ClothingBags.kit, ClothingBags.platform = ok, platform
end)

AddEventHandler('nayzeee-backpack:bagkit:msg', function(src, kind, data)
    if kind == 'scan' then
        local todo = #(data.new or {}) + #(data.changed or {})
        if todo + #(data.removed or {}) > 0 then
            Console.log('info', 'clothing bags: %d new, %d changed, %d with no files any more (of %d found)',
                #(data.new or {}), #(data.changed or {}), #(data.removed or {}), data.found or 0)
        end
        ClothingBags.scan = data
        if bootPhase and CC.autoBuild ~= false and todo > 0 then autoBuild = true end
        if src and src > 0 then notify(src, ('Found %d bag(s): %d new, %d changed.'):format(data.found or 0, #(data.new or {}), #(data.changed or {}))) end
    elseif kind == 'skip' or kind == 'warn' then
        local p = ClothingBags.problems
        if #p < 50 then p[#p + 1] = { kind = kind, label = data.label, file = data.file, reason = data.reason } end
        Console.log('warn', 'bagkit %s %s: %s', kind == 'skip' and 'skipped' or 'warning,', tostring(data.label or data.key), tostring(data.reason))
    elseif kind == 'done' then
        local failed = (data.tried or 0) - (data.built or 0)
        if data.icons then
            Console.log('ok', 'bagkit drew %d picture(s)', data.built or 0)
        else
            Console.check('converter', failed > 0 and 'warn' or 'ok', 'Converter', failed > 0
                and ('converted %d of %d bag(s): the notes say why the rest couldn\'t be'):format(data.built or 0, data.tried or 0)
                or ('converted %d bag(s)%s'):format(data.built or 0, (data.removed or 0) > 0 and (', removed %d'):format(data.removed) or ''))
        end
        if (data.built or 0) > 0 or (data.removed or 0) > 0 or data.icons then
            restartProps()
        elseif bootBuild then
            startProps() -- the start-up build made nothing: start the props as they are
            reportProps(false)
        end
        bootBuild = false
        if src and src > 0 then
            if data.icons then notify(src, ('Drew %d picture(s).'):format(data.built or 0), 'success')
            elseif failed > 0 then notify(src, ('Converted %d of %d bag(s): the server console says why.'):format(data.built or 0, data.tried or 0), 'error')
            elseif (data.built or 0) > 0 then notify(src, ('Converted %d bag(s). The props restart in a moment.'):format(data.built), 'success')
            elseif (data.removed or 0) > 0 then notify(src, ('Removed %d bag(s) whose files are gone.'):format(data.removed), 'success')
            else notify(src, 'Nothing new to convert.') end
        end
    elseif kind == 'error' then
        ClothingBags.running = false -- the program may never have started, so no exit will come
        local help = sandboxHelp(data.message)
        Console.check('converter', 'error', 'Converter', help or ('bagkit failed: %s'):format(tostring(data.message)))
        if bootPhase or bootBuild then
            local wasBoot = bootPhase
            bootPhase, bootBuild = false, false
            startProps()
            reportProps(wasBoot)
        end
        notify(src, help or tostring(data.message), 'error')
    elseif kind == 'busy' then
        notify(src, 'The converter is already running.', 'error')
    end
end)

AddEventHandler('nayzeee-backpack:bagkit:exit', function(src, mode, code, tail)
    if ClothingBags.running == mode or mode == 'scan' then ClothingBags.running = false end
    if bootBuild and mode ~= 'scan' then
        bootBuild = false -- the start-up build died without saying it was done
        startProps()
        reportProps(false)
    end
    if code ~= 0 then
        Console.log('error', 'bagkit %s stopped with code %s: %s', mode, tostring(code), (tostring(tail or ''):gsub('%s+', ' ')))
    end
    if mode == 'scan' and autoBuild then
        autoBuild = false
        local s = ClothingBags.scan or {}
        local n = #(s.new or {}) + #(s.changed or {})
        if ClothingBags.run('build', 0) then
            bootPhase, bootBuild = false, true
            -- a first conversion can take a minute: the start-up block doesn't wait for it, the result prints after
            Console.check('converter', 'info', 'Converter', ('converting %d bag(s), the props start when it\'s done'):format(n))
            Console.check('bagprops', 'info', 'Bag props', ('%s starts after converting'):format(RES))
            Console.check('clothing', 'info', 'Clothing bags', ('%d being converted'):format(n))
            Console.done('converter')
            return
        end
    end
    if mode == 'scan' then
        if code ~= 0 then
            Console.check('converter', 'error', 'Converter', sandboxHelp(tail) or 'bagkit could not scan the bags folder (the note below says why)')
        else
            local gone = #((ClothingBags.scan or {}).removed or {})
            Console.check('converter', gone > 0 and 'warn' or 'ok', 'Converter', gone > 0
                and ('bagkit ready; %d bag(s) have no files any more (kept): put them back, or  /bagconvert prune'):format(gone)
                or 'bagkit ready, nothing new to convert')
        end
    end
    if bootPhase then
        bootPhase = false
        startProps() -- nothing (more) to build: start it now (a build that did something restarted it already)
        reportProps(true)
    end
end)

-----------------------------------------------------------------
-- /bagconvert [build | rebuild | icons | prune | scan]
-----------------------------------------------------------------

lib.addCommand('bagconvert', {
    help = 'Convert bag clothing in the bags folder into props (admin)',
    params = { { name = 'mode', type = 'string', help = 'build (default), rebuild, icons, prune or scan', optional = true } },
    restricted = false,
}, function(src, args)
    if src ~= 0 and not Framework.isAdmin(src) then return end
    local mode = args.mode or 'build'
    if mode ~= 'scan' and mode ~= 'build' and mode ~= 'rebuild' and mode ~= 'icons' and mode ~= 'prune' then
        return notify(src, 'Use build, rebuild, icons, prune or scan.', 'error')
    end
    if ClothingBags.run(mode, src) then
        notify(src, mode == 'scan' and 'Looking for bags...' or 'Converting... this can take a minute.')
        if Logs then Logs.simple('admin', 'Clothing bags', src, mode) end
    end
end)

-----------------------------------------------------------------
-- start-up
-----------------------------------------------------------------

Console.wait('converter')
CreateThread(function()
    Wait(500) -- every resource (and server/bagkit.js) has loaded by now
    TriggerEvent('nayzeee-backpack:bagkit:check', CC.kit)
    Wait(200)
    if ClothingBags.kit then
        ClothingBags.run('scan', 0)
        -- the props start when the scan (and the build after it) is done; never wait forever
        SetTimeout(180000, function()
            if bootPhase or bootBuild then bootPhase, bootBuild = false, false; startProps(); reportProps(false) end
        end)
    else
        bootPhase = false
        Console.check('converter', 'warn', 'Converter', ('bagkit missing (tools/bagkit/%s, in the release zip): new clothing bags can\'t be converted'):format(
            ClothingBags.platform == 'win32' and 'win-x64/bagkit.exe' or 'linux-x64/bagkit'))
        startProps()
        reportProps(true)
    end
end)
