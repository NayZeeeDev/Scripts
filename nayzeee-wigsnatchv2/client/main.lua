-- Boot, vault, wig making / dyeing callbacks and misc events

local registered = false

local function registerTargets()
    if registered or CB.Target == 'none' then return end
    registered = true
    CB.AddGlobalPlayer(Snatch.TargetOptions)
    CB.AddGlobalPlayer(Cutting.TargetOptions)
    CB.AddGlobalPlayer(Restrain.TargetOptions)
    CB.AddGlobalPlayer(Interact.TargetOptions)
end

local function boot()
    registerTargets()
    PhoneBridge.Init()
    TriggerServerEvent('nz-wig:s:styleNames')
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
    if Snatch.busy or Tables.busy or Restrain.acting or Restrain.tied or Restrain.held or (NUI.app and NUI.app ~= 'vault') then
        return CB.Notify(L('busy'), 'error')
    end
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

RegisterNUICallback('nearby', function(d, cb)
    cb(lib.callback.await('nz-wig:nearby', false, d and d.range) or {})
end)

RegisterNUICallback('offer', function(d, cb)
    local ok, msg = lib.callback.await('nz-wig:offer', false, d and d.target, d and d.key, d and d.price)
    CB.Notify(msg or L('invalid'), ok and 'success' or 'error')
    cb({ ok = ok })
end)

-- put a wig from the vault on someone close by
RegisterNUICallback('vaultPutOn', function(d, cb)
    if d and d.key and d.target then
        NUI.CloseApp()
        TriggerServerEvent('nz-wig:s:putOn', tonumber(d.target), d.key)
    end
    cb(1)
end)

-- making / dyeing (from the wig table window) ----------------------------------------------------

-- with wig tables on, making and dyeing wigs happens at the table you're standing at
local function atTable()
    return Config.Tables.Enabled
end

RegisterNUICallback('craft', function(d, cb)
    cb(1)
    if not d or type(d.keys) ~= 'table' then return end
    NUI.CloseSide()
    if atTable() then return Tables.Job('craft', { keys = d.keys }, d.view) end
    TriggerServerEvent('nz-wig:s:craft', d.keys)
end)

RegisterNUICallback('dyeWig', function(d, cb)
    cb(1)
    if not d or not d.key then return end
    NUI.CloseSide()
    if atTable() then return Tables.Job('dye', { key = d.key, c = d.c, h = d.h }, d.view) end
    TriggerServerEvent('nz-wig:s:dye', d.key, d.c, d.h)
end)

-- using a hair dye from the inventory: the colour picker for your own hair
RegisterNetEvent('nz-wig:c:hairDye', function(data)
    if NUI.app or Snatch.busy then return end
    data.palette = HairPalette()
    NUI.Side('dye', data)
end)

RegisterNUICallback('dyeClose', function(_, cb)
    NUI.CloseSide()
    cb(1)
end)

RegisterNUICallback('dyeSelf', function(d, cb)
    if d then TriggerServerEvent('nz-wig:s:dyeSelf', d.c, d.h) end
    cb(1)
end)

RegisterNUICallback('rinse', function(_, cb)
    TriggerServerEvent('nz-wig:s:rinse')
    cb(1)
end)

-- the game's hair colour palette, as hex, for the dye picker and the phone app
local palette
function HairPalette()
    if not palette then
        palette = {}
        for i = 0, GetNumHairColors() - 1 do
            local r, g, b = GetPedHairRgbColor(i)
            palette[#palette + 1] = ('#%02x%02x%02x'):format(r, g, b)
        end
    end
    return palette
end

RegisterNUICallback('hairPalette', function(_, cb) cb(HairPalette()) end)

RegisterNetEvent('nz-wig:c:crafted', function(d)
    if Tables.busy then return end   -- made at a table: the table shows its own result card
    NUI.Send('reveal', { wig = d.wig, xp = d.xp, crafted = true })
end)

-- one-shot animations triggered by the server ------------------------------------------------

RegisterNetEvent('nz-wig:c:anim', function(kind, other)
    if kind == 'wear' then
        PlayAnim({ dict = Config.Wig.WearAnim.dict, clip = Config.Wig.WearAnim.clip, flag = 48 }, Config.Wig.WearAnim.duration)
    elseif kind == 'glue' then
        PlayAnim({ dict = Config.Glue.Anim.dict, clip = Config.Glue.Anim.clip, flag = 49 }, Config.Glue.Anim.duration)
    elseif kind == 'apply' then
        local o = other and PedOf(other) or 0
        if o ~= 0 then FaceEntity(PlayerPedId(), o) end
        PlayAnim({ dict = Config.Anims.Apply.dict, clip = Config.Anims.Apply.clip, flag = 48 }, 1500)
    end
end)

-- positional sound for everyone nearby
RegisterNetEvent('nz-wig:c:sound', function(s)
    local me = GetEntityCoords(PlayerPedId())
    local dist = #(me - vec3(s.coords.x, s.coords.y, s.coords.z))
    if dist > s.range then return end
    NUI.Send('sound', { name = s.sound, volume = math.max(0.05, 1.0 - dist / s.range), duration = s.duration })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    Snatch.Cleanup()
    Cutting.Cleanup()
    Restrain.Cleanup()
    Phone.Cleanup()
    Studio.Cleanup()
end)

exports('IsBusy', function() return Snatch.busy or Restrain.acting or Restrain.tied or Restrain.held ~= nil end)
exports('OpenVault', openVault)
