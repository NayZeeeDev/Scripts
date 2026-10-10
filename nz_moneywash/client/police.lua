--[[ Police — UV serial scanner on players, dispatch alerts ]]

PoliceUI = {}

local function scanPlayer(serverId)
    U.run(function()
        U.playPed(Config.Anims.scan, 1)
        local ok = UI.progress('Sweeping UV over their cash', 3000)
        U.stopPed()
        if not ok then return end
        local res = lib.callback.await('nzmw:scan:player', false, serverId)
        if not res or not res.ok then return UI.err(res) end
        UI.await('scan', res)
    end)
end

function PoliceUI.init()
    Target.addGlobalPlayer({
        { name = 'uvscan', label = 'UV scan cash', icon = 'fas fa-magnifying-glass-dollar', distance = 2.0,
          canInteract = function() return not U.busy and CBridge.isPolice() and CBridge.hasItem(Config.Heat.scannerItem) end,
          onSelect = function(entity)
              local idx = NetworkGetPlayerIndexFromPed(entity)
              if idx and idx ~= -1 then scanPlayer(GetPlayerServerId(idx)) end
          end },
    })

    if CBridge.target == 'none' then
        RegisterCommand('uvscan', function()
            if not CBridge.isPolice() then return end
            local player = lib.getClosestPlayer(GetEntityCoords(PlayerPedId()), 3.0, false)
            if not player then return UI.toast('UV scanner', 'Nobody close enough.', 'error') end
            scanPlayer(GetPlayerServerId(player))
        end, false)
    end
end

RegisterNetEvent('nzmw:policeAlert', function(d)
    local pos = vec3(d.x, d.y, d.z)
    UI.toast(('%s · %s'):format(d.code, d.title), d.message, 'error', 9000)
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)

    -- fuzzy radius so they have to search the block
    local jitter = vec3(math.random(-40, 40), math.random(-40, 40), 0)
    local area = AddBlipForRadius(pos.x + jitter.x, pos.y + jitter.y, pos.z, 90.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 110)
    local blip = AddBlipForCoord(pos.x + jitter.x, pos.y + jitter.y, pos.z)
    SetBlipSprite(blip, 500)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.code .. ' ' .. d.title)
    EndTextCommandSetBlipName(blip)

    SetTimeout(120000, function()
        RemoveBlip(area)
        RemoveBlip(blip)
    end)
end)
