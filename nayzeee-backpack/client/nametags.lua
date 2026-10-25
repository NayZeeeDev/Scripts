-----------------------------------------------------------------
-- Name tags (client)
--
-- Finds tagged bags close to the camera (a few times a second), then,
-- only while one is in range, places their tags on screen every frame.
-- Nothing runs per frame when no tagged bag is near you.
-----------------------------------------------------------------

local cfg = Config.NameTags
if not cfg or not cfg.enabled then return end

local myId = GetPlayerServerId(PlayerId())
local dims = {}       -- [model] = { c = centre, h = half height }
local visible = {}    -- what we're drawing
local drawing = false
local lastSig = ''
local editing = false

local function anchorOf(entity)
    local model = GetEntityModel(entity)
    local d = dims[model]
    if not d then
        local mn, mx = GetModelDimensions(model)
        d = {
            c = (mn + mx) * 0.5,
            h = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) * 0.5,
        }
        dims[model] = d
    end
    local w = GetOffsetFromEntityInWorldCoords(entity, d.c.x, d.c.y, d.c.z)
    return vector3(w.x, w.y, w.z + d.h * 0.55)
end

local function sigOf(t)
    return table.concat({ t.t or '', t.f or '', t.c or '', t.c2 or '', t.s or '', t.e or '', t.p or '' }, '|')
end

local function draw()
    if drawing then return end
    drawing = true
    CreateThread(function()
        while #visible > 0 do
            local pos = {}
            if not IsPauseMenuActive() and not editing then
                local cam = GetFinalRenderedCamCoord()
                for _, v in ipairs(visible) do
                    if DoesEntityExist(v.entity) then
                        local a = anchorOf(v.entity)
                        local on, x, y = GetScreenCoordFromWorldCoord(a.x, a.y, a.z)
                        if on then
                            local d = #(a - cam)
                            local scale = math.max(0.42, math.min(1.15, 1.6 / math.max(d, 0.5)))
                            local alpha = math.max(0.0, math.min(1.0, cfg.distance - d)) -- fades over the last metre
                            pos[v.k] = { x, y, scale, alpha }
                        end
                    end
                end
            end
            SendNUIMessage({ action = 'tagPos', data = pos })
            Wait(0)
        end
        SendNUIMessage({ action = 'tagSet', data = {} })
        drawing = false
    end)
end

CreateThread(function()
    Wait(1500)
    SendNUIMessage({ action = 'tagInit', data = { fonts = cfg.fonts } })

    while true do
        local list = {}
        local cam = GetFinalRenderedCamCoord()
        local me = PlayerPedId()

        local function consider(k, entity, tag, locked, own)
            local d = #(GetEntityCoords(entity) - cam)
            if d > cfg.distance + 2.0 then return end
            -- don't read tags through walls (your own is always in view)
            if not own and not HasEntityClearLosToEntity(me, entity, 17) then return end
            list[#list + 1] = { k = k, entity = entity, tag = tag, l = locked or false, d = d }
        end

        for _, t in ipairs(BagTagTargets and BagTagTargets() or {}) do
            local own = t.id == myId
            if not own or cfg.showOwn then consider('p' .. t.id, t.entity, t.tag, t.locked, own) end
        end
        if cfg.showPlaced and PlacedTagTargets then
            for _, t in ipairs(PlacedTagTargets()) do consider('g' .. t.id, t.entity, t.tag, false, false) end
        end

        table.sort(list, function(a, b) return a.d < b.d end)
        for i = #list, (cfg.maxVisible or 4) + 1, -1 do list[i] = nil end

        local parts = {}
        for i, v in ipairs(list) do parts[i] = v.k .. '=' .. sigOf(v.tag) .. tostring(v.l) end
        local sig = table.concat(parts, ';')
        if sig ~= lastSig then
            lastSig = sig
            local send = {}
            for i, v in ipairs(list) do send[i] = { k = v.k, tag = v.tag, l = v.l } end
            SendNUIMessage({ action = 'tagSet', data = send })
        end

        visible = list
        if #list > 0 then draw() end
        Wait(#list > 0 and 250 or 750)
    end
end)

-----------------------------------------------------------------
-- editor
-----------------------------------------------------------------

local function closeEditor()
    if not editing then return end
    editing = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'tagEditClose' })
end

RegisterNetEvent('nayzeee-backpack:tag:edit', function(data)
    data = data or {}
    data.cfg = {
        fonts = cfg.fonts, colors = cfg.colors, customColors = cfg.customColors ~= false,
        styles = cfg.styles, effects = cfg.effects, particles = cfg.particles, maxLength = cfg.maxLength or 18,
    }
    editing = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'tagEdit', data = data })
end)

RegisterNUICallback('tag:save', function(d, cb)
    cb('ok')
    if d and d.tag then TriggerServerEvent('nayzeee-backpack:tag:save', d.tag) end
    closeEditor()
end)

RegisterNUICallback('tag:remove', function(_, cb)
    cb('ok')
    TriggerServerEvent('nayzeee-backpack:tag:remove')
    closeEditor()
end)

RegisterNUICallback('tag:close', function(_, cb) cb('ok') closeEditor() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and editing then SetNuiFocus(false, false) end
end)
