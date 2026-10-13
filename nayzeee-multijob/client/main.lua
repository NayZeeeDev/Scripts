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
local PlayerBossJobs = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CLOCK-IN POINTS
-- ═══════════════════════════════════════════════════════════════════════════

local pointBlips = {}
local pointZones = {}
local markedJob = nil

local function PointsCfg()
    local cfg = Config.DutyPoints
    return (cfg and cfg.enabled) and cfg or nil
end

local function ToVector(c)
    return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
end

local function PointsForJob(jobName)
    local cfg = PointsCfg()
    if not cfg or Shared.IsDefaultJob(jobName) then return nil end
    local list = {}
    for _, point in ipairs(cfg.points or {}) do
        if point.job == jobName and point.coords then list[#list + 1] = point end
    end
    return #list > 0 and list or nil
end

local function NearestPoint(jobName)
    local points = PointsForJob(jobName)
    if not points then return nil end
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, point in ipairs(points) do
        local dist = #(pos - ToVector(point.coords))
        if not bestDist or dist < bestDist then best, bestDist = point, dist end
    end
    return best, bestDist
end

-- What the Duty tab needs to know about the nearest point
local function DutyPointState()
    local point, dist = NearestPoint(PlayerJob)
    if not point then return { required = false } end
    local cfg = PointsCfg()
    return {
        required = true,
        outRequired = cfg.clockOutAtPoint == true,
        inside = dist <= (point.radius or 3.0),
        label = point.label or point.job,
        distance = math.floor(dist + 0.5),
    }
end

local function MarkPoint(point)
    if not point then return end
    SetNewWaypoint(point.coords.x + 0.0, point.coords.y + 0.0)
end

local function ClearPointMarkers()
    for _, blip in ipairs(pointBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    pointBlips = {}
    for _, id in ipairs(pointZones) do
        pcall(function() exports.ox_target:removeZone(id) end)
    end
    pointZones = {}
end

-- Blips and ox_target zones follow the job the player is working right now
local function RefreshPointMarkers()
    local cfg = PointsCfg()
    local key = tostring(PlayerJob) .. (cfg and ':on' or ':off')
    if markedJob == key then return end
    markedJob = key
    ClearPointMarkers()

    local points = PointsForJob(PlayerJob)
    if not cfg or not points then return end

    local useTarget = cfg.interact == 'target' and GetResourceState('ox_target') == 'started'

    for _, point in ipairs(points) do
        if cfg.blips ~= false and point.blip ~= false then
            local style = type(point.blip) == 'table' and point.blip or {}
            local blip = AddBlipForCoord(point.coords.x + 0.0, point.coords.y + 0.0, point.coords.z + 0.0)
            SetBlipSprite(blip, style.sprite or 1)
            SetBlipColour(blip, style.colour or style.color or 2)
            SetBlipScale(blip, style.scale or 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(point.label or Config.Locale['clock_in'])
            EndTextCommandSetBlipName(blip)
            pointBlips[#pointBlips + 1] = blip
        end

        if useTarget then
            local job = point.job
            local ok, id = pcall(function()
                return exports.ox_target:addSphereZone({
                    coords = ToVector(point.coords),
                    radius = point.radius or 3.0,
                    debug = Config.Debug,
                    options = {
                        {
                            name = 'nayzeee_clock_in',
                            icon = 'fa-solid fa-clock',
                            label = Config.Locale['clock_in'],
                            canInteract = function() return not isOnDuty and PlayerJob == job end,
                            onSelect = function() TriggerServerEvent('nayzeee-multijob:clockIn') end,
                        },
                        {
                            name = 'nayzeee_clock_out',
                            icon = 'fa-solid fa-clock-rotate-left',
                            label = Config.Locale['clock_out'],
                            canInteract = function() return isOnDuty and PlayerJob == job end,
                            onSelect = function() TriggerServerEvent('nayzeee-multijob:clockOut', false) end,
                        },
                    },
                })
            end)
            if ok and id then pointZones[#pointZones + 1] = id end
        end
    end
end

-- 'textui': show a prompt inside the point and clock in / out on the key
CreateThread(function()
    local shown = nil

    while true do
        local sleep = 1000
        local cfg = PointsCfg()

        if cfg and cfg.interact == 'textui' and not isUIOpen and not isAdminOpen then
            local point, dist = NearestPoint(PlayerJob)
            if point and dist <= (point.radius or 3.0) then
                sleep = 0
                local text = Shared.L(isOnDuty and 'duty_point_prompt_out' or 'duty_point_prompt_in', point.label or point.job)
                if shown ~= text then
                    lib.showTextUI(text, { icon = 'clock' })
                    shown = text
                end
                if IsControlJustReleased(0, cfg.key or 38) then
                    if isOnDuty then
                        TriggerServerEvent('nayzeee-multijob:clockOut', false)
                    else
                        TriggerServerEvent('nayzeee-multijob:clockIn')
                    end
                end
            else
                if point and dist < 40.0 then sleep = 250 end
            end
        end

        if sleep > 0 and shown then
            lib.hideTextUI()
            shown = nil
        end
        Wait(sleep)
    end
end)

-- The server refused a clock in/out away from a point: mark the nearest one
RegisterNetEvent('nayzeee-multijob:dutyPointHint', function(hint)
    if type(hint) ~= 'table' then return end
    SetNewWaypoint((tonumber(hint.x) or 0) + 0.0, (tonumber(hint.y) or 0) + 0.0)
    Shared.Notify('Duty', Shared.L(hint.out and 'duty_point_needed_out' or 'duty_point_waypoint', hint.label or ''), 'error')
end)

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
    PlayerBossJobs = data.bossJobs or {}
    RefreshPointMarkers()
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
        bossJobs = PlayerBossJobs,
        dutyPoint = DutyPointState(),
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
        if isUIOpen then
            if isOnDuty then
                SendNUIMessage({ action = 'updateDutyTime', time = DutySeconds() })
            end
            if PointsForJob(PlayerJob) then
                SendNUIMessage({ action = 'dutyPoint', data = DutyPointState() })
            end
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

RegisterNUICallback('adminSearch', function(data, cb)
    lib.callback('nayzeee-multijob:adminSearch', false, function(results)
        cb({ results = results or {} })
    end, data.query)
end)

-- target = an online server id or a character identifier (offline players)
RegisterNUICallback('adminGetPlayer', function(data, cb)
    lib.callback('nayzeee-multijob:adminGetPlayer', false, function(pdata)
        cb(pdata or {})
    end, data.target)
end)

RegisterNUICallback('adminAddJob', function(data, cb)
    lib.callback('nayzeee-multijob:adminAddJob', false, function(ok)
        cb({ ok = ok == true })
    end, data.target, data.job, data.grade)
end)

RegisterNUICallback('adminRemoveJob', function(data, cb)
    lib.callback('nayzeee-multijob:adminRemoveJob', false, function(ok)
        cb({ ok = ok == true })
    end, data.target, data.job)
end)

RegisterNUICallback('adminSetJob', function(data, cb)
    lib.callback('nayzeee-multijob:adminSetJob', false, function(ok)
        cb({ ok = ok == true })
    end, data.target, data.job, data.grade)
end)

RegisterNUICallback('dutyWaypoint', function(_, cb)
    MarkPoint(NearestPoint(PlayerJob))
    cb('ok')
end)

-- Team tab (bosses). The server checks the boss grade on every call.
RegisterNUICallback('bossTeam', function(data, cb)
    lib.callback('nayzeee-multijob:bossTeam', false, function(team)
        cb(team or {})
    end, data.job)
end)

RegisterNUICallback('bossNearby', function(data, cb)
    lib.callback('nayzeee-multijob:bossNearby', false, function(result)
        cb(result or { players = {} })
    end, data.job)
end)

RegisterNUICallback('bossHire', function(data, cb)
    lib.callback('nayzeee-multijob:bossHire', false, function(ok)
        cb({ ok = ok == true })
    end, data.job, data.target, data.grade)
end)

RegisterNUICallback('bossFire', function(data, cb)
    lib.callback('nayzeee-multijob:bossFire', false, function(ok)
        cb({ ok = ok == true })
    end, data.job, data.ref)
end)

RegisterNUICallback('bossSetGrade', function(data, cb)
    lib.callback('nayzeee-multijob:bossSetGrade', false, function(ok)
        cb({ ok = ok == true })
    end, data.job, data.ref, data.grade)
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

-- A hire went through: reload the Team tab if the boss has it open
RegisterNetEvent('nayzeee-multijob:teamChanged', function()
    if isUIOpen then SendNUIMessage({ action = 'teamChanged' }) end
end)

-- A boss offered this player a job
RegisterNetEvent('nayzeee-multijob:jobOffer', function(offer)
    if type(offer) ~= 'table' or not offer.id then return end

    local answered, expired = false, false
    SetTimeout((tonumber(offer.timeout) or 60) * 1000, function()
        if not answered then
            expired = true
            lib.closeAlertDialog()
        end
    end)

    local answer = lib.alertDialog({
        header = Shared.L('boss_offer_title'),
        content = Shared.L('boss_offer_text', offer.from or '?', offer.jobLabel or '?', offer.gradeLabel or '?'),
        centered = true,
        cancel = true,
        labels = { confirm = Shared.L('boss_offer_accept'), cancel = Shared.L('boss_offer_decline') },
    })
    answered = true

    -- ox_lib drops NUI focus when its dialog closes; give it back to an open menu
    if isUIOpen or isAdminOpen then SetNuiFocus(true, true) end
    if expired then return end

    TriggerServerEvent('nayzeee-multijob:offerResponse', offer.id, answer == 'confirm')
end)

RegisterNetEvent('nayzeee-multijob:shiftEnded', function(data)
    Shared.Debug('Shift ended:', data and data.job, data and data.duration, data and data.earnings)
    LoadPlayerData()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isUIOpen or isAdminOpen then SetNuiFocus(false, false) end
    ClearPointMarkers()
    lib.hideTextUI()
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
