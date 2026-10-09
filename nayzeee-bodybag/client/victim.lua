-- ═══════════════════════════════════════════════════════════════
--  VICTIM SIDE - what happens to YOU when you get bagged
-- ═══════════════════════════════════════════════════════════════
local bagged = false

local function restorePed()
    if not bagged then return end
    bagged = false
    HideHint()
    DoScreenFadeIn(600)
    local ped = cache.ped
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
end

RegisterNetEvent('nayzeee-bodybag:client:youGotBagged', function()
    if bagged then return end
    bagged = true
    -- full black screen (the bottom prompt stays visible over it so it doesn't read as a loading screen)
    DoScreenFadeOut(600)
    ShowHint('You are inside a body bag...')

    CreateThread(function()
        local ped = cache.ped
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        while bagged do
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true) -- chat stays available for /me etc
            EnableControlAction(0, 249, true) -- push to talk
            Wait(0)
        end
    end)

    -- revived while inside (admin /revive, medic, bleed-out)? -> tell the server so you climb out
    if Config.ReleaseOnRevive and Config.OnlyDeadBodies then
        CreateThread(function()
            Wait(5000) -- give the ambulance script a moment to settle
            local aliveFor = 0
            while bagged do
                Wait(1000)
                aliveFor = IsPlayerTrulyDead(cache.ped) and 0 or aliveFor + 1
                if aliveFor >= 3 then
                    TriggerServerEvent('nayzeee-bodybag:server:victimRevived')
                    aliveFor = -10 -- don't spam if the server says no
                end
            end
        end)
    end
end)

-- follow the bag: server pushes coords so victim stays with their body (and in voice range)
RegisterNetEvent('nayzeee-bodybag:client:syncToBag', function(coords)
    if not bagged then return end
    SetEntityCoordsNoOffset(cache.ped, coords.x, coords.y, coords.z, false, false, false)
end)

-- released (taken out of the bag / bag destroyed / revived)
RegisterNetEvent('nayzeee-bodybag:client:released', restorePed)

-- body destroyed -> forced respawn (only when Config.CK.OnDisposal = 'respawn')
RegisterNetEvent('nayzeee-bodybag:client:forceRespawn', function()
    restorePed()
    Config.Hooks.Respawn()
    Config.Notify('Your body was destroyed. You remember nothing after your death. (NLR applies)', 'error')
end)

-- exports['nayzeee-bodybag']:IsBagged() -> true while YOU are inside a bag/crate/trunk
exports('IsBagged', function() return bagged end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then restorePed() end
end)

-- ═══════════════════════════════════════════════════════════════
--  CK CONSENT DIALOG
-- ═══════════════════════════════════════════════════════════════
local consentOpen = false

RegisterNetEvent('nayzeee-bodybag:client:ckConsent', function(requester, reason, timeout)
    consentOpen = true
    local alert = lib.alertDialog({
        header = 'CHARACTER KILL REQUEST',
        content = ('**%s** wants to permanently kill this character.\n\n%sThis is **irreversible**. You have %ss to answer.\n\nDo you consent?')
            :format(requester, (reason and reason ~= '') and ('Reason: *' .. reason .. '*\n\n') or '', timeout or 60),
        centered = true, cancel = true,
        labels = { confirm = 'ACCEPT CK', cancel = 'Decline' },
    })
    if not consentOpen then return end -- expired while the dialog was open
    consentOpen = false
    TriggerServerEvent('nayzeee-bodybag:server:ckConsentResult', alert == 'confirm')
end)

RegisterNetEvent('nayzeee-bodybag:client:ckConsentExpired', function()
    if not consentOpen then return end
    consentOpen = false
    lib.closeAlertDialog()
    Config.Notify('The CK request expired.', 'inform', 'CK')
end)

-- CK kick/deletion is handled fully server-side (server/ck.lua)
