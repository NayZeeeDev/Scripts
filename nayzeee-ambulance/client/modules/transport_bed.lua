--[[
    NAYZEEE AMBULANCE - Transport (client): hospital beds & tables

    Any hospital point whose type is listed in Config.Transport.Beds.types (bed, surgery, xray, angio,
    ultrasound, donation) or whose data / type data has bed = true is "bed-like": a patient on a
    stretcher (or carried) can be moved onto it. The patient lies at the point coords (+ the type's
    nudge, or point.data.lie = { x, y, z }) and the server sets patient.meta.bed = { point, type }, which
    the X-ray / surgery / angiography / ultrasound procedures check.

      NZA.Transport.Bed.IsBed(point) → bool          Label(point) → text
      NZA.Transport.Bed.Nearest(coords, range, free) → point, dist
      NZA.Transport.Bed.Occupied(point) → bool        (someone placed there through this module)
      NZA.Transport.Bed.Transfer(point, stretcherEnt) → bool     stretcher → bed
      NZA.Transport.Bed.PlaceFromCarry(point, target) → bool     shoulder → bed
      NZA.Transport.Bed.HelpOff(entity, target)                  'Help patient off the table'
      NZA.Transport.Bed.PointFromSpot(vector4) → point | nil
    Callbacks used: nza:transport:bed:place, nza:transport:bed:leave
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local Tr = NZA.Transport
Tr.Bed = Tr.Bed or {}
local B = Tr.Bed

local function coords(pt)
    local c = pt and pt.coords
    if not c then return nil end
    return vector3(c.x, c.y, c.z)
end

function B.IsBed(pt)
    if type(pt) ~= 'table' then return false end
    local types = Tr.Cfg('Beds').types or {}
    if types[pt.type] then return true end
    if type(pt.data) == 'table' and pt.data.bed == true then return true end
    local def = NZA.Points.Type(pt.type)
    return def ~= nil and type(def.data) == 'table' and def.data.bed == true
end

function B.Label(pt)
    if not pt then return '' end
    if type(pt.label) == 'string' and pt.label ~= '' then return pt.label end
    local k = 'transport.pt_' .. tostring(pt.type)
    local s = NZA.L(k)
    if s ~= k then return s end
    local def = NZA.Points.Type(pt.type)
    if def and type(def.label) == 'string' then return def.label end
    return Tr.L('pt_other')
end

local function lyingOn(ped, pt)
    local b = Tr.Bag(ped)
    return type(b) == 'table' and b.m == 'bed' and tostring(b.b) == tostring(pt.id)
end

function B.Occupied(pt)
    local c = coords(pt)
    if not c then return false end
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if #(GetEntityCoords(ped) - c) < 4.0 and lyingOn(ped, pt) then return true end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - c) < 4.0 and NetworkGetEntityIsNetworked(ped) and lyingOn(ped, pt) then
            return true
        end
    end
    return false
end

function B.Nearest(pos, range, freeOnly)
    if Tr.Cfg('Beds').enabled == false then return nil end
    local best, bestD = nil, range or 3.0
    for _, pt in ipairs(NZA.Points.All()) do
        if B.IsBed(pt) then
            local c = coords(pt)
            if c then
                local d = #(pos - c)
                if d <= bestD and (not freeOnly or not B.Occupied(pt)) then best, bestD = pt, d end
            end
        end
    end
    if not best then return nil end
    return best, bestD
end

function B.PointFromSpot(at)
    if not at then return nil end
    local v = vector3(at.x, at.y, at.z)
    for _, pt in ipairs(NZA.Points.All()) do
        local c = coords(pt)
        if c and #(c - v) < 0.05 then return pt end
    end
    return nil
end

local function liftAnim(target)
    local me = PlayerPedId()
    local pick = Tr.Cfg('Carry').pickup
    if type(pick) ~= 'table' then return nil end
    local ent = NZA.Target.Entity(target)
    if ent ~= 0 then
        TaskTurnPedToFaceEntity(me, ent, 400)
        Wait(350)
    end
    Tr.Play(me, pick, { flag = 48 })
    Wait(math.floor((pick.ms or 900) * 0.6))
    return pick
end

local function patientOfStretcher(ent)
    local bag = Tr.StrBag(ent)
    return bag and bag.pk or nil
end

function B.Transfer(pt, strEnt)
    if not pt or not strEnt or strEnt == 0 then return false end
    local target = patientOfStretcher(strEnt)
    if not target then
        Tr.Err({ err = 'no_patient' })
        return false
    end
    if target.kind == 'npc' then
        local npc = NZA.Target.Entity(target)
        if npc ~= 0 then Tr.Control(npc, 1500) end
    end
    local pushing = Tr.S.pushing and Tr.S.pushing.ent == strEnt
    local pick = not pushing and liftAnim(target) or nil
    local ok, res = Tr.Call('bed:place', pt.id, Tr.Net(strEnt))
    if pick then Tr.StopAnim(PlayerPedId(), pick) end
    if not ok then
        Tr.Err(res)
        return false
    end
    if res.npc then Tr.ApplyNpc(res.target or target, res.cmd) end
    Tr.Toast(res.msg, 'success')
    return true
end

function B.PlaceFromCarry(pt, target)
    if not pt then return false end
    if target and target.kind == 'npc' then
        local npc = NZA.Target.Entity(target)
        if npc ~= 0 then Tr.Control(npc, 1500) end
    end
    local ok, res = Tr.Call('bed:place', pt.id, nil)
    if not ok then
        Tr.Err(res)
        return false
    end
    if res.npc then Tr.ApplyNpc(res.target or target, res.cmd) end
    Tr.Toast(res.msg, 'success')
    return true
end

function B.HelpOff(entity, target)
    if target.kind == 'npc' then Tr.Control(entity, 1500) end
    local me = PlayerPedId()
    TaskTurnPedToFaceEntity(me, entity, 500)
    Wait(400)
    local anim = Tr.Cfg('HelpUp').anim
    if anim then
        Tr.Play(me, anim, { flag = 48 })
        Wait(math.floor((anim.ms or 1000) * 0.5))
    end
    local ok, res = Tr.Call('bed:leave', target)
    if anim then Tr.StopAnim(me, anim) end
    if not ok then return Tr.Err(res) end
    if res.npc then Tr.ApplyNpc(res.target or target, res.cmd) end
    Tr.Toast(res.msg, 'success')
end
