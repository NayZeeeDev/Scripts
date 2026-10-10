--[[ Client helpers: models with fallbacks, local props / peds, blips, camera rays ]]

Util = {}

local warned = {}

--- loads `model` (name or hash). Falls back to `fallback` / Config.FallbackModel when it isn't streamed.
function Util.model(model, fallback)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        if not warned[model] then
            warned[model] = true
            print(('^3[%s] model %s is not streamed, using a fallback^7'):format(RES, tostring(model)))
        end
        if fallback == false then return nil end
        return Util.model(fallback or Config.FallbackModel, false)
    end
    lib.requestModel(hash, 10000)
    return hash
end

function Util.groundZ(x, y, z)
    for _, dz in ipairs({ 1.5, 5.0, 25.0, 100.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + dz, false)
        if ok then return gz end
    end
    return z
end

--- position + heading + uniform scale in one go (scale only works on props without collision)
function Util.transform(ent, pos, heading, scale)
    if not ent or not DoesEntityExist(ent) then return end
    scale = scale or 1.0
    local r = math.rad(heading or 0.0)
    local fx, fy = -math.sin(r) * scale, math.cos(r) * scale
    local rx, ry = math.cos(r) * scale, math.sin(r) * scale
    SetEntityMatrix(ent, fx, fy, 0.0, rx, ry, 0.0, 0.0, 0.0, scale, pos.x, pos.y, pos.z)
end

--- non-networked object, frozen. opts = { noCollision, fallback, freeze, scale }
function Util.prop(model, coords, heading, opts)
    opts = opts or {}
    local hash = Util.model(model, opts.fallback)
    if not hash then return nil end
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, opts.freeze ~= false)
    if opts.noCollision then SetEntityCollision(obj, false, false) end
    if opts.scale and opts.scale ~= 1.0 then Util.transform(obj, coords, heading, opts.scale) end
    SetModelAsNoLongerNeeded(hash)
    return obj
end

function Util.delete(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

--- local, invincible, calm ped standing / doing a scenario
function Util.ped(model, coords, scenario)
    local hash = Util.model(model, 'a_m_m_hillbilly_01')
    local z = Util.groundZ(coords.x, coords.y, coords.z)
    local ped = CreatePed(4, hash, coords.x, coords.y, z, coords.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, true)
    if scenario then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    return ped
end

function Util.blip(coords, cfg, label, route)
    local b = AddBlipForCoord(coords.x, coords.y, coords.z or 0.0)
    SetBlipSprite(b, cfg.sprite or 1)
    SetBlipColour(b, cfg.color or 0)
    SetBlipScale(b, cfg.scale or 0.8)
    SetBlipAsShortRange(b, not route)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or cfg.label or 'Blip')
    EndTextCommandSetBlipName(b)
    if route then
        SetBlipRoute(b, true)
        SetBlipRouteColour(b, cfg.color or 0)
    end
    return b
end

function Util.removeBlip(b)
    if b and DoesBlipExist(b) then RemoveBlip(b) end
end

function Util.fade(out, ms)
    ms = ms or 400
    if out then DoScreenFadeOut(ms) else DoScreenFadeIn(ms) end
    local t = GetGameTimer() + ms + 100
    while (out and not IsScreenFadedOut() or not out and not IsScreenFadedIn()) and GetGameTimer() < t do Wait(0) end
end

function Util.teleport(c, heading)
    local ped = cache.ped
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, heading or c.w or 0.0)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(0) end
end

function Util.anim(ped, dict, clip, flag, dur)
    lib.requestAnimDict(dict)
    TaskPlayAnim(ped, dict, clip, 3.0, 3.0, dur or -1, flag or 49, 0, false, false, false)
    RemoveAnimDict(dict)
end

--[[ camera maths ]]

function Util.rotToDir(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vec3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

--- world-space ray through screen point (sx, sy in 0..1) for a scripted camera
function Util.screenRay(cam, sx, sy)
    local pos, rot = GetCamCoord(cam), GetCamRot(cam, 2)
    local fwd = Util.rotToDir(rot)
    local z = math.rad(rot.z)
    local right = vec3(math.cos(z), math.sin(z), 0.0)
    local up = vec3(right.y * fwd.z - right.z * fwd.y, right.z * fwd.x - right.x * fwd.z, right.x * fwd.y - right.y * fwd.x)
    local tanY = math.tan(math.rad(GetCamFov(cam)) * 0.5)
    local tanX = tanY * GetAspectRatio(true)
    local nx, ny = (sx * 2.0 - 1.0) * tanX, (1.0 - sy * 2.0) * tanY
    local dir = fwd + right * nx + up * ny
    return pos, dir / #dir
end

--- where the ray hits the horizontal plane at height `z`
function Util.rayPlane(pos, dir, z)
    if math.abs(dir.z) < 1e-4 then return nil end
    local t = (z - pos.z) / dir.z
    if t <= 0 then return nil end
    return pos + dir * t
end

function Util.toScreen(p)
    local ok, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    if not ok then return nil end
    return x, y
end

--- cursor position (0..1) while the NUI has focus
function Util.cursor()
    local x, y = GetNuiCursorPosition()
    local w, h = GetActiveScreenResolution()
    return x / w, y / h, w, h
end

function Util.rel(origin, rel)
    return vec3(origin.x + rel.x, origin.y + rel.y, origin.z + rel.z)
end

--- world position of a local offset on an entity
function Util.off(ent, v)
    return GetOffsetFromEntityInWorldCoords(ent, v.x, v.y, v.z)
end

RegisterCommand('nzwlcoords', function()
    local c, h = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)
    local s = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, h)
    lib.setClipboard(s)
    UI.notify('Copied ' .. s, 'success')
end, false)
