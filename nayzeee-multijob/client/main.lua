--[[
    NAYZEEE MULTIJOB - Client Main
    Version: 1.0.0
    Discord: discord.gg/nayzeeedev

    Duty, jobs and permissions are decided by the server. The client asks,
    then mirrors the state the server sends back.
]]

if not NAYZEEE_LOCK_OK then return end

local isUIOpen = false
local isAdminOpen = false
local PlayerJob = Config.DefaultJob.name
local PlayerGrade = 0
local PlayerName = nil
local PlayerJobs = {}
local PlayerFavorites = {}
local PlayerStats = {}
local PlayerSchedules = {}
local PlayerShifts = {}

local isOnDuty = false
local afkPaused = false
local dutyStartTime = 0
local lastActivity = GetGameTimer()
local awaitingAutoClockOut = false
local autoClockOutSentAt = 0

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER DATA
-- ═══════════════════════════════════════════════════════════════════════════

local function DutySeconds()
    return isOnDuty and (GetGameTimer() - dutyStartTime) / 1000 or 0
end

local function ApplyPlayerData(data)
    PlayerJobs = data.jobs or {}
    PlayerFavorites = data.favorites or {}
    PlayerStats = data.stats or { jobs = {} }
    PlayerSchedules = data.schedules or {}
    PlayerShifts = data.shifts or {}
    PlayerJob = data.currentJob or PlayerJob
    PlayerGrade = data.currentGrade or 0
    PlayerName = data.name or PlayerName
    isOnDuty = data.isOnDuty == true
    afkPaused = data.afkPaused == true
    dutyStartTime = GetGameTimer() - math.floor((tonumber(data.dutyTime) or 0) * 1000)
end

local function MenuPayload()
    return {
        currentJob = PlayerJob,
        currentGrade = PlayerGrade,
        jobs = PlayerJobs,
        favorites = PlayerFavorites,
        stats = PlayerStats,
        schedules = PlayerSchedules,
        shifts = PlayerShifts,
        categories = Config.Categories,
        defaultJob = Config.DefaultJob.name,
        isOnDuty = isOnDuty,
        afkPaused = afkPaused,
        isUnemployed = Shared.IsDefaultJob(PlayerJob),
        dutyTime = DutySeconds(),
        maxJobs = Config.MaxJobs,
        locale = Config.Locale,
        leaderboards = Config.Leaderboards and Config.Leaderboards.enabled,
        leaderboardCategories = Config.Leaderboards and Config.Leaderboards.categories,
        scheduleEnabled = Config.Schedule and Config.Schedule.enabled,
        scheduleCanCreate = Config.Schedule and Config.Schedule.playerCanCreate,
        maxSchedules = Config.Schedule and Config.Schedule.maxSchedules,
        ui = Config.UI,
        playerName = PlayerName or GetPlayerName(PlayerId()),
    }
end

-- Several events can ask for a reload at once; collapse them into one fetch
local loadQueued = false

