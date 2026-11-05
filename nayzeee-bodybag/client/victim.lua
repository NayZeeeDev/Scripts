-- ═══════════════════════════════════════════════════════════════
--  VICTIM SIDE - what happens to YOU when you get bagged
--  Dark screen + a live panel that tells you what's going on.
-- ═══════════════════════════════════════════════════════════════
local bagged = false
local status = 'bodybag'
local baggedAtTimer = 0   -- GetGameTimer() when we were bagged (corrected by the server)

local STATUS_TEXT = {
    bodybag = 'Zipped inside a body bag',
    crate   = 'Sealed inside a military crate',
    coffin  = 'Lying in a coffin',
    carried = 'Someone is carrying you...',
    trunk   = 'Locked in a car trunk - you feel it moving',
    barrel  = 'Stuffed inside a metal barrel',
    burning = 'The barrel is getting hot...',
}

local function elapsed()
    return math.floor((GetGameTimer() - baggedAtTimer) / 1000)
end

local function fateLine()
    if Config.CK.Enabled and Config.CK.OnDisposal == 'ck' then
        return 'If your body is destroyed, this character dies for good.'
    end
    return 'If your body is destroyed, you wake up in hospital (NLR).'
end

local function panelText()
    local lines = {
        '**YOU ARE DEAD**',
        STATUS_TEXT[status] or STATUS_TEXT.bodybag,
        'Time: ' .. FormatTime(elapsed()),
        fateLine(),
    }
    local after = (Config.Victim.GiveUpAfter or 0) * 60
    if after > 0 then
        local left = after - elapsed()
        lines[#lines + 1] = left > 0 and ('/%s unlocks in %s'):format(Config.Victim.GiveUpCommand, FormatTime(left))
            or ('Type /%s to stop waiting'):format(Config.Victim.GiveUpCommand)
    end
    lines[#lines + 1] = 'Chat + push-to-talk still work'
    return table.concat(lines, '  \n')
end

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
    bagged, status, baggedAtTimer = true, 'bodybag', GetGameTimer()
    DoScreenFadeOut(600)

    -- frozen, invisible, no controls except chat + push-to-talk
    CreateThread(function()
        local ped = cache.ped
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        while bagged do
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true) -- chat
            EnableControlAction(0, 249, true) -- push to talk
            Wait(0)
        end
    end)

    -- the status panel (bottom of the black screen)
    CreateThread(function()
        local last
        while bagged do
            local text = Config.Victim.StatusPanel and panelText() or 'You are inside a body bag...'
            if text ~= last then ShowHint(text) last = text end
            Wait(1000)
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

-- server tells us what's happening to our body
RegisterNetEvent('nayzeee-bodybag:client:victimStatus', function(newStatus, serverElapsed)
    if not bagged then return end
    status = newStatus
    if serverElapsed then baggedAtTimer = GetGameTimer() - serverElapsed * 1000 end
    if newStatus == 'burning' then
        Config.Notify('You smell smoke. The barrel is on fire.', 'error')
    end
end)

-- follow the bag: server pushes coords so victim stays with their body (and in voice range)
RegisterNetEvent('nayzeee-bodybag:client:syncToBag', function(coords)
    if not bagged then return end
    SetEntityCoordsNoOffset(cache.ped, coords.x, coords.y, coords.z, false, false, false)
end)

-- released (taken out of the bag / bag destroyed / revived)
RegisterNetEvent('nayzeee-bodybag:client:released', function()
    if not bagged then return end
    restorePed()
    Config.Notify('You\'re out of the bag.', 'inform')
end)

-- body destroyed -> forced respawn (only when Config.CK.OnDisposal = 'respawn')
RegisterNetEvent('nayzeee-bodybag:client:forceRespawn', function()
    restorePed()
    Config.Hooks.Respawn()
    Config.Notify('Your body was destroyed. You remember nothing after your death. (NLR applies)', 'error')
end)

-- ═══════════════════════════════════════════════════════════════
--  /acceptfate - stop waiting
-- ═══════════════════════════════════════════════════════════════
if (Config.Victim.GiveUpAfter or 0) > 0 then
    RegisterCommand(Config.Victim.GiveUpCommand, function()
        if not bagged then return Config.Notify('You\'re not inside a body bag.', 'error') end
        local left = Config.Victim.GiveUpAfter * 60 - elapsed()
        if left > 0 then return Config.Notify(('You can do this in %s.'):format(FormatTime(left)), 'error') end

        local ck = Config.CK.Enabled and Config.CK.OnDisposal == 'ck'
        local answer = lib.alertDialog({
            header = 'Accept your fate?',
            content = ck and 'Your character **dies permanently** right now (CK). You will be disconnected.\n\nYour body stays where it is.'
                or 'You wake up in hospital and remember nothing (NLR).\n\nYour body stays where it is.',
            centered = true, cancel = true,
            labels = { confirm = ck and 'Accept death' or 'Wake up', cancel = 'Keep waiting' },
        })
        if answer == 'confirm' then TriggerServerEvent('nayzeee-bodybag:server:acceptFate') end
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. Config.Victim.GiveUpCommand, 'Inside a body bag: stop waiting')
end

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
