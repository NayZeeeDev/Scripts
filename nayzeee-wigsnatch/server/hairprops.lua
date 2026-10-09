-- 3D wigs: keeps every hairstyle the server streams turned into a prop for the foam head.
-- hairkit (tools/hairkit, run by server/hairkit.js) finds the hair files in every started resource,
-- converts new / changed ones into nzw_hairprops/stream and writes hairmap.json, which says which prop
-- belongs to which hairstyle ("m|mp_m_mypack|3" = male, collection mp_m_mypack, local hairstyle 3).

HairProps = { map = {}, scan = nil, running = false, kit = false, platform = nil }

local CH = Config.HairProps
local RES = CH.Resource
local booting = true      -- the first scan after start may build on its own (AutoBuild)
local autoBuild = false

local function outDir()
    if GetResourceState(RES) ~= 'missing' then return GetResourcePath(RES) end
    local mine = GetResourcePath(RESOURCE):gsub('[/\\]+$', '')
    return (mine:match('^(.*)[/\\][^/\\]+$') or mine) .. '/' .. RES
end

local function roots()
    local skip = { [RESOURCE] = true, [RES] = true }
    for _, r in ipairs(CH.Skip or {}) do skip[r] = true end
    local out = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and not skip[name] and GetResourceState(name) == 'started' then
            local p = GetResourcePath(name)
            if p and p ~= '' then out[#out + 1] = p end
        end
    end
    return out
end

local function loadMap()
    HairProps.map = {}
    local raw = GetResourceState(RES) ~= 'missing' and LoadResourceFile(RES, 'hairmap.json') or nil
    local ok, data = pcall(json.decode, raw or '{}')
    for key, e in pairs(ok and type(data) == 'table' and data.props or {}) do
        if type(e) == 'table' and type(e.prop) == 'string' then HairProps.map[key] = e.prop end
    end
    return HairProps.map
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function HairProps.Status()
    local s = HairProps.scan or {}
    return {
        enabled = CH.Enabled, kit = HairProps.kit, platform = HairProps.platform, running = HairProps.running,
        props = count(HairProps.map), found = s.found or 0,
        new = #(s.new or {}), changed = #(s.changed or {}), removed = #(s.removed or {}),
    }
end

local function tell(src, data)
    if src and src > 0 then TriggerClientEvent('nz-wig:c:hairkit', src, data) end
end

-- mode: 'scan' | 'build' (new + changed + removed) | 'rebuild' (everything)
function HairProps.Run(mode, src)
    if not CH.Enabled or HairProps.running then return false end
    if not HairProps.kit then
        if src and src > 0 then Notify(src, L('hairkit_missing'), 'error') end
        return false
    end
    HairProps.running = mode
    tell(src, { kind = 'start', mode = mode })
    TriggerEvent('nz-wig:hairkit:run', { mode = mode, src = src or 0, kits = CH.Kit, roots = roots(), out = outDir(), tex = CH.TextureSize })
    return true
end

local function restartProps()
    ExecuteCommand('refresh')
    if GetResourceState(RES) == 'started' then ExecuteCommand('restart ' .. RES) else ExecuteCommand('ensure ' .. RES) end
    SetTimeout(4000, function()
        if GetResourceState(RES) ~= 'started' then
            print(('^3[%s] Couldn\'t start %s. Let this resource run the commands, in server.cfg:^0'):format(RESOURCE, RES))
            print(('^3    add_ace resource.%s command.refresh allow^0'):format(RESOURCE))
            print(('^3    add_ace resource.%s command.ensure allow^0'):format(RESOURCE))
            print(('^3    add_ace resource.%s command.restart allow^0'):format(RESOURCE))
            print(('^3  or add "ensure %s" to server.cfg after this resource.^0'):format(RES))
        end
        loadMap()
        TriggerClientEvent('nz-wig:c:hairmap', -1, HairProps.map)
    end)
end

AddEventHandler('nz-wig:hairkit:kit', function(ok, platform)
    HairProps.kit, HairProps.platform = ok, platform
end)

AddEventHandler('nz-wig:hairkit:msg', function(src, kind, data)
    if kind == 'scan' then
        HairProps.scan = data
        local todo = #(data.new or {}) + #(data.changed or {}) + #(data.removed or {})
        if todo > 0 then
            print(('^5[%s]^7 3D wigs: %d new, %d changed, %d removed hairstyle(s) out of %d.'):format(
                RESOURCE, #(data.new or {}), #(data.changed or {}), #(data.removed or {}), data.found or 0))
        end
        tell(src, { kind = 'status', status = HairProps.Status() })
        if booting and CH.AutoBuild and todo > 0 then autoBuild = true end
    elseif kind == 'progress' then
        tell(src, { kind = 'progress', i = data.i, n = data.n, key = data.key })
    elseif kind == 'done' then
        print(('^2[%s]^7 3D wigs: built %d of %d, removed %d, %d hairstyle props in %s.'):format(
            RESOURCE, data.built or 0, data.tried or 0, data.removed or 0, data.props or 0, RES))
        if (data.built or 0) > 0 or (data.removed or 0) > 0 then restartProps() end
        HairProps.scan = { found = data.props, new = {}, changed = {}, removed = {} }
        if src and src > 0 then Notify(src, L('hairkit_done', data.built or 0), 'success', 8000) end
        tell(src, { kind = 'done', built = data.built, status = HairProps.Status() })
    elseif kind == 'error' then
        print(('^1[%s]^7 3D wigs: %s'):format(RESOURCE, tostring(data.message)))
        if src and src > 0 then Notify(src, tostring(data.message), 'error', 8000) end
    elseif kind == 'busy' then
        if src and src > 0 then Notify(src, L('hairkit_busy'), 'error') end
    end
end)

AddEventHandler('nz-wig:hairkit:exit', function(src, mode, code, tail)
    if HairProps.running == mode or mode == 'scan' then HairProps.running = false end
    if code ~= 0 then
        print(('^1[%s]^7 3D wigs: hairkit %s stopped with code %s\n%s'):format(RESOURCE, mode, tostring(code), tostring(tail or '')))
    end
    booting = false
    if mode == 'scan' and autoBuild then
        autoBuild = false
        return HairProps.Run('build', 0)
    end
    tell(src, { kind = 'status', status = HairProps.Status() })
end)

-- studio ------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:hairkitStatus', function(src)
    if not Studio.Allowed(src) then return false end
    return HairProps.Status()
end)

RegisterNetEvent('nz-wig:s:hairkit', function(mode)
    local src = source
    if not Studio.Allowed(src) or (mode ~= 'scan' and mode ~= 'build' and mode ~= 'rebuild') then return end
    if not HairProps.Run(mode, src) then tell(src, { kind = 'status', status = HairProps.Status() }) end
    Log('admin', '3D wigs', ('%s ran hairkit %s'):format(GetPlayerName(src) or src, mode))
end)

-- clients ask for the hairstyle -> prop map after joining
RegisterNetEvent('nz-wig:s:hairmap', function()
    TriggerClientEvent('nz-wig:c:hairmap', source, HairProps.map)
end)

CreateThread(function()
    if not CH.Enabled then return end
    Wait(3000) -- every resource (and server/hairkit.js) has started by now
    TriggerEvent('nz-wig:hairkit:check', CH.Kit)
    if GetResourceState(RES) == 'stopped' or GetResourceState(RES) == 'uninitialized' then ExecuteCommand('ensure ' .. RES) end
    loadMap()
    TriggerClientEvent('nz-wig:c:hairmap', -1, HairProps.map)
    if CH.AutoScan and HairProps.kit then HairProps.Run('scan', 0)
    else booting = false end
end)
