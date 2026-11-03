--[[
  nayzeee-garages — notification integration (client): NZ.Notify.
  Every notification of the resource ends in NZ.Notify.show(kind, message, title, duration):
  client code (NZ.NUI.notify / NZ.Bridge.notify), the server (event nz:client:notify) and the
  interface (NUI callback 'notify'). While a garage window holds NUI focus it is drawn inside
  that window (Config.Notify.inInterface, see showSafe); otherwise it is handed to the system
  picked with Config.Integrations.notify, and when that resource is not started (or its call
  fails) the notification is shown with ox_lib instead. NZ.Notify.show never throws.
]]

local Notify = NZ.Notify

---------------------------------------------------------------------------------------
-- Custom notifications  (Config.Integrations.notify = 'custom')
--
-- Edit this function to send the garage notifications to any notification resource.
--   kind      'success' | 'error' | 'info' | 'warning'
--   message   string, already translated, plain text (max 300 characters)
--   title     string|nil: the notification's own title, otherwise Config.Notify.title
--             (nil when there is none)
--   duration  number, milliseconds (Config.Notify.duration unless the sender chose one)
-- Return false (or raise an error) to show that notification with ox_lib instead.
-- While a garage window holds the mouse, notifications are drawn inside that window and do
-- not reach this function (set Config.Notify.inInterface = false to change that).
-- Out of the box it returns false, so ox_lib is used until you fill it in, e.g.:
--   exports['my_notify']:Send({ type = kind, title = title, text = message, time = duration })
--   return true
---------------------------------------------------------------------------------------
function Notify.custom(kind, message, title, duration) -- luacheck: ignore 212
  return false
end

---------------------------------------------------------------------------------------
-- Limits & tables
---------------------------------------------------------------------------------------

local MAX_MESSAGE = 300        -- characters (UTF-8 code points)
local MAX_TITLE = 60
local DEFAULT_DURATION = 5000  -- ms
local MIN_DURATION, MAX_DURATION = 1000, 30000
local REPEAT_MS = 1500         -- the same notification twice within this window is shown once

-- Accepted kinds (+ the aliases other systems use) -> our four kinds.
local KINDS = {
  success = 'success', error = 'error', info = 'info', warning = 'warning',
  inform = 'info', primary = 'info', warn = 'warning', danger = 'error',
}

-- ox_lib (and lation_ui) positions.
local POSITIONS = {
  ['top'] = true, ['top-right'] = true, ['top-left'] = true,
  ['bottom'] = true, ['bottom-right'] = true, ['bottom-left'] = true,
  ['center-right'] = true, ['center-left'] = true,
}

-- Config value (lower case, punctuation-insensitive) -> adapter name.
local ALIASES = {
  ox_lib = 'ox_lib', oxlib = 'ox_lib', ox = 'ox_lib', lib = 'ox_lib',
  framework = 'framework', auto = 'auto',
  qb = 'qb', qbcore = 'qb', ['qb-core'] = 'qb',
  qbx = 'qbx', qbox = 'qbx', qbx_core = 'qbx',
  esx = 'esx', es_extended = 'esx', esx_notify = 'esx',
  okoknotify = 'okokNotify', okok = 'okokNotify',
  mythic_notify = 'mythic_notify', mythic = 'mythic_notify',
  pnotify = 'pNotify',
  wasabi_notify = 'wasabi_notify', wasabi = 'wasabi_notify',
  brutal_notify = 'brutal_notify', brutal = 'brutal_notify',
  lation_ui = 'lation_ui', lation = 'lation_ui',
  ['t-notify'] = 't-notify', t_notify = 't-notify', tnotify = 't-notify',
  custom = 'custom',
}

-- 'auto': the first dedicated notification resource that is running, otherwise ox_lib.
local AUTO_ORDER = {
  'okokNotify', 'wasabi_notify', 'brutal_notify', 'lation_ui', 't-notify', 'mythic_notify', 'pNotify',
}

---------------------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------------------

local function running(resource)
  return GetResourceState(resource) == 'started'
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local ZWSP = '\u{200B}' -- zero-width space

--- Plain text: no control characters except line breaks, no angle brackets (so notification
--- UIs that render HTML - qb-core, mythic, pNotify, okokNotify, ... - cannot be injected
--- through player-chosen names) and no image syntax: `![` gets a zero-width space, which
--- breaks markdown images (ox_lib / qbx_core descriptions) and t-notify's `![url]` image tag
--- without any visible change, so a notification never makes the client load a remote URL.
local function plain(value)
  local s = tostring(value)
  s = s:gsub('\r\n', '\n'):gsub('[\0-\9\11-\31\127]', ''):gsub('<', '‹'):gsub('>', '›')
  s = s:gsub('!%[', '!' .. ZWSP .. '[')
  return trim(s)
end

