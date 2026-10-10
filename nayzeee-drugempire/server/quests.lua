--[[
    Journal: a chain of quests that walks a new player from the first text to a running
    operation. Each step completes on a progress key (fired by the other modules).
    Steps with `count` need the key that many times. Steps with `level` complete at a level.
]]

Quests = {}

local LIST = {
    { id = 'contact', title = 'A New Contact', steps = {
        { key = 'story:go',    text = 'Answer the text from the unknown number' },
        { key = 'story:meet',  text = 'Meet the unknown number' },
    } },
    { id = 'wheels', title = 'Wheels', steps = {
        { key = 'story:steal',  text = 'Steal the RV' },
        { key = 'story:return', text = 'Drive the RV back to Uncle Benson' },
    } },
    { id = 'start', title = 'Getting Started', steps = {
        { key = 'rv:enter',   text = 'Go inside your RV (rear door)' },
        { key = 'place:pot',  text = 'Place a pot anywhere in the RV' },
        { key = 'pot:soil',   text = 'Pour soil into the pot' },
        { key = 'pot:seed',   text = 'Plant a weed seed in the pot' },
        { key = 'pot:water',  text = 'Fill the watering can at the tap and water the plant' },
    } },
    { id = 'wrap', title = 'Wrapping Up', steps = {
        { key = 'pot:harvest',  text = 'Harvest the plant with your trimmers' },
        { key = 'place:packer', text = 'Place the packaging station' },
        { key = 'pack',         text = 'Bag your weed at the packaging station' },
    } },
    { id = 'rounds', title = 'Making the Rounds', steps = {
        { key = 'app:contacts', text = 'Open the contacts in the Empire app' },
        { key = 'sample',       text = 'Give a free sample to a new customer' },
        { key = 'deal',         text = 'Complete a deal' },
    } },
    { id = 'paradise', title = 'Another Day in Paradise', steps = {
        { key = 'order',  text = 'Order supplies in the Deliveries app' },
        { key = 'deal',   text = 'Complete 5 deals', count = 5 },
        { key = 'level',  text = 'Reach Street Rat III (unlocks mixing)', level = 3 },
    } },
    { id = 'chemist', title = 'The Chemist', steps = {
        { key = 'place:mixer', text = 'Place a mixing station' },
        { key = 'mix',         text = 'Mix a brand new product' },
        { key = 'level',       text = 'Reach Hoodlum I (unlocks dealers)', level = 6 },
    } },
    { id = 'crew', title = 'Middle Management', steps = {
        { key = 'dealer:hire',   text = 'Hire a dealer in the Dealers app' },
        { key = 'dealer:assign', text = 'Assign a customer to your dealer' },
        { key = 'level',         text = 'Reach Hoodlum III (unlocks meth)', level = 8 },
    } },
    { id = 'blue', title = 'Blue Sky', steps = {
        { key = 'cook:meth_liquid', text = 'Cook liquid meth at a chemistry station' },
        { key = 'cook:meth',        text = 'Bake and smash it in a lab oven' },
        { key = 'level',            text = 'Reach Peddler III (unlocks shrooms)', level = 13 },
    } },
    { id = 'fungi', title = 'Fun Guy', steps = {
        { key = 'cook:spawn',     text = 'Make mushroom spawn at a spawn station' },
        { key = 'grow:shroom',    text = 'Harvest a mushroom bed' },
        { key = 'level',          text = 'Reach Hustler III (unlocks cocaine)', level = 18 },
    } },
    { id = 'snow', title = 'Snowfall', steps = {
        { key = 'grow:coca',   text = 'Harvest a coca plant' },
        { key = 'rack:coca',   text = 'Dry the leaves on a drying rack' },
        { key = 'cook:base',   text = 'Make coca base in the cauldron' },
        { key = 'cook:coke',   text = 'Bake cocaine in the lab oven' },
    } },
}

Quests.list = LIST

local function questIndex(P)
    for i, q in ipairs(LIST) do
        if not P.quests.done[q.id] then return i, q end
    end
end

local function stepDone(P, step, prog)
    if step.level then return Profile.level(P) >= step.level end
    return (prog or 0) >= (step.count or 1)
end

--- { title, step, text, count, need } of the active step, nil when the journal is finished
function Quests.current(P)
    local _, q = questIndex(P)
    if not q then return nil end
    local pr = P.quests.prog[q.id] or { step = 1, n = 0 }
    local step = q.steps[pr.step]
    if not step then return nil end
    return { id = q.id, title = q.title, text = step.text, n = pr.n or 0, need = step.count, index = pr.step, total = #q.steps }
end

--- advance the active quest. returns true if something moved
function Quests.progress(src, key, amount)
    local P = Profile.get(src)
    if not P then return false end
    local moved = false
    while true do
        local _, q = questIndex(P)
        if not q then break end
        local pr = P.quests.prog[q.id]
        if not pr then pr = { step = 1, n = 0 } P.quests.prog[q.id] = pr end
        local step = q.steps[pr.step]
        if not step then P.quests.done[q.id] = true moved = true goto continue end
        if step.key == key and not step.level then
            pr.n = (pr.n or 0) + (amount or 1)
            amount = 0
        end
        if stepDone(P, step, pr.n) and (step.key == key or step.level) then
            pr.step = pr.step + 1
            pr.n = 0
            moved = true
            if not q.steps[pr.step] then
                P.quests.done[q.id] = true
                TriggerClientEvent('nzde:notify', src, ('Journal: %s complete'):format(q.title), 'success')
            end
        else
            break
        end
        ::continue::
    end
    if moved then
        Profile.dirty(src)
        Profile.sync(src)
    end
    return moved
end

--- journal view for the app
function Quests.view(P)
    local out = {}
    for _, q in ipairs(LIST) do
        local done = P.quests.done[q.id] == true
        local pr = P.quests.prog[q.id] or { step = 1, n = 0 }
        local steps = {}
        for i, s in ipairs(q.steps) do
            steps[i] = { text = s.text, done = done or i < pr.step, n = (i == pr.step) and pr.n or nil, need = s.count }
        end
        out[#out + 1] = { id = q.id, title = q.title, done = done, steps = steps }
        if not done then break end
    end
    return out
end
