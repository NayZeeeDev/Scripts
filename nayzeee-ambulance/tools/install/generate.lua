--[[
    NAYZEEE AMBULANCE - Install file generator

    Builds the inventory install files from config/items.lua:
      install/ox_inventory_items.lua   ox_inventory  (data/items.lua entries)
      install/qb_shared_items.lua      qb-core shared items (also qs / codem / tgiann / ps / lj)
      install/esx_items.sql            ESX `items` table (INSERT IGNORE)

    Run it with plain Lua 5.4 after renaming items in config/items.lua:
      lua5.4 tools/install/generate.lua                 (from the resource folder)
      lua5.4 tools/install/generate.lua --esx-grams     ESX weights in grams instead of kg

    Developer tool: tools/ is not part of the released resource.
]]

if not NAYZEEE_LOCK_OK and GetCurrentResourceName then return end

NAYZEEE_LOCK_OK = true
Config = {}

local RESOURCE = 'nayzeee-ambulance'

-- ════════════════════════════════════════════════════════════════════════
-- PATHS
-- ════════════════════════════════════════════════════════════════════════

local script = arg and arg[0] or 'tools/install/generate.lua'
local function parent(path) return path:match('^(.*)[/\\][^/\\]*$') end
local scriptDir = parent(script) or '.'
local root = scriptDir == '.' and '../..' or (parent(parent(scriptDir) or '.') or '.')
local installDir = root .. '/install'

local esxGrams = false
for _, a in ipairs(arg or {}) do
    if a == '--esx-grams' then esxGrams = true end
end

local function load(path)
    local chunk, err = loadfile(path)
    if not chunk then error(('cannot load %s: %s'):format(path, tostring(err))) end
    chunk()
end

load(root .. '/config/items.lua')

local Items, Defs = Config.Items, Config.ItemDefs
assert(type(Items) == 'table' and type(Defs) == 'table', 'config/items.lua did not define Config.Items / Config.ItemDefs')

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local CATEGORY_ORDER = {
    first_aid = 1, wound_care = 2, medication = 3, fluids = 4, orthopedic = 5,
    airway = 6, surgery = 7, equipment = 8, documents = 9,
}

