--[[
    3D props: keeps every shoe the server streams turned into props (one per colourway) for the shop,
    boxes and crafting. sneakerkit (tools/sneakerkit, started by server/sneakerkit.js) finds the shoe
    files in every started resource, converts new / changed ones into the props resource
    (Config.Studio.PropsResource) and writes its catalogue.json, which server/studio.lua reads.
]]

ShoeProps = { scan = nil, running = false, kit = false, platform = nil }

local CP = Config.ShoeProps
local RES = Config.Studio.PropsResource
local RESOURCE = GetCurrentResourceName()
local booting = true      -- the first scan after start may build on its own (AutoBuild)
local autoBuild = false

local function outDir()
    if GetResourceState(RES) ~= 'missing' then return GetResourcePath(RES) end
    local mine = GetResourcePath(RESOURCE):gsub('[/\\]+$', '')
    return (mine:match('^(.*)[/\\][^/\\]+$') or mine) .. '/' .. RES
end

local function iconDir()
    if not CP.CopyIcons then return nil end
    for _, r in ipairs({ { 'ox_inventory', '/web/images' }, { 'qb-inventory', '/html/images' }, { 'ps-inventory', '/html/images' } }) do
        if GetResourceState(r[1]) ~= 'missing' then return GetResourcePath(r[1]) .. r[2] end
    end
end

local function roots()
    local skip = { [RESOURCE] = true, [RES] = true }
    for _, r in ipairs(CP.Skip or {}) do skip[r] = true end
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

function ShoeProps.Status()
    local s = ShoeProps.scan or {}
    return {
        enabled = CP.Enabled, kit = ShoeProps.kit, platform = ShoeProps.platform, running = ShoeProps.running,
        props = Studio.CatalogueCount(), found = s.found or 0, resource = RES, state = GetResourceState(RES),
        new = #(s.new or {}), changed = #(s.changed or {}), removed = #(s.removed or {}),
    }
end

local function tell(src, data)
    if src and src > 0 then TriggerClientEvent('nayzeee-sneakers:client:kit', src, data) end
end

--- mode: 'scan' | 'build' (new + changed + removed) | 'rebuild' (everything)
function ShoeProps.Run(mode, src)
    if not CP.Enabled or ShoeProps.running then return false end
    if not ShoeProps.kit then
        if src and src > 0 then Bridge.Notify(src, Config.Text.kitMissing, 'error') end
        return false
    end
    ShoeProps.running = mode
    tell(src, { kind = 'start', mode = mode })
    TriggerEvent('nzs:kit:run', { mode = mode, src = src or 0, kits = CP.Kit, roots = roots(), out = outDir(), tex = CP.TextureSize, icons = iconDir() })
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
        Studio.Reload()
    end)
end

AddEventHandler('nzs:kit:found', function(ok, platform)
    ShoeProps.kit, ShoeProps.platform = ok, platform
end)

AddEventHandler('nzs:kit:msg', function(src, kind, data)
    if kind == 'scan' then
        ShoeProps.scan = data
        local todo = #(data.new or {}) + #(data.changed or {}) + #(data.removed or {})
        if todo > 0 then
            print(('^5[%s]^7 3D props: %d new, %d changed, %d removed shoe(s) out of %d.'):format(
                RESOURCE, #(data.new or {}), #(data.changed or {}), #(data.removed or {}), data.found or 0))
        end
        tell(src, { kind = 'status', status = ShoeProps.Status() })
        if booting and CP.AutoBuild and todo > 0 then autoBuild = true end
    elseif kind == 'progress' then
        tell(src, { kind = 'progress', i = data.i, n = data.n, key = data.key })
    elseif kind == 'done' then
        print(('^2[%s]^7 3D props: built %d of %d, removed %d, %d shoes in %s.'):format(
            RESOURCE, data.built or 0, data.tried or 0, data.removed or 0, data.props or 0, RES))
        for _, e in ipairs(data.errors or {}) do print(('^1[%s]^7 3D props: %s'):format(RESOURCE, tostring(e))) end
        if (data.built or 0) > 0 or (data.removed or 0) > 0 then restartProps() end
        ShoeProps.scan = { found = data.props, new = {}, changed = {}, removed = {} }
        if src and src > 0 then Bridge.Notify(src, Config.Text.kitDone:format(data.built or 0), 'success') end
        tell(src, { kind = 'done', built = data.built, status = ShoeProps.Status() })
    elseif kind == 'error' then
        print(('^1[%s]^7 3D props: %s'):format(RESOURCE, tostring(data.message)))
        if src and src > 0 then Bridge.Notify(src, tostring(data.message), 'error') end
    elseif kind == 'busy' then
        if src and src > 0 then Bridge.Notify(src, Config.Text.kitBusy, 'error') end
    end
end)

AddEventHandler('nzs:kit:exit', function(src, mode, code, tail)
    if ShoeProps.running == mode or mode == 'scan' then ShoeProps.running = false end
    if code ~= 0 then
        print(('^1[%s]^7 3D props: sneakerkit %s stopped with code %s\n%s'):format(RESOURCE, mode, tostring(code), tostring(tail or '')))
    end
    booting = false
    if mode == 'scan' and autoBuild then
        autoBuild = false
        return ShoeProps.Run('build', 0)
    end
    tell(src, { kind = 'status', status = ShoeProps.Status() })
end)

-- studio ------------------------------------------------------------------------------------------

RegisterNetEvent('nayzeee-sneakers:server:kit', function(mode)
    local src = source
    if not Studio.Allowed(src) or (mode ~= 'scan' and mode ~= 'build' and mode ~= 'rebuild') then return end
    if not ShoeProps.Run(mode, src) then tell(src, { kind = 'status', status = ShoeProps.Status() }) end
    Logs.Send('Studio: 3D props', { { 'Admin', Logs.Who(src) }, { 'Ran', mode } })
end)

CreateThread(function()
    if not CP.Enabled then return end
    Wait(3000) -- every resource (and server/sneakerkit.js) has started by now
    TriggerEvent('nzs:kit:check', CP.Kit)
    local st = GetResourceState(RES)
    if st == 'stopped' or st == 'uninitialized' then ExecuteCommand('ensure ' .. RES) end
    if CP.AutoScan and ShoeProps.kit then ShoeProps.Run('scan', 0)
    else booting = false end
end)
