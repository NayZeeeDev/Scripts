--[[
    One world scan for everything players place (shoe boxes, display cases): every 750 ms it walks the
    object pool once and hands each new match to whoever watches that model. The server keeps a count
    of each kind in GlobalState, so with nothing placed anywhere the scan doesn't run at all.
]]

Stream = {}

local watchers = {}   -- { models = { [hash] = true }, range, key (GlobalState count), add = fn(entity), has = fn(entity) }

--- models: list of hashes. key: GlobalState count to check (nil = always). add(entity) is called once
--- per new matching object within range; has(entity) says whether the watcher already tracks it.
function Stream.Watch(models, range, key, has, add)
    local set = {}
    for _, m in ipairs(models) do set[m & 0xFFFFFFFF] = true end
    watchers[#watchers + 1] = { models = set, range = range, key = key, has = has, add = add }
end

CreateThread(function()
    while true do
        local active = {}
        for _, w in ipairs(watchers) do
            if not w.key or (GlobalState[w.key] or 0) > 0 then active[#active + 1] = w end
        end
        if #active > 0 then
            local me = GetEntityCoords(PlayerPedId())
            for _, obj in ipairs(GetGamePool('CObject')) do
                local m = GetEntityModel(obj) & 0xFFFFFFFF
                for i = 1, #active do
                    local w = active[i]
                    if w.models[m] and not w.has(obj) and #(GetEntityCoords(obj) - me) < w.range then w.add(obj) end
                end
            end
            Wait(750)
        else
            Wait(2000)
        end
    end
end)
