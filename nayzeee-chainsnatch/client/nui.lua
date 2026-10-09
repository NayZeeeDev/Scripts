-----------------------------------------------------------------
-- NUI glue, the registry, small shared events
-----------------------------------------------------------------

NUI = { hintText = nil }

function NUI.send(action, data) SendNUIMessage({ action = action, data = data }) end

--- Bottom-centre key hint bar. Text uses <kc>KEY</kc> for key caps. nil hides it.
function NUI.hint(text, id)
    if text == NUI.hintText then return end
    NUI.hintText = text
    NUI.send('hint', { text = text, id = id })
end

local function init()
    NUI.send('init', {
        scale = Config.UI.Scale or 1.0, toasts = Config.UI.Toasts or 'top-right',
        self = GetCurrentResourceName(), props = Config.PropsResource,
        inventory = GetResourceState('ox_inventory') ~= 'missing' and 'ox_inventory' or nil,
    })
end

RegisterNetEvent('nzc:c:registry', function(list)
    Chains.set(list)
    TriggerEvent('nzc:registry')
end)

RegisterNetEvent('nzc:c:notify', function(msg, kind, duration) CB.Notify(msg, kind, duration) end)

RegisterNetEvent('nzc:c:dispatch', function(coords)
    pcall(Config.Dispatch, coords, GetPlayerServerId(PlayerId()))
end)

-- one-shot animations the server asks for
RegisterNetEvent('nzc:c:anim', function(kind)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
    if kind == 'wear' then Util.playAnim(Config.Wear.Anim, Config.Wear.Anim.duration, 48)
    elseif kind == 'pickup' then Util.playAnim(Config.Drops.PickupAnim, Config.Drops.PickupAnim.duration, 48)
    elseif kind == 'catch' then Util.playAnim({ dict = 'mp_common', clip = 'givetake1_b' }, 1200, 48)
    elseif kind == 'snatch' then Util.playAnim(Config.Snatch.Anim, Config.Snatch.Anim.duration, 48)
    elseif kind == 'snatched' then SetTimeout(500, function() Util.playAnim(Config.Snatch.Reaction, Config.Snatch.Reaction.duration, 48) end)
    end
end)

local function ready()
    init()
    TriggerServerEvent('nzc:s:registry')
    TriggerServerEvent('nzc:s:drops')
    TriggerServerEvent('nzc:s:ready')
end

CB.OnLoaded(function() SetTimeout(1000, ready) end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Wait(500)
    init()
    TriggerServerEvent('nzc:s:registry')
    TriggerServerEvent('nzc:s:drops')
    if CB.IsLoaded() then TriggerServerEvent('nzc:s:ready') end
end)
