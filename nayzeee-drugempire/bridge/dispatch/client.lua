--[[ Dispatch bridge (client) ]]

RegisterNetEvent('nzde:dispatch', function(kind, data)
    if GetInvokingResource() then return end
    local c = data.coords
    local ok, err = pcall(function()
        if kind == 'ps' then
            exports['ps-dispatch']:CustomAlert({
                coords = c, message = data.title, dispatchCode = data.code, description = data.message,
                radius = 0, sprite = 161, color = 1, scale = 1.2, length = 3, jobs = { 'leo' },
            })
        elseif kind == 'cd' then
            local info = exports['cd_dispatch']:GetPlayerInfo()
            TriggerServerEvent('cd_dispatch:AddNotification', {
                job_table = data.jobs, coords = c, title = data.code .. ' - ' .. data.title, message = data.message,
                flash = 0, unique_id = info.unique_id, sound = 1,
                blip = { sprite = 161, scale = 1.2, colour = 1, flashes = true, text = data.title, time = 5, radius = 0 },
            })
        elseif kind == 'qs' then
            TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
                job = data.jobs, callLocation = c, callCode = { code = data.code, snippet = data.title },
                message = data.message, flashes = true,
                blip = { sprite = 161, scale = 1.2, colour = 1, flashes = true, text = data.title, time = 300000 },
            })
        elseif kind == 'tk' then
            exports.tk_dispatch:addCall({
                title = data.title, code = data.code, priority = 'Priority 1', coords = c,
                showLocation = true, showGender = false, playSound = true, jobs = data.jobs,
                blip = { color = 1, sprite = 161, scale = 1.2 },
            })
        elseif kind == 'custom' then
            -- Put your own dispatch call here.
            TriggerEvent('nzde:customDispatch', data)
        end
    end)
    if not ok then print('^1[nzde] dispatch error: ' .. tostring(err)) end
end)

RegisterNetEvent('nzde:dispatch:builtin', function(data)
    if GetInvokingResource() then return end
    local cfg = Config.Police.alertBlip
    local c = data.coords
    local radius = AddBlipForRadius(c.x, c.y, c.z, cfg.radius)
    SetBlipColour(radius, cfg.color)
    SetBlipAlpha(radius, 110)
    SetBlipFlashes(radius, true)
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.code .. ' ' .. data.title)
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)
    UI.notify(('%s - %s'):format(data.title, data.message), 'error', 9000)

    SetTimeout(cfg.duration * 1000, function()
        RemoveBlip(radius)
        RemoveBlip(blip)
    end)
end)
