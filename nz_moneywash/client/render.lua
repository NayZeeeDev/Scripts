--[[ Render — every machine is a client-side prop rig driven by the server's GlobalState.
     Same state for everyone → door swings, drum spins, press runs and blade drops in sync. ]]

Render = { stations = {}, decor = {} }

local stations = Render.stations
local P, PA = Config.Props, Config.PropAnims

function Render.get(id) return stations[id] end
function Render.data(id) return stations[id] and stations[id].data end

---------------------------------------------------------------------------------------------------
-- entity slots
---------------------------------------------------------------------------------------------------
local function setEnt(s, key, model, pos, heading, opts)
    local cur = s.ents[key]
    local hash = U.hash(model)
    -- compare unsigned: GetEntityModel and joaat can disagree on sign
    if cur and DoesEntityExist(cur) and (GetEntityModel(cur) & 0xFFFFFFFF) == (hash & 0xFFFFFFFF) then return cur, false end
    U.deleteEnt(cur)
    s.ents[key] = U.spawnProp(model, pos, heading, opts)
    return s.ents[key], true
end

local function delEnt(s, key)
    U.deleteEnt(s.ents[key])
    s.ents[key] = nil
end

local function stopFx(s)
    if s.fx then StopParticleFxLooped(s.fx, false) s.fx = nil end
end

local function startFx(s)
    if s.fx then return end
    local fx = Config.JamFx
    lib.requestNamedPtfxAsset(fx.asset, 5000)
    UseParticleFxAsset(fx.asset)
    local pos = U.offset(s.data, fx.offset)
    s.fx = StartParticleFxLoopedAtCoord(fx.name, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fx.scale, false, false, false, false)
end

local function despawn(s)
    for key in pairs(s.ents) do delEnt(s, key) end
    stopFx(s)
    s.spawned = false
end

local function base(d) return vec3(d.x, d.y, d.z) end

local function playProp(ent, dict, clip, toEnd)
    if not ent or not DoesEntityExist(ent) then return end
    lib.requestAnimDict(dict, 5000)
    PlayEntityAnim(ent, clip, dict, 8.0, false, true, false, 0.0, 0)
    if toEnd then
        CreateThread(function()
            Wait(0)
            SetEntityAnimCurrentTime(ent, dict, clip, 0.999)
        end)
    end
end

---------------------------------------------------------------------------------------------------
-- per-type visuals
---------------------------------------------------------------------------------------------------
local Visual = {}

local function doorOpen(state) return state == 'open' or state == 'loaded' end
local function hasCash(state)
    return state == 'loaded' or state == 'ready' or state == 'done' or state == 'jammed'
end

function Visual.washer(s, prev, fresh)
    local d = s.data
    local model = NZ.mainModel('washer', d.state)
    local main, swapped = setEnt(s, 'main', model, base(d), d.h)
    local open = doorOpen(d.state)

    if model == P.washer then
        local wasOpen = (not fresh and not swapped and prev and doorOpen(prev.state)) or false
        if open and not wasOpen then
            playProp(main, PA.washerDict, PA.open, fresh or swapped)
        elseif not open and wasOpen then
            playProp(main, PA.washerDict, PA.close, false)
        end
    end

    if open then
        setEnt(s, 'blocker', P.washerBlocker, base(d), d.h, { invisible = true })
    else
        delEnt(s, 'blocker')
    end

    local bagOff = Config.Offsets.washer.bag
    if d.state == 'open' then
        setEnt(s, 'bag', P.bagFull, U.offset(d, bagOff), d.h + bagOff.w)
    elseif d.state == 'loaded' then
        setEnt(s, 'bag', P.bagEmpty, U.offset(d, bagOff), d.h + bagOff.w)
    else
        delEnt(s, 'bag')
    end

    if hasCash(d.state) then
        setEnt(s, 'money', P.washerMoney, base(d), d.h, { noCollision = true })
    else
        delEnt(s, 'money')
    end
end

function Visual.printer(s)
    local d = s.data
    setEnt(s, 'main', NZ.mainModel('printer', d.state), base(d), d.h)
    local po = Config.Offsets.printer
    setEnt(s, 'paper', P.paperRoll, U.offset(d, po.paper), d.h + po.paper.w)
    if d.state == 'done' then
        setEnt(s, 'sheets', P.sheets[1], U.offset(d, po.sheets), d.h + po.sheets.w, { noCollision = true })
    else
        delEnt(s, 'sheets')
    end
end

