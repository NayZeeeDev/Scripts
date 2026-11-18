if not NAYZEEE_LOCK_OK then return end

--[[
    Floating nameplates. Every ~40 ms while the lobby view is up, project each actor's head to 0..1 screen
    space and send `plates` only when something moved (> 0.002) or changed. Crew peds never get a plate.
]]

Plates = { on = false, last = nil, token = 0 }

local EPS = 0.002

local function jobLabel(j)
    if type(j) ~= 'table' then return nil end
    return j.label or j.name
end

local function collect()
    local items = {}
    for slot, a in pairs(Actors.list) do
        if a.kind ~= 'ghost' and DoesEntityExist(a.ped) then
            local data = a.char or a.other or {}
            local h = U.Head(a.ped)
            local on, x, y = GetScreenCoordFromWorldCoord(h.x, h.y, h.z + 0.32)
            local online = nil
            if a.kind ~= 'self' and a.other then online = a.other.online == true end
            items[#items + 1] = {
                key = 'slot' .. slot, x = x, y = y, visible = on == true or on == 1,
                name = data.name or ((data.firstname or '') .. ' ' .. (data.lastname or '')),
                sub = jobLabel(data.job),
                badge = a.kind == 'self' and 'self' or (a.kind == 'couple' and 'partner' or 'squad'),
                online = online,
            }
        end
    end
    local p = Actors.pet
    if p and DoesEntityExist(p.ped) then
        local c = GetEntityCoords(p.ped)
        local min, max = GetModelDimensions(GetEntityModel(p.ped))
        local on, x, y = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + max.z + 0.25)
        items[#items + 1] = { key = 'pet', x = x, y = y, visible = on == true or on == 1,
            name = p.name or (p.def and p.def.label), sub = p.def and p.def.label, badge = 'pet' }
    end
    table.sort(items, function(a, b) return a.key < b.key end)
    return items
end

local function changed(a, b)
    if not b or #a ~= #b then return true end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if x.key ~= y.key or x.visible ~= y.visible or x.name ~= y.name or x.sub ~= y.sub or x.online ~= y.online then return true end
        if math.abs(x.x - y.x) > EPS or math.abs(x.y - y.y) > EPS then return true end
    end
    return false
end

local function wanted()
    return Main.open and Main.mode == 'lobby' and Settings.Get('plates') and Config.UI.nameplates ~= false
end

function Plates.Start()
    if Plates.on then return end
    Plates.on = true
    Plates.token = Plates.token + 1
    local my = Plates.token
    CreateThread(function()
        while Plates.on and Plates.token == my and Main.open do
            if wanted() then
                local items = collect()
                if changed(items, Plates.last) then
                    Plates.last = items
                    U.Send('plates', { items = items })
                end
            elseif Plates.last == nil or #Plates.last > 0 then
                Plates.last = {}
                U.Send('plates', { items = {} })
            end
            Wait(40)
        end
        if Plates.token == my then Plates.on = false end
    end)
end

function Plates.Stop()
    Plates.on = false
    Plates.token = Plates.token + 1
    Plates.last = nil
    U.Send('plates', { items = {} })
end