--- Markdown-safe text for fields rendered as markdown (ox_lib's notification description,
--- also used by qbx_core): every ASCII punctuation character is backslash-escaped, so names
--- like "Mc_Gregor" or "#1 Dealer" show literally instead of turning into emphasis or
--- headings, and line breaks stay line breaks.
local function markdown(s)
  return (s:gsub('%p', '\\%0'):gsub('\n', '  \n'))
end

--- Cap to `max` characters (UTF-8 aware), ending with an ellipsis when cut.
local function clip(s, max)
  local len = utf8.len(s)
  if not len then
    return #s > max and s:sub(1, max) or s
  end
  if len <= max then return s end
  return s:sub(1, utf8.offset(s, max) - 1) .. '…'
end

--- "Title: message" for systems without a title field (explicit titles only).
local function joined(title, message)
  if title:find('[%.!%?:]$') then return title .. ' ' .. message end
  return title .. ': ' .. message
end

local function escapeHtml(s)
  return (s:gsub('&', '&amp;'):gsub('"', '&quot;'))
end

local function configured()
  local cfg = Config.Notify
  return type(cfg) == 'table' and cfg or {}
end

--- Build the normalized notification or nil when there is nothing to show.
local function build(kind, message, title, duration)
  if message == nil then return nil end
  message = plain(message)
  if message == '' then return nil end

  local n = {
    kind = KINDS[type(kind) == 'string' and kind:lower() or ''] or 'info',
    message = clip(message, MAX_MESSAGE),
    explicitTitle = false,
  }

  if type(title) == 'string' then
    title = plain(title)
    if title ~= '' then
      n.title = clip(title, MAX_TITLE)
      n.explicitTitle = true
    end
  end
  if not n.title then
    local cfgTitle = configured().title
    if type(cfgTitle) == 'string' and trim(cfgTitle) ~= '' then
      n.title = clip(plain(L(trim(cfgTitle))), MAX_TITLE)
    end
  end

  local ms = tonumber(duration)
  if not ms or ms ~= ms or ms <= 0 then ms = tonumber(configured().duration) end
  if not ms or ms ~= ms then ms = DEFAULT_DURATION end
  n.duration = math.floor(math.max(MIN_DURATION, math.min(ms, MAX_DURATION)))

  local position = configured().position
  if type(position) == 'string' and POSITIONS[position] then n.position = position end
  return n
end

---------------------------------------------------------------------------------------
-- Adapters: show(n) displays the notification; returning false means "not handled".
-- n = { kind, message, title|nil, explicitTitle, duration, position|nil }
---------------------------------------------------------------------------------------

local adapters = {}

-- ox_lib: lib.notify (types info / warning / success / error). The title is plain text, the
-- description is rendered as markdown (ox_lib 3+). Without a position the player's own
-- ox_lib notification position is used.
adapters.ox_lib = {
  resource = 'ox_lib',
  show = function(n)
    lib.notify({
      title = n.title,
      description = markdown(n.message),
      type = n.kind,
      duration = n.duration,
      position = n.position,
    })
  end,
}

-- QBCore: QBCore.Functions.Notify(text, type, length) through its 'QBCore:Notify' event.
-- `text` may be { text, caption }: the caption is the smaller, dimmed line below. An explicit
-- title becomes the headline with the message as caption; the generic Config.Notify.title is
-- shown as the caption under the message.
local QB_TYPES = { success = 'success', error = 'error', info = 'primary', warning = 'warning' }
adapters.qb = {
  resource = 'qb-core',
  show = function(n)
    local text = n.message
    if n.explicitTitle then
      text = { text = n.title, caption = n.message }
    elseif n.title then
      text = { text = n.message, caption = n.title }
    end
    TriggerEvent('QBCore:Notify', text, QB_TYPES[n.kind], n.duration)
  end,
}

-- Qbox: exports.qbx_core:Notify(text, type, duration, subTitle). qbx_core uses the title as
-- the ox_lib notification id, so a shared title would make every garage notification
-- replace the previous one: only explicit titles are passed. The message always lands in
-- the ox_lib description (markdown): `text` without a subTitle, otherwise the subTitle.
local QBX_TYPES = { success = 'success', error = 'error', info = 'inform', warning = 'warning' }
adapters.qbx = {
  resource = 'qbx_core',
  show = function(n)
    if n.explicitTitle then
      exports.qbx_core:Notify(n.title, QBX_TYPES[n.kind], n.duration, markdown(n.message))
    else
      exports.qbx_core:Notify(markdown(n.message), QBX_TYPES[n.kind], n.duration)
    end
  end,
}

