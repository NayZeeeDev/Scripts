--[[ Money pallet — load the duffel, grab a stack, seize the lot ]]

PalletUI = {}

local A, C = Config.Anims, Config.Pallet

-- a duffel on the floor in front of the player (empty → full while you load it)
local function dropBag(model)
    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.55, 0.0)
    return U.spawnProp(model, vec3(pos.x, pos.y, GetEntityCoords(ped).z - 0.98), GetEntityHeading(ped) + 90.0, { noCollision = true })
end

local function fillBag(bag)
    if not bag then return nil end
    local c, h = GetEntityCoords(bag), GetEntityHeading(bag)
    U.deleteEnt(bag)
    return U.spawnProp(Config.Props.bagFull, c, h, { noCollision = true })
end

local function work(d, label, ms)
    U.faceCoords(vec3(d.x, d.y, d.z))
    local bag = dropBag(Config.Props.bagEmpty)
    U.playPed(A.grab, 1)
    local ok = UI.progress(label, ms)
    if ok then bag = fillBag(bag) end
    U.stopPed()
    return ok, bag
end

function PalletUI.take(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'done' then return end
        local ok, bag = work(d, 'Loading the duffel bag', C.loadTime)
        if not ok then U.deleteEnt(bag) return end
        local res = lib.callback.await('nzmw:pallet:take', false, id)
        Wait(600)
        U.deleteEnt(bag)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Duffel loaded', ('%d load(s) · %s%s'):format(res.taken, NZ.money(res.total),
            res.left > 0 and (' · %d left, your bag is full'):format(res.left) or ''), 'success', 7000)
    end)
end

function PalletUI.grab(id)
    U.run(function()
        local d = Render.data(id)
        if not d or d.state ~= 'done' then return end
        local res = lib.callback.await('nzmw:pallet:grab', false, id, 'start')
        if not res or not res.ok then return UI.err(res) end
        local ok, bag = work(d, 'Stuffing a bag', C.theftTime)
        if not ok then U.deleteEnt(bag) return end
        res = lib.callback.await('nzmw:pallet:grab', false, id, 'finish')
        Wait(600)
        U.deleteEnt(bag)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Score', ('%s off the pallet.'):format(NZ.money(res.amount)), 'success')
    end)
end

function PalletUI.seize(id)
    U.run(function()
        local d = Render.data(id)
        if not d then return end
        U.faceCoords(vec3(d.x, d.y, d.z))
        local ok = UI.progress('Bagging the cash as evidence', 6000)
        if not ok then return end
        local res = lib.callback.await('nzmw:pallet:seize', false, id)
        if not res or not res.ok then return UI.err(res) end
        UI.toast('Seized', ('%d load(s) · %s into evidence.'):format(res.loads, NZ.money(res.seized)), 'success')
    end)
end
