--[[ Client state from the server, the HUD (journal + deals) and startup ]]

Main = { state = { stage = 'none', deals = {}, orders = {}, dealers = {} }, water = 0 }

function Main.refreshHud()
    if Interact.active or Dialogue.active then return end
    local st = Main.state
    local deals = {}
    for _, d in ipairs(st.deals or {}) do
        local spot = Config.Spots[d.spot]
        deals[#deals + 1] = { title = 'Deal for ' .. d.name, text = ('%dx %s, %s'):format(d.qty, d.product, spot and spot.label or '?'), exp = d.exp }
    end
    if st.sample then
        local spot = Config.Spots[st.sample.spot]
        deals[#deals + 1] = { title = 'Sample for ' .. st.sample.name, text = spot and spot.label or '', sample = true }
    end
    local q = st.quest
    if not q and #deals == 0 then return UI.hud(false) end
    UI.hud({
        quest = q and { title = q.title, text = q.text, n = q.n, need = q.need } or nil,
        deals = deals, now = st.now, skew = (st.now or Utils.now()) - Utils.now(),
    })
end

RegisterNetEvent('nzde:state', function(st)
    if GetInvokingResource() then return end
    local before = Main.state
    Main.state = st
    Main.water = st.water or Main.water
    if st.app and not PhoneBridge.installed then PhoneBridge.Install() end
    if st.rv and st.rv.net ~= RV.net then RV.setNet(st.rv.net) end
    Story.refresh(st)
    Customers.refresh(st)
    Dealers.refresh(st)
    Deliveries.refresh(st)
    Main.refreshHud()
    if before.level and st.level and st.level > before.level then
        PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
    end
end)

RegisterNetEvent('nzde:xp', function(amount, why)
    if GetInvokingResource() then return end
    UI.send('xp', { amount = amount, why = why })
end)

RegisterNetEvent('nzde:levelup', function(data)
    if GetInvokingResource() then return end
    UI.send('levelup', data)
end)

RegisterNetEvent('nzde:reset', function()
    if GetInvokingResource() then return end
    if RV.inside then RV.exit() end
    PhoneBridge.Uninstall()
end)

local booted = false
local function ready()
    if booted then return end
    booted = true
    TriggerServerEvent('nzde:ready')
end

FW.onLoaded(function()
    booted = false
    SetTimeout(3000, ready)
end)

FW.onUnloaded(function()
    booted = false
    if RV.inside then RV.exit() end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2000)
    if FW.isLoaded() then ready() end
end)
