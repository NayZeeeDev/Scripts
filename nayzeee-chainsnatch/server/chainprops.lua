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
                print(('^3[%s] Config.ScanResources: no resource called %s^0'):format(SELF, name))
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
        print(('^3[%s] Your server blocks starting the converter. Add this to server.cfg and restart:^0'):format(SELF))
        print(('^3    add_unsafe_child_process_permission "%s"^0'):format(SELF))
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
        if state ~= 'started' then
            print(('^3[%s] %s didn\'t start (it is "%s").^0'):format(SELF, RES, tostring(state)))
            local missing = {}
            for _, c in ipairs({ 'refresh', 'ensure', 'restart' }) do
                if not aceOk(c) then missing[#missing + 1] = c end
            end
            if #missing > 0 then
                print('^3  This resource isn\'t allowed to run those commands. Add to server.cfg:^0')
                for _, c in ipairs(missing) do print(('^3    add_ace resource.%s command.%s allow^0'):format(SELF, c)) end
            elseif state == 'missing' then
                print(('^3  The server can\'t see the folder. It should be at %s^0'):format(outDir()))
            else
                print(('^3  Type  ensure %s  in this console: the error it prints is why.^0'):format(RES))
            end
        end
        Registry.reload()
        CopyKitIcons(false)
    end)
end

AddEventHandler('nzc:chainkit:kit', function(ok, platform)
    ChainProps.kit, ChainProps.platform = ok, platform
end)

AddEventHandler('nzc:chainkit:msg', function(src, kind, data)
    if kind == 'scan' then
        ChainProps.scan = data
        local todo = #(data.new or {}) + #(data.changed or {}) + #(data.removed or {})
        if todo > 0 then
            print(('^5[%s]^7 chains: %d new, %d changed, %d removed (of %d found).'):format(
                SELF, #(data.new or {}), #(data.changed or {}), #(data.removed or {}), data.found or 0))
        end
        tell(src, { kind = 'status', status = ChainProps.status() })
        if booting and CC.AutoBuild and todo > 0 then autoBuild = true end
    elseif kind == 'skip' or kind == 'warn' then
        -- why a chain wasn't converted (or is very heavy): shown in the studio's Convert tab
        local p = ChainProps.problems
        if #p < 50 then p[#p + 1] = { kind = kind, label = data.label, file = data.file, reason = data.reason } end
        print(('^3[%s]^7 chainkit %s %s: %s'):format(SELF, kind == 'skip' and 'skipped' or 'warning,', tostring(data.label or data.key), tostring(data.reason)))
    elseif kind == 'progress' then
        tell(src, { kind = 'progress', i = data.i, n = data.n, key = data.key, label = data.label })
    elseif kind == 'done' then
        print(('^2[%s]^7 chainkit: built %d of %d, removed %d, %d chain(s) in %s.'):format(
            SELF, data.built or 0, data.tried or 0, data.removed or 0, data.chains or 0, RES))
        if data.icons then
            CopyKitIcons(false)
        elseif (data.built or 0) > 0 or (data.removed or 0) > 0 then
            restartProps()
        end
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
        print(('^1[%s]^7 chainkit: %s'):format(SELF, tostring(data.message)))
        local help = sandboxHelp(data.message)
        if src and src > 0 then Worn.notify(src, help or tostring(data.message), 'error', 12000) end
    elseif kind == 'busy' then
        if src and src > 0 then Worn.notify(src, 'The converter is already running.', 'error') end
    end
end)

AddEventHandler('nzc:chainkit:exit', function(src, mode, code, tail)
    if ChainProps.running == mode or mode == 'scan' then ChainProps.running = false end
    if code ~= 0 then
        print(('^1[%s]^7 chainkit %s stopped with code %s\n%s'):format(SELF, mode, tostring(code), tostring(tail or '')))
        local help = sandboxHelp(tail)
        if help and src and src > 0 then Worn.notify(src, help, 'error', 12000) end
    end
    booting = false
    if mode == 'scan' and autoBuild then
        autoBuild = false
        return ChainProps.run('build', 0)
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

CreateThread(function()
    if not CC.Enabled then return end
    Wait(3000) -- every resource (and server/chainkit.js) has started by now
    TriggerEvent('nzc:chainkit:check', CC.Kit)
    Wait(200)
    local st = GetResourceState(RES)
    if st == 'stopped' or st == 'uninitialized' then ExecuteCommand('ensure ' .. RES) end
    if CC.AutoScan and ChainProps.kit then ChainProps.run('scan', 0)
    else
        booting = false
        if not ChainProps.kit then
            print(('^3[%s] chainkit isn\'t installed (tools/chainkit/%s). Chains can\'t be converted on this server.^0'):format(SELF,
                ChainProps.platform == 'win32' and 'win-x64/chainkit.exe' or 'linux-x64/chainkit'))
        end
    end
end)
