--[[
    Floating "ADMIN JAIL" tag over inmates for nearby players.
    Driven by the `adminJailed` player state bag: while nobody is jailed no thread runs.
]]

if not Config.Overhead.enabled then return end

local cfg = Config.Overhead
local jailed = {}   -- [serverId] = true
local count = 0
local running = false

local function draw3D(x, y, z, text, r, g, b, scale)
    SetDrawOrigin(x, y, z, 0)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function start()
    if running then return end
    running = true
    CreateThread(function()
        local near = {}
        local lastScan = 0
        while count > 0 do
            local now = GetGameTimer()
            if now - lastScan > 1000 then
                lastScan = now
                near = {}
                local me = GetEntityCoords(cache.ped)
                for sid in pairs(jailed) do
                    local pid = GetPlayerFromServerId(sid)
                    if pid ~= -1 then
                        local ped = GetPlayerPed(pid)
                        if ped ~= 0 and #(GetEntityCoords(ped) - me) < cfg.distance then near[#near + 1] = ped end
                    end
                end
            end

            if #near == 0 then
                Wait(500)
            else
                for i = 1, #near do
                    local ped = near[i]
                    if DoesEntityExist(ped) then
                        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                        draw3D(head.x, head.y, head.z + 0.42, cfg.label, 8, 175, 162, 0.36)
                        draw3D(head.x, head.y, head.z + 0.30, 'INMATE', 220, 224, 226, 0.26)
                    end
                end
                Wait(0)
            end
        end
        running = false
    end)
end

local function set(sid, value)
    if sid == cache.serverId then return end
    if value and not jailed[sid] then
        jailed[sid] = true
        count = count + 1
    elseif not value and jailed[sid] then
        jailed[sid] = nil
        count = count - 1
    end
    if count > 0 then start() end
end

AddStateBagChangeHandler('adminJailed', nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if sid then set(sid, value == true) end
end)

-- Players already jailed when this client joined.
CreateThread(function()
    Wait(2000)
    for _, pid in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pid)
        if Player(sid).state.adminJailed then set(sid, true) end
    end
end)