function Visual.cutter(s, prev, fresh)
    local d = s.data
    local main = setEnt(s, 'main', P.cutter, base(d), d.h)
    if d.state == 'cutting' or d.state == 'done' then
        local stage = math.min((d.cut or 0) + 1, #P.sheets)
        if d.state == 'done' then stage = #P.sheets end
        setEnt(s, 'sheet', P.sheets[stage], U.offset(d, Config.Offsets.cutter.sheet), d.h, { noCollision = true })
    else
        delEnt(s, 'sheet')
    end
    if not fresh and prev and d.seq ~= prev.seq then
        CreateThread(function()
            playProp(main, PA.cutterDict, PA.bladeDown, false)
            Wait(Config.Anims.cutting.bladeUp)
            playProp(main, PA.cutterDict, PA.bladeUp, false)
        end)
    end
end

local function apply(s, prev, fresh)
    local fn = Visual[s.data.type]
    if fn then fn(s, prev, fresh) end
    if s.data.state == 'jammed' then startFx(s) else stopFx(s) end
end

---------------------------------------------------------------------------------------------------
-- state sync
---------------------------------------------------------------------------------------------------
function Render.update(id, value)
    local s = stations[id]
    if not value then
        if s then
            despawn(s)
            Interact.remove(s)
            stations[id] = nil
        end
        return
    end
    if not s then
        s = { id = id, data = value, ents = {}, spawned = false }
        stations[id] = s
        Interact.add(s)
        return
    end
    local prev = s.data
    s.data = value
    if s.spawned then apply(s, prev, false) end
end

function Render.syncIndex(list)
    local keep = {}
    for _, id in ipairs(list or {}) do
        keep[id] = true
        if not stations[id] then Render.update(id, GlobalState[NZ.stateKey(id)]) end
    end
    for id in pairs(stations) do
        if not keep[id] then Render.update(id, nil) end
    end
end

-- Handlers only queue work; one worker thread applies it so prop spawning never races.
local queue = {}

AddStateBagChangeHandler(nil, 'global', function(_, key, value)
    if key == 'nzmw:index' then
        queue[#queue + 1] = { index = value }
    elseif key:sub(1, #NZ.StatePrefix) == NZ.StatePrefix then
        queue[#queue + 1] = { id = key:sub(#NZ.StatePrefix + 1), value = value }
    end
end)

---------------------------------------------------------------------------------------------------
-- streaming loop
---------------------------------------------------------------------------------------------------
function Render.start()
    for _, op in ipairs(Config.Operations) do
        for _, dcr in ipairs(op.decor or {}) do
            Render.decor[#Render.decor + 1] = { model = dcr.model, coords = dcr.coords }
        end
    end

    local function stream()
        local pos = GetEntityCoords(PlayerPedId())
        local dist = Config.RenderDistance
        for _, s in pairs(stations) do
            local near = #(pos - vec3(s.data.x, s.data.y, s.data.z)) < dist
            if near and not s.spawned then
                s.spawned = true
                apply(s, nil, true)
            elseif not near and s.spawned then
                despawn(s)
            end
        end
        for _, dc in ipairs(Render.decor) do
            local near = #(pos - dc.coords.xyz) < dist
            if near and not dc.ent then
                dc.ent = U.spawnProp(dc.model, dc.coords.xyz, dc.coords.w)
            elseif not near and dc.ent then
                U.deleteEnt(dc.ent)
                dc.ent = nil
            end
        end
    end

    CreateThread(function()
        local nextStream = 0
        while true do
            while #queue > 0 do
                local q = table.remove(queue, 1)
                if q.id then Render.update(q.id, q.value) else Render.syncIndex(q.index) end
            end
            if GetGameTimer() >= nextStream then
                stream()
                nextStream = GetGameTimer() + 750
            end
            Wait(50)
        end
    end)

    if Config.StatusText.enabled then
        CreateThread(function()
            while true do
                local sleep = 500
                local pos = GetEntityCoords(PlayerPedId())
                for _, s in pairs(stations) do
                    if s.spawned then
                        local d = s.data
                        local p = vec3(d.x, d.y, d.z + (d.type == 'printer' and 2.05 or d.type == 'washer' and 1.35 or 1.25))
                        if #(pos - p) < Config.StatusText.distance then
                            sleep = 0
                            Render.drawStatus(p, d)
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end

local stateLabel = {
    idle = 'IDLE', open = 'DOOR OPEN', loaded = 'LOADED', ready = 'READY', running = 'RUNNING',
    jammed = 'JAMMED', done = 'DONE', cutting = 'CUTTING',
}

local function text3d(pos, str, scale, r, g, b, a)
    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, a)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

function Render.drawStatus(pos, d)
    local label = stateLabel[d.state] or d.state:upper()
    local r, g, b = 8, 175, 162
    if d.state == 'jammed' then r, g, b = 229, 72, 77 end
    if d.state == 'idle' then r, g, b = 158, 165, 170 end

    local line = d.label:upper() .. '  ·  ' .. label
    if d.state == 'running' and d.endsAt then
        local left = d.endsAt - U.now()
        local pct = d.total and d.total > 0 and (1 - left / d.total) or 0
        local bars = math.floor(NZ.clamp(pct, 0, 1) * 12)
        line = line .. '  ' .. U.fmtTime(left) .. '\n' .. ('|'):rep(bars) .. ('.'):rep(12 - bars)
    elseif d.state == 'cutting' then
        line = line .. ('  %d/%d'):format(d.cut or 0, Config.Stages.cutter.cuts)
    end
    text3d(pos, line, 0.32, r, g, b, 235)
    if d.wear and d.wear >= 60 then
        text3d(vec3(pos.x, pos.y, pos.z - 0.12), ('WEAR %d%%'):format(math.floor(d.wear)), 0.26, 229, 165, 10, 220)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.Resource then return end
    for _, s in pairs(stations) do despawn(s) end
    for _, dc in ipairs(Render.decor) do U.deleteEnt(dc.ent) end
end)
