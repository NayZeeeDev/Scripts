-----------------------------------------------------------------
-- Equip / unequip / open animations
-----------------------------------------------------------------

Anim = {}

local busy = false

function Anim.isBusy() return busy end

--- Play one of the configured animations. Blocking.
--- Returns false if it could not run, so callers can carry on regardless.
--- `force` skips the enabled switch (the studio uses it to preview).
function Anim.play(name, force)
    local cfg = Config.Animations
    if not cfg or (not cfg.enabled and not force) then return false end

    local a = cfg[name]
    if not a or not a.dict or not a.anim then return false end
    if busy then return false end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedDeadOrDying(ped, true) then
        return false
    end

    if not Util.loadDict(a.dict) then return false end

    busy = true
    TriggerEvent('nayzeee-backpack:client:animStart', name, a.duration or 1000)
    if cfg.freeze then FreezeEntityPosition(ped, true) end

    TaskPlayAnim(ped, a.dict, a.anim, 3.0, -3.0, a.duration or 1000, a.flag or 49, 0, false, false, false)
    Wait(a.duration or 1000)

    StopAnimTask(ped, a.dict, a.anim, 3.0)
    RemoveAnimDict(a.dict)

    if cfg.freeze then FreezeEntityPosition(ped, false) end
    busy = false
    TriggerEvent('nayzeee-backpack:client:animEnd', name)

    return true
end

--- Fire and forget, for when the caller shouldn't wait.
function Anim.playAsync(name, force)
    CreateThread(function() Anim.play(name, force) end)
end
