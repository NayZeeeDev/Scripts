--[[
    Network glue, loaded on both sides before anything else that talks to the other side.

    RES is the resource's folder name. Every event is prefixed with it (so a renamed copy never clashes
    with this one) and every file uses this one definition.

    Callbacks: a tiny request / response layer on top of net events, so nothing depends on a framework.
]]
RES = GetCurrentResourceName()
NZ = NZ or {}

if IsDuplicityVersion() then
    local handlers = {}
    function NZ.RegisterCallback(name, fn) handlers[name] = fn end

    RegisterNetEvent(RES .. ':cb:req', function(name, reqId, ...)
        local src = source
        local fn = handlers[name]
        if not fn then return TriggerClientEvent(RES .. ':cb:res', src, reqId) end
        local ok, a, b, c = pcall(fn, src, ...)
        if not ok then
            print(('^1[%s] callback %s failed: %s^7'):format(RES, name, a))
            a, b, c = nil, nil, nil
        end
        TriggerClientEvent(RES .. ':cb:res', src, reqId, a, b, c)
    end)
else
    local pending, nextId = {}, 0

    RegisterNetEvent(RES .. ':cb:res', function(reqId, ...)
        local p = pending[reqId]
        if p then pending[reqId] = nil p:resolve(table.pack(...)) end
    end)

    --[[
        How long to wait for an answer. Most come back at once; these look songs up on the web, and
        with no API key and slow or dead search hosts (9 s each, then 12 s for youtube.com) one lookup
        can take most of a minute. Giving up sooner would show "nothing found" while the server
        is still working, and throw its real answer away.
    ]]
    local WAIT = { search = 60000, ['shop:preview'] = 90000, ['pl:import'] = 150000, ['pl:prompted'] = 180000 }

    -- table.pack keeps a leading nil (callbacks answer `nil, 'reason'`), a plain { ... } may not
    function NZ.Callback(name, ...)
        nextId = nextId + 1
        local id, p = nextId, promise.new()
        pending[id] = p
        TriggerServerEvent(RES .. ':cb:req', name, id, ...)
        SetTimeout(WAIT[name] or 15000, function()
            if pending[id] then pending[id] = nil p:resolve({ n = 0 }) end
        end)
        local r = Citizen.Await(p)
        return table.unpack(r, 1, r.n)
    end
end
