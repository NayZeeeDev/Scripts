--[[
  nayzeee-garages — logging (server): NZ.Logs.

  NZ.Logs.add(event, src, data) enriches an event with the acting player (character name,
  identifier), prints it (Config.Debug; security events always), stores it in `nz_logs`
  (ServerConfig.DatabaseLogs) and queues a Discord embed for the webhook of its channel
  (event prefix -> ServerConfig.Webhooks). Embeds are batched per webhook (max 10 per
  request, Discord size limits respected), flushed every 3 seconds, and HTTP 429 /
  rate-limit headers are honoured. Logging never throws into the caller.
]]

local Logs = NZ.Logs
local Utils = NZ.Utils

local COLOR_DEFAULT = 0x08afa2
local COLOR_SECURITY = 0xe5484d

local FLUSH_MS = 3000            -- batching window / flush interval
local MAX_EMBEDS = 10            -- Discord: embeds per message
local MAX_MESSAGE_CHARS = 6000   -- Discord: characters across every embed of one message
local MAX_EMBED_CHARS = 5500     -- our budget for a single embed (leaves headroom)
local MAX_FIELDS = 25
local MAX_TITLE = 256
local MAX_DESCRIPTION = 4096
local MAX_FIELD_NAME = 256
local MAX_FIELD_VALUE = 1024
local MAX_QUEUE = 300            -- per webhook; oldest embeds are dropped beyond this
local MAX_ATTEMPTS = 3           -- network / 5xx retries per batch
local WARN_EVERY_MS = 60000

local CHANNELS = {
  vehicle = 'vehicles',
  garage = 'vehicles',
  impound = 'impound',
  admin = 'admin',
  security = 'security',
}

-- Data keys shown first in embeds (others follow alphabetically).
local PRIORITY = { 'plate', 'model', 'garage', 'garageKey', 'location', 'locationId', 'target', 'reason', 'fee', 'price' }
local PRIORITY_RANK = {}
for i = 1, #PRIORITY do PRIORITY_RANK[PRIORITY[i]] = i end

local queues = {}          -- [url] = { items = { { embed, size, attempts } }, inFlight, retryAt, warnedAt }
local flushScheduled = false

---------------------------------------------------------------------------------------
-- Value helpers
---------------------------------------------------------------------------------------

--- Cut a string to at most maxBytes bytes without breaking a UTF-8 sequence.
local function truncate(s, maxBytes)
  if #s <= maxBytes then return s end
  local cut = s:sub(1, math.max(0, maxBytes - 3))
  while #cut > 0 and not utf8.len(cut) do cut = cut:sub(1, -2) end
  return cut .. '...'
end

local function charCount(s)
  return utf8.len(s) or #s
end

local function formatNumber(n)
  if n ~= n then return 'NaN' end
  if n == math.huge or n == -math.huge then return tostring(n) end
  if math.type(n) == 'integer' then return tostring(n) end
  if n == math.floor(n) and math.abs(n) < 1e15 then return ('%d'):format(n) end
  local s = ('%.2f'):format(n):gsub('0+$', ''):gsub('%.$', '')
  return s
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == 'number' end
    if ta == 'number' or ta == 'string' then return a < b end
    return tostring(a) < tostring(b)
  end)
  return keys
end

