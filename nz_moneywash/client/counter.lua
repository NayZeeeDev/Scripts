--[[ Money counter — a live digital screen (DUI) floats on the front of the machine, ticking up for
     everyone nearby, with GTA's heist cash-counter sounds and banknotes flicking out while it runs. ]]

CounterUI = {}

local C = Config.Counter
local TXD, TEX = 'nzmw_counter_txd', 'screen'
local dui, lastKey, active

local function ensureDui()
    if dui then return end
    dui = CreateDui(('nui://%s/web/counter.html'):format(NZ.Resource), 512, 256)
    local txd = CreateRuntimeTxd(TXD)
    CreateRuntimeTextureFromDuiHandle(txd, TEX, GetDuiHandle(dui))
end

local function send(msg)
    if dui then SendDuiMessage(dui, json.encode(msg)) end
end

local function playAnim()
    local a = C.anim
    if a and DoesAnimDictExist(a.dict) then
        U.playPed(a, 1)
    else
        U.playPed(Config.Anims.machine, 1)
    end
end

function CounterUI.start(id, mode)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'idle' then return end
        U.faceCoords(vec3(d.x, d.y, d.z))
        playAnim()
        local res = lib.callback.await('nzmw:counter:start', false, id, mode)
        if not res or not res.ok then U.stopPed() return UI.err(res) end
        UI.progress(mode == 'stacks' and ('Feeding %d stack(s) through'):format(res.stacks) or 'Running your cash through',
            res.duration * 1000, { canCancel = false })
        U.stopPed()
    end)
end

-- screen geometry: a panel just above the machine's front edge, facing whoever stands in front of it
local function screenQuad(s)
    local ent = s.ents.device or s.ents.main
    if not ent or not DoesEntityExist(ent) then return nil end
    local mn, mx = GetModelDimensions(GetEntityModel(ent))
    local pos = GetEntityCoords(ent)
    local h = math.rad(GetEntityHeading(ent))
    local fwd = vec3(-math.sin(h), math.cos(h), 0.0)
    local right = vec3(math.cos(h), math.sin(h), 0.0)
    local up = vec3(0.0, 0.0, 1.0)
    local w2, h2 = C.screen.width / 2, C.screen.height / 2
    local c = pos + fwd * (mn.y - 0.01) + up * (mx.z + C.screen.lift + h2)
    return {
        tl = c - right * w2 + up * h2, tr = c + right * w2 + up * h2,
        bl = c - right * w2 - up * h2, br = c + right * w2 - up * h2,
        front = pos + fwd * (mn.y - 0.05) + up * (mx.z * 0.65),
    }
end

local function tri(a, b, c, ua, va, ub, vb, uc, vc)
    DrawSpritePoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, 255, TXD, TEX,
        ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0)
end

local function drawQuad(q)
    -- both windings so the panel shows whatever the backface culling does
    tri(q.tl, q.tr, q.br, 0, 0, 1, 0, 1, 1)
    tri(q.tl, q.br, q.bl, 0, 0, 1, 1, 0, 1)
    tri(q.tl, q.br, q.tr, 0, 0, 1, 1, 1, 0)
    tri(q.tl, q.bl, q.br, 0, 0, 0, 1, 1, 1)
end

-- the counter worth drawing: one that's counting / showing a total wins, else the nearest
local function pick(pos)
    local best, bestScore
    for _, s in pairs(Render.stations) do
        if s.spawned and s.data.type == 'counter' then
            local d = #(pos - vec3(s.data.x, s.data.y, s.data.z))
            if d < C.drawDistance then
                local score = d - ((s.data.state ~= 'idle') and 100 or 0)
                if not bestScore or score < bestScore then best, bestScore = s, score end
            end
        end
    end
    return best
end

CreateThread(function()
    local nextTick, nextFx = 0, 0
    while true do
        local sleep = 500
        local pos = GetEntityCoords(PlayerPedId())
        local s = pick(pos)
        if s then
            sleep = 0
            ensureDui()
            local d = s.data
            local key = ('%s|%s|%s|%s'):format(s.id, d.state, d.endsAt or 0, d.amount or 0)
            if key ~= lastKey then
                -- counting just finished on the counter we're looking at → chime
                if active == s.id and lastKey and lastKey:find('|counting|', 1, true) and d.state == 'result' then
                    PlaySoundFromCoord(-1, C.sounds.finish.name, d.x, d.y, d.z + 1.0, C.sounds.finish.set, false, 10, false)
                end
                lastKey, active = key, s.id
                local remaining = d.endsAt and (d.endsAt - U.now()) or 0
                send({
                    theme = Config.UI, state = d.state, mode = d.mode, amount = d.amount or 0, amount2 = d.amount2,
                    bills = d.bills or 0, duration = (d.total or 0) * 1000,
                    elapsed = math.max(0, ((d.total or 0) - remaining) * 1000),
                })
            end
            local q = screenQuad(s)
            if q then
                drawQuad(q)
                if d.state == 'counting' then
                    local t = GetGameTimer()
                    if t >= nextTick and #(pos - q.front) < 12.0 then
                        PlaySoundFromCoord(-1, C.sounds.tick.name, q.front.x, q.front.y, q.front.z, C.sounds.tick.set, false, 8, false)
                        nextTick = t + C.sounds.tick.every
                    end
                    if C.fx and t >= nextFx then
                        lib.requestNamedPtfxAsset(C.fx.asset, 1000)
                        UseParticleFxAsset(C.fx.asset)
                        StartParticleFxNonLoopedAtCoord(C.fx.name, q.front.x, q.front.y, q.front.z, 0.0, 0.0, 0.0, C.fx.scale, false, false, false)
                        nextFx = t + C.fx.every
                    end
                end
            end
        elseif lastKey then
            lastKey, active = nil, nil
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == NZ.Resource and dui then DestroyDui(dui) end
end)
