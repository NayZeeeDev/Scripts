-- Tiny self-contained callback layer (no framework dependency)
NZ = NZ or {}
local RES = GetCurrentResourceName()

if IsDuplicityVersion() then
    local handlers = {}
    function NZ.RegisterCallback(name, fn) handlers[name] = fn end

    RegisterNetEvent(RES .. ':cb:req', function(name, reqId, ...)
        local src = source
        local fn = handlers[name]
        if not fn then return TriggerClientEvent(RES .. ':cb:res', src, reqId) end
        local ok, a, b, c = pcall(fn, src, ...)
        if not ok then print(('^1[nayzeee-speaker] callback %s failed: %s^7'):format(name, a)) a, b, c = nil, nil, nil end
        TriggerClientEvent(RES .. ':cb:res', src, reqId, a, b, c)
    end)
else
    local pending, nextId = {}, 0
    RegisterNetEvent(RES .. ':cb:res', function(reqId, ...)
        local p = pending[reqId]
        if p then pending[reqId] = nil; p:resolve({ ... }) end
    end)

    function NZ.Callback(name, ...)
        nextId = nextId + 1
        local id = nextId
        local p = promise.new()
        pending[id] = p
        TriggerServerEvent(RES .. ':cb:req', name, id, ...)
        SetTimeout(15000, function()
            if pending[id] then pending[id] = nil; p:resolve({}) end
        end)
        return table.unpack(Citizen.Await(p))
    end
end
