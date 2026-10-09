if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  THE MACHINE
--
--  The page becomes the prop's screen texture, and the buttons you
--  press are the ones modelled on the machine. You look around with
--  the mouse inside a set of limits, a button lights up when it is
--  under the middle of your view, and you click to push it.
--
--  The page never learns any of that. Lua works out which button is
--  being looked at and tells the page which one to light; the page
--  is a screen and nothing more. That keeps every decision — what a
--  button does in a given state, whether a PIN is right — on this
--  side, where it belongs.
-- ═══════════════════════════════════════════════════════════

local DUI = {
  obj = nil, txd = nil, replaced = {},
  active = false, entity = nil, model = nil, cfg = nil, cam = nil,
  buttons = {}, hover = nil, look = nil, base = nil,
  state = 'boot', data = {},
  pin = '', buffer = '', stage = nil, mode = nil,
  card = nil, payload = nil, busy = false
}

local TXD_NAME = 'nz_atm_txd'
local TEX_NAME = 'nz_atm_tex'

local KEYS = Config.ATM.keypad or {}

-- ═══════════════════════════════════════════════════════════
--  TYPING ON A REAL KEYBOARD
--
--  FiveM cannot read a raw key, only named controls, and the number
--  row's control IDs are not consistent between builds — which is
--  how the zero key ended up doing nothing.
--
--  RegisterKeyMapping sidesteps the whole problem: it binds by the
--  key's actual name, so '0' is the 0 key on every build, and the
--  player can rebind it in FiveM's own settings if they want.
--
--  The control IDs in config stay as a second path, for anyone whose
--  keybinds are already set up that way. Both routes land in the same
--  place and a guard below drops the duplicate.
-- ═══════════════════════════════════════════════════════════
local pressKeyRef

for digit = 0, 9 do
  local name = tostring(digit)
  RegisterCommand('nzatm_' .. name, function()
    if pressKeyRef then pressKeyRef(name) end
  end, false)
  RegisterKeyMapping('nzatm_' .. name, 'ATM keypad · ' .. name, 'keyboard', name)
end

RegisterCommand('nzatm_del', function() if pressKeyRef then pressKeyRef('del') end end, false)
RegisterKeyMapping('nzatm_del', 'ATM keypad · delete', 'keyboard', 'BACK')

RegisterCommand('nzatm_enter', function() if pressKeyRef then pressKeyRef('enter') end end, false)
RegisterKeyMapping('nzatm_enter', 'ATM keypad · enter', 'keyboard', 'RETURN')

-- ═══════════════════════════════════════════════════════════
--  ASKING THE SERVER
-- ═══════════════════════════════════════════════════════════
--- A callback that dies server-side leaves lib.callback.await pending
--- for good, which on screen is a spinner that never finishes. This
--- turns that into a decline the player can read.
local function ask(name, ...)
  local args = table.pack(...)
  local done, result = false, nil

  CreateThread(function()
    result = lib.callback.await(name, false, table.unpack(args, 1, args.n))
    done = true
  end)

  local waited = 0
  local limit = (Config.ATM.timeoutSeconds or 10) * 1000

  while not done and waited < limit do
    Wait(50)
    waited = waited + 50
  end

  if not done then
    print(('^1[nayzeee-banking]^7 %s did not answer in %ds — the server console should say why.')
      :format(name, limit / 1000))
    return nil
  end

  return result
end

-- ═══════════════════════════════════════════════════════════
--  SETUP
-- ═══════════════════════════════════════════════════════════
local function modelConfig(model)
  local s = Config.ATM.screen
  local per = s.models and s.models[model]

  local merged = {}
  for k, v in pairs(s) do merged[k] = v end
  if per then for k, v in pairs(per) do merged[k] = v end end
  return merged
end

local function buttonsFor(model)
  local b = Config.ATM.buttons or {}
  return (b.models and b.models[model]) or b.default or {}
end

local function createDui()
  if DUI.obj then return true end

  local s = Config.ATM.screen
  local resource = GetCurrentResourceName()
  local url = ('nui://%s/web/atm.html?resource=%s'):format(resource, resource)

  DUI.obj = CreateDui(url, s.width or 1024, s.height or 820)
  if not DUI.obj then return false end

  local handle = GetDuiHandle(DUI.obj)
  if not handle then
    DestroyDui(DUI.obj)
    DUI.obj = nil
    return false
  end

  DUI.txd = CreateRuntimeTxd(TXD_NAME)

  -- the dictionary needs a moment before a texture can be built from
  -- the browser handle, or it comes out empty
  Wait(250)
  CreateRuntimeTextureFromDuiHandle(DUI.txd, TEX_NAME, handle)

  Wait(400)
  return true
