--[[
  nayzeee-garages — interior creator, client side (NZ.Creator).
  Runs the in-world editor behind the NUI app 'creator': picks the entry / exit, loads IPL
  profiles, records camera points and previews the cutscene, places vehicle slots with the
  ghost tool (numbered ghosts stay visible), walk mode, save / cancel. Every 'creator:*'
  NUI callback of docs/ARCHITECTURE.md §8.2 is handled here.
]]

local Creator = NZ.Creator
local Utils = NZ.Utils

local GHOST_MODEL = 'sultan'
local SLOT_ALPHA = 140
local LABEL_DISTANCE = 80.0

local active = nil        -- { data, startPos, walking, busy, slots, ghosts, profile }
local focusKeybind = nil

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

--- Await a server callback and always return a result table.
local function await(name, payload)
  local ok, res = pcall(lib.callback.await, name, false, payload or {})
  if not ok then
    lib.print.error(('[nayzeee-garages] callback "%s" failed: %s'):format(name, res))
    return Utils.fail(L('The server did not respond, try again'))
  end
  if type(res) ~= 'table' or type(res.ok) ~= 'boolean' then
    return Utils.fail(L('The server did not respond, try again'))
  end
  if not res.ok and type(res.error) ~= 'string' then res.error = L('Something went wrong') end
  return res
end

local function roundV4(v)
  return {
    x = Utils.round(v.x, 3),
    y = Utils.round(v.y, 3),
    z = Utils.round(v.z, 3),
    w = Utils.round((tonumber(v.w) or 0.0) % 360.0, 2),
  }
end

local function pedV4()
  local ped = PlayerPedId()
  local c = Utils.v3(GetEntityCoords(ped)) or { x = 0.0, y = 0.0, z = 0.0 }
  return roundV4({ x = c.x, y = c.y, z = c.z, w = tonumber(GetEntityHeading(ped)) or 0.0 })
end

