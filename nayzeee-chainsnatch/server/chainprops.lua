-----------------------------------------------------------------
-- The converter (server side)
--
-- chainkit (tools/chainkit, run by server/chainkit.js) turns chain
-- clothing into props:
--   chains/<Chain Name>/teef_000_u.ydd + teef_diff_000_a_*.ytd ...
--   and, if Config.Convert.ScanResources says so, chains streamed
--   as clothing by other resources
-- into nayzeee-chainprops/stream (one prop per texture), plus
-- chainmap.json and an icon per prop. Only what's new or changed is
-- rebuilt; props of chains that were removed are deleted.
-----------------------------------------------------------------

ChainProps = { scan = nil, running = false, kit = false, platform = nil }

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
                print(('^3[%s] Config.Convert.ScanResources: no resource called %s^0'):format(SELF, name))
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
        new = s.new or {}, changed = s.changed or {}, removed = s.removed or {},
        folder = ('%s/%s'):format(SELF, CC.DropFolder or 'chains'), out = RES,
    }
end

local function tell(src, data)
    if src and src > 0 then TriggerClientEvent('nzc:c:chainkit', src, data) end
end

--- mode: 'scan' | 'build' (new + changed + removed) | 'rebuild' (everything) | 'icons'
function ChainProps.run(mode, src)
    if not CC.Enabled or ChainProps.running then return false end
    if not ChainProps.kit then
        if src and src > 0 then Worn.notify(src, 'chainkit is missing for this server (tools/chainkit, see the README).', 'error') end
        return false
    end
    ChainProps.running = mode
    tell(src, { kind = 'start', mode = mode })
    TriggerEvent('nzc:chainkit:run', {
        mode = mode, src = src or 0, kits = CC.Kit, roots = roots(), drops = { CC.DropFolder or 'chains' }, out = outDir(),
        tex = CC.TextureSize, icons = CC.IconSize, lod = CC.LodDistance,
    })
    return true
end

local function restartProps()
    ExecuteCommand('refresh')
    if GetResourceState(RES) == 'started' then ExecuteCommand('restart ' .. RES) else ExecuteCommand('ensure ' .. RES) end
    SetTimeout(4000, function()
        if GetResourceState(RES) ~= 'started' then
            print(('^3[%s] Couldn\'t start %s. Let this resource run the commands, in server.cfg:^0'):format(SELF, RES))
            print(('^3    add_ace resource.%s command.refresh allow^0'):format(SELF))
            print(('^3    add_ace resource.%s command.ensure allow^0'):format(SELF))
            print(('^3    add_ace resource.%s command.restart allow^0'):format(SELF))
            print(('^3  or add "ensure %s" to server.cfg after this resource.^0'):format(RES))
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
        ChainProps.scan = { found = data.chains, new = {}, changed = {}, removed = {} }
        if src and src > 0 then Worn.notify(src, ('Converted %d chain(s). Props restart in a moment.'):format(data.built or 0), 'success', 8000) end
        tell(src, { kind = 'done', built = data.built, status = ChainProps.status() })
    elseif kind == 'error' then
        print(('^1[%s]^7 chainkit: %s'):format(SELF, tostring(data.message)))
        if src and src > 0 then Worn.notify(src, tostring(data.message), 'error', 8000) end
    elseif kind == 'busy' then
        if src and src > 0 then Worn.notify(src, 'The converter is already running.', 'error') end
    end
end)

AddEventHandler('nzc:chainkit:exit', function(src, mode, code, tail)
    if ChainProps.running == mode or mode == 'scan' then ChainProps.running = false end
    if code ~= 0 then
        print(('^1[%s]^7 chainkit %s stopped with code %s\n%s'):format(SELF, mode, tostring(code), tostring(tail or '')))
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
    if mode ~= 'scan' and mode ~= 'build' and mode ~= 'rebuild' and mode ~= 'icons' then return end
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
