-- Builds install/ item files from Config.Items.  lua5.4 tests/gen_install.lua <resource dir>
local root = arg[1] or '.'
local function v(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec2, vec3, vec4 = v, v, v
function IsDuplicityVersion() return false end
function GetCurrentResourceName() return 'nayzeee-weedlab' end
for _, f in ipairs({ 'config/main.lua', 'config/strains.lua', 'config/equipment.lua', 'config/shop.lua' }) do dofile(root .. '/' .. f) end

local usable = {}
for _, e in pairs(Config.Equipment) do usable[e.item] = true end
for _, l in pairs(Config.Lights) do usable[l.item] = true end
local names = {}
for k in pairs(Config.Items) do names[#names + 1] = k end
table.sort(names)
local function q(s) return string.format('%q', s) end

local ox = { '-- ox_inventory: paste into ox_inventory/data/items.lua (inside the return table)', '-- Product items (weed, baggies, jars, bricks) get their strain, quality and effects from metadata.' }
local qb = { '-- qb-core: paste into qb-core/shared/items.lua (QBShared.Items = { ... })', '-- Use a recent qb-inventory: product items rely on item info (metadata).' }
local esx = { '-- ESX (default inventory): products lose their metadata without ox_inventory or another metadata inventory.', 'INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES' }
local rows = {}
for _, name in ipairs(names) do
    local label, grams, desc = table.unpack(Config.Items[name])
    local use = usable[name] and true or false
    ox[#ox + 1] = ("    [%s] = { label = %s, weight = %d, stack = true, close = %s, description = %s },"):format(q(name), q(label), grams, tostring(use), q(desc))
    qb[#qb + 1] = ("    %s = { name = %s, label = %s, weight = %d, type = 'item', image = %s, unique = false, useable = %s, shouldClose = true, description = %s },"):format(name, q(name), q(label), grams, q(name .. '.png'), tostring(use), q(desc))
    rows[#rows + 1] = ("    (%s, %s, %d, 0, 1)"):format(q(name):gsub('"', "'"), q(label):gsub('"', "'"), math.max(1, math.floor(grams / 1000 + 0.5)))
end
esx[#esx + 1] = table.concat(rows, ',\n') .. ';'
local function write(file, lines) local f = assert(io.open(root .. '/install/' .. file, 'w')) f:write(table.concat(lines, '\n') .. '\n') f:close() end
write('items_ox_inventory.lua', ox)
write('items_qb.lua', qb)
write('items_esx.sql', esx)
print(('wrote %d items'):format(#names))