-- every item, sorted by category then by the order in Config.Items is lost
-- in a Lua table, so sort by category + label for a stable file
local list = {}
for key, name in pairs(Items) do
    local def = Defs[key]
    if not def then error(('Config.ItemDefs.%s is missing'):format(key)) end
    list[#list + 1] = { key = key, name = name, def = def }
end
table.sort(list, function(a, b)
    local ca, cb = CATEGORY_ORDER[a.def.category] or 99, CATEGORY_ORDER[b.def.category] or 99
    if ca ~= cb then return ca < cb end
    return a.def.label < b.def.label
end)

local function luaString(s)
    return "'" .. tostring(s):gsub('\\', '\\\\'):gsub("'", "\\'"):gsub('\n', '\\n') .. "'"
end

local function sqlString(s)
    return "'" .. tostring(s):gsub('\\', '\\\\'):gsub("'", "''") .. "'"
end

local function imageFile(entry)
    return entry.def.image or (entry.name .. '.png')
end

local function write(path, text)
    local f = assert(io.open(path, 'w'))
    f:write(text)
    f:close()
    print(('  wrote %s'):format(path))
end

local HEADER_NOTE = 'Built from config/items.lua. If you rename an item there, rename it here too.'

-- ════════════════════════════════════════════════════════════════════════
-- ox_inventory
-- ════════════════════════════════════════════════════════════════════════

local function oxFile()
    local out = {}
    out[#out + 1] = '--[['
    out[#out + 1] = '    NAYZEEE AMBULANCE - ox_inventory items'
    out[#out + 1] = '    ' .. HEADER_NOTE
    out[#out + 1] = ''
    out[#out + 1] = '    Copy every entry below into ox_inventory/data/items.lua (inside its'
    out[#out + 1] = '    "return { ... }" table). Images load straight from this resource, no'
    out[#out + 1] = '    copying needed.'
    out[#out + 1] = ''
    out[#out + 1] = '    consume = 0: nayzeee-ambulance removes items itself when a treatment'
    out[#out + 1] = '    succeeds, so ox must never take one on use.'
    out[#out + 1] = ']]'
    out[#out + 1] = ''
    out[#out + 1] = 'return {'
    local lastCategory
    for _, e in ipairs(list) do
        if e.def.category ~= lastCategory then
            out[#out + 1] = ''
            out[#out + 1] = ('    -- %s'):format(e.def.category:gsub('_', ' '):upper())
            lastCategory = e.def.category
        end
        out[#out + 1] = ('    [%s] = {'):format(luaString(e.name))
        out[#out + 1] = ('        label = %s,'):format(luaString(e.def.label))
        out[#out + 1] = ('        weight = %d,'):format(e.def.weight)
        out[#out + 1] = ('        stack = %s,'):format(tostring(e.def.stack ~= false))
        out[#out + 1] = '        close = true,'
        out[#out + 1] = '        consume = 0,'
        out[#out + 1] = ('        description = %s,'):format(luaString(e.def.description or ''))
        out[#out + 1] = '        client = {'
        out[#out + 1] = ('            image = %s,'):format(luaString(('nui://%s/html/img/items/%s'):format(RESOURCE, imageFile(e))))
        out[#out + 1] = '        },'
        out[#out + 1] = '    },'
    end
    out[#out + 1] = '}'
    out[#out + 1] = ''
    return table.concat(out, '\n')
end

-- ════════════════════════════════════════════════════════════════════════
-- qb-core shared items
-- ════════════════════════════════════════════════════════════════════════

local function qbFile()
    local out = {}
    out[#out + 1] = '--[['
    out[#out + 1] = '    NAYZEEE AMBULANCE - QBCore shared items'
    out[#out + 1] = '    ' .. HEADER_NOTE
    out[#out + 1] = ''
    out[#out + 1] = '    qb-core:   paste the entries into qb-core/shared/items.lua (QBShared.Items)'
    out[#out + 1] = '    qs-inventory / codem-inventory / tgiann-inventory / ps-inventory /'
    out[#out + 1] = '    lj-inventory use the same item format: paste into their item list.'
    out[#out + 1] = '    Copy html/img/items/*.png into the inventory image folder'
    out[#out + 1] = '    (qb-inventory/html/images, see install/README.md for the others).'
    out[#out + 1] = ']]'
    out[#out + 1] = ''
    out[#out + 1] = 'return {'
    local lastCategory
    for _, e in ipairs(list) do
        if e.def.category ~= lastCategory then
            out[#out + 1] = ''
            out[#out + 1] = ('    -- %s'):format(e.def.category:gsub('_', ' '):upper())
            lastCategory = e.def.category
        end
        out[#out + 1] = ('    [%s] = { name = %s, label = %s, weight = %d, type = \'item\', image = %s, unique = %s, useable = true, shouldClose = true, combinable = nil, description = %s },')
            :format(luaString(e.name), luaString(e.name), luaString(e.def.label), e.def.weight, luaString(imageFile(e)),
                tostring(e.def.stack == false), luaString(e.def.description or ''))
    end
    out[#out + 1] = '}'
    out[#out + 1] = ''
    return table.concat(out, '\n')
end

-- ════════════════════════════════════════════════════════════════════════
-- ESX SQL
-- ════════════════════════════════════════════════════════════════════════

local function esxWeight(grams)
    if esxGrams then return grams end
    local kg = math.floor(grams / 1000 + 0.5)
    if kg < 1 then kg = 1 end
    return kg
end

local function esxFile()
    local out = {}
    out[#out + 1] = '-- NAYZEEE AMBULANCE - ESX items'
    out[#out + 1] = '-- ' .. HEADER_NOTE
    out[#out + 1] = ('-- Weights are in %s (gram based servers: take the gram weights from install/ox_inventory_items.lua).'):format(esxGrams and 'grams' or 'kg (minimum 1)')
    out[#out + 1] = '-- Not needed with ox_inventory (use install/ox_inventory_items.lua instead).'
    out[#out + 1] = ''
    out[#out + 1] = 'INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES'
    for i, e in ipairs(list) do
        out[#out + 1] = ('    (%s, %s, %d, 0, 1)%s'):format(sqlString(e.name), sqlString(e.def.label), esxWeight(e.def.weight), i < #list and ',' or ';')
    end
    out[#out + 1] = ''
    return table.concat(out, '\n')
end

-- ════════════════════════════════════════════════════════════════════════
-- RUN
-- ════════════════════════════════════════════════════════════════════════

print(('NAYZEEE AMBULANCE - generating install files for %d items'):format(#list))
write(installDir .. '/ox_inventory_items.lua', oxFile())
write(installDir .. '/qb_shared_items.lua', qbFile())
write(installDir .. '/esx_items.sql', esxFile())
print('done')
