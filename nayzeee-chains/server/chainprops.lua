-----------------------------------------------------------------
-- The converter (server side)
--
-- chainkit (tools/chainkit, run by server/chainkit.js) turns chain
-- clothing into props:
--   chains/<Chain Name>/teef_000_u.ydd + teef_diff_000_a_*.ytd ...
--   and, if Config.ScanResources says so, chains streamed
--   as clothing by other resources
-- into nayzeee-chainprops/stream (one prop per texture), plus
-- chainmap.json and an icon per prop. Only what's new or changed is
-- rebuilt; props of chains that were removed are deleted.
-----------------------------------------------------------------

ChainProps = { scan = nil, running = false, kit = false, platform = nil, problems = {} }

local CC = Config.Convert
local RES = Config.PropsResource
local SELF = GetCurrentResourceName()
local booting = true
local autoBuild = false
local bootPhase = true      -- until the start-up scan is done, the props resource waits
local bootBuild = false     -- ...and while the start-up build runs

-- On start the props resource is started only AFTER new chains are converted, so it starts once, with everything in
-- it. (Restarting it while players are still loading in is what used to need a second server restart.)
local function startProps()
    local st = GetResourceState(RES)
    if st == 'started' or st == 'starting' then return end
    ExecuteCommand('refresh')
    ExecuteCommand('ensure ' .. RES)
end

local function outDir()
    if GetResourceState(RES) ~= 'missing' then return GetResourcePath(RES) end
    local mine = GetResourcePath(SELF):gsub('[/\\]+$', '')
    return (mine:match('^(.*)[/\\][^/\\]+$') or mine) .. '/' .. RES
end

local function roots()
    local out = {}
    local want = CC.ScanResources
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
                Console.log('warn', 'Config.ScanResources: no resource called %s', name)
            end
        end
    end
    return out
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function ChainProps.status()
    local s = ChainProps.scan or {}
    return {
        enabled = CC.Enabled, kit = ChainProps.kit, platform = ChainProps.platform, running = ChainProps.running,
        chains = count(Chains.list), found = s.found or 0,
        new = s.new or {}, changed = s.changed or {}, removed = s.removed or {}, problems = ChainProps.problems,
        folder = ('%s/%s'):format(SELF, CC.DropFolder or 'chains'), out = RES,
    }
end

--- Newer FXServer builds sandbox resources: say exactly which server.cfg line is missing
local function sandboxHelp(text)
    text = tostring(text or '')
    if text:find('child', 1, true) and (text:find('restricted', 1, true) or text:find('not allowed', 1, true)) then
        Console.log('warn', 'Your server blocks starting the converter. Add to server.cfg and restart:  add_unsafe_child_process_permission "%s"', SELF)
        return 'The server blocks the converter: add  add_unsafe_child_process_permission "' .. SELF .. '"  to server.cfg and restart.'
    end
    return nil
end

local function tell(src, data)
    if src and src > 0 then TriggerClientEvent('nzc:c:chainkit', src, data) end
end

--- mode: 'scan' | 'build' (new + changed) | 'rebuild' (everything) | 'icons' | 'prune' (also delete chains whose files are gone)
function ChainProps.run(mode, src)
    if not CC.Enabled or ChainProps.running then return false end
    if not ChainProps.kit then
        if src and src > 0 then Worn.notify(src, 'chainkit is missing for this server (tools/chainkit, see the README).', 'error') end
        return false
    end
    ChainProps.running = mode
    if mode ~= 'scan' then ChainProps.problems = {} end
    tell(src, { kind = 'start', mode = mode })
    TriggerEvent('nzc:chainkit:run', {
        mode = mode, src = src or 0, kits = CC.Kit, roots = roots(), drops = { CC.DropFolder or 'chains' }, out = outDir(),
        tex = CC.TextureSize, icons = CC.IconSize, lod = CC.LodDistance,
    })
    return true
end

local function aceOk(cmd)
    local ok, yes = pcall(IsPrincipalAceAllowed, 'resource.' .. SELF, 'command.' .. cmd)
    return not ok or yes -- old builds without the native: assume yes
end

