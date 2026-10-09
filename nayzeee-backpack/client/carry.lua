-----------------------------------------------------------------
-- Carry poses
--
-- Purses and pocketbooks loop an UPPER BODY pose while worn, so the
-- legs keep the normal walk/run but the arm holds the bag properly
-- instead of swinging it around.
--
-- Costs nothing: one check every Config.Carry.checkInterval ms, and
-- only while a carry-style bag is actually on.
-----------------------------------------------------------------

Carry = { suspended = false }

if not Config.Carry or not Config.Carry.enabled then
    function Carry.preview() end
    function Carry.stopPreview() end
    return
end

local cfg = Config.Carry
local UNARMED = `WEAPON_UNARMED`
local FLAG = 49 -- loop + upper body + player keeps control
local SCRIPTED_ANIM_TASK = 134

local current = nil  -- pose table currently looping
local walkSet = nil  -- clipset we applied, so we only reset our own
local previewing = nil -- pose the studio / shop try-on is showing

local function wantedPose()
    if Carry.suspended then return nil end
    local st = LocalPlayer.state.nayzeee_backpack
    if not st or not st.bag or st.stowed then return nil end
    return Bags.poseFor(st.bag, st.pose)
end

--- Anything that should pause the pose for a moment.
local function blocked(ped)
    if IsPedInAnyVehicle(ped, true) then return true end
    if IsPedSwimming(ped) or IsPedClimbing(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) then return true end
    if IsPedJumping(ped) or IsPedVaulting(ped) or IsPedInCover(ped, false) then return true end
    if IsPedDeadOrDying(ped, true) or IsPedUsingAnyScenario(ped) then return true end
    if GetSelectedPedWeapon(ped) ~= UNARMED or IsPlayerFreeAiming(PlayerId()) then return true end
    if Anim.isBusy() then return true end
    if LocalPlayer.state.invBusy then return true end
    if lib.progressActive and lib.progressActive() then return true end
    return false
end

local function stopPose(ped, pose)
    if pose and IsEntityPlayingAnim(ped, pose.dict, pose.clip, 3) then
        StopAnimTask(ped, pose.dict, pose.clip, 2.0)
    end
end

local function setWalk(ped, on)
    if not cfg.walkStyle then return end
    if on and not walkSet then
        if Util.loadClipset(cfg.walkStyle) then
            SetPedMovementClipset(ped, cfg.walkStyle, 0.25)
            walkSet = cfg.walkStyle
        end
    elseif not on and walkSet then
        ResetPedMovementClipset(ped, 0.25)
        RemoveClipSet(walkSet)
        walkSet = nil
        Integrations.each('restoreWalk')
    end
end

local function playPose(ped, pose)
    if not Util.loadDict(pose.dict) then return false end
    TaskPlayAnim(ped, pose.dict, pose.clip, cfg.blendIn or 4.0, -2.0, -1, FLAG, 0.0, false, false, false)
    return true
end

CreateThread(function()
    local interval = cfg.checkInterval or 600

    while true do
        local pose = wantedPose()
        local ped = PlayerPedId()

        if pose ~= current then
            -- bag changed, came off, or the player picked another pose.
            -- Leave it alone if a preview is playing the same clip.
            local shared = previewing and current and previewing.dict == current.dict and previewing.clip == current.clip
            if not shared then stopPose(ped, current) end
            if current and not shared and current.dict ~= (pose and pose.dict) then RemoveAnimDict(current.dict) end
            current = pose
            setWalk(ped, pose ~= nil)
        end

        if current then
            local ours = IsEntityPlayingAnim(ped, current.dict, current.clip, 3)

            if blocked(ped) then
                if ours then stopPose(ped, current) end
            elseif not ours and not GetIsTaskActive(ped, SCRIPTED_ANIM_TASK) then
                -- nobody else is animating the ped, so take it back
                playPose(ped, current)
            end

            Wait(interval)
        else
            Wait(1500)
        end
    end
end)

-----------------------------------------------------------------
-- studio preview
-----------------------------------------------------------------

function Carry.preview(poseKey)
    local pose = Bags.pose(poseKey)
    local ped = PlayerPedId()
    Carry.stopPreview()
    if not pose then return false end
    if not playPose(ped, pose) then return false end
    previewing = pose
    return true
end

function Carry.stopPreview()
    if previewing then
        stopPose(PlayerPedId(), previewing)
        previewing = nil
    end
end

function Carry.isPreviewing() return previewing ~= nil end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    stopPose(ped, current)
    stopPose(ped, previewing)
    setWalk(ped, false)
end)
