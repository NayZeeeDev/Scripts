-----------------------------------------------------------------
-- Animations
-----------------------------------------------------------------

Anim = {}

local busy = false

function Anim.isBusy() return busy end

local function loadDict(dict)
    if not dict or HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeout then
            print(('^3[nayzeee-backpack] anim dict "%s" did not load^0'):format(dict))
            return false
        end
    end
    return true
end

--- Play one of the configured animations. Blocking.
--- Returns false if it could not run, so callers can carry on regardless.
function Anim.play(name)
    local cfg = Config.Animations
    if not cfg or not cfg.enabled then return false end

    local a = cfg[name]
    if not a or not a.dict or not a.anim then return false end
    if busy then return false end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedDeadOrDying(ped, true) then
        return false
    end

    if not loadDict(a.dict) then return false end

    busy = true
    if cfg.freeze then FreezeEntityPosition(ped, true) end

    TaskPlayAnim(ped, a.dict, a.anim, 3.0, -3.0, a.duration, a.flag or 49, 0, false, false, false)
    Wait(a.duration or 1000)

    StopAnimTask(ped, a.dict, a.anim, 3.0)
    RemoveAnimDict(a.dict)

    if cfg.freeze then FreezeEntityPosition(ped, false) end
    busy = false

    return true
end

--- Fire and forget, for when the caller shouldn't wait.
function Anim.playAsync(name)
    CreateThread(function() Anim.play(name) end)
end
