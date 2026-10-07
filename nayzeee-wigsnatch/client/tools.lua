-- Scissors + clippers on other players

Tools = { PickerId = nil, prop = nil, running = false }

local CT = Config.Tools

local function serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

local function hasNaturalHair(entity)
    local m = ModelKey(GetEntityModel(entity))
    if not m or not ModelEnabled(m) then return false end
    return not IsBaldDrawable(m, GetPedDrawableVariation(entity, 2))
end

local function canStyle(entity)
    return not Snatch.busy and not Tools.running and not NUI.app and hasNaturalHair(entity)
end

local function canForce(entity)
    if not canStyle(entity) then return false end
    local sid = serverIdOf(entity)
    return CB.IsRestrained(entity, sid) or CB.HandsUp(entity) or CB.IsDowned(entity, sid)
end

local function request(entity, tool, forced)
    local sid = serverIdOf(entity)
    if not sid then return end
    TriggerServerEvent('nz-wig:s:toolRequest', sid, tool, forced == true)
end

Tools.TargetOptions = {}
if CT.Scissors.Enabled then
    Tools.TargetOptions[#Tools.TargetOptions + 1] = {
        name = 'nzwig_scissors', label = CT.Scissors.Label, icon = CT.Scissors.Icon, distance = CT.Range,
        item = Config.Items.Scissors, canInteract = canStyle,
        onSelect = function(e) request(e, 'scissors') end,
    }
end
if CT.Clippers.Enabled then
    Tools.TargetOptions[#Tools.TargetOptions + 1] = {
        name = 'nzwig_clippers', label = CT.Clippers.Label, icon = CT.Clippers.Icon, distance = CT.Range,
        item = Config.Items.Clippers, canInteract = canStyle,
        onSelect = function(e) request(e, 'clippers') end,
    }
    if CT.Clippers.AllowForced then
        Tools.TargetOptions[#Tools.TargetOptions + 1] = {
            name = 'nzwig_buzz', label = 'Force Buzz', icon = 'fa-solid fa-user-slash', distance = CT.Range,
            item = Config.Items.Clippers, canInteract = canForce,
            onSelect = function(e) request(e, 'clippers', true) end,
        }
    end
end

-- picker ----------------------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:cutPicker', function(data)
    Tools.PickerId = data.id
    NUI.Open('cuts', data)
end)

RegisterNUICallback('cutPick', function(d, cb)
    if Tools.PickerId and d and d.index then
        local id = Tools.PickerId
        Tools.PickerId = nil -- don't cancel on close
        NUI.CloseApp()
        TriggerServerEvent('nz-wig:s:toolPick', id, d.index)
    end
    cb(1)
end)

-- running the cut ----------------------------------------------------------------------------

local function removeProp()
    if Tools.prop and DoesEntityExist(Tools.prop) then DeleteEntity(Tools.prop) end
    Tools.prop = nil
end

local function stop()
    local me = PlayerPedId()
    removeProp()
    ClearPedTasks(me)
    FreezeEntityPosition(me, false)
    Tools.running = false
end

RegisterNetEvent('nz-wig:c:toolRun', function(d)
    local me = PlayerPedId()
    Tools.running = true
    local other = Snatch.PedOf(d.other)
    if other ~= 0 and DoesEntityExist(other) then
        local a, b = GetEntityCoords(me), GetEntityCoords(other)
        SetEntityHeading(me, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
    end

    if d.role == 'barber' then
        local p = CT.Prop
        if pcall(lib.requestModel, p.model, 1500) then
            local c = GetEntityCoords(me)
            Tools.prop = CreateObject(p.model, c.x, c.y, c.z + 0.2, true, true, false)
            AttachEntityToEntity(Tools.prop, me, GetPedBoneIndex(me, p.bone), p.pos.x, p.pos.y, p.pos.z, p.rot.x, p.rot.y, p.rot.z, true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(p.model)
        end
        PlayAnim({ dict = CT.Anim.dict, clip = CT.Anim.clip, flag = 49 }, d.duration)
        NUI.Send('progress', { label = d.tool == 'clippers' and 'Buzzing' or 'Cutting', duration = d.duration })
    else
        FreezeEntityPosition(me, true)
    end
    SetTimeout(d.duration, stop)
end)

RegisterNetEvent('nz-wig:c:toolStop', stop)

-- positional sound for everyone nearby
RegisterNetEvent('nz-wig:c:sound', function(s)
    local me = GetEntityCoords(PlayerPedId())
    local dist = #(me - vec3(s.coords.x, s.coords.y, s.coords.z))
    if dist > s.range then return end
    NUI.Send('sound', { name = s.sound, volume = math.max(0.05, 1.0 - dist / s.range) * 0.8, duration = s.duration })
end)

function Tools.Cleanup()
    removeProp()
end
