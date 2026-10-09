-----------------------------------------------------------------
-- Builds the chain registry (see shared/chains.lua) and keeps
-- every client's copy current.
--
-- Studio edits are saved in data/overrides.json and win over the
-- converter output and config.lua. Keep that file when you update.
-----------------------------------------------------------------

Registry = { overrides = {}, owners = {} }   -- owners stay on the server: [key] = { { license, name }, ... }

local RES = GetCurrentResourceName()
local FILE = 'data/overrides.json'

local function vec(t)
    if type(t) ~= 'table' then return nil end
    local x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function fit(f)
    if type(f) ~= 'table' then return nil end
    local pos, rot = vec(f.pos), vec(f.rot)
    if not pos or not rot then return nil end
    return { bone = math.floor(tonumber(f.bone) or 39317), pos = pos, rot = rot }
end

function Registry.loadOverrides()
    local raw = LoadResourceFile(RES, FILE)
    local ok, data = pcall(json.decode, raw or '{}')
    Registry.overrides = (ok and type(data) == 'table') and data or {}
end

function Registry.saveOverrides()
    local ok = SaveResourceFile(RES, FILE, json.encode(Registry.overrides, { indent = true }), -1)
    if not ok then print(('^1[%s] could not write %s^0'):format(RES, FILE)) end
    return ok
end

local function chainmap()
    if GetResourceState(Config.PropsResource) == 'missing' then return {} end
    local raw = LoadResourceFile(Config.PropsResource, 'chainmap.json')
    local ok, data = pcall(json.decode, raw or '{}')
    return ok and type(data) == 'table' and type(data.chains) == 'table' and data.chains or {}
end

function Registry.build()
    local list = {}

    for key, e in pairs(chainmap()) do
        if type(e) == 'table' and type(e.variants) == 'table' and #e.variants > 0 then
            local vars = {}
            for _, v in ipairs(e.variants) do
                if type(v.prop) == 'string' then vars[#vars + 1] = { letter = tostring(v.letter or 'a'), prop = v.prop } end
            end
            list[key] = {
                key = key, label = e.label or key, origin = e.origin or 'drop',
                gender = e.gender, collection = e.collection, ['local'] = e['local'],
                centre = vec(e.centre), min = vec(e.min), max = vec(e.max),
                variants = vars, fit = {}, value = Config.DefaultValue,
            }
        end
    end

    for key, c in pairs(Config.Chains or {}) do
        local vars = {}
        for i, v in ipairs(c.variants or {}) do
            if v.prop then vars[#vars + 1] = { letter = string.char(96 + i), prop = v.prop, label = v.label } end
        end
        if #vars > 0 then
            list[key] = {
                key = key, label = c.label or key, origin = 'config', variants = vars,
                fit = { worn = fit(c.worn), hold = fit(c.hold) }, value = c.value or Config.DefaultValue,
            }
        end
    end

    for key, o in pairs(Registry.overrides) do
        local d = list[key]
        if d and type(o) == 'table' then
            if type(o.label) == 'string' and o.label ~= '' then d.label = o.label end
            if tonumber(o.value) then d.value = math.floor(tonumber(o.value)) end
            for mode, f in pairs(type(o.fit) == 'table' and o.fit or {}) do
                d.fit[mode] = fit(f) or d.fit[mode]
            end
            for _, v in ipairs(d.variants) do
                local l = type(o.vlabels) == 'table' and o.vlabels[v.letter]
                if type(l) == 'string' and l ~= '' then v.label = l end
            end
            if o.forSale ~= nil then d.forSale = o.forSale == true end
            if tonumber(o.price) then d.price = math.floor(tonumber(o.price)) end
            if o.craftable ~= nil then d.craftable = o.craftable == true end
        end
    end

    -- exclusive chains: who may buy them is kept here; clients only learn THAT a chain is exclusive
    Registry.owners = {}
    for key, d in pairs(list) do
        if d.forSale == nil then d.forSale = Config.Store.SellAll ~= false end
        if d.craftable == nil then d.craftable = true end
        local o = Registry.overrides[key]
        local owners = type(o) == 'table' and type(o.owners) == 'table' and o.owners or {}
        if #owners > 0 then
            Registry.owners[key] = owners
            d.exclusive = true
            local names = {}
            for _, w in ipairs(owners) do names[#names + 1] = w.name end
            d.madeFor = table.concat(names, ' & ')
        end
    end

    Chains.set(list)
    return list
end

function Registry.publish(target)
    TriggerLatentClientEvent('nzc:c:registry', target or -1, 200000, Chains.list)
end

function Registry.reload()
    Registry.build()
    Registry.publish()
    TriggerEvent('nzc:registryChanged')
end

RegisterNetEvent('nzc:s:registry', function()
    if Logs.throttle(source, 'registry', 5000) then return end
    Registry.publish(source)
end)

Registry.loadOverrides()
Registry.build()

AddEventHandler('onResourceStart', function(res)
    if res == Config.PropsResource then SetTimeout(500, Registry.reload) end
end)

CreateThread(function()
    Wait(1000)
    local n = 0
    for _ in pairs(Chains.list) do n = n + 1 end
    print(('^5[%s]^7 %d chain(s) ready%s'):format(RES, n,
        GetResourceState(Config.PropsResource) == 'missing' and (' (no %s yet, convert some in /%s)'):format(Config.PropsResource, Config.Studio.Command) or ''))
end)

--- May this player buy this chain? (exclusive chains: only their licenses)
function Registry.canBuy(src, key)
    local owners = Registry.owners[key]
    if not owners then return true end
    local lic = Bridge.GetLicense(src)
    for _, w in ipairs(owners) do
        if w.license == lic then return true end
    end
    return false
end
