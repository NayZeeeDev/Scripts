--[[
    NAYZEEE AMBULANCE - Patient data callbacks                     ARCHITECTURE §4.3

    lib.callback (ox_lib):
      nza:patient:get   (target)          → medic snapshot | nil, err
      nza:patient:watch (target, on)      → bool   (watchers get 'nza:patient:update' every watchRate ms)
      nza:self:get      ()                → self snapshot | nil   (loads the player's record when missing;
                                                                    rate limited to 4/s, then cached only)
      nza:records:get   (target, limit)   → treatment history rows | nil, err   (perm 'assess', same view rules)

    View rules (NZA.Core.CanView): permission 'assess' AND server-side distance ≤
    Config.Physiology.examDistance, OR the medic is in the same treatment bay
    (patient.meta.bay == the medic's own patient meta.bay, set server-side with
    NZA.Patients.SetMeta(medicPid, 'bay', id)), OR the patient is in a hospital bed
    (patient.meta.bed set) and the medic is within 6 m.
    Errors: 'no_patient' 'no_perm' 'too_far' 'rate'
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Core = NZA.Core or {}
NZA.Patients = NZA.Patients or {}
local Core = NZA.Core
local P = NZA.Patients

local BED_RANGE = 6.0

function Core.CanView(src, p, slack)
    src = tonumber(src)
    if not p then return false, 'no_patient' end
    if src == 0 then return true end
    if not src then return false, 'no_perm' end
    if not NZA.Staff.Can(src, 'assess') then return false, 'no_perm' end
    if p.kind == 'player' and p.src == src then return true end
    slack = slack or 0
    local maxD = ((Config.Physiology and Config.Physiology.examDistance) or 4.0) + slack
    local dist = Core.DistanceTo(src, p)
    if dist <= maxD then return true end
    local bay = p.meta and p.meta.bay
    if bay ~= nil then
        -- only server-side meta counts: player state bags can be written by the client
        local me = P.GetBySource(src)
        if me and me.meta.bay == bay then return true end
    end
    if p.meta and p.meta.bed and dist <= BED_RANGE + slack then return true end
    return false, 'too_far'
end

lib.callback.register('nza:patient:get', function(src, target)
    if not Core.Rate('nza:patient:get', src, 12, 1000) then return nil, 'rate' end
    local p = P.Resolve(target)
    if not p then return nil, 'no_patient' end
    local ok, err = Core.CanView(src, p)
    if not ok then return nil, err end
    return P.Snapshot(p, 'medic')
end)

lib.callback.register('nza:patient:watch', function(src, target, on)
    if not Core.Rate('nza:patient:watch', src, 10, 1000) then return false end
    local p = P.Resolve(target)
    if not p then return false end
    if not on then
        P.Watch(p, src, false)
        return true
    end
    if not Core.CanView(src, p) then return false end
    return P.Watch(p, src, true)
end)

lib.callback.register('nza:self:get', function(src)
    if not Core.Rate('nza:self:get', src, 4, 1000) then
        local cached = P.GetBySource(src)
        return cached and P.Snapshot(cached, 'self') or nil
    end
    local p = P.GetBySource(src) or P.LoadPlayer(src)
    if not p then return nil end
    return P.Snapshot(p, 'self')
end)

lib.callback.register('nza:records:get', function(src, target, limit)
    if not Core.Rate('nza:records:get', src, 3, 2000) then return nil, 'rate' end
    local p = P.Resolve(target)
    if not p then return nil, 'no_patient' end
    local ok, err = Core.CanView(src, p)
    if not ok then return nil, err end
    if p.kind ~= 'player' or not p.identifier then return {} end
    return NZA.Records.Get(p.identifier, math.min(100, tonumber(limit) or 25))
end)