--- JSON-safe deep copy: vectors -> {x,y,z[,w]}, functions/userdata dropped, depth capped.
local function plain(value, depth)
  local t = type(value)
  if t == 'string' then return truncate(value, 2000) end
  if t == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return tostring(value) end
    return value
  end
  if t == 'boolean' then return value end
  if t == 'vector2' then return { x = value.x, y = value.y } end
  if t == 'vector3' then return { x = value.x, y = value.y, z = value.z } end
  if t == 'vector4' then return { x = value.x, y = value.y, z = value.z, w = value.w } end
  if t ~= 'table' then return nil end
  depth = depth or 0
  if depth >= 5 then return '[...]' end
  local out, count = {}, 0
  if Utils.isArray(value) then
    for i = 1, math.min(#value, 100) do
      local v = plain(value[i], depth + 1)
      if v ~= nil then out[#out + 1] = v end
    end
    return out
  end
  for k, v in pairs(value) do
    if count >= 100 then break end
    local key = type(k) == 'string' and k or tostring(k)
    local copy = plain(v, depth + 1)
    if copy ~= nil then
      out[key] = copy
      count = count + 1
    end
  end
  return out
end

--- Compact one-line text of a (plain) value for embeds and console lines.
local function compact(value, depth)
  local t = type(value)
  if t == 'string' then return value end
  if t == 'number' then return formatNumber(value) end
  if t == 'boolean' then return value and 'true' or 'false' end
  if t ~= 'table' then return tostring(value) end
  depth = depth or 0
  if depth >= 3 then return '{...}' end
  if next(value) == nil then return '-' end
  local parts = {}
  if Utils.isArray(value) then
    for i = 1, #value do parts[#parts + 1] = compact(value[i], depth + 1) end
    local s = table.concat(parts, ', ')
    return depth == 0 and s or ('[' .. s .. ']')
  end
  for _, k in ipairs(sortedKeys(value)) do
    parts[#parts + 1] = ('%s: %s'):format(tostring(k), compact(value[k], depth + 1))
  end
  local s = table.concat(parts, ', ')
  return depth == 0 and s or ('{' .. s .. '}')
end

--- 'garageKey' -> 'Garage key'
local function prettyKey(key)
  local s = tostring(key):gsub('_', ' '):gsub('(%l)(%u)', function(a, b) return a .. ' ' .. b:lower() end)
  return (s:gsub('^%l', string.upper))
end

---------------------------------------------------------------------------------------
-- Actor & routing
---------------------------------------------------------------------------------------

local function bridgeCall(fn, src)
  if type(fn) ~= 'function' then return nil end
  local ok, res = pcall(fn, src)
  if ok and type(res) == 'string' and res ~= '' then return res end
  return nil
end

--- Who did it: { source, name, identifier, account, license } or nil for server/console.
local function actorOf(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  local key = tostring(math.tointeger(src) or src)
  local account = GetPlayerName(key)
  local actor = {
    source = math.tointeger(src) or src,
    name = bridgeCall(NZ.Bridge.getName, src),
    identifier = bridgeCall(NZ.Bridge.getIdentifier, src),
    account = type(account) == 'string' and account or nil,
  }
  if account then
    local ok, license = pcall(GetPlayerIdentifierByType, key, 'license')
    if ok and type(license) == 'string' then actor.license = license end
  end
  return actor
end

local function channelOf(event)
  local prefix = event:match('^([%w_]+)%.')
  return prefix and CHANNELS[prefix] or 'default'
end

local function validUrl(url)
  if type(url) ~= 'string' then return nil end
  url = Utils.trim(url)
  if url == '' or not url:match('^https?://') then return nil end
  return url
end

local function webhookFor(channel)
  local hooks = ServerConfig and ServerConfig.Webhooks
  if type(hooks) ~= 'table' then return nil end
  return validUrl(hooks[channel]) or validUrl(hooks.default)
end

local function actorLabel(actor)
  if not actor then return L('Server') end
  local name = actor.name or actor.account or L('Unknown')
  return ('%s [%s]'):format(name, tostring(actor.source))
end

---------------------------------------------------------------------------------------
-- Discord
---------------------------------------------------------------------------------------

local function embedSize(embed)
  local n = charCount(embed.title or '') + charCount(embed.description or '')
  if embed.footer then n = n + charCount(embed.footer.text or '') end
  for _, field in ipairs(embed.fields or {}) do
    n = n + charCount(field.name) + charCount(field.value)
  end
  return n
end

local function buildEmbed(event, actor, data)
  local security = event:sub(1, 9) == 'security.'
  local lines = {}
  if actor then
    lines[#lines + 1] = ('**%s** (%s %s)'):format(actor.name or actor.account or L('Unknown'), L('ID'), tostring(actor.source))
    if actor.identifier then lines[#lines + 1] = ('%s: `%s`'):format(L('Identifier'), actor.identifier) end
    if actor.account and actor.account ~= actor.name then lines[#lines + 1] = ('%s: %s'):format(L('Account'), actor.account) end
    if security and actor.license then lines[#lines + 1] = ('%s: `%s`'):format(L('License'), actor.license) end
  else
    lines[#lines + 1] = ('**%s**'):format(L('Server'))
  end

  local embed = {
    title = truncate(event, MAX_TITLE),
    description = truncate(table.concat(lines, '\n'), MAX_DESCRIPTION),
    color = security and COLOR_SECURITY or COLOR_DEFAULT,
    fields = {},
    footer = { text = NZ.ResourceName },
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
  }

  if type(data) == 'table' then
    local keys = sortedKeys(data)
    table.sort(keys, function(a, b)
      local ra, rb = PRIORITY_RANK[a] or 1000, PRIORITY_RANK[b] or 1000
      if ra ~= rb then return ra < rb end
      return tostring(a) < tostring(b)
    end)
    local budget = MAX_EMBED_CHARS - embedSize(embed)
    for i, key in ipairs(keys) do
      if #embed.fields >= MAX_FIELDS - 1 and i < #keys then
        embed.fields[#embed.fields + 1] = { name = '...', value = L('{count} more', { count = #keys - i + 1 }), inline = false }
        break
      end
      local name = truncate(prettyKey(key), MAX_FIELD_NAME)
      local value = compact(data[key])
      if value == '' then value = '-' end
      value = truncate(value, math.min(MAX_FIELD_VALUE, math.max(16, budget - charCount(name))))
      local cost = charCount(name) + charCount(value)
      if cost > budget then break end
      budget = budget - cost
      embed.fields[#embed.fields + 1] = { name = name, value = value, inline = charCount(value) <= 40 }
    end
  elseif data ~= nil then
    local value = truncate(compact(data), MAX_FIELD_VALUE)
    embed.fields[1] = { name = L('Details'), value = value ~= '' and value or '-', inline = false }
  end
  return embed
end

local function header(headers, name)
  if type(headers) ~= 'table' then return nil end
  local lower = name:lower()
  for k, v in pairs(headers) do
    if type(k) == 'string' and k:lower() == lower then return v end
  end
  return nil
end

local function warnOnce(state, message)
  local now = GetGameTimer()
  if state.warnedAt and now - state.warnedAt < WARN_EVERY_MS then return end
  state.warnedAt = now
  lib.print.warn(message)
end

local scheduleFlush

local function requeue(state, batch)
  for i = #batch, 1, -1 do table.insert(state.items, 1, batch[i]) end
  while #state.items > MAX_QUEUE do table.remove(state.items) end
end

--- Delay (ms) Discord asked for: JSON body retry_after (seconds) or Retry-After header.
local function retryDelay(body, headers)
  local seconds = nil
  if type(body) == 'string' and body ~= '' then
    local ok, decoded = pcall(json.decode, body)
    if ok and type(decoded) == 'table' then seconds = tonumber(decoded.retry_after) end
  end
  seconds = seconds or tonumber(header(headers, 'Retry-After')) or 5
  return math.floor(seconds * 1000) + 250
end

local function onResponse(url, state, batch, status, body, headers, errorData)
  state.inFlight = false
  status = tonumber(status) or 0
  local now = GetGameTimer()

  if status >= 200 and status < 300 then
    if header(headers, 'X-RateLimit-Remaining') == '0' then
      local after = tonumber(header(headers, 'X-RateLimit-Reset-After'))
      if after then state.retryAt = now + math.floor(after * 1000) + 100 end
    end
  elseif status == 429 then
    state.retryAt = now + retryDelay(body or errorData, headers)
    requeue(state, batch)
  elseif status == 0 or status >= 500 then
    local retry = {}
    for i = 1, #batch do
      batch[i].attempts = batch[i].attempts + 1
      if batch[i].attempts < MAX_ATTEMPTS then retry[#retry + 1] = batch[i] end
    end
    requeue(state, retry)
    state.retryAt = now + FLUSH_MS * 2
    warnOnce(state, ('logs: Discord webhook unreachable (HTTP %d), retrying'):format(status))
  else
    warnOnce(state, ('logs: Discord webhook rejected %d embed(s) (HTTP %d): %s'):format(
      #batch, status, truncate(tostring(body or errorData or ''), 200)))
  end

  if #state.items == 0 and not (state.retryAt and state.retryAt > now) then queues[url] = nil end
  scheduleFlush()
end

local function sendBatch(url, state)
  if state.inFlight or #state.items == 0 then return end
  if state.retryAt and GetGameTimer() < state.retryAt then return end

  local batch, embeds, size = {}, {}, 0
  while #batch < MAX_EMBEDS and state.items[1] do
    local item = state.items[1]
    if #batch > 0 and size + item.size > MAX_MESSAGE_CHARS then break end
    table.remove(state.items, 1)
    batch[#batch + 1] = item
    embeds[#embeds + 1] = item.embed
    size = size + item.size
  end
  if #batch == 0 then return end

  local ok, payload = pcall(json.encode, {
    username = NZ.ResourceName,
    embeds = embeds,
    allowed_mentions = { parse = {} },
  })
  if not ok or type(payload) ~= 'string' then
    warnOnce(state, ('logs: could not encode Discord payload: %s'):format(tostring(payload)))
    return
  end

  state.inFlight = true
  local sent, err = pcall(PerformHttpRequest, url, function(status, body, headers, errorData)
    local handled, handleErr = pcall(onResponse, url, state, batch, status, body, headers, errorData)
    if not handled then
      state.inFlight = false
      lib.print.warn(('logs: webhook response handling failed: %s'):format(tostring(handleErr)))
    end
  end, 'POST', payload, { ['Content-Type'] = 'application/json' })
  if not sent then
    state.inFlight = false
    requeue(state, batch)
    warnOnce(state, ('logs: webhook request failed: %s'):format(tostring(err)))
  end
end

local function flush()
  flushScheduled = false
  local now = GetGameTimer()
  local pending, nextAt = false, nil
  for url, state in pairs(queues) do
    sendBatch(url, state)
    if #state.items > 0 or state.inFlight then
      pending = true
      if state.retryAt and state.retryAt > now and (not nextAt or state.retryAt < nextAt) then
        nextAt = state.retryAt
      end
    elseif not (state.retryAt and state.retryAt > now) then
      queues[url] = nil
    end
  end
  if pending then
    local delay = FLUSH_MS
    if nextAt and nextAt - now > delay then delay = nextAt - now end
    scheduleFlush(delay)
  end
end

scheduleFlush = function(delay)
  if flushScheduled or next(queues) == nil then return end
  flushScheduled = true
  SetTimeout(delay or FLUSH_MS, function()
    local ok, err = pcall(flush)
    if not ok then
      flushScheduled = false
      lib.print.warn(('logs: flush failed: %s'):format(tostring(err)))
    end
  end)
end

local function queueEmbed(url, embed)
  local state = queues[url]
  if not state then
    state = { items = {}, inFlight = false }
    queues[url] = state
  end
  local size = math.min(embedSize(embed), MAX_MESSAGE_CHARS)
  state.items[#state.items + 1] = { embed = embed, size = size, attempts = 0 }
  if #state.items > MAX_QUEUE then
    table.remove(state.items, 1)
    warnOnce(state, 'logs: Discord queue is full, dropping the oldest entries')
  end
  scheduleFlush()
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

local function addLog(event, src, data)
  if type(event) ~= 'string' or event == '' then return end
  event = truncate(event:gsub('%c', ''), 48)
  local actor = actorOf(src)
  local clean = plain(data)
  local security = event:sub(1, 9) == 'security.'

  -- Console
  if Config.Debug or security then
    local line = ('[log] %s | %s | %s'):format(event, actorLabel(actor), truncate(compact(clean or {}), 800))
    if security then lib.print.warn(line) else lib.print.info(line) end
  end

  -- Database
  if not (ServerConfig and ServerConfig.DatabaseLogs == false) and type(NZ.DB.logs) == 'table'
    and type(NZ.DB.logs.add) == 'function' then
    local record = clean
    if record ~= nil and type(record) ~= 'table' then record = { value = record } end
    if actor then
      record = record and Utils.deepCopy(record) or {}
      record.actorSource = actor.source
      record.actorName = actor.name or actor.account
    end
    local identifier = actor and actor.identifier
    if not identifier and type(clean) == 'table' and type(clean.identifier) == 'string' then
      identifier = clean.identifier
    end
    local plate = type(clean) == 'table' and Utils.plate(clean.plate) or nil
    local ok, err = pcall(NZ.DB.logs.add, event, identifier, plate, record)
    if not ok then lib.print.warn(('logs: database insert failed: %s'):format(tostring(err))) end
  end

  -- Discord
  local url = webhookFor(channelOf(event))
  if url then queueEmbed(url, buildEmbed(event, actor, clean)) end
end

--- Record an event: console (debug / security), database (nz_logs) and Discord webhook.
--- Never throws. Event names: 'vehicle.*', 'garage.*' (vehicles channel), 'impound.*',
--- 'admin.*', 'security.*'; anything else goes to the default webhook.
---@param event string e.g. 'vehicle.retrieve'
---@param src number|nil acting player (nil / 0 = server)
---@param data table|nil details (plate, garage, ...)
function Logs.add(event, src, data)
  local ok, err = pcall(addLog, event, src, data)
  if not ok then pcall(lib.print.warn, ('logs: could not log "%s": %s'):format(tostring(event), tostring(err))) end
end
