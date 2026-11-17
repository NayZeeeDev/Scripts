if not NAYZEEE_LOCK_OK then return end

local function detect()
    local f = Config.Framework
    if f and f ~= 'auto' then return f end
    -- qbx_core also "provides" qb-core, so check it first
    if GetResourceState('qbx_core') ~= 'missing' then return 'qbox' end
    if GetResourceState('es_extended') ~= 'missing' then return 'esx' end
    if GetResourceState('qb-core') ~= 'missing' then return 'qb' end
    return 'none'
end

NZ.Framework = detect()
NZ.IsESX = NZ.Framework == 'esx'
NZ.IsQB = NZ.Framework == 'qb' or NZ.Framework == 'qbox'
NZ.IsQbox = NZ.Framework == 'qbox'
