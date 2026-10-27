-- Dev tool: live-tune a boombox's hand position. Only active with Config.Debug = true.
if not Config.Debug then return end

local editing = nil   -- the prop while the editor is open

RegisterCommand('nzspk_attach', function(_, args)
    local item = args[1]
    local cfg = item and Config.Boomboxes[item]
    if not cfg or not cfg.attach then return print('^1usage: /nzspk_attach <portable item name>^7') end
    if editing or Carrying then return print('^1put the boombox down / close the editor first^7') end
    local hash = Bridge.LoadModel(cfg.model)
    if not hash then return print(('^1model %s is not in the game^7'):format(cfg.model)) end
    local a = cfg.attach
    local hasAnim = Bridge.LoadAnimDict(a.dict)
    local ped = PlayerPedId()
    local prop = CreateObject(hash, GetEntityCoords(ped), false, false, false)
    SetModelAsNoLongerNeeded(hash)
    editing = prop
    local off, rot = a.offset, a.rotation
    local rotMode, step = false, 0.005

    local function attach()
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone), off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    end
    attach()
    ShowHints({
        { key = 'Arrows', label = 'X / Y' }, { key = 'PgUp/PgDn', label = 'Z' },
        { key = 'Shift', label = 'Rotate mode' }, { key = 'Enter', label = 'Print' }, { key = 'Back', label = 'Exit' },
    })

    while editing == prop do
        local d = rotMode and 1.0 or step
        local dx, dy, dz = 0.0, 0.0, 0.0
        if IsControlPressed(0, 174) then dx = -d end   -- left
        if IsControlPressed(0, 175) then dx = d end    -- right
        if IsControlPressed(0, 172) then dy = d end    -- up
        if IsControlPressed(0, 173) then dy = -d end   -- down
        if IsControlPressed(0, 10) then dz = d end     -- pgup
        if IsControlPressed(0, 11) then dz = -d end    -- pgdn
        if dx ~= 0 or dy ~= 0 or dz ~= 0 then
            if rotMode then rot = rot + vector3(dx, dy, dz) else off = off + vector3(dx, dy, dz) end
            attach()
        end
        if IsControlJustPressed(0, 21) then rotMode = not rotMode end
        if IsControlJustPressed(0, 191) then
            print(('offset = vector3(%.3f, %.3f, %.3f), rotation = vector3(%.1f, %.1f, %.1f),'):format(off.x, off.y, off.z, rot.x, rot.y, rot.z))
        end
        if IsControlJustPressed(0, 177) then break end
        if hasAnim and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
            TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
        end
        Wait(0)
    end
    if DoesEntityExist(prop) then DeleteEntity(prop) end
    if editing == prop then editing = nil end
    ClearPedTasks(ped)
    HideHints()
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES or not editing then return end
    if DoesEntityExist(editing) then DeleteEntity(editing) end
    ClearPedTasks(PlayerPedId())
    editing = nil
end)
