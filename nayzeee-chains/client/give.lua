-----------------------------------------------------------------
-- Giving chains (client): picking who, and answering an offer.
-- [Y] accept  [X] decline, rebindable in Settings > Key Bindings > FiveM
-----------------------------------------------------------------

Give = { offer = nil }

local cfg = Config.Give

--- kind = 'give' | 'puton' | 'swap'; slot = from the pockets (nil = the one you wear)
function Give.start(kind, slot)
    if not cfg.Enabled then return end
    local ped = Util.closestInFront(cfg.Distance or 2.5)
    if not ped then return CB.Notify(Config.Text.no_target, 'error') end
    local sid = Util.serverIdOf(ped)
    if sid then TriggerServerEvent('nzc:s:offer', kind, sid, slot) end
end

local function answer(yes)
    local o = Give.offer
    if not o then return end
    Give.offer = nil
    NUI.send('offer:hide')
    TriggerServerEvent('nzc:s:offerAnswer', o.id, yes)
end

RegisterNetEvent('nzc:c:offer', function(o)
    Give.offer = o
    o.hint = Config.Text.hint_offer
    NUI.send('offer:show', o)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    local id = o.id
    SetTimeout((o.timeout or 15) * 1000, function()
        if Give.offer and Give.offer.id == id then Give.offer = nil; NUI.send('offer:hide') end
    end)
end)

RegisterNetEvent('nzc:c:offerEnd', function(id)
    if Give.offer and Give.offer.id == id then Give.offer = nil; NUI.send('offer:hide') end
end)

RegisterNetEvent('nzc:c:giveAnim', function(other, role)
    local ped = PlayerPedId()
    local opp = Util.pedOf(other)
    if opp ~= 0 and DoesEntityExist(opp) then Util.face(ped, opp) end
    local a = role == 'give' and cfg.Anim or cfg.TakeAnim
    Util.playAnim(a, a.duration, 48)
end)

RegisterCommand('chainaccept', function() answer(true) end, false)
RegisterCommand('chaindecline', function() answer(false) end, false)
RegisterKeyMapping('chainaccept', 'Accept a chain offer', 'keyboard', 'Y')
RegisterKeyMapping('chaindecline', 'Decline a chain offer', 'keyboard', 'X')
