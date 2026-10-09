-- Dev tool: live-tune a boombox's hand position. Only active with Config.Debug = true.
if not Config.Debug then return end

RegisterCommand('nzspk_attach', function(_, args)
    local item = args[1]
    local cfg = item and Config.Boomboxes[item]
    if not cfg or not cfg.attach then return print('^1usage: /nzspk_attach <portable item name>^7') end
    local a = cfg.attach
    local ped = PlayerPedId()
    local hash = joaat(cfg.model)
    RequestModel(hash) while not HasModelLoaded(hash) do Wait(0) end
    RequestAnimDict(a.dict) while not HasAnimDictLoaded(a.dict) do Wait(0) end
    local prop = CreateObject(hash, GetEntityCoords(ped), false, false, false)
    local off, rot = a.offset, a.rotation
    local rotMode, step = false, 0.005

    local function attach()
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone), off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    end
    attach()
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
    ShowHints({
        { key = 'Arrows', label = 'X / Y' }, { key = 'PgUp/PgDn', label = 'Z' },
        { key = 'Shift', label = 'Rotate mode' }, { key = 'Enter', label = 'Print' }, { key = 'Back', label = 'Exit' },
    })

    while true do
        local d = rotMode and 1.0 or step
        local v = rotMode and rot or off
        local dx, dy, dz = 0.0, 0.0, 0.0
        if IsControlPressed(0, 174) then dx = -d end   -- left
        if IsControlPressed(0, 175) then dx = d end    -- right
        if IsControlPressed(0, 172) then dy = d end    -- up
        if IsControlPressed(0, 173) then dy = -d end   -- down
        if IsControlPressed(0, 10) then dz = d end     -- pgup
        if IsControlPressed(0, 11) then dz = -d end    -- pgdn
        if dx ~= 0 or dy ~= 0 or dz ~= 0 then
            v = v + vector3(dx, dy, dz)
            if rotMode then rot = v else off = v end
            attach()
        end
        if IsControlJustPressed(0, 21) then rotMode = not rotMode end
        if IsControlJustPressed(0, 191) then
            print(('offset = vector3(%.3f, %.3f, %.3f), rotation = vector3(%.1f, %.1f, %.1f),'):format(off.x, off.y, off.z, rot.x, rot.y, rot.z))
        end
        if IsControlJustPressed(0, 177) then break end
        if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
            TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
        end
        Wait(0)
    end
    DeleteEntity(prop)
    ClearPedTasks(ped)
    HideHints()
end, false)