end

local function replaceScreen(cfg)
  if not DUI.obj or cfg.mode == 'draw' then return false end

  for _, r in ipairs(DUI.replaced) do
    RemoveReplaceTexture(r.dict, r.tex)
  end
  DUI.replaced = {}

  local name, tex = cfg.modelName, cfg.screenTexture
  if not name or not tex then
    print('^3[nayzeee-banking]^7 this ATM model has no screenTexture in ' ..
          'Config.ATM.screen.models — set its mode to \'draw\', or add the texture name.')
    return false
  end

  local dicts = { name }
  if cfg.lodVariants then
    dicts[#dicts + 1] = 'prop_atm'
    dicts[#dicts + 1] = name .. '+hidr'
    dicts[#dicts + 1] = name .. '+hifr'
  end

  local seen = {}
  for _, dict in ipairs(dicts) do
    if not seen[dict] then
      seen[dict] = true
      AddReplaceTexture(dict, tex, TXD_NAME, TEX_NAME)
      DUI.replaced[#DUI.replaced + 1] = { dict = dict, tex = tex }
    end
  end

  Bank.debug(('ATM screen: %s/%s across %d dictionaries'):format(name, tex, #DUI.replaced))
  return true
end

local function destroyDui()
  for _, r in ipairs(DUI.replaced) do
    RemoveReplaceTexture(r.dict, r.tex)
  end
  DUI.replaced = {}

  if DUI.obj then DestroyDui(DUI.obj) end
  DUI.obj, DUI.txd = nil, nil
end

local function send(payload)
  if not DUI.obj then return end
  SendDuiMessage(DUI.obj, json.encode(payload))
end

local function alive()
  return DUI.active and DUI.entity and DoesEntityExist(DUI.entity)
end

-- ═══════════════════════════════════════════════════════════
--  GEOMETRY
-- ═══════════════════════════════════════════════════════════
local DEFAULT_AIM = vec3(0.0, -0.104, 1.018)

local function spriteSize(cfg)
  local w = cfg.size or 0.247
  local duiAspect = (cfg.width or 1024) / (cfg.height or 820)
  return w, w * GetAspectRatio(false) / duiAspect
end

--- Work out every button's world position once, rather than asking
--- the engine twenty times a frame for points that are not moving.
local function cacheButtons(entity, model)
  DUI.buttons = {}
  if not Config.ATM.buttons or not Config.ATM.buttons.enabled then return end

  for id, off in pairs(buttonsFor(model)) do
    DUI.buttons[#DUI.buttons + 1] = {
      id  = id,
      pos = GetOffsetFromEntityInWorldCoords(entity, off.x, off.y, off.z)
    }
  end
end

--- Which button is nearest the middle of the view, if any is close
--- enough. The horizontal distance is scaled by the aspect ratio so
--- the area you have to hit is a circle rather than a wide ellipse
--- that changes shape on an ultrawide monitor.
local function buttonUnderCrosshair()
  local best, bestDist = nil, (Config.ATM.buttons.proximity or 0.030)
  local aspect = GetAspectRatio(false)

  for _, b in ipairs(DUI.buttons) do
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(b.pos.x, b.pos.y, b.pos.z)
    if onScreen then
      local dx = (sx - 0.5) * aspect
      local dy = sy - 0.5
      local dist = math.sqrt(dx * dx + dy * dy)

      if dist < bestDist then
        best, bestDist = b, dist
      end
    end
  end

  return best
end

-- ═══════════════════════════════════════════════════════════
--  CAMERA
-- ═══════════════════════════════════════════════════════════
local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end

--- A camera rotation as a unit direction. Not a native — GTA gives
--- you Euler angles and expects you to do this yourself.
local function rotationToDirection(rot)
  local z = math.rad(rot.z)
  local x = math.rad(rot.x)
  local flat = math.abs(math.cos(x))
  return vec3(-math.sin(z) * flat, math.cos(z) * flat, math.sin(x))
end

local function startScene(entity, cfg)
  local ped = PlayerPedId()
  local pedZ = GetEntityCoords(ped).z

  local rad = math.rad(cfg.headingOffset or 0.0)
  local dist = cfg.playerDist or 0.7
  local stand = GetOffsetFromEntityInWorldCoords(entity,
    math.sin(rad) * dist, -math.cos(rad) * dist, 0.0)

  SetEntityCoordsNoOffset(ped, stand.x, stand.y, pedZ, false, false, false)
  TaskTurnPedToFaceEntity(ped, entity, 500)
  Wait(450)
  if not DoesEntityExist(entity) then return false end
  FreezeEntityPosition(ped, true)

  local a = cfg.aim or DEFAULT_AIM
  local c = cfg.camera or {}

  local side, back, up = c.side or 0.0, c.back or 0.85, c.up or 0.22
  local eye = GetOffsetFromEntityInWorldCoords(entity, a.x + side, a.y - back, a.z + up)

  -- Where the camera starts is worked out from where it is standing,
  -- not set by hand. Point it at the machine's face, a little below
  -- the middle of the glass so the keypad is in frame from the start.
  --
  -- Setting the angle by hand is how the screen ended up sitting low
  -- and off to one side: move the camera and the hand-set angle is
  -- wrong again. This cannot drift.
  local tilt = c.tilt or -0.06
  local dx, dy, dz = -side, back, tilt - up
  local horizontal = math.sqrt(dx * dx + dy * dy)

  DUI.base = {
    pitch = math.deg(math.atan(dz, horizontal)),
    yaw   = GetEntityHeading(entity) + math.deg(math.atan(-dx, dy))
  }
  DUI.look = { pitch = DUI.base.pitch, yaw = DUI.base.yaw }

  DUI.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
    eye.x, eye.y, eye.z, DUI.look.pitch, 0.0, DUI.look.yaw, c.fov or 46.0, false, 0)
  SetCamActive(DUI.cam, true)
  SetFocusEntity(entity)
  RenderScriptCams(true, true, 650, true, true)

  if Config.ATM.hideRadar ~= false then DisplayRadar(false) end
  return true
end

--- Mouse look, clamped so the player can reach the screen and the
--- keypad but never end up staring at the sky.
local function updateLook()
  local c = DUI.cfg.camera or {}
  local sens = c.sensitivity or 4.0

  local dx = GetDisabledControlNormal(0, 1) * sens
  local dy = GetDisabledControlNormal(0, 2) * sens
  if dx == 0.0 and dy == 0.0 then return end

  DUI.look.pitch = clamp(DUI.look.pitch - dy,
    DUI.base.pitch - (c.lookDown or 52.0), DUI.base.pitch + (c.lookUp or 18.0))
  DUI.look.yaw = clamp(DUI.look.yaw - dx,
    DUI.base.yaw - (c.lookSide or 28.0), DUI.base.yaw + (c.lookSide or 28.0))

  SetCamRot(DUI.cam, DUI.look.pitch, 0.0, DUI.look.yaw, 2)
end

local function stopScene()
  FreezeEntityPosition(PlayerPedId(), false)
  ClearFocus()
  if Config.ATM.hideRadar ~= false then DisplayRadar(true) end

  if DUI.cam then
    local cam = DUI.cam
    DUI.cam = nil
    RenderScriptCams(false, true, 650, true, true)
    SetTimeout(700, function()
      if DoesCamExist(cam) then DestroyCam(cam, false) end
    end)
  end
end

-- ═══════════════════════════════════════════════════════════
--  WHAT THE SIDE BUTTONS DO, BY SCREEN
--
--  The same eight buttons mean different things on different
--  screens. Lua owns that map and hands the page labels to print
--  beside them, so the two can never drift apart.
-- ═══════════════════════════════════════════════════════════
local function sidesFor(state)
  if state == 'home' then
    local map = {
      side_l1 = { act = 'withdraw', label = 'Withdraw' },
      side_l2 = { act = 'deposit',  label = 'Deposit'  },
      side_l3 = { act = 'transfer', label = 'Transfer' },
      side_r4 = { act = 'exit',     label = 'Eject card' },
    }
    if Config.Statements and Config.Statements.enabled then
      map.side_l4 = { act = 'statement', label = 'Statement' }
    end
    return map
  end

  if state == 'amount' or state == 'transfer' then
    return {
      side_r3 = { act = 'confirm', label = 'Confirm' },
      side_r4 = { act = 'cancel',  label = 'Cancel'  },
    }
  end

  if state == 'statement' or state == 'done' then
    return { side_r4 = { act = 'cancel', label = 'Back' } }
  end

  if state == 'pin' then
    return { side_r4 = { act = 'exit', label = 'Cancel' } }
  end

  return {}
end

-- ═══════════════════════════════════════════════════════════
--  SCREENS
-- ═══════════════════════════════════════════════════════════
local function showSides()
  send({ action = 'sides', sides = sidesFor(DUI.state) })
end

local function goHome()
  DUI.state = 'home'
  DUI.buffer, DUI.stage, DUI.mode = '', nil, nil

  send({
    action     = 'home',
    balance    = DUI.data.balance or 0,
    overdraft  = DUI.data.overdraft,
    cardType   = DUI.card and DUI.card.typeLabel or 'Debit Card',
    cardNumber = DUI.card and DUI.card.number or '',
    serverName = Config.ServerName
  })
  showSides()
end

local function quickFor(mode)
  return mode == 'deposit' and { 500, 1000, 5000 } or { 500, 1000, 5000, 10000 }
end

local function goAmount(mode)
  DUI.state, DUI.mode, DUI.buffer = 'amount', mode, ''

  send({
    action  = 'amount',
    mode    = mode,
    balance = DUI.data.balance or 0,
    cash    = DUI.data.cash or 0,
    amount  = '',
    quick   = quickFor(mode)
  })
  showSides()
end

local function goTransfer()
  DUI.state, DUI.stage, DUI.buffer = 'transfer', 'account', ''
  DUI.payload = { to = '', amount = '' }

  send({ action = 'transfer', stage = 'account', to = '', amount = '' })
  showSides()
end

local function goDone(ok, title, text)
  DUI.state = 'done'
  Bank.atmSound(ok and 'approved' or 'declined')

  send({
    action = 'done', ok = ok, title = title, text = text,
    balance = DUI.data.balance or 0
  })
  showSides()

  SetTimeout(2600, function()
    if DUI.active and DUI.state == 'done' then goHome() end
  end)
end

local function refresh()
  local data = ask('nz_bank:getData', 'atm')
  if not data then return end

  DUI.data.balance = data.summary and data.summary.balance or 0
  DUI.data.cash = data.player and data.player.cash or 0
  DUI.data.primary = data.primary
  DUI.data.overdraft = data.overdraft
end

-- ═══════════════════════════════════════════════════════════
--  ACTIONS
-- ═══════════════════════════════════════════════════════════
local printStatement

local function runAction(act)
  if DUI.busy or not act then return end

  if act == 'exit' then DUI.active = false return end

  if DUI.state == 'home' then
    if act == 'withdraw' or act == 'deposit' then return goAmount(act) end
    if act == 'transfer' then return goTransfer() end
    if act == 'statement' then return printStatement() end
    return
  end

  if DUI.state == 'statement' or DUI.state == 'done' then
    return goHome()
  end

  if act == 'cancel' then return goHome() end
  if act ~= 'confirm' then return end

  if DUI.state == 'amount' then
    local amount = tonumber(DUI.buffer)
    if not amount or amount <= 0 then
      return goDone(false, 'Declined', 'Enter an amount above zero.')
    end

    DUI.busy = true
    local depositing = DUI.mode == 'deposit'
    send({ action = 'busy', text = depositing and 'Counting cash' or 'Dispensing cash' })
    Bank.atmSound('cash')

    local res = depositing
      and ask('nz_bank:deposit', DUI.data.primary, amount)
      or  ask('nz_bank:withdraw', DUI.data.primary, amount, true)

    refresh()
    DUI.busy = false

    if res and res.ok and alive() then
      Bank.atmCashProp(DUI.entity, DUI.model, depositing and 'in' or 'out')
    end

    if not res then
      return goDone(false, 'Declined', 'The bank did not answer. Try again in a moment.')
    end
    return goDone(res.ok, res.ok and 'Approved' or 'Declined', res.msg or '')
  end

  if DUI.state == 'transfer' then
    if DUI.stage == 'account' then
      if DUI.buffer == '' then return end
      DUI.payload.to = DUI.buffer
      DUI.stage, DUI.buffer = 'amount', ''
      return send({ action = 'transfer', stage = 'amount', to = DUI.payload.to, amount = '' })
    end

    local amount = tonumber(DUI.buffer)
    if not amount or amount <= 0 then
      return goDone(false, 'Declined', 'Enter an amount above zero.')
    end

    DUI.busy = true
    send({ action = 'busy', text = 'Sending' })

    local res = ask('nz_bank:transfer', DUI.data.primary, DUI.payload.to, amount, 'ATM transfer')

    refresh()
    DUI.busy = false

    if not res then
      return goDone(false, 'Declined', 'The bank did not answer. Try again in a moment.')
    end
    return goDone(res.ok, res.ok and 'Sent' or 'Declined', res.msg or '')
  end
end

printStatement = function()
  if DUI.busy then return end

  DUI.busy = true
  send({ action = 'busy', text = 'Printing' })
  Bank.atmSound('receipt')

  local res = ask('nz_bank:accountStatement',
    DUI.data.primary, Config.Statements and Config.Statements.atmPeriod or 'week')

  DUI.busy = false

  if not res then
    return goDone(false, 'Declined', 'The bank did not answer. Try again in a moment.')
  end
  if not res.ok then
    return goDone(false, 'Declined', res.msg or 'No statement available.')
  end

  if alive() then Bank.atmReceiptProp(DUI.entity, DUI.model) end

  send({ action = 'statement', statement = res.statement })
  DUI.state = 'statement'
  showSides()

  SetTimeout(12000, function()
    if DUI.active and DUI.state == 'statement' then goHome() end
  end)
end

local function pushBuffer()
  if DUI.state == 'amount' then
    send({
      action = 'amount', mode = DUI.mode,
      balance = DUI.data.balance or 0, cash = DUI.data.cash or 0,
      amount = DUI.buffer, quick = quickFor(DUI.mode)
    })
  elseif DUI.state == 'transfer' then
    send({
      action = 'transfer', stage = DUI.stage,
      to = DUI.stage == 'amount' and DUI.payload.to or DUI.buffer,
      amount = DUI.stage == 'amount' and DUI.buffer or ''
    })
  end
end

local lastPress = {}

local function pressKey(key)
  if not DUI.active or DUI.busy then return end
  if IsNuiFocused() then return end

  -- The key mapping and the control ID can both land on the same
  -- press. Take the first and drop the echo; 50ms is far quicker
  -- than anyone can tap the same key twice on purpose.
  local now = GetGameTimer()
  if lastPress[key] and now - lastPress[key] < 50 then return end
  lastPress[key] = now

  Bank.atmSound('key')

  if DUI.state == 'pin' then
    if key == 'del' then
      DUI.pin = DUI.pin:sub(1, -2)
      return send({ action = 'pin', length = #DUI.pin })
    end
    if key == 'enter' or #DUI.pin >= 4 then return end

    DUI.pin = DUI.pin .. key
    send({ action = 'pin', length = #DUI.pin })
    if #DUI.pin < 4 then return end

    DUI.busy = true
    local res = ask('nz_bank:verifyPin', DUI.card.id, DUI.pin)
    DUI.busy = false

    if res and res.ok then
      Bank.atmSound('approved')
      refresh()
      return goHome()
    end

    DUI.pin = ''
    Bank.atmSound('declined')
    send({ action = 'pin', length = 0, error = res and res.msg or 'Wrong PIN' })

    if res and res.msg and res.msg:lower():find('blocked') then
      SetTimeout(1400, function() DUI.active = false end)
    end
    return
  end

  if DUI.state == 'statement' or DUI.state == 'done' then return goHome() end
  if DUI.state ~= 'amount' and DUI.state ~= 'transfer' then return end

  if key == 'del' then
    DUI.buffer = DUI.buffer:sub(1, -2)
  elseif key == 'enter' then
    return runAction('confirm')
  elseif #DUI.buffer < 10 then
    DUI.buffer = DUI.buffer .. key
  end

  pushBuffer()
end

pressKeyRef = pressKey

--- A button on the machine was pushed. Side buttons mean whatever
--- the current screen says they mean; the pad is always the pad.
local function pressButton(id)
  if not id then return end

  local digit = id:match('^pin_(%d)$')
  if digit then return pressKey(digit) end
  if id == 'pin_clear' then return pressKey('del') end
  if id == 'pin_enter' then return pressKey('enter') end

  local side = sidesFor(DUI.state)[id]
  if side then
    Bank.atmSound('key')
    runAction(side.act)
  end
end

-- ═══════════════════════════════════════════════════════════
--  THE SESSION
-- ═══════════════════════════════════════════════════════════
function Bank.useATMScreen(entity, model, card, data)
  -- A session whose machine has gone can leave this set. Clearing it
  -- beats refusing every use from here on.
  if DUI.active and (not DUI.entity or not DoesEntityExist(DUI.entity)) then
    Bank.debug('a previous ATM session was left open without its machine; clearing it')
    DUI.active = false
  end

  if DUI.active then return false end
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if not createDui() then return false end
  if not DoesEntityExist(entity) then return false end

  local cfg = modelConfig(model)

  DUI.active, DUI.entity, DUI.model, DUI.cfg = true, entity, model, cfg
  DUI.card, DUI.hover = card, nil
  DUI.data = {
    balance   = data.summary and data.summary.balance or 0,
    cash      = data.player and data.player.cash or 0,
    primary   = data.primary,
    overdraft = data.overdraft
  }
  DUI.pin, DUI.buffer, DUI.busy = '', '', false
  DUI.state = 'boot'

  send({
    action        = 'init',
    ui            = data.config and data.config.ui,
    serverName    = Config.ServerName,
    currency      = Config.Currency,
    currencyRight = Config.CurrencyRight,
    statements    = Config.Statements and Config.Statements.enabled or false,
    island        = cfg.island,
    outside       = cfg.outside
  })

  replaceScreen(cfg)
  cacheButtons(entity, model)

  if not startScene(entity, cfg) then
    DUI.active = false
    stopScene()
    destroyDui()
    return false
  end

  Bank.atmEnter(entity)
  Bank.atmCardProp(entity, model, 'in')

  Wait(600)
  if not alive() then DUI.active = false end

  if DUI.active then
    local needPin = Config.ATM.requirePin
      and ask('nz_bank:pinRequired', card.id, nil)

    if needPin then
      DUI.state = 'pin'
      send({ action = 'view', view = 'pin' })
      send({ action = 'pin', length = 0 })
      showSides()
    else
      refresh()
      goHome()
    end
  end

  -- ── the loop ──
  CreateThread(function()
    while DUI.active do
      if not DoesEntityExist(DUI.entity) then DUI.active = false break end

      -- ESC reaches the pause menu above the control system, so
      -- disabling the control is not enough. Close it again and take
      -- it as what the player meant: done with the machine.
      --
      -- This has to come first. Letting the menu sit open stops the
      -- session listening, which leaves it running with nobody at it
      -- — and then the next use finds a machine that thinks it is
      -- still busy and drops the player onto the fallback pad.
      if IsPauseMenuActive() then
        SetPauseMenuActive(false)
        DUI.active = false
        break
      end

      -- Everything is read through the Disabled variants, so the game
      -- never acts on any of it — no walking, no shooting, and no
      -- turning the ped underneath a camera that is not following it.
      DisableAllControlActions(0)

      -- A few controls stay live so the player can still reach their
      -- own things — an inventory, a phone — without walking away
      -- from the machine first.
      for _, control in ipairs(Config.ATM.allowControls or {}) do
        EnableControlAction(0, control, true)
      end

      -- While something else owns the screen — an inventory, say — the
      -- machine keeps its picture but stops listening. A click meant
      -- for an inventory slot must not also push a button on the ATM
      -- behind it.
      local busyElsewhere = IsNuiFocused()

      if not busyElsewhere then updateLook() end

      -- ── paint, in draw mode ──
      if DUI.cfg.mode == 'draw' then
        local o = DUI.cfg.aim or DEFAULT_AIM
        local w, h = spriteSize(DUI.cfg)
        local world = GetOffsetFromEntityInWorldCoords(DUI.entity, o.x, o.y, o.z)

        SetDrawOrigin(world.x, world.y, world.z, 0)
        DrawSprite(TXD_NAME, TEX_NAME, 0.0, 0.0, w, h, 0.0, 255, 255, 255, 255)
        ClearDrawOrigin()
      end

      -- ── what am I looking at ──
      local found = not busyElsewhere and buttonUnderCrosshair() or nil
      local id = found and found.id or nil

      if id ~= DUI.hover then
        DUI.hover = id
        send({ action = 'hover', button = id })
      end


      -- the crosshair, small enough to aim with and not notice
      if not busyElsewhere then
        DrawRect(0.5, 0.5, 0.0022, 0.0039, 255, 255, 255, id and 40 or 170)
      end

      -- ── input ──
      if not busyElsewhere then
        if IsDisabledControlJustPressed(0, KEYS.press or 24) then
          pressButton(DUI.hover)
        end

        for digit, control in pairs(KEYS.digits or {}) do
          if IsDisabledControlJustPressed(0, control) then pressKey(digit) end
        end
        for digit, control in pairs(KEYS.alternate or {}) do
          if IsDisabledControlJustPressed(0, control) then pressKey(digit) end
        end

        if KEYS.backspace and IsDisabledControlJustPressed(0, KEYS.backspace) then
          pressKey('del')
        end
        if KEYS.enter and IsDisabledControlJustPressed(0, KEYS.enter) then
          pressKey('enter')
        end
        if KEYS.cancel and IsDisabledControlJustPressed(0, KEYS.cancel) then
          DUI.active = false
        end
      end

      Wait(0)
    end

    if DUI.entity and DoesEntityExist(DUI.entity) then
      Bank.atmCardProp(DUI.entity, DUI.model, 'out')
    end

    stopScene()
    Bank.atmExit()
    destroyDui()

    DUI.entity, DUI.model, DUI.card, DUI.payload, DUI.cfg = nil, nil, nil, nil, nil
    DUI.buttons, DUI.hover = {}, nil
    ask('nz_bank:atmEnd')
  end)

  return true
end

function Bank.screenActive() return DUI.active end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  DUI.active = false
  stopScene()
  destroyDui()
  DisplayRadar(true)
end)

-- ═══════════════════════════════════════════════════════════
--  CALIBRATION
--
--  Every one of these needs Config.Debug = true.
-- ═══════════════════════════════════════════════════════════
if not Config.Debug then return end

local function nearestATM()
  local pos = GetEntityCoords(PlayerPedId())
  for _, m in ipairs(Config.ATMModels) do
    local found = GetClosestObjectOfType(pos.x, pos.y, pos.z, 4.0, m, false, false, false)
    if found ~= 0 and DoesEntityExist(found) then return found end
  end
end

-- ── /atmkeys — what control is this key? ──────────────────
local finding = false
RegisterCommand('atmkeys', function()
  finding = not finding
  Bank.notify('Key finder', finding
    and 'Press a key — the console prints its control ID. Run it again to stop.'
    or 'Key finder off', 'inform')
  if not finding then return end

  CreateThread(function()
    while finding do
      for control = 0, 360 do
        if IsControlJustPressed(0, control) then
          print(('^5[atmkeys]^7 control ^3%d^7'):format(control))
        end
      end
      Wait(0)
    end
  end)
end, false)

-- ── /atmbuttons — record where each button really is ──────
--
-- Stand at a machine, look at a button, press ENTER. It writes down
-- the point you were looking at, moves to the next button, and
-- prints a block to paste when it has them all.
local ORDER = {
  'side_l1','side_l2','side_l3','side_l4',
  'side_r1','side_r2','side_r3','side_r4',
  'pin_1','pin_2','pin_3','pin_4','pin_5','pin_6',
  'pin_7','pin_8','pin_9','pin_clear','pin_0','pin_enter'
}

RegisterCommand('atmbuttons', function()
  local atm = nearestATM()
  if not atm then
    return Bank.notify('Calibration', 'Stand closer to an ATM.', 'error')
  end

  local model = GetEntityModel(atm)
  local cfg = modelConfig(model)
  local found, index = {}, 1

  Bank.notify('Calibration',
    'Look at each button and press ENTER. BACKSPACE goes back, ESC prints what you have.', 'inform')

  CreateThread(function()
    local a = cfg.aim or DEFAULT_AIM
    local c = cfg.camera or {}

    local side, back, up = c.side or 0.0, c.back or 0.85, c.up or 0.22
    local eye = GetOffsetFromEntityInWorldCoords(atm, a.x + side, a.y - back, a.z + up)

    local tilt = c.tilt or -0.06
    local dx, dy, dz = -side, back, tilt - up
    local horizontal = math.sqrt(dx * dx + dy * dy)

    local base = {
      pitch = math.deg(math.atan(dz, horizontal)),
      yaw   = GetEntityHeading(atm) + math.deg(math.atan(-dx, dy))
    }
    local look = { pitch = base.pitch, yaw = base.yaw }

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
      eye.x, eye.y, eye.z, look.pitch, 0.0, look.yaw, c.fov or 46.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    FreezeEntityPosition(PlayerPedId(), true)

    local function report()
      print('^3[atmbuttons]^7 ' .. tostring(cfg.modelName or model) .. ' —')
      for _, id in ipairs(ORDER) do
        local v = found[id]
        if v then
          print(('    %-9s = vec3(%+.3f, %+.3f, %.3f),'):format(id, v.x, v.y, v.z))
        end
      end
    end

    while index <= #ORDER do
      DisableAllControlActions(0)

      local sens = c.sensitivity or 4.0
      look.pitch = clamp(look.pitch - GetDisabledControlNormal(0, 2) * sens,
        base.pitch - (c.lookDown or 52.0), base.pitch + (c.lookUp or 18.0))
      look.yaw = clamp(look.yaw - GetDisabledControlNormal(0, 1) * sens,
        base.yaw - (c.lookSide or 28.0), base.yaw + (c.lookSide or 28.0))
      SetCamRot(cam, look.pitch, 0.0, look.yaw, 2)

      DrawRect(0.5, 0.5, 0.0022, 0.0039, 8, 175, 162, 220)

      -- everything recorded so far, so you can see the shape forming
      for _, v in pairs(found) do
        local w = GetOffsetFromEntityInWorldCoords(atm, v.x, v.y, v.z)
        DrawMarker(28, w.x, w.y, w.z, 0,0,0, 0,0,0, 0.012, 0.012, 0.012,
          8, 175, 162, 160, false, false, 2, nil, nil, false)
      end

      BeginTextCommandDisplayHelp('STRING')
      AddTextComponentSubstringPlayerName(
        ('Look at ~g~%s~s~ and press ENTER    (%d of %d)'):format(ORDER[index], index, #ORDER))
      EndTextCommandDisplayHelp(0, false, true, -1)

      if IsDisabledControlJustPressed(0, 191) then
        -- A ray from the camera through the middle of the view, out to
        -- where it meets the machine. That is the point being aimed at.
        local dir = rotationToDirection(GetCamRot(cam, 2))
        local from = GetCamCoord(cam)
        local to = vec3(from.x + dir.x * 3.0, from.y + dir.y * 3.0, from.z + dir.z * 3.0)

        local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 16, atm, 0)
        local _, hit, coords = GetShapeTestResult(ray)

        if hit == 1 then
          found[ORDER[index]] = GetOffsetFromEntityGivenWorldCoords(atm, coords.x, coords.y, coords.z)
          index = index + 1
        else
          Bank.notify('Calibration', 'Nothing under the crosshair — aim at the machine.', 'error')
        end
      end

      if IsDisabledControlJustPressed(0, 194) and index > 1 then
        index = index - 1
        found[ORDER[index]] = nil
      end

      if IsDisabledControlJustPressed(0, 200) then break end

      Wait(0)
    end

    RenderScriptCams(false, true, 400, true, true)
    SetTimeout(500, function() if DoesCamExist(cam) then DestroyCam(cam, false) end end)
    FreezeEntityPosition(PlayerPedId(), false)

    report()
    Bank.notify('Calibration', 'Printed to the console — paste it into Config.ATM.buttons.', 'success')
  end)
end, false)

-- ── /atmuv — sit the page inside the screen's patch ───────
local uv = { on = false, edge = 'pos', step = 0.005 }

RegisterCommand('atmuv', function()
  uv.on = not uv.on
  Bank.notify('Screen mapping', uv.on
    and 'Arrows move · TAB size/position · [ ] step · ENTER print'
    or 'Off', 'inform')
  if not uv.on then return end

  CreateThread(function()
    while uv.on do
      local atm = DUI.entity or nearestATM()
      if atm then
        local model = DUI.model or GetEntityModel(atm)
        local per = Config.ATM.screen.models[model]
        local target = (per and per.island) or Config.ATM.screen.island
        if per and not per.island then per.island = { x=0, y=0, w=1, h=1 }; target = per.island end

        local function nudge(dx, dy)
          if uv.edge == 'pos' then
            target.x = target.x + dx; target.y = target.y + dy
          else
            target.w = math.max(0.02, target.w + dx); target.h = math.max(0.02, target.h + dy)
          end
          send({ action = 'island', island = target })
        end

        if IsControlJustPressed(0, 174) then nudge(-uv.step, 0) end
        if IsControlJustPressed(0, 175) then nudge( uv.step, 0) end
        if IsControlJustPressed(0, 172) then nudge(0, -uv.step) end
        if IsControlJustPressed(0, 173) then nudge(0,  uv.step) end
        if IsControlJustPressed(0, 37)  then uv.edge = uv.edge == 'pos' and 'size' or 'pos' end
        if IsControlJustPressed(0, 39)  then uv.step = 0.001 end
        if IsControlJustPressed(0, 40)  then uv.step = 0.005 end

        if IsControlJustPressed(0, 191) then
          print(('^3[atmuv]^7 island = { x = %.3f, y = %.3f, w = %.3f, h = %.3f }')
            :format(target.x, target.y, target.w, target.h))
        end

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(
          ('Editing ~g~%s~s~   x %.3f  y %.3f  w %.3f  h %.3f   step %.3f')
          :format(uv.edge, target.x, target.y, target.w, target.h, uv.step))
        EndTextCommandDisplayHelp(0, false, true, -1)
      end

      Wait(0)
    end
  end)
end, false)