-- ESX: esx_notify, the notification resource of ESX Legacy (1.9+), called directly:
-- exports.esx_notify:Notify(type, length, message, title?, position?), types success / error /
-- info / warning. Title and position are read by recent versions (older ones ignore them).
-- Without a title the title is '' rather than nil: esx_notify replaces a nil title with its
-- own "New Notification" heading, and '' (truthy in Lua) keeps it empty. ESX.ShowNotification only
-- forwards to this export (and does nothing when esx_notify is missing), and the
-- 'esx:showNotification' event drops local triggers on 1.11 / 1.12 (secured net event), so
-- neither is used: when esx_notify is not started the notification is shown with ox_lib.
local ESX_POSITIONS = {
  ['top'] = 'top-middle', ['top-right'] = 'top-right', ['top-left'] = 'top-left',
  ['bottom'] = 'bottom-middle', ['bottom-right'] = 'bottom-right', ['bottom-left'] = 'bottom-left',
  ['center-right'] = 'middle-right', ['center-left'] = 'middle-left',
}
adapters.esx = {
  resource = 'esx_notify',
  show = function(n)
    exports['esx_notify']:Notify(n.kind, n.duration, n.message, n.title or '', ESX_POSITIONS[n.position])
  end,
}

-- okokNotify: exports.okokNotify:Alert(title, message, time, type, playSound).
adapters.okokNotify = {
  resource = 'okokNotify',
  show = function(n)
    exports['okokNotify']:Alert(n.title or '', n.message, n.duration, n.kind, false)
  end,
}

-- mythic_notify: v1.0.x exports DoCustomHudText(type, text, length, style); v1.1.0 renamed
-- it to SendAlert(type, text, length, style) with the same arguments. Both are tried (the
-- one that worked is tried first next time); when neither exists the call raises and the
-- notification goes to ox_lib. Types: inform / error / success, so warnings use 'inform'
-- with an amber style. No title field.
local MYTHIC_TYPES = { success = 'success', error = 'error', info = 'inform', warning = 'inform' }
local MYTHIC_WARNING = { ['background-color'] = 'rgb(229, 165, 10)', ['color'] = '#1d1400' }
local MYTHIC_CALLS = {
  function(t, text, ms, style) exports['mythic_notify']:DoCustomHudText(t, text, ms, style) end, -- v1.0.x
  function(t, text, ms, style) exports['mythic_notify']:SendAlert(t, text, ms, style) end,       -- v1.1.0
}
local mythicCall = 1
adapters.mythic_notify = {
  resource = 'mythic_notify',
  show = function(n)
    local text = n.explicitTitle and joined(n.title, n.message) or n.message
    local t, style = MYTHIC_TYPES[n.kind], n.kind == 'warning' and MYTHIC_WARNING or nil
    if pcall(MYTHIC_CALLS[mythicCall], t, text, n.duration, style) then return end
    mythicCall = 3 - mythicCall
    MYTHIC_CALLS[mythicCall](t, text, n.duration, style) -- raises when missing too -> ox_lib
  end,
}

-- pNotify: SendNotification({ text (HTML), type, timeout, layout }). Types success / error /
-- info / warning (Noty).
local PNOTIFY_LAYOUTS = {
  ['top'] = 'topCenter', ['top-right'] = 'topRight', ['top-left'] = 'topLeft',
  ['bottom'] = 'bottomCenter', ['bottom-right'] = 'bottomRight', ['bottom-left'] = 'bottomLeft',
  ['center-right'] = 'centerRight', ['center-left'] = 'centerLeft',
}
adapters.pNotify = {
  resource = 'pNotify',
  show = function(n)
    local text = escapeHtml(n.message)
    if n.title then text = ('<b>%s</b><br>%s'):format(escapeHtml(n.title), text) end
    exports['pNotify']:SendNotification({
      text = text,
      type = n.kind,
      timeout = n.duration,
      layout = PNOTIFY_LAYOUTS[n.position], -- nil: pNotify's own default layout
    })
  end,
}

-- wasabi_notify: exports.wasabi_notify:notify(title, message, duration, type).
adapters.wasabi_notify = {
  resource = 'wasabi_notify',
  show = function(n)
    exports['wasabi_notify']:notify(n.title or '', n.message, n.duration, n.kind)
  end,
}

-- brutal_notify: exports.brutal_notify:SendAlert(title, message, time, type, playSound).
adapters.brutal_notify = {
  resource = 'brutal_notify',
  show = function(n)
    exports['brutal_notify']:SendAlert(n.title or '', n.message, n.duration, n.kind, false)
  end,
}

-- lation_ui: exports.lation_ui:notify({ title, message, type, duration, position }).
adapters.lation_ui = {
  resource = 'lation_ui',
  show = function(n)
    exports['lation_ui']:notify({
      title = n.title,
      message = n.message,
      type = n.kind,
      duration = n.duration,
      position = n.position,
    })
  end,
}

