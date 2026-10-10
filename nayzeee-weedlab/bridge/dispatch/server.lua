--[[ Dispatch bridge (server). Client-side dispatch resources are called through the robber's client. ]]

Dispatch = {}

local function detect()
    if Config.Dispatch ~= 'auto' then return Config.Dispatch end
    local map = {
        { 'ps-dispatch', 'ps' }, { 'cd_dispatch', 'cd' }, { 'qs-dispatch', 'qs' },
        { 'rcore_dispatch', 'rcore' }, { 'tk_dispatch', 'tk' }, { 'lb-tablet', 'lb' },
    }
    for i = 1, #map do
        if GetResourceState(map[i][1]) == 'started' then return map[i][2] end
    end
    return 'builtin'
end

Dispatch.name = detect()

local CLIENT_SIDE = { ps = true, cd = true, qs = true, tk = true, custom = true }

---@param src number robber that triggered the alert
---@param data { coords: vector3, title: string, message: string, code?: string }
function Dispatch.alert(src, data)
    data.code = data.code or '10-90'
    data.jobs = Config.Police.jobs
    data.coords = Utils.vec3(data.coords)

    if CLIENT_SIDE[Dispatch.name] then
        TriggerClientEvent('nzwl:dispatch', src, Dispatch.name, data)
        return
    end

    if Dispatch.name == 'rcore' then
        TriggerEvent('rcore_dispatch:server:sendAlert', {
            code = data.code, default_priority = 'high', coords = data.coords, job = data.jobs,
            text = data.message, type = 'alerts', blip_time = 5,
            blip = { sprite = 161, colour = 1, scale = 1.0, text = data.title, flashes = true, radius = 0 },
        })
        return
    elseif Dispatch.name == 'lb' then
        for i = 1, #data.jobs do
            pcall(function()
                exports['lb-tablet']:AddDispatch({
                    priority = 'high', code = data.code, title = data.title, description = data.message,
                    location = { label = data.title, coords = vec2(data.coords.x, data.coords.y) },
                    time = 300, job = data.jobs[i],
                })
            end)
        end
        return
    end

    -- builtin: notify every on-duty cop + timed area blip
    local cops = FW.policePlayers()
    for i = 1, #cops do
        TriggerClientEvent('nzwl:dispatch:builtin', cops[i], data)
    end
end

Utils.debug('dispatch:', Dispatch.name)