function LoadPlayerData()
    if loadQueued then return end
    loadQueued = true

    SetTimeout(250, function()
        loadQueued = false
        lib.callback('nayzeee-multijob:getPlayerData', false, function(data)
            if not data then return end
            ApplyPlayerData(data)
            Shared.Debug('Loaded player data:', #PlayerJobs, 'jobs,', #PlayerShifts, 'shifts')

            if isUIOpen then
                SendNUIMessage({ action = 'refreshData', data = MenuPayload() })
            end
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1000)

    local fw = Shared.GetFramework()
    local FW = Shared.GetFrameworkObject()

    if fw == 'esx' then
        while not FW.IsPlayerLoaded() do Wait(250) end
    elseif fw == 'qbcore' or fw == 'qbox' then
        while not (FW.Functions.GetPlayerData() or {}).citizenid do Wait(250) end
    else
        return
    end

    TriggerServerEvent('nayzeee-multijob:syncJob')
    LoadPlayerData()

    if Config.DutyTracking and Config.DutyTracking.enabled then
        StartDutyTracking()
    end
end)

-- The server hooks the same framework events itself. These pings are only a
-- fallback and carry no data - the server reads the job from the framework.
local function OnFrameworkJobChange()
    TriggerServerEvent('nayzeee-multijob:syncJob')
end

RegisterNetEvent('esx:setJob', OnFrameworkJobChange)
RegisterNetEvent('esx:playerLoaded', LoadPlayerData)
RegisterNetEvent('QBCore:Client:OnJobUpdate', OnFrameworkJobChange)
RegisterNetEvent('QBCore:Client:SetDuty', OnFrameworkJobChange)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', LoadPlayerData)

-- ═══════════════════════════════════════════════════════════════════════════
-- UI FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- If the server never answers, don't leave the menu stuck as "opening"
local openToken = 0

local function WatchOpen(token)
    SetTimeout(5000, function()
        if openToken == token then
            openToken = 0
            isUIOpen = false
            isAdminOpen = false
        end
    end)
end

function OpenJobMenu()
    if isUIOpen or isAdminOpen then return end
    isUIOpen = true
    lastActivity = GetGameTimer()
    openToken = openToken + 1
    local token = openToken
    WatchOpen(token)

    lib.callback('nayzeee-multijob:getPlayerData', false, function(data)
        if openToken ~= token or not isUIOpen then return end -- closed or timed out
        openToken = 0
        if data then ApplyPlayerData(data) end

        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openMenu', data = MenuPayload() })
    end)
end

function OpenAdminPanel()
    if isAdminOpen or isUIOpen then return end
    isAdminOpen = true
    openToken = openToken + 1
    local token = openToken
    WatchOpen(token)

    -- the server checks the permission; nil means "not staff"
    lib.callback('nayzeee-multijob:getAdminData', false, function(data)
        if openToken ~= token or not isAdminOpen then return end
        openToken = 0
        if not data then
            isAdminOpen = false
            Shared.Notify('Error', Config.Locale['admin_no_permission'], 'error')
            return
        end

        SetNuiFocus(true, true)
        data.ui = Config.UI
        SendNUIMessage({ action = 'openAdmin', data = data })
    end)
end

function CloseUI()
    openToken = 0
    isUIOpen = false
    isAdminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DUTY TRACKING
-- ═══════════════════════════════════════════════════════════════════════════

local inactivityWarned = false

RegisterNetEvent('nayzeee-multijob:dutyState', function(state)
    if type(state) ~= 'table' then return end

    isOnDuty = state.onDuty == true
    afkPaused = state.afkPaused == true
    dutyStartTime = GetGameTimer() - math.floor((tonumber(state.elapsed) or 0) * 1000)
    awaitingAutoClockOut = false
    inactivityWarned = false
    lastActivity = GetGameTimer()

    SendNUIMessage({
        action = 'updateDutyStatus',
        data = { isOnDuty = isOnDuty, afkPaused = afkPaused, dutyTime = DutySeconds() },
    })

    Shared.Debug('Duty state:', isOnDuty, state.job, afkPaused and '(afk paused)' or '')
end)

function StartDutyTracking()
    local cfg = Config.DutyTracking.autoClockOut or {}

    -- Movement, turning, driving or having the menu open all count as activity
    CreateThread(function()
        local lastPos, lastHeading

        while true do
            Wait(5000)

            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)

            local moved = lastPos ~= nil and #(pos - lastPos) > 0.5
            local turned = lastHeading ~= nil and math.abs(heading - lastHeading) > 5.0
            local driving = IsPedInAnyVehicle(ped, false) and GetEntitySpeed(ped) > 1.0
            lastPos, lastHeading = pos, heading

            if moved or turned or driving or isUIOpen or isAdminOpen then
                lastActivity = GetGameTimer()
                inactivityWarned = false

                -- default job was paused for inactivity: pick it back up
                if afkPaused and not isOnDuty then
                    afkPaused = false
                    TriggerServerEvent('nayzeee-multijob:clockIn')
                end
            end

            -- the request can be dropped (rate limit); ask again after 15s
            if awaitingAutoClockOut and GetGameTimer() - autoClockOutSentAt > 15000 then
                awaitingAutoClockOut = false
            end

            if isOnDuty and cfg.enabled and not awaitingAutoClockOut then
                local idle = (GetGameTimer() - lastActivity) / 60000
                local max = cfg.inactivityMinutes or 30
                local warn = cfg.warningMinutes or (max - 5)

                if idle >= max then
                    awaitingAutoClockOut = true
                    autoClockOutSentAt = GetGameTimer()
                    TriggerServerEvent('nayzeee-multijob:clockOut', true)
                elseif idle >= warn and not inactivityWarned then
                    inactivityWarned = true
                    Shared.Notify('Warning', Shared.L('inactivity_warning', math.max(1, math.ceil(max - idle))), 'warning')
                end
            end
        end
    end)
end

-- Keeps the open menu's shift clock honest against the server start time
CreateThread(function()
    while true do
        Wait(1000)
        if isOnDuty and isUIOpen then
            SendNUIMessage({ action = 'updateDutyTime', time = DutySeconds() })
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ═══════════════════════════════════════════════════════════════════════════

local function Str(v)
    return type(v) == 'string' and v or nil
end

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    LoadPlayerData()
    cb('ok')
end)