local function normalizeSlots(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for i = 1, #list do
    local v = Utils.v4(list[i])
    if v then out[#out + 1] = v end
  end
  return out
end

local function keyLabel(keybind, fallback)
  if keybind and type(keybind.getCurrentKey) == 'function' then
    local ok, key = pcall(keybind.getCurrentKey, keybind)
    if ok and type(key) == 'string' and key ~= '' then return key end
  end
  return fallback
end

--- Give / take NUI focus to the creator app without closing it.
local function setEditorFocus(focus)
  if type(NZ.NUI.setFocus) == 'function' then
    NZ.NUI.setFocus('creator', focus)
  else
    SetNuiFocus(focus, focus)
  end
end

local function emptyObject(t)
  if next(t) == nil then setmetatable(t, { __jsontype = 'object' }) end
  return t
end

--- Fill every Interior field the editor relies on.
local function normalizeInterior(raw)
  local out = Utils.deepCopy(raw)
  out.name = type(out.name) == 'string' and out.name or ''
  out.enabled = out.enabled ~= false
  if type(out.profile) ~= 'string' or out.profile == '' then out.profile = nil end
  out.options = emptyObject(type(out.options) == 'table' and out.options or {})
  out.entry = Utils.v4(out.entry) or pedV4()
  local cut = type(out.cutscene) == 'table' and out.cutscene or {}
  out.cutscene = {
    enabled = cut.enabled == true,
    transition = math.floor(Utils.clamp(tonumber(cut.transition) or 3000, 0, 60000)),
    returnTime = math.floor(Utils.clamp(tonumber(cut.returnTime) or 1000, 0, 30000)),
    points = type(cut.points) == 'table' and cut.points or {},
  }
  out.slots = normalizeSlots(out.slots)
  out.exit = Utils.v4(out.exit)
  out.gtaInteriorId = math.tointeger(tonumber(out.gtaInteriorId))
  return out
end

---------------------------------------------------------------------------------------
-- Slot ghosts
---------------------------------------------------------------------------------------

local function clearGhosts(s)
  for i = 1, #s.ghosts do
    if s.ghosts[i] then NZ.Placement.removeGhost(s.ghosts[i]) end
  end
  s.ghosts = {}
end

--- Show one ghost per slot (reusing / moving existing ones).
local function syncGhosts(s, slots)
  local count = math.max(#slots, #s.ghosts)
  for i = 1, count do
    local want, ghost = slots[i], s.ghosts[i]
    if want then
      if ghost and DoesEntityExist(ghost) then
        NZ.Placement.moveGhost(ghost, want)
      else
        s.ghosts[i] = NZ.Placement.createGhost(GHOST_MODEL, want, SLOT_ALPHA) or false
      end
    elseif ghost ~= nil then
      if ghost then NZ.Placement.removeGhost(ghost) end
      s.ghosts[i] = nil
    end
  end
  s.slots = slots
end

--- Slot numbers above the ghosts (per frame only while the editor has slots).
local function startLabelLoop(s)
  CreateThread(function()
    while active == s do
      local count = #s.slots
      if count > 0 then
        local p = Utils.v3(GetEntityCoords(PlayerPedId())) or { x = 0.0, y = 0.0, z = 0.0 }
        for i = 1, count do
          local c = s.slots[i]
          if c and not s.hidden[i] and Utils.dist(c, p) < LABEL_DISTANCE then
            NZ.Placement.drawText3D(c.x, c.y, c.z + 1.3, ('#%d'):format(i), 0.55)
          end
        end
        Wait(0)
      else
        Wait(500)
      end
    end
  end)
end

--- Crash / logout marker of the editor: `entry` = where the admin is working now.
local function setMarker(s, entry)
  if active ~= s or type(NZ.Interior.creatorMarker) ~= 'function' then return end
  NZ.Interior.creatorMarker(Utils.v3(entry), s.startPos)
end

---------------------------------------------------------------------------------------
-- Keybind (walk mode)
---------------------------------------------------------------------------------------

local function ensureKeybind()
  if focusKeybind then return end
  focusKeybind = lib.addKeybind({
    name = 'nz_creator_focus',
    description = L('Interior editor: open the editor'),
    defaultKey = Config.Keys.creatorFocus or 'E',
    onPressed = function()
      local s = active
      if not s or not s.walking or s.busy or IsPauseMenuActive() then return end
      s.walking = false
      NZ.NUI.hint(nil)
      setEditorFocus(true)
    end,
  })
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Open the interior editor with CreatorData { mode, interior, profiles, gtaInteriorName }.
--- opts = { returnTo = Vec4 (where stop() brings the admin back; default: here),
---          teleport = false (go to interior.entry after loading its profile) }.
--- Blocking when teleporting; call from a thread.
---@param creatorData table
---@param opts table|nil
---@return boolean
function Creator.start(creatorData, opts)
  opts = type(opts) == 'table' and opts or {}
  if type(creatorData) ~= 'table' or type(creatorData.interior) ~= 'table' then
    NZ.NUI.notify('error', L('This interior could not be opened'))
    return false
  end
  if NZ.Interior.isInside() then
    NZ.NUI.notify('error', L('Leave the garage interior first'))
    return false
  end

  local returnTo = Utils.v4(opts.returnTo)
  if active then
    returnTo = returnTo or active.startPos
    Creator.stop({ teleport = false })
  end

  local interior = normalizeInterior(creatorData.interior)
  local data = {
    mode = creatorData.mode == 'edit' and 'edit' or 'create',
    interior = interior,
    profiles = type(creatorData.profiles) == 'table' and creatorData.profiles or NZ.Interior.profileViews(),
    gtaInteriorName = type(creatorData.gtaInteriorName) == 'string' and creatorData.gtaInteriorName or nil,
  }
  local s = {
    data = data,
    startPos = returnTo or pedV4(),
    walking = false,
    busy = true,
    slots = {},
    ghosts = {},
    hidden = {},
    profile = interior.profile,
  }
  active = s

  if interior.profile then NZ.Interior.loadProfile(interior.profile, interior.options, interior.entry) end
  -- A crash / logout while editing (often inside a sealed interior): next login takes the
  -- admin back to s.startPos (see NZ.Interior.creatorMarker).
  setMarker(s, interior.entry)
  if opts.teleport then NZ.Interior.teleport(interior.entry) end
  if active ~= s then return false end

  ensureKeybind()
  syncGhosts(s, normalizeSlots(interior.slots))
  startLabelLoop(s)
  s.busy = false
  NZ.NUI.open('creator', data)
  return true
end

--- Close the editor: delete the slot ghosts, clear the hint, close the app and (unless
--- opts.teleport == false) teleport back to where the editor was started. Blocking.
--- opts.keepMarker keeps the crash / logout marker (character unload).
---@param opts table|nil
function Creator.stop(opts)
  local s = active
  if not s then return end
  opts = type(opts) == 'table' and opts or {}
  active = nil
  if not opts.keepMarker and type(NZ.Interior.creatorMarker) == 'function' then NZ.Interior.creatorMarker(nil) end
  NZ.NUI.hint(nil)
  clearGhosts(s)
  if NZ.Camera.isPlaying() then NZ.Camera.stop() end
  FreezeEntityPosition(PlayerPedId(), false)
  SetModelAsNoLongerNeeded(joaat(GHOST_MODEL))
  if NZ.NUI.isOpen('creator') then NZ.NUI.close('creator') end
  if opts.teleport ~= false and s.startPos then NZ.Interior.teleport(s.startPos) end
end

--- Whether the editor is open.
---@return boolean
function Creator.isActive()
  return active ~= nil
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

--- Register a creator callback that needs an open editor (and no action in progress
--- unless `allowBusy`).
local function handler(name, fn, allowBusy)
  NZ.NUI.register(name, function(data)
    local s = active
    if not s then return Utils.fail(L('The interior editor is not open')) end
    if s.busy and not allowBusy then return Utils.fail(L('Finish the current action first')) end
    return fn(s, data)
  end)
end

handler('creator:pickEntry', function()
  local ped = PlayerPedId()
  local interiorId = math.tointeger(tonumber(GetInteriorFromEntity(ped))) or 0
  return {
    entry = pedV4(),
    gtaInteriorId = interiorId ~= 0 and interiorId or nil,
    gtaInteriorName = nil,
  }
end)

handler('creator:applyProfile', function(s, data)
  local key = data.profile
  if key == nil or key == false or key == '' then
    s.profile = nil
    return { entry = nil }
  end
  local profiles = Config.IplProfiles
  local raw = type(key) == 'string' and type(profiles) == 'table' and profiles[key] or nil
  if type(raw) ~= 'table' then return Utils.fail(L('Unknown interior profile')) end
  local options = type(data.options) == 'table' and data.options or {}
  local coords = Utils.v4(raw.coords)
  local changed = key ~= s.profile

  NZ.Interior.loadProfile(key, options, coords or s.data.interior.entry)
  s.profile = key
  if not changed or not coords then return { entry = nil } end

  s.busy = true
  setMarker(s, coords)
  NZ.Interior.teleport(coords)
  -- Entity sets refresh once the interior is streamed in around the player.
  NZ.Interior.loadProfile(key, options, coords)
  s.busy = false
  return { entry = roundV4(coords) }
end)

handler('creator:addCameraPoint', function()
  return NZ.Camera.current()
end)

handler('creator:previewCutscene', function(s, data)
  local cut = type(data.cutscene) == 'table' and data.cutscene or nil
  if not cut or type(cut.points) ~= 'table' or #cut.points == 0 then
    return Utils.fail(L('Add at least one camera point first'))
  end
  s.busy = true
  s.walking = false
  setEditorFocus(false)
  NZ.NUI.hint({ title = L('Cutscene preview'), keys = { { keys = { 'Esc' }, label = L('Stop preview') } } })
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  local ok, err = pcall(NZ.Camera.playPath, cut.points, tonumber(cut.transition) or 3000, {
    returnTime = tonumber(cut.returnTime) or 1000,
    skippable = true,
  })
  FreezeEntityPosition(ped, false)
  NZ.NUI.hint(nil)
  if active == s then setEditorFocus(true) end
  s.busy = false
  if not ok then
    lib.print.error(('[nayzeee-garages] cutscene preview failed: %s'):format(err))
    return Utils.fail(L('Something went wrong'))
  end
  return nil
end)

handler('creator:placeSlot', function(s, data)
  local slot = Utils.v4(data.slot)
  s.busy = true
  s.walking = false
  setEditorFocus(false)

  -- The ghost of the slot being edited hides while its replacement is placed.
  local editIndex = nil
  if slot then
    for i = 1, #s.slots do
      if Utils.dist(s.slots[i], slot) < 0.05 then
        editIndex = i
        break
      end
    end
  end
  local edited = editIndex and s.ghosts[editIndex] or nil
  if editIndex then s.hidden[editIndex] = true end
  if edited and DoesEntityExist(edited) then SetEntityVisible(edited, false, false) end

  local ok, result = pcall(NZ.Placement.vehicle, {
    model = GHOST_MODEL,
    start = slot,
    title = L('Place vehicle'),
  })
  if not ok then
    lib.print.error(('[nayzeee-garages] slot placement failed: %s'):format(result))
    result = nil
  end

  if editIndex then s.hidden[editIndex] = nil end
  if edited and DoesEntityExist(edited) then SetEntityVisible(edited, true, false) end
  if active == s then
    if result then
      local list = {}
      for i = 1, #s.slots do list[i] = s.slots[i] end
      if editIndex then
        list[editIndex] = result
      else
        list[#list + 1] = result
      end
      syncGhosts(s, list)
    end
    setEditorFocus(true)
  end
  s.busy = false
  return result
end)

handler('creator:showSlots', function(s, data)
  syncGhosts(s, normalizeSlots(data.slots))
  return nil
end, true)

handler('creator:pickExit', function()
  return pedV4()
end)

handler('creator:teleport', function(s, data)
  if not Utils.v3(data.coords) then return Utils.fail(L('Invalid coordinates')) end
  s.busy = true
  setMarker(s, data.coords)
  NZ.Interior.teleport(data.coords)
  s.busy = false
  return nil
end)

handler('creator:walk', function(s)
  s.walking = true
  setEditorFocus(false)
  NZ.NUI.hint({
    keys = { { keys = { keyLabel(focusKeybind, Config.Keys.creatorFocus or 'E') }, label = L('Open editor') } },
  })
  return nil
end)

handler('creator:save', function(s, data)
  if type(data.interior) ~= 'table' then return Utils.fail(L('Nothing to save')) end
  s.busy = true
  local res = await('nz:creator:save', { interior = data.interior })
  s.busy = false
  if not res.ok then return res end
  if active == s then Creator.stop() end
  NZ.NUI.notify('success', L('Interior saved'))
  NZ.AdminClient.open('interiors')
  return Utils.ok(res.data)
end)

NZ.NUI.register('creator:cancel', function()
  local s = active
  if s and s.busy then return Utils.fail(L('Finish the current action first')) end
  Creator.stop()
  NZ.AdminClient.open('interiors')
  return nil
end)

---------------------------------------------------------------------------------------
-- Forced close, unload, resource stop
---------------------------------------------------------------------------------------

NZ.NUI.onClose('creator', function(_, reason)
  local s = active
  if not s then return end
  CreateThread(function()
    if active ~= s then return end
    -- Everything was closed to enter a garage interior: do not teleport over it.
    if NZ.Interior.isInside() then
      Creator.stop({ teleport = false })
      return
    end
    Creator.stop()
    -- Closed from the interface (close button): behave like "Cancel".
    if reason == 'nui' then NZ.AdminClient.open('interiors') end
  end)
end)

AddEventHandler('nz:client:playerUnloaded', function()
  local s = active
  if not s then return end
  Creator.stop({ teleport = false, keepMarker = true })
  -- Best effort: back to where the editor was opened before the framework saves the
  -- position (the marker stays for the next login in case the save came first).
  local p = s.startPos
  if p then
    local ped = PlayerPedId()
    SetEntityCoords(ped, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, (tonumber(p.w) or 0.0) + 0.0)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  local s = active
  if not s then return end
  active = nil
  clearGhosts(s)
  local ped = PlayerPedId()
  FreezeEntityPosition(ped, false)
  local p = s.startPos
  if p then
    SetEntityCoords(ped, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, p.w + 0.0)
    if type(NZ.Interior.creatorMarker) == 'function' then NZ.Interior.creatorMarker(nil) end
  end
end)
