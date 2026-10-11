-- Lua data-file engine for the ox_inventory editor.
-- Edits are applied as text splices so comments, spacing, backtick hashes and functions
-- that the panel never touched stay byte-for-byte identical.
LuaDoc = {}

local sub, find, match, byte = string.sub, string.find, string.match, string.byte

local KEYWORDS = {
    ['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true, ['elseif'] = true, ['end'] = true,
    ['false'] = true, ['for'] = true, ['function'] = true, ['goto'] = true, ['if'] = true, ['in'] = true,
    ['local'] = true, ['nil'] = true, ['not'] = true, ['or'] = true, ['repeat'] = true, ['return'] = true,
    ['then'] = true, ['true'] = true, ['until'] = true, ['while'] = true,
}
local OPEN_BLOCK = { ['function'] = true, ['if'] = true, ['do'] = true, ['repeat'] = true }
local CLOSE_BLOCK = { ['end'] = true, ['until'] = true }
local OPS3 = { ['...'] = true }
local OPS2 = { ['..'] = true, ['=='] = true, ['~='] = true, ['<='] = true, ['>='] = true, ['//'] = true, ['::'] = true,
    ['<<'] = true, ['>>'] = true, ['+='] = true, ['-='] = true, ['*='] = true, ['/='] = true, ['?.'] = true, ['?['] = true }

--- Tokenize Lua source. Each token: { t = kind, s = startPos, e = endPos, v = text for names/punct }
local function tokenize(src)
    local toks, n, i = {}, #src, 1
    while true do
        i = find(src, '%S', i)
        if not i then break end
        local c = sub(src, i, i)
        if c == '-' and sub(src, i + 1, i + 1) == '-' then
            local lvl = match(src, '^%[(=*)%[', i + 2)
            if lvl then
                local close = ']' .. lvl .. ']'
                local e = find(src, close, i + 2, true)
                i = e and (e + #close) or (n + 1)
            else
                local e = find(src, '\n', i, true)
                i = e and (e + 1) or (n + 1)
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = sub(src, j, j)
                if d == '\\' then j = j + 2
                elseif d == c or d == '\n' then break
                else j = j + 1 end
            end
            toks[#toks + 1] = { t = 'str', s = i, e = j }
            i = j + 1
        elseif c == '`' then
            local e = find(src, '`', i + 1, true) or n
            toks[#toks + 1] = { t = 'hash', s = i, e = e }
            i = e + 1
        elseif c == '[' and match(src, '^%[=*%[', i) then
            local lvl = match(src, '^%[(=*)%[', i)
            local close = ']' .. lvl .. ']'
            local e = find(src, close, i, true)
            local stop = e and (e + #close - 1) or n
            toks[#toks + 1] = { t = 'str', s = i, e = stop }
            i = stop + 1
        elseif match(c, '[%a_]') then
            local e = select(2, find(src, '^[%w_]+', i))
            local word = sub(src, i, e)
            toks[#toks + 1] = { t = KEYWORDS[word] and 'kw' or 'name', s = i, e = e, v = word }
            i = e + 1
        elseif match(c, '%d') or (c == '.' and match(sub(src, i + 1, i + 1), '%d')) then
            local e = select(2, find(src, '^0[xX][%x%.]*[pP]?[%+%-]?%x*', i))
            if not e then e = select(2, find(src, '^%d*%.?%d*[eE][%+%-]?%d+', i)) end
            if not e then e = select(2, find(src, '^%d*%.?%d*', i)) end
            toks[#toks + 1] = { t = 'num', s = i, e = e }
            i = e + 1
        else
            local three, two = sub(src, i, i + 2), sub(src, i, i + 1)
            local v = OPS3[three] and three or OPS2[two] and two or c
            toks[#toks + 1] = { t = 'op', s = i, e = i + #v - 1, v = v }
            i = i + #v
        end
    end
    return toks
end
LuaDoc.tokenize = tokenize

local function tokv(tk) return tk and tk.v end

--- Decode a literal key token ('name', "name", [[name]], 12) into a Lua value.
local function literalKey(src, tk)
    if not tk then return nil end
    local text = sub(src, tk.s, tk.e)
    if tk.t == 'num' then return tonumber(text) end
    if tk.t == 'hash' then return text end
    if tk.t == 'str' then
        local fn = load('return ' .. text, '=key', 't', {})
        if fn then
            local ok, v = pcall(fn)
            if ok then return v end
        end
    end
    return text
end

local parseTable

--- Scan an expression that starts at token index i. Returns the index of its last token.
local function scanExpr(toks, i)
    local depth, j, last = 0, i, i
    while toks[j] do
        local tk = toks[j]
        local v = tk.v
        if tk.t == 'op' then
            if v == '(' or v == '{' or v == '[' or v == '?[' then depth = depth + 1
            elseif v == ')' or v == ']' then depth = depth - 1
            elseif v == '}' then
                if depth == 0 then return last end
                depth = depth - 1
            elseif (v == ',' or v == ';') and depth == 0 then return last end
        elseif tk.t == 'kw' then
            if OPEN_BLOCK[v] then depth = depth + 1
            elseif CLOSE_BLOCK[v] then depth = depth - 1 end
        end
        last = j
        j = j + 1
    end
    return last
end

--- Parse a table constructor whose '{' token is toks[k].
--- Returns node { open = k, close = idx, fields = { ... } }
parseTable = function(src, toks, k)
    local node = { open = k, fields = {} }
    local i, arr = k + 1, 0
    while true do
        local tk = toks[i]
        if not tk then error('unclosed table starting at character ' .. toks[k].s, 0) end
        if tk.t == 'op' and tk.v == '}' then node.close = i break end
        local f = { first = i }
        if tk.t == 'op' and tk.v == '[' then
            local j, d = i + 1, 1
            while toks[j] do
                local x = toks[j]
                if x.t == 'op' and (x.v == '[' or x.v == '?[') then d = d + 1
                elseif x.t == 'op' and x.v == ']' then d = d - 1 if d == 0 then break end end
                j = j + 1
            end
            if not toks[j] or tokv(toks[j + 1]) ~= '=' then error('bad table key near character ' .. tk.s, 0) end
            f.key = (j == i + 2) and literalKey(src, toks[i + 1]) or sub(src, toks[i + 1].s, toks[j - 1].e)
            f.bracket = true
            f.vstart = j + 2
        elseif tk.t == 'name' and tokv(toks[i + 1]) == '=' then
            f.key = tk.v
            f.vstart = i + 2
        else
            arr = arr + 1
            f.key = arr
            f.positional = true
            f.vstart = i
        end
        local vt = toks[f.vstart]
        if not vt then error('missing value near character ' .. tk.s, 0) end
        if vt.t == 'op' and vt.v == '{' then
            local child = parseTable(src, toks, f.vstart)
            local after = toks[child.close + 1]
            if after and not (after.t == 'op' and (after.v == ',' or after.v == ';' or after.v == '}')) then
                f.vend = scanExpr(toks, f.vstart)
            else
                f.table = child
                f.vend = child.close
            end
        else
            f.vend = scanExpr(toks, f.vstart)
        end
        local sep = toks[f.vend + 1]
        if sep and sep.t == 'op' and (sep.v == ',' or sep.v == ';') then
            f.sep = f.vend + 1
            i = f.vend + 2
        else
            i = f.vend + 1
        end
        node.fields[#node.fields + 1] = f
    end
    return node
end

--- Parse a whole data file. The table is either the final `return { ... }` statement, or, when
--- `root` is given (e.g. 'QBShared.Items'), the last `QBShared.Items = { ... }` assignment.
--- Returns doc { src, toks, root = tableNode } or nil, err
function LuaDoc.parse(src, root)
    local ok, toks = pcall(tokenize, src)
    if not ok then return nil, toks end
    local open
    if root and root ~= '' then
        local parts = {}
        for p in tostring(root):gmatch('[^%.]+') do parts[#parts + 1] = p end
        for i = #toks, 1, -1 do
            local j, good = i, true
            for pi, p in ipairs(parts) do
                local tk = toks[j]
                if not tk or tk.t ~= 'name' or tk.v ~= p then good = false break end
                j = j + 1
                if pi < #parts then
                    if tokv(toks[j]) ~= '.' then good = false break end
                    j = j + 1
                end
            end
            if good and tokv(toks[j]) == '=' and tokv(toks[j + 1]) == '{' and tokv(toks[i - 1]) ~= '.' then
                open = j + 1
                break
            end
        end
        if not open then return nil, ('could not find `%s = { ... }` in this file'):format(root) end
    else
        for i = #toks, 1, -1 do
            local tk = toks[i]
            if tk.t == 'kw' and tk.v == 'return' and tokv(toks[i + 1]) == '{' then open = i + 1 break end
        end
        if not open then return nil, 'this file does not end in a plain `return { ... }` table' end
    end
    local ok2, node = pcall(parseTable, src, toks, open)
    if not ok2 then return nil, node end
    return { src = src, toks = toks, root = node, rootPath = root }
end

--- Parse a standalone table constructor snippet `{ ... }`.
function LuaDoc.parseSnippet(src)
    local ok, toks = pcall(tokenize, src)
    if not ok then return nil, toks end
    if tokv(toks[1]) ~= '{' then return nil, 'entry must be a table { ... }' end
    local ok2, root = pcall(parseTable, src, toks, 1)
    if not ok2 then return nil, root end
    if root.close ~= #toks then return nil, 'unexpected text after the closing }' end
    return { src = src, toks = toks, root = root }
end

local function fieldByKey(node, key)
    for idx, f in ipairs(node.fields) do
        if f.key == key then return f, idx end
    end
    if type(key) == 'string' then
        local asNum = tonumber(key)
        if asNum then
            for idx, f in ipairs(node.fields) do if f.key == asNum then return f, idx end end
        end
    end
end
LuaDoc.fieldByKey = fieldByKey

--- Find a table node along a path of keys (strings/numbers). Returns node or nil.
function LuaDoc.nodeAt(doc, path)
    local node = doc.root
    for i = 1, #(path or {}) do
        local f = fieldByKey(node, path[i])
        if not f or not f.table then return nil end
        node = f.table
    end
    return node
end

--- Text helpers -------------------------------------------------------------------------------
local function lineStart(src, pos)
    local p = pos
    while p > 1 and sub(src, p - 1, p - 1) ~= '\n' do p = p - 1 end
    return p
end

local function indentOf(src, pos)
    local ls = lineStart(src, pos)
    return match(src, '^[ \t]*', ls)
end

function LuaDoc.detectIndentUnit(src)
    local tabs = select(2, src:gsub('\n\t', ''))
    local spaces4 = select(2, src:gsub('\n    ', ''))
    local spaces2 = select(2, src:gsub('\n  %S', ''))
    if tabs >= spaces4 and tabs >= spaces2 then return '\t' end
    if spaces4 >= spaces2 then return '    ' end
    return '  '
end

function LuaDoc.fieldText(doc, f)
    return sub(doc.src, doc.toks[f.first].s, doc.toks[f.vend].e)
end

function LuaDoc.valueText(doc, f)
    return sub(doc.src, doc.toks[f.vstart].s, doc.toks[f.vend].e)
end

--- Serializer: JSON-ish value -> Lua source ---------------------------------------------------
local IDENT = '^[%a_][%w_]*$'

local function quote(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\'):gsub("'", "\\'"):gsub('\n', '\\n'):gsub('\r', '\\r')
    return "'" .. s .. "'"
end
LuaDoc.quote = quote

local function numText(n)
    if math.type and math.type(n) == 'integer' then return tostring(n) end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format('%d', n) end
    local s = string.format('%.6f', n):gsub('0+$', ''):gsub('%.$', '.0')
    return s
end

local function fmtNum(v) return type(v) == 'number' and numText(v) or tostring(tonumber(v) or 0) end

function LuaDoc.keyText(key, bracketStyle)
    if type(key) == 'number' then return '[' .. numText(key) .. ']' end
    if match(tostring(key), '^`[^`]+`$') then return '[' .. key .. ']' end
    if not bracketStyle and match(key, IDENT) and not KEYWORDS[key] then return key end
    return '[' .. quote(key) .. ']'
end

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local function sortedKeys(t, order)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    local rank = {}
    for i, k in ipairs(order or {}) do rank[k] = i end
    table.sort(keys, function(a, b)
        local ra, rb = rank[a] or 999, rank[b] or 999
        if ra ~= rb then return ra < rb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- Serialize a value. Special tables: { __vec3 = {x,y,z} }, { __vec4 }, { __vec2 }, { __hash = 'name' },
--- { __raw = 'lua code' }. Empty JSON objects arrive as empty tables.
function LuaDoc.serialize(v, indent, unit, order, bracketKeys)
    indent, unit = indent or '', unit or '\t'
    local tv = type(v)
    if tv == 'string' then return quote(v) end
    if tv == 'number' then return numText(v) end
    if tv == 'boolean' then return tostring(v) end
    if tv ~= 'table' then return 'nil' end
    if v.__raw then return tostring(v.__raw) end
    if v.__hash then return '`' .. tostring(v.__hash):gsub('`', '') .. '`' end
    if v.__vec3 then local a = v.__vec3 return ('vec3(%s, %s, %s)'):format(fmtNum(a[1] or a.x), fmtNum(a[2] or a.y), fmtNum(a[3] or a.z)) end
    if v.__vec4 then local a = v.__vec4 return ('vec4(%s, %s, %s, %s)'):format(fmtNum(a[1] or a.x), fmtNum(a[2] or a.y), fmtNum(a[3] or a.z), fmtNum(a[4] or a.w)) end
    if v.__vec2 then local a = v.__vec2 return ('vec2(%s, %s)'):format(fmtNum(a[1] or a.x), fmtNum(a[2] or a.y)) end
    if next(v) == nil then return '{}' end

    local arr, n = isArray(v)
    local inner = indent .. unit
    local parts = {}
    if arr then
        local simple = true
        for i = 1, n do
            local x = v[i]
            if type(x) == 'table' and not (x.__vec3 or x.__vec4 or x.__vec2 or x.__hash) then simple = false break end
        end
        if simple and n <= 12 then
            for i = 1, n do parts[i] = LuaDoc.serialize(v[i], inner, unit) end
            return '{ ' .. table.concat(parts, ', ') .. ' }'
        end
        for i = 1, n do parts[i] = inner .. LuaDoc.serialize(v[i], inner, unit, order) .. ',' end
        return '{\n' .. table.concat(parts, '\n') .. '\n' .. indent .. '}'
    end

    local short = true
    local count = 0
    for _, x in pairs(v) do
        count = count + 1
        if type(x) == 'table' and not (x.__vec3 or x.__vec4 or x.__vec2 or x.__hash or x.__raw) then short = false end
        if type(x) == 'string' and #x > 40 then short = false end
    end
    local keys = sortedKeys(v, order)
    if short and count <= 3 and not bracketKeys then
        for i, k in ipairs(keys) do parts[i] = LuaDoc.keyText(k) .. ' = ' .. LuaDoc.serialize(v[k], inner, unit) end
        return '{ ' .. table.concat(parts, ', ') .. ' }'
    end
    for i, k in ipairs(keys) do
        parts[i] = inner .. LuaDoc.keyText(k, bracketKeys) .. ' = ' .. LuaDoc.serialize(v[k], inner, unit, order) .. ','
    end
    return '{\n' .. table.concat(parts, '\n') .. '\n' .. indent .. '}'
end

--- Same as serialize, but everything on one line (for files like qb-core's items.lua).
function LuaDoc.serializeInline(v, order)
    local tv = type(v)
    if tv ~= 'table' then return LuaDoc.serialize(v) end
    if v.__raw or v.__hash or v.__vec3 or v.__vec4 or v.__vec2 then return LuaDoc.serialize(v) end
    if next(v) == nil then return '{}' end
    local parts = {}
    local arr, n = isArray(v)
    if arr then
        for i = 1, n do parts[i] = LuaDoc.serializeInline(v[i]) end
    else
        for i, k in ipairs(sortedKeys(v, order)) do parts[i] = LuaDoc.keyText(k) .. ' = ' .. LuaDoc.serializeInline(v[k]) end
    end
    return '{ ' .. table.concat(parts, ', ') .. ' }'
end

--- Editing primitives on a snippet or file -----------------------------------------------------

local function splice(src, s, e, text)
    return sub(src, 1, s - 1) .. text .. sub(src, e + 1)
end

--- Replace the value of field f.
local function replaceValue(doc, f, valueText)
    return splice(doc.src, doc.toks[f.vstart].s, doc.toks[f.vend].e, valueText)
end

--- Remove field f including its separator, indentation and trailing newline.
local function removeField(doc, f)
    local src, toks = doc.src, doc.toks
    local s = toks[f.first].s
    local e = toks[f.sep or f.vend].e
    local ls = lineStart(src, s)
    if match(sub(src, ls, s - 1), '^[ \t]*$') then s = ls end
    local rest = match(src, '^[ \t]*\r?\n', e + 1)
    if not rest and sub(src, s - 1, s - 1) == ' ' and sub(src, e + 1, e + 1) == ' ' then e = e + 1 end
    if rest then
        e = e + #rest
        -- swallow one blank line if the field was framed by blank lines
        local blank = match(src, '^[ \t]*\r?\n', e + 1)
        if blank and s > 2 and sub(src, s - 2, s - 1) == '\n\n' then e = e + #blank end
    end
    return splice(src, s, e, '')
end

--- Insert a new field text into node (before its closing brace).
local function insertField(doc, node, fieldText, unit, gapLine)
    local src, toks = doc.src, doc.toks
    local closeTok = toks[node.close]
    local last = node.fields[#node.fields]
    -- a table written on one line stays on one line
    if not find(sub(src, toks[node.open].s, closeTok.e), '\n', 1, true) then
        if not last then return splice(src, toks[node.open].e + 1, closeTok.s - 1, ' ' .. fieldText .. ' ') end
        if last.sep then return splice(src, toks[last.sep].e + 1, toks[last.sep].e, ' ' .. fieldText .. ',') end
        return splice(src, toks[last.vend].e + 1, toks[last.vend].e, ', ' .. fieldText)
    end
    if last then
        local indent = indentOf(src, toks[last.first].s)
        local insertAt, prefix
        if last.sep then
            insertAt = toks[last.sep].e
            prefix = ''
        else
            insertAt = toks[last.vend].e
            prefix = ','
        end
        local gap = gapLine and '\n' or ''
        return splice(src, insertAt + 1, insertAt, prefix .. '\n' .. gap .. indent .. fieldText .. ',')
    end
    -- empty table
    local openTok = toks[node.open]
    local baseIndent = indentOf(src, openTok.s)
    local between = sub(src, openTok.e + 1, closeTok.s - 1)
    local body = '\n' .. baseIndent .. unit .. fieldText .. ',\n' .. baseIndent
    if match(between, '^%s*$') then
        return splice(src, openTok.e + 1, closeTok.s - 1, body)
    end
    return splice(src, closeTok.s, closeTok.s - 1, body)
end

--- Does the node separate its fields with blank lines (like items.lua)?
local function usesBlankGaps(doc, node)
    local f1, f2 = node.fields[#node.fields - 1], node.fields[#node.fields]
    if not f1 or not f2 then return false end
    local between = sub(doc.src, doc.toks[f1.vend].e + 1, doc.toks[f2.first].s - 1)
    return find(between, '\n[ \t]*\r?\n') ~= nil
end

local function usesBracketKeys(node)
    for _, f in ipairs(node.fields) do
        if not f.positional then return f.bracket == true end
    end
    return false
end

--- Apply a set/unset at a path inside a snippet doc. Returns new source or nil, err.
--- op = { path = { 'client', 'image' }, value = <json>, unset = bool }
function LuaDoc.applyOp(src, op, unit, parser)
    parser = parser or LuaDoc.parseSnippet
    local doc, err = parser(src)
    if not doc then return nil, err end
    unit = unit or LuaDoc.detectIndentUnit(src)
    local node = doc.root
    local path = op.path or {}
    if #path == 0 then return nil, 'empty path' end
    for i = 1, #path - 1 do
        local f = fieldByKey(node, path[i])
        if not f then
            if op.unset then return src end
            -- create the missing parent chain in one go
            local nested = op.value
            for j = #path, i + 1, -1 do nested = { [path[j]] = nested } end
            local indent
            if node.fields[1] then indent = indentOf(doc.src, doc.toks[node.fields[#node.fields].first].s)
            else indent = indentOf(doc.src, doc.toks[node.open].s) .. unit end
            local text = LuaDoc.keyText(path[i]) .. ' = ' .. LuaDoc.serialize(nested, indent, unit)
            return insertField(doc, node, text, unit, false)
        end
        if not f.table then
            if op.unset then return src end
            local nested = op.value
            for j = #path, i + 1, -1 do nested = { [path[j]] = nested } end
            local indent = indentOf(doc.src, doc.toks[f.first].s)
            return replaceValue(doc, f, LuaDoc.serialize(nested, indent, unit))
        end
        node = f.table
    end
    local key = path[#path]
    local f = fieldByKey(node, key)
    if op.unset then
        if not f then return src end
        return removeField(doc, f)
    end
    if f then
        local indent = indentOf(doc.src, doc.toks[f.first].s)
        return replaceValue(doc, f, LuaDoc.serialize(op.value, indent, unit))
    end
    local indent
    if node.fields[1] then indent = indentOf(doc.src, doc.toks[node.fields[#node.fields].first].s)
    else indent = indentOf(doc.src, doc.toks[node.open].s) .. unit end
    local text = LuaDoc.keyText(key, usesBracketKeys(node)) .. ' = ' .. LuaDoc.serialize(op.value, indent, unit)
    return insertField(doc, node, text, unit, false)
end

--- Apply a list of ops to an entry snippet.
function LuaDoc.applyOps(src, ops, unit)
    for _, op in ipairs(ops or {}) do
        local out, err = LuaDoc.applyOp(src, op, unit)
        if not out then return nil, err end
        src = out
    end
    return src
end

--- Entry-level file operations ------------------------------------------------------------------
--- collectionPath: path to the table that holds entries (e.g. {} for items, { 'Weapons' } for weapons)

--- Return the entry snippet (value text) and the field.
function LuaDoc.getEntry(doc, collectionPath, key)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    local f = fieldByKey(node, key)
    if not f then return nil, 'entry not found' end
    return LuaDoc.valueText(doc, f), f
end

--- Re-indent a snippet so its first line matches `indent` (subsequent lines shift by the delta).
local function reindent(snippet, fromIndent, toIndent)
    if fromIndent == toIndent then return snippet end
    local out = snippet:gsub('\n' .. fromIndent:gsub('%p', '%%%0'), '\n' .. toIndent)
    return out
end

function LuaDoc.replaceEntry(doc, collectionPath, key, snippet)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    local f = fieldByKey(node, key)
    if not f then return nil, 'entry not found' end
    return replaceValue(doc, f, snippet)
end

function LuaDoc.removeEntry(doc, collectionPath, key)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    local f = fieldByKey(node, key)
    if not f then return nil, 'entry not found' end
    return removeField(doc, f)
end

--- Add an entry. key = string for keyed collections, nil for arrays. snippet is the value source,
--- written as if its first line sits at `entryIndent`; pass the indent you serialized with.
function LuaDoc.addEntry(doc, collectionPath, key, snippet)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    if key ~= nil and fieldByKey(node, key) then return nil, 'an entry with that name already exists' end
    local text
    if key == nil then text = snippet
    else text = LuaDoc.keyText(key, usesBracketKeys(node)) .. ' = ' .. snippet end
    return insertField(doc, node, text, LuaDoc.detectIndentUnit(doc.src), usesBlankGaps(doc, node))
end

--- Add many keyed entries in one splice (imports). list = { { key = 'name', snippet = '{ ... }' }, ... }
--- Snippets must already be indented for the collection. Existing keys are left to the caller.
function LuaDoc.addEntries(doc, collectionPath, list)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    if #list == 0 then return doc.src end
    local indent = LuaDoc.entryIndent(doc, collectionPath)
    local gap = usesBlankGaps(doc, node) and '\n' or ''
    local bracket = usesBracketKeys(node)
    local parts = {}
    for i, e in ipairs(list) do parts[i] = LuaDoc.keyText(e.key, bracket) .. ' = ' .. e.snippet end
    return insertField(doc, node, table.concat(parts, ',\n' .. gap .. indent), LuaDoc.detectIndentUnit(doc.src), gap ~= '')
end

--- Replace the values of many entries in one pass. map = { [key] = snippet }
function LuaDoc.replaceEntries(doc, collectionPath, map)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    local hits = {}
    for key, snippet in pairs(map) do
        local f = fieldByKey(node, key)
        if f then hits[#hits + 1] = { s = doc.toks[f.vstart].s, e = doc.toks[f.vend].e, text = snippet } end
    end
    -- splice from the end of the file backwards so earlier positions stay valid
    table.sort(hits, function(a, b) return a.s > b.s end)
    local src = doc.src
    for _, h in ipairs(hits) do src = splice(src, h.s, h.e, h.text) end
    return src
end

--- Indentation that a new entry in the collection will sit at.
function LuaDoc.entryIndent(doc, collectionPath)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return '' end
    local last = node.fields[#node.fields]
    if last then return indentOf(doc.src, doc.toks[last.first].s) end
    return indentOf(doc.src, doc.toks[node.open].s) .. LuaDoc.detectIndentUnit(doc.src)
end

function LuaDoc.entryKeys(doc, collectionPath)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return {} end
    local keys = {}
    for i, f in ipairs(node.fields) do keys[i] = f.key end
    return keys
end

--- Rename a keyed entry in place (keeps its position in the file).
function LuaDoc.renameEntry(doc, collectionPath, key, newKey)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    if not node then return nil, 'collection not found' end
    local f = fieldByKey(node, key)
    if not f or f.positional then return nil, 'entry not found' end
    if fieldByKey(node, newKey) then return nil, 'an entry with that name already exists' end
    local s = doc.toks[f.first].s
    local e = doc.toks[f.vstart - 2].e
    return splice(doc.src, s, e, LuaDoc.keyText(newKey, f.bracket))
end

--- Indentation of the line an entry starts on.
function LuaDoc.entryLineIndent(doc, collectionPath, key)
    local node = LuaDoc.nodeAt(doc, collectionPath)
    local f = node and fieldByKey(node, key)
    if not f then return '' end
    return indentOf(doc.src, doc.toks[f.first].s)
end

LuaDoc.reindent = reindent
LuaDoc.indentOf = indentOf

--- Cheap content hash (djb2) used as a file version for conflict detection.
function LuaDoc.hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + byte(s, i)) % 4294967296 end
    return ('%08x%05x'):format(h, #s % 1048576)
end

return LuaDoc