RegisterNUICallback('switchJob', function(data, cb)
    if Str(data.job) then TriggerServerEvent('nayzeee-multijob:switchJob', data.job) end
    cb('ok')
end)

RegisterNUICallback('removeJob', function(data, cb)
    if Str(data.job) then TriggerServerEvent('nayzeee-multijob:removeJob', data.job) end
    cb('ok')
end)

RegisterNUICallback('quitJob', function(data, cb)
    if Str(data.job) then TriggerServerEvent('nayzeee-multijob:quitJob', data.job) end
    cb('ok')
end)

RegisterNUICallback('toggleFavorite', function(data, cb)
    if Str(data.job) then TriggerServerEvent('nayzeee-multijob:toggleFavorite', data.job) end
    cb('ok')
end)

RegisterNUICallback('clockIn', function(_, cb)
    TriggerServerEvent('nayzeee-multijob:clockIn')
    cb('ok')
end)

RegisterNUICallback('clockOut', function(_, cb)
    TriggerServerEvent('nayzeee-multijob:clockOut', false)
    cb('ok')
end)

RegisterNUICallback('getLeaderboards', function(_, cb)
    lib.callback('nayzeee-multijob:getLeaderboards', false, function(data)
        cb(data or {})
    end)
end)

RegisterNUICallback('saveSchedule', function(data, cb)
    lib.callback('nayzeee-multijob:saveSchedule', false, function(ok)
        if ok then LoadPlayerData() end
        cb({ ok = ok == true })
    end, data)
end)

RegisterNUICallback('deleteSchedule', function(data, cb)
    lib.callback('nayzeee-multijob:deleteSchedule', false, function(ok)
        if ok then LoadPlayerData() end
        cb({ ok = ok == true })
    end, data.id)
end)

RegisterNUICallback('toggleSchedule', function(data, cb)
    lib.callback('nayzeee-multijob:toggleSchedule', false, function(ok)
        if ok then LoadPlayerData() end
        cb({ ok = ok == true })
    end, data.id)
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    lib.callback('nayzeee-multijob:getAdminData', false, function(data)
        if data and isAdminOpen then
            SendNUIMessage({ action = 'refreshAdmin', data = data })
        end
        cb('ok')
    end)
end)

RegisterNUICallback('adminGetPlayer', function(data, cb)
    lib.callback('nayzeee-multijob:adminGetPlayer', false, function(pdata)
        cb(pdata or {})
    end, data.id)
end)

RegisterNUICallback('adminAddJob', function(data, cb)
    lib.callback('nayzeee-multijob:adminAddJob', false, function(ok)
        cb({ ok = ok == true })
    end, data.playerId, data.job, data.grade)
end)

RegisterNUICallback('adminRemoveJob', function(data, cb)
    lib.callback('nayzeee-multijob:adminRemoveJob', false, function(ok)
        cb({ ok = ok == true })
    end, data.playerId, data.job)
end)

RegisterNUICallback('adminBulkAction', function(data, cb)
    lib.callback('nayzeee-multijob:adminBulkAction', false, function(ok)
        cb({ ok = ok == true })
    end, data.action, data.playerIds, data.job, data.grade)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- COMMANDS & KEYBINDS
-- ═══════════════════════════════════════════════════════════════════════════

RegisterCommand(Config.Command, function()
    OpenJobMenu()
end, false)

RegisterCommand(Config.AdminCommand, function()
    OpenAdminPanel()
end, false)

if Config.Keybind then
    RegisterKeyMapping(Config.Command, 'Open Job Menu', 'keyboard', Config.Keybind)
end

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Open the job menu')
    TriggerEvent('chat:addSuggestion', '/' .. Config.AdminCommand, 'Open the job admin panel (staff)')
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- NET EVENTS
-- ═══════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nayzeee-multijob:refresh', LoadPlayerData)

RegisterNetEvent('nayzeee-multijob:shiftEnded', function(data)
    Shared.Debug('Shift ended:', data and data.job, data and data.duration, data and data.earnings)
    LoadPlayerData()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and (isUIOpen or isAdminOpen) then
        SetNuiFocus(false, false)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════════════════

exports('GetPlayerJobs', function() return PlayerJobs end)
exports('GetCurrentJob', function() return PlayerJob, PlayerGrade end)
exports('IsOnDuty', function() return isOnDuty end)
exports('GetDutyTime', DutySeconds)
exports('ClockIn', function() TriggerServerEvent('nayzeee-multijob:clockIn') end)
exports('ClockOut', function() TriggerServerEvent('nayzeee-multijob:clockOut', false) end)
exports('OpenMenu', OpenJobMenu)
