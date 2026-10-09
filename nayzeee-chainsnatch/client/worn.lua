-----------------------------------------------------------------
-- Everyone's chains
--
-- Each player's statebag `nzc_worn` = { c = chain, v = texture, h = holding }.
-- Every client draws its own local prop for every player in range,
-- on the neck (fit 'worn') or in the hand (fit 'hold'). No networked
-- objects, nothing to clean up when someone crashes.
--
-- The loop idles at 2s and only runs at 500ms while someone in range
-- wears a chain. Statebag changes redraw straight away.
-----------------------------------------------------------------

WornProps = {}

local props = {}       -- [serverId] = { entity, sig }
local hiddenSelf = false
local version = 0      -- bumped when fits change, forces a redraw
local dirty = {}

local function me() return GetPlayerServerId(PlayerId()) end

local function remove(sid)
    local p = props[sid]
    if not p then return end
    Util.delete(p.entity)
    props[sid] = nil
end

local function refresh(sid, ped)
    local st = Player(sid).state.nzc_worn
    if not st or not Chains.exists(st.c) or (sid == me() and hiddenSelf) then return remove(sid) end

    local female = Util.isFemale(ped)
    local mode = st.h and 'hold' or 'worn'
    local sig = ('%s|%s|%s|%d|%s|%d'):format(st.c, st.v or 'a', mode, ped, female and 'f' or 'm', version)
    local p = props[sid]
    if p and p.sig == sig and DoesEntityExist(p.entity) and IsEntityAttachedToEntity(p.entity, ped) then return end

    local entity = p and DoesEntityExist(p.entity) and p.model == Chains.model(st.c, st.v) and p.entity or nil
    if not entity then
        remove(sid)
        entity = Util.spawnChain(st.c, st.v, GetEntityCoords(ped))
        if not entity then return end
    end
    local f = Chains.fit(st.c, mode, female)
    Util.attach(entity, ped, f.bone, f.pos, f.rot)
    props[sid] = { entity = entity, sig = sig, model = Chains.model(st.c, st.v) }
end

local function tick()
    local range = Config.Wear.RenderDistance or 120.0
    local myPed = PlayerPedId()
    local mc = GetEntityCoords(myPed)
    local seen, any = {}, false
    for _, pl in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pl)
        local ped = GetPlayerPed(pl)
        if ped ~= 0 and DoesEntityExist(ped) and (ped == myPed or #(GetEntityCoords(ped) - mc) < range) then
            seen[sid] = true
            if Player(sid).state.nzc_worn then any = true end
            refresh(sid, ped)
        end
    end
    for sid in pairs(props) do
        if not seen[sid] then remove(sid) end
    end
    return any
end

CreateThread(function()
    while true do
        local any = tick()
        local wait = any and 500 or 2000
        local t = 0
        while t < wait do
            Wait(100)
            t = t + 100
            if next(dirty) then break end
        end
        dirty = {}
    end
end)

AddStateBagChangeHandler('nzc_worn', nil, function(bagName)
    local pl = GetPlayerFromStateBagName(bagName)
    if pl and pl ~= 0 then dirty[GetPlayerServerId(pl)] = true else dirty[0] = true end
end)

AddEventHandler('nzc:registry', function()
    version = version + 1
    dirty[0] = true
end)

--- The studio hides your own chain while it shows its preview.
function WornProps.hideSelf(on)
    hiddenSelf = on and true or false
    dirty[0] = true
    if on then remove(me()) end
end

function WornProps.entity(sid) local p = props[sid or me()]; return p and p.entity or nil end

--- What I'm wearing right now: key, letter, holding
function WornProps.mine()
    local st = LocalPlayer.state.nzc_worn
    if not st then return nil end
    return st.c, st.v, st.h == true
end

function WornProps.of(ped)
    local sid = Util.serverIdOf(ped)
    return sid and Player(sid).state.nzc_worn or nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for sid in pairs(props) do remove(sid) end
end)
