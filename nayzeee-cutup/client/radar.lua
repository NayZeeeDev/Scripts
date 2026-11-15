-- Threat arrows: players outside your crew closing in on you. They orbit your car
-- (on screen) and drop off once the player is past you.
Radar = {}

local wasShowing = false

function Radar.Update()
    local cfg = Config.Radar
    if not cfg.Enabled or not CU.Active or CU.Veh == 0 or not CU.Settings.gameplay.showArrows then
        if wasShowing then UI.Send('arrows', {}) wasShowing = false end
        return
    end
    local myVeh = CU.Veh
    local arrows = {}
    for _, o in ipairs(Crew.Others()) do
        if not o.crew and o.dist < cfg.Range and DoesEntityExist(o.veh) then
            local p = GetEntityCoords(o.veh)
            local lo = GetOffsetFromEntityGivenWorldCoords(myVeh, p.x, p.y, p.z)
            if lo.y < cfg.AheadClear then
                local closing = CU.Speed - GetEntitySpeed(o.veh)
                arrows[#arrows + 1] = {
                    angle = math.deg(math.atan(lo.x, lo.y)),     -- 0 ahead, 90 right, 180 behind
                    intensity = Util.Clamp(1.0 - o.dist / cfg.Range, 0.1, 1.0),
                    closing = closing < -1.0,                     -- they're gaining on you
                    name = o.name,
                    dist = math.floor(o.dist),
                }
            end
        end
    end
    UI.Send('arrows', arrows)
    wasShowing = #arrows > 0
end