-- t-notify: Alert({ style, message, duration }) / Custom({ style, title, message, duration }).
-- (Its position field must be a table, so the resource's own position config is used.)
adapters['t-notify'] = {
  resource = 't-notify',
  show = function(n)
    if n.title then
      exports['t-notify']:Custom({ style = n.kind, title = n.title, message = n.message, duration = n.duration })
    else
      exports['t-notify']:Alert({ style = n.kind, message = n.message, duration = n.duration })
    end
  end,
}

-- custom: NZ.Notify.custom at the top of this file.
adapters.custom = {
  show = function(n)
    return Notify.custom(n.kind, n.message, n.title, n.duration)
  end,
}

---------------------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------------------

local FRAMEWORK_ADAPTER = { qb = 'qb', qbx = 'qbx', esx = 'esx' }

local configuredName -- normalized Config.Integrations.notify (resolved once)
local warned = {}

local function warnOnce(key, text)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] Notifications: %s'):format(text))
end

local function configuredAdapter()
  if configuredName then return configuredName end
  local value = Config.Integrations and Config.Integrations.notify
  local name = 'ox_lib'
  if type(value) == 'string' and value ~= '' then
    name = ALIASES[value:lower():gsub('%s+', '')] or ALIASES[value:lower():gsub('[%s%-]+', '_')]
    if not name then
      warnOnce('unknown', ('unknown Config.Integrations.notify "%s", using ox_lib.'):format(value))
      name = 'ox_lib'
    end
  end
  configuredName = name
  return name
end

--- Adapter name used for the next notification ('auto' / 'framework' resolved).
---@return string
function Notify.current()
  local name = configuredAdapter()
  if name == 'framework' then
    return FRAMEWORK_ADAPTER[NZ.Framework] or 'ox_lib'
  end
  if name == 'auto' then
    for i = 1, #AUTO_ORDER do
      if running(AUTO_ORDER[i]) then return AUTO_ORDER[i] end
    end
    return 'ox_lib'
  end
  return name
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

local lastKey, lastAt = nil, -REPEAT_MS

--- Whether the next notification is drawn inside the interface (a window holds NUI focus).
local function inInterface()
  if configured().inInterface == false then return false end
  local nui = NZ.NUI
  return type(nui) == 'table' and type(nui.toast) == 'function' and type(nui.hasFocus) == 'function'
    and nui.hasFocus() == true
end

local function showSafe(kind, message, title, duration)
  local n = build(kind, message, title, duration)
  if not n then return false end

  local key = n.kind .. '\0' .. (n.title or '') .. '\0' .. n.message
  local now = GetGameTimer()
  if key == lastKey and now - lastAt < REPEAT_MS then return true end
  lastKey, lastAt = key, now

  -- While one of our windows holds NUI focus, FiveM draws our page above every other
  -- resource's NUI (its root page raises the focused frame), so the notify resource would be
  -- hidden behind the window: draw the notification inside our own page instead. Only an
  -- explicit title is shown there (the generic Config.Notify.title is redundant inside the
  -- garage window). Config.Notify.inInterface = false always uses the integration.
  if inInterface() then
    local ok, err = pcall(NZ.NUI.toast, {
      type = n.kind,
      title = n.explicitTitle and n.title or nil,
      message = n.message,
      duration = n.duration,
    })
    if ok then return true end
    warnOnce('failed:interface', ('drawing in the interface failed (%s), using the integration.'):format(tostring(err)))
  end

  local name = Notify.current()
  local adapter = adapters[name]
  if adapter and name ~= 'ox_lib' then
    if adapter.resource and not running(adapter.resource) then
      warnOnce('stopped:' .. name, ('%s is not started, using ox_lib instead.'):format(adapter.resource))
    else
      local ok, res = pcall(adapter.show, n)
      if ok and res ~= false then return true end
      if not ok then
        warnOnce('failed:' .. name, ('%s failed (%s), using ox_lib instead.'):format(name, tostring(res)))
      end
    end
  end

  local ok, err = pcall(adapters.ox_lib.show, n)
  if ok then return true end
  warnOnce('failed:ox_lib', ('ox_lib notify failed (%s).'):format(tostring(err)))
  print(('[nayzeee-garages] %s%s'):format(n.title and (n.title .. ': ') or '', n.message))
  return false
end

--- Show a notification through the configured integration.
---@param kind 'success'|'error'|'info'|'warning'|string|nil unknown kinds show as 'info'
---@param message string
---@param title string|nil defaults to Config.Notify.title ('' = none)
---@param duration number|nil milliseconds, defaults to Config.Notify.duration
---@return boolean shown
function Notify.show(kind, message, title, duration)
  local ok, res = pcall(showSafe, kind, message, title, duration)
  if ok then return res == true end
  lib.print.error(('[nayzeee-garages] NZ.Notify.show failed: %s'):format(tostring(res)))
  return false
end
