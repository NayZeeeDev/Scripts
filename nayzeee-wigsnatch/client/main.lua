-- Boot, vault and misc events

local registered = false

local function registerTargets()
    if registered or CB.Target == 'none' then return end
    registered = true
    CB.AddGlobalPlayer(Snatch.TargetOptions)
    if #Tools.TargetOptions > 0 then CB.AddGlobalPlayer(Tools.TargetOptions) end
end

local function boot()
    registerTargets()
    -- give the appearance script time to dress the ped, then ask for our layer
    SetTimeout(2500, function() TriggerServerEvent('nz-wig:s:ready') end)
end

CB.OnLoaded(boot)
CB.OnUnloaded(function()
    Hair.state, Hair.applied, Hair.natural = nil, nil, nil
end)

CreateThread(function()
    -- resource (re)started while already in the city
    if CB.IsLoaded() then boot() end
end)

RegisterNetEvent('nz-wig:c:notify', function(msg, kind, duration)
    CB.Notify(msg, kind, duration)
end)

-- vault -------------------------------------------------------------------------------------

local function openVault(tab)
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    NUI.Open('vault', { tab = tab or 'profile' })
end

RegisterCommand(Config.Vault.Command, function() openVault() end, false)
if Config.Vault.Keybind then
    RegisterKeyMapping(Config.Vault.Command, 'Open the wig vault', 'keyboard', Config.Vault.Keybind)
end

RegisterNetEvent('nz-wig:c:openVault', function(tab) openVault(tab) end)

RegisterNetEvent('nz-wig:c:refresh', function()
    if NUI.app then NUI.Send('app:refresh', { view = NUI.app }) end
end)

RegisterNUICallback('vaultFetch', function(_, cb)
    cb(lib.callback.await('nz-wig:vault', false) or false)
end)

RegisterNUICallback('wear', function(d, cb)
    if d and d.key then
        NUI.CloseApp()
        TriggerServerEvent('nz-wig:s:wear', d.key)
    end
    cb(1)
end)

RegisterNUICallback('unwear', function(_, cb)
    NUI.CloseApp()
    TriggerServerEvent('nz-wig:s:unwear')
    cb(1)
end)

RegisterNUICallback('repair', function(d, cb)
    if d and d.key then TriggerServerEvent('nz-wig:s:repair', d.key) end
    cb(1)
end)

RegisterNUICallback('placeBounty', function(d, cb)
    local ok, msg = lib.callback.await('nz-wig:placeBounty', false, d and d.identifier, d and d.amount)
    CB.Notify(msg or L('invalid'), ok and 'success' or 'error')
    cb({ ok = ok })
end)

RegisterNUICallback('nearby', function(_, cb)
    cb(lib.callback.await('nz-wig:nearby', false) or {})
end)

RegisterNUICallback('offer', function(d, cb)
    local ok, msg = lib.callback.await('nz-wig:offer', false, d and d.target, d and d.key, d and d.price)
    CB.Notify(msg or L('invalid'), ok and 'success' or 'error')
    cb({ ok = ok })
end)

-- one-shot animations triggered by the server ------------------------------------------------

RegisterNetEvent('nz-wig:c:anim', function(kind)
    if kind == 'wear' then
        PlayAnim({ dict = Config.Wig.WearAnim.dict, clip = Config.Wig.WearAnim.clip, flag = 48 }, Config.Wig.WearAnim.duration)
    elseif kind == 'glue' then
        PlayAnim({ dict = Config.Glue.Anim.dict, clip = Config.Glue.Anim.clip, flag = 49 }, Config.Glue.Anim.duration)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    Snatch.Cleanup()
    Tools.Cleanup()
    Buyer.Cleanup()
    Barber.Cleanup()
end)

exports('IsBusy', function() return Snatch.busy or Tools.running end)
exports('OpenVault', openVault)
