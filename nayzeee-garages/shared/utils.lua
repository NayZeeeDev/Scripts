--[[
  nayzeee-garages — shared utilities (NZ.Utils). Pure helpers, no side effects.
]]

local Utils = NZ.Utils

---------------------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------------------

--- Success result for callbacks.
function Utils.ok(data)
  return { ok = true, data = data }
end

--- Failure result for callbacks. `message` should already be translated with L().
function Utils.fail(message)
  return { ok = false, error = message or L('Something went wrong') }
end

--- Wrap a callback handler so runtime errors become a failure result instead of a hang.
---@param fn function
---@return function
function Utils.safe(fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if ok then
      if res == nil then return Utils.ok(nil) end
      return res
    end
    lib.print.error(('[nayzeee-garages] %s'):format(res))
    return Utils.fail(L('Something went wrong'))
  end
end

function Utils.debug(...)
  if Config.Debug then
    lib.print.info('[debug]', ...)
  end
end

---------------------------------------------------------------------------------------
-- Strings & plates
---------------------------------------------------------------------------------------

function Utils.trim(s)
  if type(s) ~= 'string' then return s end
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Normalize a plate for comparisons: trimmed, upper-case.
---@param p any
---@return string|nil
function Utils.plate(p)
  if type(p) ~= 'string' then return nil end
  local t = Utils.trim(p):upper()
  if t == '' then return nil end
  return t
end

--- Clean user supplied text (names, reasons). Strips control chars and caps length.
function Utils.cleanText(s, maxLen)
  if type(s) ~= 'string' then return nil end
  s = s:gsub('[%c]', ''):gsub('<', ''):gsub('>', '')
  s = Utils.trim(s)
  if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
  if s == '' then return nil end
  return s
end

local plateChars = {
  digit = '0123456789',
  letter = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
}

--- Generate a plate from a template: '#' digit, '@' letter, '*' either, others literal.
--- Empty template generates a random 8 char plate. Result is max 8 characters.
---@param template string|nil
---@return string
function Utils.generatePlate(template)
  if type(template) ~= 'string' or template == '' then template = '@@@#####' end
  local out = {}
  for i = 1, math.min(#template, 8) do
    local c = template:sub(i, i)
    if c == '#' then
      local n = math.random(1, 10)
      out[#out + 1] = plateChars.digit:sub(n, n)
    elseif c == '@' then
      local n = math.random(1, 26)
      out[#out + 1] = plateChars.letter:sub(n, n)
    elseif c == '*' then
      local pool = plateChars.digit .. plateChars.letter
      local n = math.random(1, #pool)
      out[#out + 1] = pool:sub(n, n)
    else
      out[#out + 1] = c:upper()
    end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------------------
-- Garage keys:  L<locationId> | G<groupId> | H<houseId>
---------------------------------------------------------------------------------------

Utils.key = {}

function Utils.key.location(id) return 'L' .. tostring(id) end
function Utils.key.group(id) return 'G' .. tostring(id) end
function Utils.key.house(id) return 'H' .. tostring(id) end

--- Parse a garage key. Returns kind ('L'|'G'|'H') and id (number for L/G, string for H).
---@param key string
---@return string|nil kind, number|string|nil id
function Utils.key.parse(key)
  if type(key) ~= 'string' or #key < 2 then return nil end
  local kind, rest = key:sub(1, 1), key:sub(2)
  if kind == 'L' or kind == 'G' then
    local n = tonumber(rest)
    if not n then return nil end
    return kind, n
  elseif kind == 'H' then
    return kind, rest
  end
  return nil
end

---------------------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------------------

--- GTA vehicle class -> category used by locations.
---@param class integer
---@return 'car'|'sea'|'air'
function Utils.vehicleTypeFromClass(class)
  if class == 14 then return 'sea' end
  if class == 15 or class == 16 then return 'air' end
  return 'car'
end

Utils.vehicleTypes = { car = true, sea = true, air = true }

---------------------------------------------------------------------------------------
-- Numbers & tables
---------------------------------------------------------------------------------------

function Utils.clamp(n, min, max)
  n = tonumber(n) or min
  if n < min then return min end
  if n > max then return max end
  return n
end

function Utils.round(n, decimals)
  local m = 10 ^ (decimals or 0)
  return math.floor((tonumber(n) or 0) * m + 0.5) / m
end

function Utils.deepCopy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Utils.deepCopy(v) end
  return out
end

--- Fill missing keys of `target` from `defaults` (recursively). Arrays are not merged.
function Utils.applyDefaults(target, defaults)
  if type(target) ~= 'table' then return Utils.deepCopy(defaults) end
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = Utils.deepCopy(v)
    elseif type(v) == 'table' and type(target[k]) == 'table' and not Utils.isArray(v) then
      Utils.applyDefaults(target[k], v)
    end
  end
  return target
end

function Utils.isArray(t)
  if type(t) ~= 'table' then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

function Utils.count(t)
  local n = 0
  if type(t) == 'table' then
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------------------
-- Vectors: data travels as plain tables {x,y,z[,w]}; convert at the edges.
---------------------------------------------------------------------------------------

function Utils.v3(t)
  if type(t) == 'vector3' or type(t) == 'vector4' then return { x = t.x, y = t.y, z = t.z } end
  if type(t) ~= 'table' then return nil end
  local x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
  if not (x and y and z) then return nil end
  return { x = x, y = y, z = z }
end

function Utils.v4(t)
  if type(t) == 'vector4' then return { x = t.x, y = t.y, z = t.z, w = t.w } end
  if type(t) == 'vector3' then return { x = t.x, y = t.y, z = t.z, w = 0.0 } end
  if type(t) ~= 'table' then return nil end
  local x, y, z = tonumber(t.x or t[1]), tonumber(t.y or t[2]), tonumber(t.z or t[3])
  if not (x and y and z) then return nil end
  return { x = x, y = y, z = z, w = tonumber(t.w or t.h or t.heading or t[4]) or 0.0 }
end

function Utils.toVec3(t)
  local v = Utils.v3(t)
  return v and vector3(v.x, v.y, v.z) or nil
end

function Utils.toVec4(t)
  local v = Utils.v4(t)
  return v and vector4(v.x, v.y, v.z, v.w) or nil
end

function Utils.dist(a, b)
  local va, vb = Utils.v3(a), Utils.v3(b)
  if not va or not vb then return math.huge end
  local dx, dy, dz = va.x - vb.x, va.y - vb.y, va.z - vb.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end
