-----------------------------------------------------------------
-- Name tags (client)
--
-- The name floats over a bag that's on the ground (set down, or put down
-- to open), and over the wearer's head too when Config.NameTags.showWorn
-- is on. Finds tags close to the camera a few times a
-- second, then, only while one is in range, places them on screen every
-- frame. Nothing runs per frame when no tag is near you.
-----------------------------------------------------------------

local cfg = Config.NameTags
if not cfg or not cfg.enabled then return end

local HEAD = 31086    -- SKEL_Head
local myId = GetPlayerServerId(PlayerId())
local tops = {}       -- [model] = top-centre offset of the model
local visible = {}    -- what we're drawing
local drawing = false
local lastSig = ''
local editing = false

local range = cfg.distance or 15.0
local height = cfg.height or 0.32       -- above the head bone
local bagHeight = cfg.bagHeight or 0.18 -- above a set-down bag

--- World point the tag's bottom-centre sits on.
local function anchorOf(v)
    if v.ped then
        local h = GetPedBoneCoords(v.ped, HEAD, 0.0, 0.0, 0.0)
        return vector3(h.x, h.y, h.z + height)
    end
    local model = GetEntityModel(v.entity)
    local t = tops[model]
    if not t then
        local mn, mx = GetModelDimensions(model)
        t = vector3((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mx.z)
        tops[model] = t
    end
    local w = GetOffsetFromEntityInWorldCoords(v.entity, t.x, t.y, t.z)
    return vector3(w.x, w.y, w.z + bagHeight)
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
                    if DoesEntityExist(v.ped or v.entity) then
                        local a = anchorOf(v)
                        local on, x, y = GetScreenCoordFromWorldCoord(a.x, a.y, a.z)
                        if on then
                            local d = #(a - cam)
                            -- full size up close, then a steady readable size, fading over the last 2 m
                            local scale = math.max(0.55, math.min(1.0, 3.0 / math.max(d, 0.5)))
                            local alpha = math.max(0.0, math.min(1.0, (range - d) / 2.0))
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

        local function consider(v, own)
            local e = v.ped or v.entity
            local d = #(GetEntityCoords(e) - cam)
            if d > range + 1.0 then return end
            -- no reading names through walls (your own always shows)
            if not own and not HasEntityClearLosToEntity(me, e, 17) then return end
            v.d = d
            list[#list + 1] = v
        end

        for _, t in ipairs(BagTagTargets and BagTagTargets() or {}) do
            local own = t.id == myId
            if not own or cfg.showOwn then
                consider({ k = 'p' .. t.id, ped = t.ped, entity = t.entity, tag = t.tag, l = t.locked or false }, own)
            end
        end
        if cfg.showPlaced and PlacedTagTargets then
            for _, t in ipairs(PlacedTagTargets()) do
                consider({ k = 'g' .. t.id, entity = t.entity, tag = t.tag, l = false }, false)
            end
        end

        table.sort(list, function(a, b) return a.d < b.d end)
        for i = #list, (cfg.maxVisible or 8) + 1, -1 do list[i] = nil end

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
