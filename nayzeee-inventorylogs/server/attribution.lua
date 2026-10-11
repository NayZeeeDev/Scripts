-- Which script really caused a money/item change. The framework bridge fires `nzinv:attr`
-- right before calling the framework's own function and clears it right after, so any event
-- the framework raises in between can be credited to the calling script.
local Attr = {}
local bridged = false

AddEventHandler('nzinv:attr', function(src, kind, name, by)
    if not src or not kind or not name then return end
    bridged = true
    local key = ('%s:%s:%s'):format(src, kind, tostring(name):lower())
    Attr[key] = by
end)

--- Script that is moving `name` for `src` right now, if the bridge told us.
function AttrFor(src, kind, name)
    return Attr[('%s:%s:%s'):format(src, kind, tostring(name or ''):lower())]
end

function FrameworkBridged() return bridged end

AddEventHandler('playerDropped', function()
    local src = tostring(source) .. ':'
    for k in pairs(Attr) do if k:sub(1, #src) == src then Attr[k] = nil end end
end)
