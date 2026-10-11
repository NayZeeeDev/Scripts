-- Live data-file editor. Which files exist comes from the inventory integration
-- (inventories/*.lua → editor.files). Structured edits and raw edits both end in commit(), which
-- validates the whole file, backs up the old copy, writes it and asks the integration to apply it.
local E = Config.Editor

local ORDER = {
    item = { 'label', 'weight', 'stack', 'close', 'description', 'consume', 'degrade', 'decay', 'allowArmed', 'allowArmedWith', 'image', 'status', 'anim', 'prop', 'usetime', 'cancel', 'disable', 'notification', 'export', 'client', 'server', 'buttons' },
    weapon = { 'label', 'weight', 'durability', 'ammoname', 'model', 'throwable', 'type', 'client' },
    shop = { 'name', 'label', 'blip', 'groups', 'inventory', 'locations', 'targets', 'model', 'id', 'colour', 'scale', 'price', 'count', 'currency', 'license', 'grade', 'metadata' },
    stash = { 'coords', 'target', 'name', 'label', 'owner', 'slots', 'weight', 'groups', 'loc', 'length', 'width', 'heading', 'minZ', 'maxZ' },
    crafting = { 'name', 'label', 'items', 'points', 'zones', 'groups', 'blip', 'ingredients', 'duration', 'count', 'metadata' },
    evidence = { 'coords', 'target' },
    license = { 'name', 'coords', 'icon', 'price' },
    anim = { 'dict', 'clip', 'flag', 'model', 'pos', 'rot', 'bone' },
    qbitem = { 'name', 'label', 'weight', 'type', 'ammotype', 'image', 'unique', 'useable', 'shouldClose', 'combinable', 'decay', 'delete', 'description' },
    qbweapon = { 'name', 'label', 'weapontype', 'ammotype', 'damagereason' },
    qbshop = { 'label', 'type', 'coords', 'ped', 'scenario', 'radius', 'targetIcon', 'targetLabel', 'products', 'showblip', 'blipsprite', 'blipscale', 'blipcolor', 'delivery', 'requiredJob', 'requiredGang', 'requiredItem', 'useStock' },
    qbproducts = { 'name', 'price', 'amount', 'info', 'type', 'slot', 'requiredJob', 'requiredGrade', 'requiresLicense' },
}
local ITEM_KINDS = { item = true, weapon = true, qbitem = true, qbweapon = true }

local function ED()
    local e = Inv.a.editor
    if not E.enabled or type(e) ~= 'table' then NZ.Fail(('The data editor is not available for %s.'):format(Inv.label)) end
    return e
end

local function def(file)
    local d = ED().files[file]
    if not d or (d.when and not d.when()) then NZ.Fail('Unknown file.') end
    return d
end
local function resOf(d) return d.resource or ED().resource or Inv.resource end
local function where(d) return ('%s/%s'):format(resOf(d), d.path) end
local function nameOf(file) local d = def(file) return d.path:match('[^/]+$') or d.path end

local function read(file)
    local d = def(file)
    local src = LoadResourceFile(resOf(d), d.path)
    if not src then NZ.Fail(('%s is missing.'):format(where(d))) end
    return src
end

-- ─── sandbox evaluation ────────────────────────────────────────────────────
local function sandbox()
    local env = {
        vec = vec, vec2 = vec2, vec3 = vec3, vec4 = vec4, vector2 = vector2, vector3 = vector3, vector4 = vector4, quat = quat,
        joaat = joaat, GetHashKey = GetHashKey, json = json, math = math, string = string, table = table,
        pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber, select = select,
        unpack = table.unpack, print = function() end, pcall = pcall, setmetatable = setmetatable, rawget = rawget,
        GetConvar = GetConvar, GetConvarInt = GetConvarInt, GetConvarBool = function(k, d) return GetConvar(k, tostring(d)) == 'true' end,
        GetResourceState = GetResourceState, locale = function(s) return s end, lib = {},
    }
    local extra = Inv.a.editor and Inv.a.editor.sandbox
    if extra then pcall(extra, env) end
    return setmetatable(env, { __index = function() return nil end })
end

local function walk(t, path)
    for part in tostring(path):gmatch('[^%.]+') do
        if type(t) ~= 'table' then return nil end
        t = t[part]
    end
    return t
end

--- Compile + run a whole file in the sandbox. Returns the file's table or nil, err
local function evaluate(src, file)
    local d = def(file)
    local env = sandbox()
    local fn, err = load(src, '@@' .. where(d), 't', env)
    if not fn then return nil, err end
    local ok, res = pcall(fn)
    if not ok then return nil, res end
    if d.root then
        local t = walk(env, d.root)
        if type(t) ~= 'table' then return nil, ('the file has to set %s = { ... }'):format(d.root) end
        return t
    end
    if type(res) ~= 'table' then return nil, 'the file has to return a table' end
    return res
end

--- Keys written as `name` (qb-core weapons) are stored under their hash
local function lookup(t, key)
    if type(t) ~= 'table' then return nil end
    local v = t[key]
    if v == nil and type(key) == 'string' then
        local h = key:match('^`(.+)`$')
        if h then v = t[GetHashKey(h)] end
        if v == nil and tonumber(key) then v = t[tonumber(key)] end
    end
    return v
end

local function toJson(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == 'vector3' then return { __vec3 = { NZ.Round(v.x, 4), NZ.Round(v.y, 4), NZ.Round(v.z, 4) } } end
    if t == 'vector4' then return { __vec4 = { NZ.Round(v.x, 4), NZ.Round(v.y, 4), NZ.Round(v.z, 4), NZ.Round(v.w, 4) } } end
    if t == 'vector2' then return { __vec2 = { NZ.Round(v.x, 4), NZ.Round(v.y, 4) } } end
    if t == 'function' then return { __fn = true } end
    if t ~= 'table' then return v end
    if depth > 8 then return { __raw = '...' } end
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    if n > 0 and n == count then
        local out = {}
        for i = 1, n do out[i] = toJson(v[i], depth + 1) end
        return out
    end
    local out = {}
    for k, x in pairs(v) do out[tostring(k)] = toJson(x, depth + 1) end
    if count == 0 then out.__empty = true end
    return out
end

local function hasFn(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    for _, x in pairs(v) do if hasFn(x) then return true end end
    return false
end

local function count(t) return type(t) == 'table' and #t or 0 end
local function bare(key) return (tostring(key):gsub('`', '')) end

local function summary(kind, key, v)
    if type(v) ~= 'table' then return { key = key, label = bare(key) } end
    local c = type(v.client) == 'table' and v.client or {}
    if kind == 'item' then
        local sv = type(v.server) == 'table' and v.server or {}
        return { key = key, label = v.label or key, weight = v.weight or 0, stack = v.stack ~= false, close = v.close ~= false,
            description = v.description, image = type(c.image) == 'string' and c.image or nil, degrade = v.degrade, consume = v.consume,
            usable = (c.status or c.usetime or c.export or sv.export) and true or false, fn = hasFn(v),
            armed = v.allowArmed and ((type(v.allowArmedWith) == 'table' and #v.allowArmedWith > 0) and #v.allowArmedWith or 'any') or nil }
    elseif kind == 'weapon' then
        return { key = key, label = v.label or key, weight = v.weight or 0, durability = v.durability, ammo = v.ammoname,
            image = type(c.image) == 'string' and c.image or nil }
    elseif kind == 'qbitem' then
        return { key = key, label = v.label or key, weight = v.weight or 0, stack = not v.unique, usable = v.useable == true,
            image = type(v.image) == 'string' and v.image or nil, itype = v.type, description = v.description, weapon = v.type == 'weapon' }
    elseif kind == 'qbweapon' then
        return { key = key, label = v.label or bare(key), name = v.name, ammo = v.ammotype, wtype = v.weapontype }
    elseif kind == 'qbshop' then
        return { key = key, label = v.label or key, items = count(v.products), blip = v.showblip == true,
            job = v.requiredJob ~= nil or v.requiredGang ~= nil, ped = v.ped }
    elseif kind == 'qbproducts' then
        return { key = key, label = key, items = count(v) }
    elseif kind == 'shop' then
        return { key = key, label = v.name or key, items = count(v.inventory), locations = count(v.locations) + count(v.targets),
            groups = v.groups or v.jobs and true or false, blip = v.blip ~= nil }
    elseif kind == 'stash' then
        return { key = key, label = v.label or v.name or ('Stash %s'):format(key), name = v.name, slots = v.slots, weight = v.weight,
            owner = v.owner, groups = v.groups ~= nil or v.jobs ~= nil }
    elseif kind == 'crafting' then
        return { key = key, label = v.label or v.name or ('Bench %s'):format(key), name = v.name, recipes = count(v.items),
            locations = count(v.points) + count(v.zones), groups = v.groups ~= nil }
    elseif kind == 'license' then
        return { key = key, label = v.name or ('License %s'):format(key), price = v.price }
    elseif kind == 'evidence' then
        return { key = key, label = ('Evidence locker %s'):format(key) }
    end
    return { key = key, label = bare(key) }
end

--- Top-level fields whose value is an expression (e.g. products = Config.Products['normal'])
local function rawFields(doc, node)
    local out
    for _, f in ipairs(node and node.fields or {}) do
        if not f.table and not f.positional and type(f.key) == 'string' then
            local text = LuaDoc.valueText(doc, f)
            if text:match('^[%a_][%w_]*[%.%[]') and not text:match('^vec') and not text:match('^vector') then
                out = out or {}
                out[f.key] = text
            end
        end
    end
    return out
end

-- ─── writing into other resources ──────────────────────────────────────────
local WRITE_HELP = 'FiveM blocks scripts from writing into other resources. Add this line to server.cfg and restart the server: add_filesystem_permission %s write %s  (or add bridge/nz_writer.lua to %s, see INSTALL.md)'

local function writeFile(res, filePath, content)
    local e = Inv.a.editor
    if e and e.write and res == (e.resource or Inv.resource) then
        local ok, r = pcall(e.write, filePath, content)
        if ok and r then return true end
    end
    local ok, r = pcall(function() return exports[res]:nzWrite(filePath, content) end)
    if ok and type(r) == 'table' and r.ok then return true end
    if SaveResourceFile(res, filePath, content, #content) then return true end
    return false, WRITE_HELP:format(NZ.Resource, res, res)
end

-- ─── backups (rotating slots so disk use stays bounded) ────────────────────
local function bkKey(file)
    local d = ED().files[file]
    return ('%s_%s'):format(Inv.id:gsub('[^%w]', ''), d and d.backupKey or file)
end

local function backupIndex(file)
    local raw = GetResourceKvpString('nzinv:bk:' .. bkKey(file))
    if not raw and Inv.id == 'ox_inventory' then raw = GetResourceKvpString('nzinv:bk:' .. file) end -- 3.0 backups
    return raw and json.decode(raw) or { n = 0, list = {} }
end

local function backup(src, file, content, action)
    local key = bkKey(file)
    local idx = backupIndex(file)
    local keep = E.backups or 25
    idx.n = (idx.n or 0) + 1
    local slot = idx.n % keep
    SaveResourceFile(NZ.Resource, ('backups/%s_%d.lua'):format(key, slot), content, -1)
    table.insert(idx.list, 1, { id = idx.n, slot = slot, key = key, time = os.time(), admin = GetPlayerName(src) or 'Console', action = action, size = #content })
    while #idx.list > keep do table.remove(idx.list) end
    SetResourceKvp('nzinv:bk:' .. key, json.encode(idx))
end

-- ─── commit ────────────────────────────────────────────────────────────────
local locked = false

local function apply(file, before, after)
    local e = ED()
    if not E.liveApply then return { ok = true, live = false, note = 'Saved. Live apply is turned off in the config.' } end
    if not e.apply then return { ok = true, live = false, note = ('Saved. Restart %s to apply it.'):format(resOf(def(file))) } end
    local ok, res = pcall(e.apply, file, before, after)
    if not ok then return { ok = false, err = tostring(res) } end
    return res or { ok = true, live = false }
end

local function commit(src, file, newSrc, action, detail)
    local d = def(file)
    local after, err = evaluate(newSrc, file)
    if err then NZ.Fail('Not saved, the file has an error: ' .. tostring(err)) end
    if not d.raw then
        local doc, perr = LuaDoc.parse(newSrc, d.root)
        if not doc then NZ.Fail('Not saved: ' .. tostring(perr)) end
    end
    if locked then NZ.Fail('Another edit is being saved, try again in a second.') end
    locked = true
    local cur = LoadResourceFile(resOf(d), d.path) or ''
    local before = evaluate(cur, file)
    backup(src, file, cur, action)
    local ok, werr = writeFile(resOf(d), d.path, newSrc)
    if not ok then locked = false NZ.Fail(werr) end
    local res = apply(file, before, after)
    locked = false
    if ITEM_KINDS[d.kind] then TriggerEvent('nzinv:catalogueChanged') end
    NZ.Audit(src, 'editor_' .. action, nameOf(file), detail)
    local me = NZ.Actor(src)
    local ACTION = { update = 'Changed', create = 'Added', delete = 'Deleted', code = 'Code edited', restore = 'Backup restored' }
    local dt = type(detail) == 'table' and detail or {}
    SendWebhook('editor', ('%s: %s'):format(ACTION[action] or action, dt.entry and tostring(dt.entry) or nameOf(file)), {
        admin = me, details = ('%s %s in %s'):format(me.name, (ACTION[action] or action):lower(), where(d)),
        extra = {
            { 'File', ('`%s`'):format(where(d)), true },
            { 'Entry', dt.entry and ('`%s`'):format(tostring(dt.entry)) or nil, true },
            { 'Category', dt.collection, true },
            { 'Renamed from', dt.renamedFrom and ('`%s`'):format(dt.renamedFrom) or nil, true },
            { 'Fields changed', dt.ops and tostring(dt.ops) or nil, true },
            { 'File size', dt.bytes and ('%s → %s bytes'):format(NZ.Comma(dt.before or 0), NZ.Comma(dt.bytes)) or nil, true },
            { 'Picture', dt.image and ('`%s`'):format(dt.image) or nil, true },
            { 'Backup', dt.backup and ('#%s from %s'):format(dt.backup, dt.from or '?') or nil, true },
            { 'Also removed', dt.purged and ('%s copies from players, stashes and vehicles'):format(NZ.Comma(dt.purged)) or nil, false },
            { 'Applied', type(res) == 'table' and (res.ok == false and ('Failed: ' .. tostring(res.err)) or res.live and 'Live for every player' or (res.note or 'After a restart')) or nil, false },
        } })
    NZ.Print(('%s edited %s (%s)'):format(me.name, where(d), action))
    return { hash = LuaDoc.hash(newSrc), apply = res }
end

local function collectionPath(file, collection)
    if def(file).categories then
        if not collection or collection == '' then NZ.Fail('Pick a category.') end
        return { collection }
    end
    return {}
end

local function keyOf(file, key)
    if def(file).keyed then return tostring(key) end
    local n = tonumber(key)
    if not n then NZ.Fail('Unknown entry.') end
    return math.floor(n)
end

local function openDoc(file, hash)
    local src = read(file)
    if hash and hash ~= LuaDoc.hash(src) then
        NZ.Fail('This file changed since you opened it (someone else saved, or it was edited on disk). Reload and try again.')
    end
    local doc, err = LuaDoc.parse(src, def(file).root)
    if not doc then NZ.Fail(('Can\'t edit %s in the form view: %s. Use the code view instead.'):format(nameOf(file), err)) end
    return doc, src
end

local function serialize(file, value, indent, unit)
    local d = def(file)
    if d.inline then return LuaDoc.serializeInline(value, ORDER[d.kind]) end
    return LuaDoc.serialize(value, indent, unit, ORDER[d.kind], d.bracketKeys)
end

--- Entry names as they appear in the file for new/renamed entries
local function newKey(file, key, collection)
    local d = def(file)
    key = NZ.Trim(key)
    if key == '' then NZ.Fail('Give it a name.') end
    if d.kind == 'item' or d.kind == 'qbitem' then key = key:lower() end
    if d.kind == 'weapon' and collection == 'Weapons' then key = key:upper() end
    if d.hashKeys then key = '`' .. key:gsub('`', ''):lower() .. '`' end
    if (d.kind == 'item' or d.kind == 'qbitem') and not key:match('^[%w_%-]+$') then NZ.Fail('Item names can only use letters, numbers, _ and -.') end
    return key
end

--- qb-core keeps the item name inside the entry too; keep it in step with the key
local function nameField(file, key)
    local k = def(file).kind
    if k == 'qbitem' or k == 'qbweapon' then return bare(key) end
end

--- Values other files can offer as choices (qb-shops: which product list a shop sells)
local function refs(file)
    local out = {}
    for field, r in pairs(def(file).refs or {}) do
        local ok, src = pcall(read, r.file)
        if ok then
            local doc = LuaDoc.parse(src, def(r.file).root)
            if doc then
                local keys = {}
                for _, k in ipairs(LuaDoc.entryKeys(doc, {})) do keys[#keys + 1] = tostring(k) end
                out[field] = { options = keys, format = r.format }
            end
        end
    end
    return next(out) and out or nil
end

-- ─── routes ────────────────────────────────────────────────────────────────
NZ.Route('ed:status', 'editor', function()
    local e = ED()
    local files = {}
    for _, id in ipairs(e.order or {}) do
        local d = e.files[id]
        if d and (not d.when or d.when()) and not d.codeHidden then
            local src = LoadResourceFile(resOf(d), d.path)
            files[#files + 1] = { id = id, label = d.label, name = d.path:match('[^/]+$'), path = where(d), kind = d.kind, raw = d.raw == true,
                size = src and #src or 0, exists = src ~= nil }
        end
    end
    local bridge
    if e.bridge then local ok, info = pcall(e.bridge) if ok then bridge = info end end
    local restart = {}
    for _, r in ipairs(e.restartable or {}) do if GetResourceState(r) ~= 'missing' then restart[#restart + 1] = r end end
    return {
        bridge = bridge, files = files, resource = Inv.resource, inventory = Inv.label,
        oxVersion = Inv.Version(), restartable = restart,
        imagepath = Inv.ImagePath(), imageMaxKB = E.imageMaxKB or 256, images = e.image ~= nil,
    }
end)

NZ.Route('ed:list', 'editor', function(src, d)
    local file = d.file
    local f = def(file)
    local text = read(file)
    local out = { file = file, hash = LuaDoc.hash(text), kind = f.kind, keyed = f.keyed, raw = f.raw == true, path = where(f), name = nameOf(file) }
    if f.raw then return out end
    local data, err = evaluate(text, file)
    if not data then out.error = err return out end
    local doc, perr = LuaDoc.parse(text, f.root)
    if not doc then out.error = perr return out end
    if f.categories then
        out.collections = {}
        for _, k in ipairs(LuaDoc.entryKeys(doc, {})) do
            if type(data[k]) == 'table' then
                local n = 0
                for _ in pairs(data[k]) do n = n + 1 end
                out.collections[#out.collections + 1] = { id = k, count = n }
            end
        end
        out.collection = d.collection or (out.collections[1] and out.collections[1].id)
    end
    local cpath = f.categories and { out.collection } or {}
    local tbl = data
    for _, k in ipairs(cpath) do tbl = tbl and tbl[k] end
    out.entries = {}
    for i, key in ipairs(LuaDoc.entryKeys(doc, cpath)) do
        out.entries[#out.entries + 1] = summary(f.kind, key, lookup(tbl, key))
        if i % 400 == 0 then Wait(0) end
    end
    return out
end)

NZ.Route('ed:get', 'editor', function(src, d)
    local file = d.file
    local f = def(file)
    local doc, text = openDoc(file)
    local cpath = collectionPath(file, d.collection)
    local key = keyOf(file, d.key)
    local snippet, fld = LuaDoc.getEntry(doc, cpath, key)
    if not snippet then NZ.Fail('That entry no longer exists, reload the list.') end
    local indent = LuaDoc.entryLineIndent(doc, cpath, key)
    local data = evaluate(text, file)
    local v = data
    for _, k in ipairs(cpath) do v = v and v[k] end
    v = lookup(v, key)
    local dedented = snippet:gsub('\n' .. indent:gsub('%p', '%%%0'), '\n')
    return { hash = LuaDoc.hash(text), key = key, source = dedented, value = toJson(v), fn = hasFn(v), kind = f.kind,
        raw = fld and fld.table and rawFields(doc, fld.table) or nil, refs = refs(file) }
end)

NZ.Route('ed:save', 'editor', function(src, d)
    local file = d.file
    local f = def(file)
    local doc = openDoc(file, d.hash)
    local cpath = collectionPath(file, d.collection)
    local key = keyOf(file, d.key)
    local snippet = LuaDoc.getEntry(doc, cpath, key)
    if not snippet then NZ.Fail('That entry no longer exists, reload the list.') end
    local indent = LuaDoc.entryLineIndent(doc, cpath, key)
    local unit = LuaDoc.detectIndentUnit(doc.src)
    local finalKey = key
    local renamed = d.rename and f.keyed and newKey(file, d.rename, d.collection)
    if renamed and renamed ~= key then
        finalKey = renamed
        local gerr = f.guard and f.guard(bare(key), 'rename')
        if gerr then NZ.Fail(gerr) end
    end
    local newSnippet
    if type(d.source) == 'string' then
        local fn, cerr = load('return ' .. d.source, '=entry', 't', sandbox())
        if not fn then NZ.Fail('Code view: ' .. tostring(cerr):gsub('^entry:', 'line ')) end
        local check, err = LuaDoc.parseSnippet(d.source)
        if not check then NZ.Fail('Code view: ' .. tostring(err)) end
        newSnippet = d.source:gsub('\n', '\n' .. indent)
    elseif d.replace ~= nil then
        newSnippet = serialize(file, d.replace, indent, unit)
    else
        local ops = d.ops or {}
        local nf = nameField(file, finalKey)
        if nf and finalKey ~= key then ops[#ops + 1] = { path = { 'name' }, value = nf } end
        local err
        newSnippet, err = LuaDoc.applyOps(snippet, ops, unit)
        if not newSnippet then NZ.Fail(err) end
    end
    local text, err = LuaDoc.replaceEntry(doc, cpath, key, newSnippet)
    if not text then NZ.Fail(err) end
    if finalKey ~= key then
        local doc2, perr = LuaDoc.parse(text, f.root)
        if not doc2 then NZ.Fail(perr) end
        text, err = LuaDoc.renameEntry(doc2, cpath, key, finalKey)
        if not text then NZ.Fail(err) end
    end
    local res = commit(src, file, text, 'update', { entry = bare(finalKey), collection = d.collection, ops = d.ops and #d.ops or nil, code = d.source ~= nil, renamedFrom = finalKey ~= key and bare(key) or nil })
    res.key = finalKey
    return res
end)

NZ.Route('ed:create', 'editor', function(src, d)
    local file = d.file
    local f = def(file)
    local doc = openDoc(file, d.hash)
    local cpath = collectionPath(file, d.collection)
    local key
    if f.keyed then key = newKey(file, d.key, d.collection) end
    local indent = LuaDoc.entryIndent(doc, cpath)
    local unit = LuaDoc.detectIndentUnit(doc.src)
    local snippet
    if type(d.source) == 'string' then
        local fn, cerr = load('return ' .. d.source, '=entry', 't', sandbox())
        if not fn then NZ.Fail('Code view: ' .. tostring(cerr):gsub('^entry:', 'line ')) end
        local check, err = LuaDoc.parseSnippet(d.source)
        if not check then NZ.Fail('Code view: ' .. tostring(err)) end
        snippet = d.source:gsub('\n', '\n' .. indent)
    else
        local value = d.value or {}
        if type(value) == 'table' then
            for k, v in pairs(value) do if v == '' then value[k] = nil end end
        end
        local nf = key and nameField(file, key)
        if nf and type(value) == 'table' then value.name = nf end
        if f.kind == 'qbitem' and type(value) == 'table' and not value.image then value.image = bare(key) .. '.png' end
        snippet = serialize(file, value, indent, unit)
    end
    local text, err = LuaDoc.addEntry(doc, cpath, key, snippet)
    if not text then NZ.Fail(err) end
    local res = commit(src, file, text, 'create', { entry = key and bare(key) or 'new', collection = d.collection })
    if not f.keyed then
        local doc2 = LuaDoc.parse(text, f.root)
        key = doc2 and #LuaDoc.entryKeys(doc2, cpath) or nil
    end
    res.key = key
    return res
end)

NZ.Route('ed:delete', 'editor', function(src, d)
    local file = d.file
    local f = def(file)
    local doc = openDoc(file, d.hash)
    local cpath = collectionPath(file, d.collection)
    local key = keyOf(file, d.key)
    local gerr = f.guard and f.guard(bare(key), 'delete')
    if gerr then NZ.Fail(gerr) end
    local removed
    if d.purge and (f.kind == 'item' or f.kind == 'weapon' or f.kind == 'qbitem') and NZ.Can(src, 'global') then
        local ok, r = NZ.Call(src, 'global:remove', { item = bare(key), scope = { online = true, offline = true, stashes = true, vehicles = true } })
        if ok then removed = r end
        doc = openDoc(file)
    end
    local text, err = LuaDoc.removeEntry(doc, cpath, key)
    if not text then NZ.Fail(err) end
    local res = commit(src, file, text, 'delete', { entry = bare(key), collection = d.collection, purged = removed and removed.total or nil })
    res.purged = removed
    return res
end)

NZ.Route('ed:raw:get', 'editor', function(src, d)
    local f = def(d.file)
    local text = read(d.file)
    return { source = text, hash = LuaDoc.hash(text), path = where(f), name = nameOf(d.file) }
end)

NZ.Route('ed:raw:save', 'editor', function(src, d)
    def(d.file)
    if type(d.source) ~= 'string' or d.source == '' then NZ.Fail('The file can\'t be empty.') end
    local cur = read(d.file)
    if d.hash and d.hash ~= LuaDoc.hash(cur) then NZ.Fail('This file changed since you opened it. Copy your work, reload, and apply it again.') end
    return commit(src, d.file, d.source, 'code', { bytes = #d.source, before = #cur })
end)

NZ.Route('ed:check', 'editor', function(src, d)
    if type(d.source) ~= 'string' then return { ok = false, err = 'Nothing to check.' } end
    if d.snippet then
        local ok, err = LuaDoc.parseSnippet(d.source)
        if not ok then return { ok = false, err = err } end
        local fn, cerr = load('return ' .. d.source, '=entry', 't', sandbox())
        if not fn then return { ok = false, err = cerr } end
        local okr, v = pcall(fn)
        if not okr then return { ok = false, err = v } end
        return { ok = true, value = toJson(v) }
    end
    local _, err = evaluate(d.source, d.file)
    return { ok = err == nil, err = err }
end)

NZ.Route('ed:preview', 'editor', function(src, d)
    def(d.file)
    local doc = openDoc(d.file)
    local cpath = collectionPath(d.file, d.collection)
    local unit = LuaDoc.detectIndentUnit(doc.src)
    if d.key ~= nil and d.key ~= '' and d.ops then
        local key = keyOf(d.file, d.key)
        local snippet = LuaDoc.getEntry(doc, cpath, key)
        if not snippet then NZ.Fail('That entry no longer exists.') end
        local indent = LuaDoc.entryLineIndent(doc, cpath, key)
        local out, err = LuaDoc.applyOps(snippet, d.ops, unit)
        if not out then NZ.Fail(err) end
        return { source = out:gsub('\n' .. indent:gsub('%p', '%%%0'), '\n') }
    end
    return { source = serialize(d.file, d.value or {}, '', unit) }
end)

NZ.Route('ed:backups', 'editor', function(src, d)
    def(d.file)
    return backupIndex(d.file).list
end)

local function backupSource(file, id)
    for _, b in ipairs(backupIndex(file).list) do
        if b.id == tonumber(id) then
            local text = LoadResourceFile(NZ.Resource, ('backups/%s_%d.lua'):format(b.key or file, b.slot))
            if not text then NZ.Fail('That backup file is missing.') end
            return text, b
        end
    end
    NZ.Fail('That backup is gone (only the newest ' .. (E.backups or 25) .. ' are kept).')
end

NZ.Route('ed:backup:get', 'editor', function(src, d)
    def(d.file)
    local text = backupSource(d.file, d.id)
    return { source = text, current = read(d.file) }
end)

NZ.Route('ed:backup:restore', 'editor', function(src, d)
    def(d.file)
    local text, b = backupSource(d.file, d.id)
    return commit(src, d.file, text, 'restore', { backup = b.id, from = os.date('%Y-%m-%d %H:%M', b.time) })
end)

NZ.Route('ed:apply', 'editor', function(src, d)
    def(d.file)
    local cur = read(d.file)
    local now = evaluate(cur, d.file)
    return apply(d.file, nil, now)
end)

NZ.Route('ed:restart', 'editor', function(src, d)
    local e = ED()
    local res = d.resource or (e.restartable or {})[1]
    local allowed = false
    for _, r in ipairs(e.restartable or {}) do if r == res then allowed = true end end
    if not allowed then NZ.Fail('That resource can\'t be restarted from the panel.') end
    NZ.Audit(src, 'editor_restart', res)
    NZ.NotifyStaff(('%s is restarting %s'):format(GetPlayerName(src) or 'Console', res), 'warning', 'staff', src)
    CreateThread(function()
        if res == 'ox_inventory' then ExecuteCommand('saveinv') Wait(1500) end
        ExecuteCommand('restart ' .. res)
    end)
    return true
end)

-- ─── item images (latent event, PNG only) ──────────────────────────────────
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64MAP = {}
for i = 1, 64 do B64MAP[B64:byte(i)] = i - 1 end

local function b64decode(s)
    s = s:gsub('[^%w%+/]', '')
    local out, n = {}, 0
    for i = 1, #s, 4 do
        local a, b, c, e = B64MAP[s:byte(i)], B64MAP[s:byte(i + 1)], B64MAP[s:byte(i + 2)], B64MAP[s:byte(i + 3)]
        if not a or not b then break end
        local v = (a << 18) | (b << 12) | ((c or 0) << 6) | (e or 0)
        n = n + 1
        if not c then out[n] = string.char(v >> 16)
        elseif not e then out[n] = string.char(v >> 16, (v >> 8) & 255)
        else out[n] = string.char(v >> 16, (v >> 8) & 255, v & 255) end
    end
    return table.concat(out)
end

RegisterNetEvent('nzinv:image', function(reqId, item, b64)
    local src = source
    local function done(ok, msg, extra)
        TriggerClientEvent('nzinv:imageDone', src, reqId, ok, msg, extra)
    end
    if not NZ.Can(src, 'editor') then return done(false, 'You do not have permission for that.') end
    local e = Inv.a.editor
    local img = type(e) == 'table' and e.image
    if not img then return done(false, ('Image upload is not set up for %s.'):format(Inv.label)) end
    item = tostring(item or ''):gsub('`', '')
    if not item:match('^[%w_%-]+$') or type(b64) ~= 'string' then return done(false, 'Bad upload.') end
    b64 = b64:gsub('^data:image/png;base64,', '')
    if #b64 * 3 / 4 > (E.imageMaxKB or 256) * 1024 then return done(false, ('Images have to be under %d KB.'):format(E.imageMaxKB or 256)) end
    local bin = b64decode(b64)
    if bin:sub(1, 8) ~= '\137PNG\r\n\26\n' then return done(false, 'Only PNG images are supported.') end
    local res = img.resource or e.resource or Inv.resource
    local filePath = img.path(item)
    local ok, werr = writeFile(res, filePath, bin)
    if not ok then return done(false, werr) end
    -- make sure the file really landed
    local back = LoadResourceFile(res, filePath)
    if not back or #back ~= #bin then
        return done(false, ('The picture was sent but %s/%s did not save. Check the server console and folder permissions.'):format(res, filePath))
    end
    -- point the item at its picture when the inventory keeps the file name in the item
    local changed = false
    if img.field then
        local fok, ferr = pcall(function()
            local fdef = def(img.field.file)
            local doc, text = openDoc(img.field.file)
            local key = keyOf(img.field.file, item)
            local snippet = LuaDoc.getEntry(doc, {}, key)
            if not snippet then return end
            local want = img.field.value(item)
            local v = lookup(evaluate(text, img.field.file), key)
            local cur = type(v) == 'table' and v
            for _, k in ipairs(img.field.path) do cur = type(cur) == 'table' and cur[k] or nil end
            if cur == want then return end
            local unit = LuaDoc.detectIndentUnit(doc.src)
            local newSnippet, err = LuaDoc.applyOps(snippet, { { path = img.field.path, value = want } }, unit)
            if not newSnippet then error(err, 0) end
            local newText, rerr = LuaDoc.replaceEntry(doc, {}, key, newSnippet)
            if not newText then error(rerr, 0) end
            commit(src, img.field.file, newText, 'update', { entry = item, image = want })
            changed = fdef ~= nil
        end)
        if not fok then NZ.Print(('Picture saved, but %s could not be pointed at it: %s'):format(item, tostring(ferr)), 'warn') end
    end
    local live = false
    if img.live then
        local okl, r = pcall(img.live, item, 'data:image/png;base64,' .. b64)
        live = okl and r ~= false
    end
    NZ.Audit(src, 'editor_image', item, { bytes = #bin, file = filePath })
    done(true, live and 'Picture saved and shown to players now.' or ('Picture saved to %s. Players see it after %s restarts.'):format(filePath, res), { file = filePath:match('[^/]+$'), live = live, changed = changed })
end)
