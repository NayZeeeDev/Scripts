-- Custom crosshair. While you aim a gun the HUD draws its own and GTA's reticle is hidden for those frames only.
-- Idle (unarmed): one native every 250 ms. Holding a gun: a few natives every 50 ms. Per-frame only while aiming.
if not Config.Crosshair.enabled then return end

local player = { enabled = true, always = false }

function NHUD.setCrosshair(s)
    if type(s) ~= 'table' then return end
    player.enabled = s.enabled ~= false
    player.always = s.always == true
end

local SNIPER = `GROUP_SNIPER`

CreateThread(function()
    local pid = PlayerId()
    local showing = false
    while true do
        local ped = cache.ped
        local armed = player.enabled and NHUD.visible and HudBridge.loaded and IsPedArmed(ped, 4)
        local aiming = armed and IsPlayerFreeAiming(pid)
        local want = false
        if armed and (aiming or player.always) then
            -- sniper scopes draw their own reticle
            want = not (aiming and GetWeapontypeGroup(GetSelectedPedWeapon(ped)) == SNIPER and IsFirstPersonAimCamActive())
        end
        if want ~= showing then
            showing = want
            NHUD.set('ch', want)
            NHUD.flush()
        end
        if aiming then
            HideHudComponentThisFrame(14)
            Wait(0)
        else
            Wait(armed and 50 or 250)
        end
    end
end)