--- why the props resource didn't start, and what to do (one line)
function ChainProps.whyNotStarted(state)
    local missing = {}
    for _, c in ipairs({ 'refresh', 'ensure', 'restart' }) do
        if not aceOk(c) then missing[#missing + 1] = ('add_ace resource.%s command.%s allow'):format(SELF, c) end
    end
    if #missing > 0 then return 'this script may not run those commands, add to server.cfg: ' .. table.concat(missing, ' / ') end
    if state == 'missing' then return ('the server can\'t see the folder, it should be at %s'):format(outDir()) end
    return ('type  ensure %s  in this console: the error it prints is why'):format(RES)
end

local function countChains()
    local n = 0
    for _ in pairs(Chains.list) do n = n + 1 end
    return n
end

--- once the props resource is up: its row, the chains row, and the start-up block may print
local function reportProps(done)
    CreateThread(function()
        local state
        for _ = 1, 20 do
            state = GetResourceState(RES)
            if state == 'started' then break end
            Wait(500)
        end
        if state == 'started' then
            Registry.reload()
            Console.check('props', 'ok', 'Props', ('%s started'):format(RES))
        else
            Console.check('props', state == 'missing' and 'info' or 'error', 'Props', state == 'missing'
                and ('no %s yet: it is made the first time a chain is converted'):format(RES)
                or ('%s didn\'t start (it is "%s"): %s'):format(RES, tostring(state), ChainProps.whyNotStarted(state)))
        end
        local n = countChains()
        Console.check('chains', n > 0 and 'ok' or 'info', 'Chains', n > 0 and ('%d ready'):format(n)
            or ('none yet: put chain clothing in %s/%s/ and restart'):format(SELF, CC.DropFolder or 'chains'))
        if done then Console.done('converter') end
    end)
end

local function restartProps()
    RestoreStudioIcons()
    ExecuteCommand('refresh')
    if GetResourceState(RES) == 'started' then ExecuteCommand('restart ' .. RES) else ExecuteCommand('ensure ' .. RES) end
    -- restarting re-hashes every streamed model first, which can take a while on a slow (or OneDrive-synced) disk:
    -- wait for it instead of judging after a few seconds
    CreateThread(function()
        local state
        for _ = 1, 60 do
            Wait(1000)
            state = GetResourceState(RES)
            if state == 'started' then break end
        end
        Registry.reload()
        if state ~= 'started' then
            Console.check('props', 'error', 'Props', ('%s didn\'t start (it is "%s"): %s'):format(RES, tostring(state), ChainProps.whyNotStarted(state)))
        else
            Console.check('props', 'ok', 'Props', ('%s started, %d chain(s) ready'):format(RES, countChains()))
        end
        CopyKitIcons(false)
    end)
end

-- chainkit's own log lines: only with Config.Debug (the results come as rows / lines above)
AddEventHandler('nzc:chainkit:line', function(l) Console.debug('chainkit: %s', tostring(l)) end)

AddEventHandler('nzc:chainkit:kit', function(ok, platform)
    ChainProps.kit, ChainProps.platform = ok, platform
end)

AddEventHandler('nzc:chainkit:msg', function(src, kind, data)
    if kind == 'scan' then
        ChainProps.scan = data
        local todo = #(data.new or {}) + #(data.changed or {}) + #(data.removed or {})
        if todo > 0 then
            Console.log('info', 'chains: %d new, %d changed, %d removed (of %d found)',
                #(data.new or {}), #(data.changed or {}), #(data.removed or {}), data.found or 0)
        end
        tell(src, { kind = 'status', status = ChainProps.status() })
        if booting and CC.AutoBuild and todo > 0 then autoBuild = true end
    elseif kind == 'skip' or kind == 'warn' then
        -- why a chain wasn't converted (or is very heavy): shown in the studio's Convert tab
        local p = ChainProps.problems
        if #p < 50 then p[#p + 1] = { kind = kind, label = data.label, file = data.file, reason = data.reason } end
        Console.log('warn', 'chainkit %s %s: %s', kind == 'skip' and 'skipped' or 'warning,', tostring(data.label or data.key), tostring(data.reason))
    elseif kind == 'progress' then
        tell(src, { kind = 'progress', i = data.i, n = data.n, key = data.key, label = data.label })
    elseif kind == 'done' then
        if data.icons then
            Console.log('ok', 'chainkit drew %d icon(s)', data.built or 0)
        else
            local failed = (data.tried or 0) - (data.built or 0)
            Console.check('converter', failed > 0 and 'warn' or 'ok', 'Converter', failed > 0
                and ('converted %d of %d chain(s): the studio\'s Convert tab says why the rest couldn\'t be'):format(data.built or 0, data.tried or 0)
                or ('converted %d chain(s)%s'):format(data.built or 0, (data.removed or 0) > 0 and (', removed %d'):format(data.removed) or ''))
        end
        if data.icons then
            CopyKitIcons(false)
        elseif (data.built or 0) > 0 or (data.removed or 0) > 0 then
            restartProps()
        elseif bootBuild then
            startProps() -- the start-up build made nothing: start the props as they are
            reportProps(false)
        end
        bootBuild = false
        local kept = (data.kept or 0) > 0 and ChainProps.scan and ChainProps.scan.removed or {}
        ChainProps.scan = { found = data.chains, new = {}, changed = {}, removed = kept }
        if src and src > 0 then
            local failed = (data.tried or 0) - (data.built or 0)
            if data.icons then
                Worn.notify(src, ('Drew %d icon(s).'):format(data.built or 0), 'success', 6000)
            elseif failed > 0 then
                Worn.notify(src, ('Converted %d of %d chain(s). %d couldn\'t be: see the Convert tab for why.'):format(data.built or 0, data.tried or 0, failed), 'warning', 10000)
            elseif (data.removed or 0) > 0 then
                Worn.notify(src, ('Removed %d chain(s) whose files are gone.'):format(data.removed), 'success', 8000)
            elseif (data.built or 0) > 0 then
                Worn.notify(src, ('Converted %d chain(s). Props restart in a moment.'):format(data.built), 'success', 8000)
            else
                Worn.notify(src, 'Nothing new to convert.', 'info', 6000)
            end
        end
        tell(src, { kind = 'done', built = data.built, status = ChainProps.status() })
    elseif kind == 'error' then
        ChainProps.running = false -- the program may never have started, so no exit will come
        local help = sandboxHelp(data.message)
        Console.check('converter', 'error', 'Converter', help and ('blocked by the server: add  add_unsafe_child_process_permission "%s"  to server.cfg'):format(SELF)
            or ('chainkit failed: %s'):format(tostring(data.message)))
        if bootPhase or bootBuild then
            local wasBoot = bootPhase
            bootPhase, bootBuild, booting = false, false, false
            startProps()
            reportProps(wasBoot)
        end
        if src and src > 0 then Worn.notify(src, help or tostring(data.message), 'error', 12000) end
    elseif kind == 'busy' then
        if src and src > 0 then Worn.notify(src, 'The converter is already running.', 'error') end
    end
end)

AddEventHandler('nzc:chainkit:exit', function(src, mode, code, tail)
    if ChainProps.running == mode or mode == 'scan' then ChainProps.running = false end
    if bootBuild and mode ~= 'scan' then
        bootBuild = false -- the start-up build died without saying it was done
        startProps()
        reportProps(false)
    end
    if code ~= 0 then
        local help = sandboxHelp(tail)
        Console.log('error', 'chainkit %s stopped with code %s: %s', mode, tostring(code), (tostring(tail or ''):gsub('%s+', ' ')))
        if help and src and src > 0 then Worn.notify(src, help, 'error', 12000) end
    end
    booting = false
    if mode == 'scan' and autoBuild then
        autoBuild = false
        local s = ChainProps.scan or {}
        local n = #(s.new or {}) + #(s.changed or {})
        if ChainProps.run('build', 0) then
            bootPhase, bootBuild = false, true
            -- a first conversion can take a minute: the start-up block doesn't wait for it, the result prints after
            Console.check('converter', 'info', 'Converter', ('converting %d chain(s), the props start when it\'s done'):format(n))
            Console.check('props', 'info', 'Props', ('%s starts after converting'):format(RES))
            Console.check('chains', 'ok', 'Chains', ('%d ready, %d more being converted'):format(countChains(), n))
            Console.done('converter')
            return
        end
    end
    if mode == 'scan' and code ~= 0 then
        Console.check('converter', 'error', 'Converter', sandboxHelp(tail) and ('blocked by the server: add  add_unsafe_child_process_permission "%s"  to server.cfg'):format(SELF)
            or 'chainkit could not scan the chains folder (the note below says why)')
    end
    if mode == 'scan' and code == 0 then
        local s = ChainProps.scan or {}
        local gone = #(s.removed or {})
        Console.check('converter', gone > 0 and 'warn' or 'ok', 'Converter', gone > 0
            and ('chainkit ready; %d chain(s) have no files any more (kept): put them back, or Remove gone chains in the studio'):format(gone)
            or 'chainkit ready, nothing new to convert')
    end
    if bootPhase then
        bootPhase = false
        startProps() -- nothing (more) to build: start it now (a build that did something restarted it already)
        reportProps(true)
    end
    tell(src, { kind = 'status', status = ChainProps.status() })
end)

lib.callback.register('nzc:chainkit:status', function(src)
    if not Studio.allowed(src) then return false end
    return ChainProps.status()
end)

RegisterNetEvent('nzc:s:chainkit', function(mode)
    local src = source
    if not Studio.allowed(src) then return end
    if mode ~= 'scan' and mode ~= 'build' and mode ~= 'rebuild' and mode ~= 'icons' and mode ~= 'prune' then return end
    if not ChainProps.run(mode, src) then tell(src, { kind = 'status', status = ChainProps.status() }) end
    Logs.send('admin', 'Converter', ('%s ran chainkit %s'):format(Logs.who(src), mode))
end)

Console.wait('converter')
CreateThread(function()
    if not CC.Enabled then
        bootPhase = false
        Console.check('converter', 'info', 'Converter', 'off (Config.Convert.Enabled = false)')
        startProps()
        return reportProps(true)
    end
    Wait(500) -- every resource (and server/chainkit.js) has loaded by now
    TriggerEvent('nzc:chainkit:check', CC.Kit)
    Wait(200)
    if CC.AutoScan and ChainProps.kit then
        ChainProps.run('scan', 0)
        -- the props start when the scan (and the build after it) is done; never wait forever
        SetTimeout(180000, function()
            if bootPhase or bootBuild then bootPhase, bootBuild = false, false; startProps(); reportProps(false) end
        end)
    else
        booting = false
        bootPhase = false
        if not ChainProps.kit then
            Console.check('converter', 'warn', 'Converter', ('chainkit missing (tools/chainkit/%s, in the release zip): new chains can\'t be converted'):format(
                ChainProps.platform == 'win32' and 'win-x64/chainkit.exe' or 'linux-x64/chainkit'))
        else
            Console.check('converter', 'ok', 'Converter', 'chainkit ready (AutoScan off: Build in the studio)')
        end
        startProps()
        reportProps(true)
    end
end)
