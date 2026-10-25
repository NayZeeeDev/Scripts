-----------------------------------------------------------------
-- Name tags (server)
--
-- The tag lives in the bag's metadata ({ t, f, c, c2, s, e, p }), so it
-- goes wherever the bag goes. Everything a client sends is checked
-- against the lists in Config.NameTags before it's saved.
-----------------------------------------------------------------

local cfg = Config.NameTags or {}
local ox = exports.ox_inventory

--- Short string that changes whenever the tag looks different.
function TagSig(t)
    if type(t) ~= 'table' then return '' end
    return table.concat({ t.t or '', t.f or '', t.c or '', t.c2 or '', t.s or '', t.e or '', t.p or '' }, '|')
end

if not cfg.enabled then return end

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end
local function tell(src, key, kind) TriggerClientEvent('nayzeee-backpack:notify', src, S(key), kind or 'error') end

local function keys(list)
    local set = {}
    for _, v in ipairs(list or {}) do set[type(v) == 'table' and v.key or v] = true end
    return set
end

local FONTS, STYLES, EFFECTS, PARTICLES = keys(cfg.fonts), keys(cfg.styles), keys(cfg.effects), keys(cfg.particles)
local PALETTE = {}
for _, c in ipairs(cfg.colors or {}) do PALETTE[c:lower()] = true end

local function color(c)
    if type(c) ~= 'string' then return nil end
    c = c:lower()
    if not c:match('^#%x%x%x%x%x%x$') then return nil end
    if not cfg.customColors and not PALETTE[c] then return nil end
    return c
end

local function cleanText(t)
    if type(t) ~= 'string' then return nil end
    t = t:gsub('[%c<>{}\\`]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s%s+', ' ')
    local len = utf8.len(t)
    if not len or len < 1 or len > (cfg.maxLength or 18) then return nil end
    local lower = t:lower()
    for _, word in ipairs(cfg.blocked or {}) do
        if lower:find(word:lower(), 1, true) then return nil end
    end
    return t
end

local function clean(tag)
    if type(tag) ~= 'table' then return nil end
    local out = {
        t = cleanText(tag.t),
        f = FONTS[tag.f] and tag.f or nil,
        s = STYLES[tag.s] and tag.s or nil,
        e = EFFECTS[tag.e] and tag.e or 'none',
        p = PARTICLES[tag.p] and tag.p or 'none',
        c = color(tag.c),
        c2 = tag.c2 and color(tag.c2) or nil,
    }
    if not out.t or not out.f or not out.s or not out.c then return nil end
    return out
end

local function wornBag(src)
    local item = FindBagItem(src)
    if not item or not item.metadata or not item.metadata.bagid then return nil end
    return item
end

local function hasItem(src)
    return (ox:Search(src, 'count', cfg.item) or 0) > 0
end

local function openEditor(src)
    local bag = wornBag(src)
    if not bag then return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error') end
    local current = bag.metadata.tag
    if not current and not hasItem(src) then return tell(src, 'nt_need_item') end
    TriggerClientEvent('nayzeee-backpack:tag:edit', src, {
        tag = current,
        bag = Bags.label(bag.name),
        free = current ~= nil and cfg.editFree ~= false,
    })
end

exports('useNameTag', function(event, item, inventory)
    if event ~= 'usingItem' then return end
    openEditor(inventory.id)
    return false -- used up when the tag is saved
end)

RegisterNetEvent('nayzeee-backpack:tag:open', function() openEditor(source) end)

RegisterNetEvent('nayzeee-backpack:tag:save', function(raw)
    local src = source
    local bag = wornBag(src)
    if not bag then return end
    local tag = clean(raw)
    if not tag then return tell(src, 'nt_bad') end

    local meta = bag.metadata
    local charge = not meta.tag or cfg.editFree == false
    if charge then
        if not hasItem(src) then return tell(src, 'nt_need_item') end
        if not ox:RemoveItem(src, cfg.item, 1) then return tell(src, 'nt_need_item') end
    end

    meta.tag = tag
    if cfg.renameItem ~= false then meta.label = tag.t end
    ox:SetMetadata(src, bag.slot, meta)
    RefreshBagState(src)
    tell(src, 'nt_saved', 'success')
    if Sounds then Sounds.play('rustle', src) end
end)

RegisterNetEvent('nayzeee-backpack:tag:remove', function()
    local src = source
    local bag = wornBag(src)
    if not bag or not bag.metadata.tag then return end
    local meta = bag.metadata
    meta.tag = nil
    meta.label = nil
    ox:SetMetadata(src, bag.slot, meta)
    RefreshBagState(src)
    tell(src, 'nt_removed', 'inform')
end)
