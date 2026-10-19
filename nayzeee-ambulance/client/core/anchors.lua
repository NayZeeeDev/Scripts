--[[
    NAYZEEE AMBULANCE - Client core: world anchors for in-world minigames (NZA.Anchors)

    Projects world points to the screen ~30 times a second and streams them to an app as
    NUI action 'anchors' → { [id] = { x = 0..1, y = 0..1, visible = bool, d = metres from
    the camera } }. JS side: NZA.ui.Anchors(app).

      NZA.Anchors.Track(app, map)      replace the tracked set of an app
          map = { [id] = { entity = ent, bone = boneId, offset = vec3 }   -- ped bone (+ local offset)
                       | { entity = ent, boneName = 'name', offset = vec3 } -- object bone
                       | { entity = ent, offset = vec3 }                    -- entity offset
                       | { coords = vec3 } }
      NZA.Anchors.Set(app, id, def)    add / replace one anchor
      NZA.Anchors.Remove(app, id)      drop one anchor
      NZA.Anchors.Clear(app)           stop tracking; sends one empty 'anchors' so JS hides them
      NZA.Anchors.Project(def) → x, y, visible, dist   (one-off projection)

    Only sends when something moved (> 0.0015 of the screen) or visibility changed.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Anchors = NZA.Anchors or {}
local A = NZA.Anchors

local INTERVAL = 33
local EPS = 0.0015      -- ~2 px at 1080p: a breathing patient's bones don't resend the map every tick

local tracked = {}     -- [app] = { [id] = def }
local lastSent = {}    -- [app] = { [id] = { x, y, visible } }
local running = false

local function worldPos(def)
    if type(def) ~= 'table' then return nil end
    local ent = def.entity
    if ent and ent ~= 0 then
        if not DoesEntityExist(ent) then return nil end
        local off = def.offset and NZA.Util.vec(def.offset) or nil
        if def.bone and IsEntityAPed(ent) then
            if off then return GetPedBoneCoords(ent, def.bone, off.x, off.y, off.z) end
            return GetPedBoneCoords(ent, def.bone, 0.0, 0.0, 0.0)
        end
        if def.boneName then
            local idx = GetEntityBoneIndexByName(ent, def.boneName)
            if idx ~= -1 then
                local p = GetWorldPositionOfEntityBone(ent, idx)
                return off and (p + off) or p
            end
        end
        if off then return GetOffsetFromEntityInWorldCoords(ent, off.x, off.y, off.z) end
        return GetEntityCoords(ent)
    end
    if def.coords then return NZA.Util.vec(def.coords) end
    return nil
end

function A.Project(def)
    local p = worldPos(def)
    if not p then return 0.0, 0.0, false, 0.0 end
    local onScreen, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    local cam = GetFinalRenderedCamCoord()
    local visible = (onScreen == true or onScreen == 1) and x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0
    return x, y, visible, #(cam - p)
end

local function tick()
    for app, map in pairs(tracked) do
        local prev = lastSent[app] or {}
        local out, changed = {}, false
        for id, def in pairs(map) do
            local x, y, visible, d = A.Project(def)
            x = math.floor(x * 10000 + 0.5) / 10000
            y = math.floor(y * 10000 + 0.5) / 10000
            local p = prev[id]
            if not p or p.visible ~= visible or math.abs(p.x - x) > EPS or math.abs(p.y - y) > EPS then
                changed = true
            end
            out[id] = { x = x, y = y, visible = visible, d = math.floor(d * 100 + 0.5) / 100 }
        end
        for id in pairs(prev) do
            if not out[id] then changed = true end
        end
        if changed then
            lastSent[app] = out
            NZA.UI.Send(app, 'anchors', out)
        end
    end
end

local function ensureLoop()
    if running then return end
    running = true
    CreateThread(function()
        while next(tracked) do
            tick()
            Wait(INTERVAL)
        end
        running = false
    end)
end

function A.Track(app, map)
    if type(app) ~= 'string' then return end
    tracked[app] = type(map) == 'table' and map or {}
    lastSent[app] = nil
    ensureLoop()
end

function A.Set(app, id, def)
    if type(app) ~= 'string' or id == nil then return end
    tracked[app] = tracked[app] or {}
    tracked[app][id] = def
    ensureLoop()
end

function A.Remove(app, id)
    local map = tracked[app]
    if not map then return end
    map[id] = nil
end

function A.Clear(app)
    if not tracked[app] then return end
    tracked[app] = nil
    lastSent[app] = nil
    NZA.UI.Send(app, 'anchors', {})
end

function A.Tracked(app)
    return tracked[app]
end
