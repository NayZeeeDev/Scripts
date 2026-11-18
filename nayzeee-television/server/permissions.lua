--[[ Who may do what ]]

Perms = {}

local adminCache = {}

function Perms.isAdmin(src)
    local c = adminCache[src]
    if c and c.t > GetGameTimer() then return c.v end
    local v = Bridge.isAdmin(src)
    adminCache[src] = { v = v, t = GetGameTimer() + 15000 }
    return v
end

AddEventHandler('playerDropped', function() adminCache[source] = nil end)

function Perms.isOwner(src, tv)
    return tv.owner ~= nil and tv.owner == Bridge.identifier(src)
end

--- Owner or admin: pick up, rename, permissions, links.
function Perms.canManage(src, tv)
    return Perms.isAdmin(src) or Perms.isOwner(src, tv)
end

--- Anyone allowed to use the remote / media panel.
function Perms.canControl(src, tv)
    if Perms.isAdmin(src) or Perms.isOwner(src, tv) then return true end
    if tv.locked then return false, 'locked' end
    local p = tv.perms or {}
    if p.allowed and p.allowed[Bridge.identifier(src)] then return true end
    if p.public then return true end
    local job, grade = Bridge.job(src)
    if job and p.jobs and p.jobs[job] ~= nil and grade >= (tonumber(p.jobs[job]) or 0) then return true end
    local gang, ggrade = Bridge.gang(src)
    if gang and p.gangs and p.gangs[gang] ~= nil and ggrade >= (tonumber(p.gangs[gang]) or 0) then return true end
    if p.ace and p.ace ~= '' and IsPlayerAceAllowed(src, p.ace) then return true end
    return false, 'no_permission'
end

function Perms.playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- Is the player close enough to reach this screen (remote / panel / phone)?
function Perms.inReach(src, tv, extra)
    if Perms.isAdmin(src) then return true end
    local pc = Perms.playerCoords(src)
    if not pc then return false end
    local reach = math.max(tv.range or 20.0, Config.Phone.Range, Config.Remote.Range) + (extra or 6.0)
    local c = tv.coords
    return #(pc - vector3(c.x, c.y, c.z)) <= reach
end
