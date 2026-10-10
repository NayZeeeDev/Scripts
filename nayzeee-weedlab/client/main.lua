--[[ Client state from the server, the HUD, Benson's texts, level ups, the lab tablet and startup ]]

Main = { state = { stage = 'none', labs = {}, level = 0 }, water = 0 }

function Main.refreshHud()
    if Interact.active or Dialogue.active then return end
    local st = Main.state
    local obj = st.objective
    if not obj then return UI.hud(false) end
    UI.hud({ quest = { title = obj.title, text = obj.text } })
end

RegisterNetEvent('nzwl:state', function(st)
    if GetInvokingResource() then return end
    local before = Main.state
    Main.state = st
    Main.water = st.water or Main.water
    local rv = st.labs and st.labs.rv
    if rv and rv.net ~= Labs.rvNet then Labs.setRV(rv.net) end
    Story.refresh(st)
    Labs.refreshDoors(st)
    Main.refreshHud()
    if before.level and st.level and st.level > before.level then
        PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
    end
end)

RegisterNetEvent('nzwl:xp', function(amount, why)
    if GetInvokingResource() then return end
    UI.send('xp', { amount = amount, why = why })
end)

RegisterNetEvent('nzwl:levelup', function(data)
    if GetInvokingResource() then return end
    UI.send('levelup', data)
end)

-- a text from Benson (an unknown number at first)
RegisterNetEvent('nzwl:text', function(data)
    if GetInvokingResource() then return end
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    UI.send('text', { from = data.title or data.from, lines = data.lines, timeout = 14 })
end)

RegisterNetEvent('nzwl:reset', function()
    if GetInvokingResource() then return end
    if Labs.inside then Labs.exit() end
end)

--[[ ─────────────── the lab tablet ─────────────── ]]
local function tabletData()
    local st = Main.state
    local lvl = st.level or 0
    local unlocks = {}
    for _, row in ipairs(Config.Store.items) do
        local need = Utils.itemLevel(row.item)
        if need > 0 then unlocks[#unlocks + 1] = { level = need, label = Utils.itemLabel(row.item), item = row.item, kind = row.cat } end
    end
    for _, id in ipairs(Config.LabOrder) do
        local L = Config.Labs[id]
        if (L.level or 0) > 0 then unlocks[#unlocks + 1] = { level = L.level, label = L.label, kind = 'lab' } end
    end
    table.sort(unlocks, function(a, b) return a.level == b.level and a.label < b.label or a.level < b.level end)
    local labs = {}
    for _, id in ipairs(Config.LabOrder) do
        local L = Config.Labs[id]
        local info = st.labs and st.labs[id] or {}
        local entrances = {}
        for i, e in ipairs(L.entrances or {}) do entrances[i] = e.label end
        labs[#labs + 1] = {
            id = id, label = L.label, icon = L.icon, level = L.level or 0, price = L.price, owned = info.owned == true,
            maxGrow = L.maxGrow, maxObjects = L.maxObjects, entrances = entrances, entrance = info.entrance,
            locked = lvl < (L.level or 0),
        }
    end
    return {
        level = lvl, xp = st.xp or 0, need = st.need, title = st.title, objective = st.objective,
        unlocks = unlocks, labs = labs, accounts = Config.Money.shopAccounts, towFee = Config.RV.towFee,
        water = Main.water, capacity = Config.WateringCan.capacity,
    }
end

local function gps(lab)
    if lab == 'rv' then
        local veh = Labs.rvVeh
        if veh and DoesEntityExist(veh) then
            local c = GetEntityCoords(veh)
            SetNewWaypoint(c.x, c.y)
            return UI.notify('GPS set to your RV', 'info')
        end
        return UI.notify('Your RV isn\'t nearby. Tow it if it\'s lost.', 'error')
    end
    local info = Main.state.labs and Main.state.labs[lab]
    local e = info and info.owned and Config.Labs[lab].entrances[info.entrance or 1]
    if e then
        SetNewWaypoint(e.door.x, e.door.y)
        UI.notify('GPS set to your ' .. Config.Labs[lab].label, 'info')
    end
end

function Main.tablet()
    if Interact.active or Dialogue.active or Placement.active then return end
    while true do
        local res = UI.panel('tablet', tabletData())
        if not res then return end
        if res.gps then
            gps(res.gps)
            return
        elseif res.tow then
            local ok, out = lib.callback.await('nzwl:rv:tow', false, res.account)
            if ok then
                SetNewWaypoint(out.x, out.y)
                UI.notify('Your RV was towed. GPS set.', 'success')
            elseif out then UI.notify(out, 'error') end
            return
        elseif res.buy then
            local ok, err = lib.callback.await('nzwl:lab:buy', false, res.buy, res.entrance, res.account)
            if ok then
                UI.notify(('The %s is yours. GPS set to the door.'):format(Config.Labs[res.buy].label), 'success', 8000)
                Wait(300)
                gps(res.buy)
                return
            end
            if err then UI.notify(err, 'error') end
            return
        else
            return
        end
    end
end

if Config.Tablet and Config.Tablet.command then
    RegisterCommand(Config.Tablet.command, function() Main.tablet() end, false)
    if Config.Tablet.key then
        RegisterKeyMapping(Config.Tablet.command, 'Weed lab tablet', 'keyboard', Config.Tablet.key)
    end
end

--[[ ─────────────── startup ─────────────── ]]
local booted = false
local function ready()
    if booted then return end
    booted = true
    TriggerServerEvent('nzwl:ready')
end

FW.onLoaded(function()
    booted = false
    SetTimeout(3000, ready)
end)

FW.onUnloaded(function()
    booted = false
    if Labs.inside then Labs.exit() end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2000)
    if FW.isLoaded() then ready() end
end)
