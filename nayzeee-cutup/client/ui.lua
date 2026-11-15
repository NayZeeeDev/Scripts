-- NUI bridge
UI = {}

function UI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function UI.Toast(title, msg, kind)
    UI.Send('toast', { title = title, msg = msg, kind = kind or 'info' })
end

function UI.Popup(text, sub, color, points)
    if not CU.Settings.hud.popups then return end
    UI.Send('popup', { text = text, sub = sub, color = color, points = points })
end

-- Everything the page needs to theme itself and label things
function UI.PushConfig()
    UI.Send('config', {
        hud = CU.Settings.hud,
        ui = CU.Settings.ui,
        playerPrefs = Config.UI.PlayerPrefs,
        presets = Config.UI.Presets,
        defaults = CU.Defaults,
        crewColors = Config.Crew.Colors,
        crewLimits = { name = Config.Crew.NameLength, tag = Config.Crew.TagLength, max = Config.Crew.MaxMembers },
        tiers = Config.Scoring.Tiers,
        ranks = Config.Ranks,
        wheel = Config.Wheel,
        keys = Config.Keys,
        serverName = Config.ServerName,
        runDuration = Config.Run.Duration,
    })
end

function UI.OpenMenu(tab)
    CU.MenuOpen = true
    SetNuiFocus(true, true)
    UI.Send('menu:open', {
        tab = tab or 'camera',
        settings = CU.Settings,
        profile = CU.Profile,
        wheelProfiles = Wheel and Wheel.GetProfiles() or {},
        cameraModes = Camera and Camera.Modes or {},
    })
end

function UI.CloseMenu()
    CU.MenuOpen = false
    SetNuiFocus(false, false)
    UI.Send('menu:close', {})
end

RegisterNUICallback('close', function(_, cb)
    UI.CloseMenu()
    cb({ ok = true })
end)

-- live settings changes from the menu (sliders preview instantly)
RegisterNUICallback('settings', function(data, cb)
    if type(data) == 'table' and data.settings then
        CU.Settings = Util.Merge(CU.Defaults, data.settings)
        CU.Settings.gameplay.density = Util.Clamp(CU.Settings.gameplay.density, 0.25, 1.5)
        if not Config.UI.PlayerPrefs then CU.Settings.ui = Util.DeepCopy(CU.Defaults.ui) end
        CU.Settings.ui.scale = Util.Clamp(CU.Settings.ui.scale, 0.8, 1.25)
        if CU.Trans.mode ~= CU.Settings.gameplay.transmission then
            Transmission.SetMode(CU.Settings.gameplay.transmission)
        end
        if data.save then CU.SaveSettings() end
        if Camera then Camera.SettingsChanged() end
        UI.PushConfig()
    end
    cb({ ok = true })
end)

RegisterNUICallback('leaderboard', function(data, cb)
    TriggerServerEvent('nayzeee-cutup:server:leaderboard', data.board or 'solo', tonumber(data.page) or 1)
    cb({ ok = true })
end)

RegisterNUICallback('crew', function(data, cb)
    TriggerServerEvent('nayzeee-cutup:server:crew', data.action, data.payload or {})
    cb({ ok = true })
end)

RegisterNUICallback('nuiReady', function(_, cb)
    UI.PushConfig()
    UI.Send('wheel:profiles', Wheel and Wheel.GetProfiles() or {})
    cb({ ok = true, resource = GetCurrentResourceName() })
end)

-- HUD feed (20 Hz)
function UI.PushHud()
    local veh = CU.Veh
    local run = CU.Run
    local speed, unit = CU.DisplaySpeed(CU.Speed)
    local rpmNorm = (veh ~= 0) and GetVehicleCurrentRpm(veh) or 0.0
    local pbPoints = math.max(CU.Profile.pbSolo or 0, CU.Profile.pbCrew or 0)
    local rank = Util.GetRank(pbPoints)

    UI.Send('hud', {
        active   = CU.Active and CU.IsDriver,
        run      = run ~= nil,
        score    = run and math.floor(run.points) or 0,
        combo    = run and math.floor(run.combo) or 0,
        speedMult= run and run.speedMult or 1.0,
        mult     = run and run.totalMult or 1.0,
        timer    = run and math.max(0, Config.Run.Duration - run.time) or Config.Run.Duration,
        hold     = run and run.holdPct or 0,
        hearts   = run and run.hearts or Config.Run.Hearts,
        maxHearts= Config.Run.Hearts,
        aggro    = CU.Bonus.aggro,
        physics  = CU.Bonus.physics,
        fpv      = CU.Bonus.fpv,
        sync     = {
            pct = CU.Sync.pct, flow = CU.Sync.flow, partner = CU.Sync.partner,
            crew = CU.Sync.crew, gap = CU.Sync.gap, gapMax = CU.Sync.gapMax, mates = CU.Sync.mates,
        },
        gear     = Transmission.DisplayGear(),
        trans    = CU.Trans.mode,
        rpm      = math.floor(rpmNorm * Config.Transmission.Redline / 5 + 0.5) * 5,
        rpmNorm  = rpmNorm,
        speed    = speed,
        unit     = unit,
        abs      = Transmission.absLight or false,
        tc       = Transmission.tcLight or false,
        pb       = pbPoints,
        pbMode   = (CU.Profile.pbCrew or 0) > (CU.Profile.pbSolo or 0) and 'CREW' or 'SOLO',
        position = CU.Profile.position or 0,
        rank     = rank,
        crew     = CU.Profile.crew,
        camera   = CU.Settings.camera.mode,
        wheel    = CU.Wheel.active,
    })
end

RegisterNUICallback('openBoard', function(_, cb)
    CU.MenuOpen = true
    SetNuiFocus(true, true)
    UI.Send('board:open', {})
    TriggerServerEvent('nayzeee-cutup:server:leaderboard', 'solo', 1)
    cb({ ok = true })
end)
