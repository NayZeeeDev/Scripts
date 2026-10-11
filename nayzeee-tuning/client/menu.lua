--[[
    Tuning menu controller. Owns the cart, the live preview and the numbers the UI shows.
    Prices shown here are for display; the server re-prices everything at checkout.
]]

Menu = { open = false }

local S            -- session from the server (see server/checkout.lua 'open')
local veh          -- vehicle being tuned
local original     -- framework props before the menu opened
local origExtras   -- custom data before the menu opened
local cart = {}    -- [itemId] = value
local order = {}   -- item ids in the order they were added
local hist, histIdx = {}, 0
local codePct, code = 0, nil
local lightsOn, doorsOpen = false, false
local openDoors = {}
local testDriving = false
local frozeIt = false
local installed = {} -- [itemId] = value on the car when the menu opened (never re-read: the car shows previews)
local mode         -- 'order' | 'self' (customer choice at staffed shops)

local LEVEL_NAMES = {
    [11] = { 'Stage 1', 'Stage 2', 'Stage 3', 'Stage 4', 'Stage 5', 'Stage 6' },
    [12] = { 'Street', 'Sport', 'Race', 'Competition', 'Pro' },
    [13] = { 'Street', 'Sport', 'Race', 'Competition', 'Pro' },
    [15] = { 'Lowered', 'Street', 'Sport', 'Competition', 'Pro', 'Pro+' },
    [16] = { 'Armor 20%', 'Armor 40%', 'Armor 60%', 'Armor 80%', 'Armor 100%', 'Armor 120%' },
}

--------------------------------------------------------------------- helpers

local function isBike() return GetVehicleClass(veh) == 8 end

local function currentExtras()
    local ex = NZ.Copy(origExtras)
    for _, id in ipairs(order) do
        if cart[id] ~= nil then NZ.ApplyToExtras(ex, id, cart[id]) end
    end
    return ex
end

local function inst(id)
    local v = installed[id]
    if v == nil then
        v = Apply.Current(veh, id, origExtras)
        installed[id] = v
    end
    return v
end

local function valueOf(id)
    if cart[id] ~= nil then return cart[id] end
    return inst(id)
end

local function priceOf(id, value)
    if not S.showPrices then return nil end
    if S.role == 'admin' then return 0 end
    local p = NZ.ItemPrice(id, value, S.vehPrice, { extras = origExtras, wear = origExtras.wear })
    if not p then return nil end
    if S.margin and S.margin ~= 0 then p = math.floor(p * (1 + S.margin / 100) + 0.5) end
    return p
end

local function modLabel(id, slot, i)
    local custom = Config.ModNames[S.model or ''] and Config.ModNames[S.model][slot]
    if custom and custom[i] then return custom[i] end
    if slot == 14 then return Config.HornNames[i] or ('Horn %d'):format(i + 1) end
    if LEVEL_NAMES[slot] then return LEVEL_NAMES[slot][i + 1] or ('Level %d'):format(i + 1) end
    local lbl = GetModTextLabel(veh, slot, i)
    local txt = lbl and lbl ~= '' and GetLabelText(lbl) or 'NULL'
    if txt == 'NULL' or txt == '' then txt = ('%s %d'):format(Config.Parts[id].label, i + 1) end
    return txt
end

local function isArmed(slot, i)
    if not Config.HideArmedMods then return false end
    local lbl = (GetModTextLabel(veh, slot, i) or ''):upper()
    for _, k in ipairs(Config.ArmedModKeywords) do
        if lbl:find(k, 1, true) then return true end
    end
    return false
end

local function modCount(slot)
    SetVehicleModKit(veh, 0)
    local n = GetNumVehicleMods(veh, slot)
    local cap = Config.MaxLevels[S.model or ''] and Config.MaxLevels[S.model][slot]
    if cap then n = math.min(n, cap + 1) end
    return n
end

local function allowed(id)
    if S.role == 'admin' then return true end
    local unlocked
    if S.unlocked then unlocked = {} for _, k in ipairs(S.unlocked) do unlocked[k] = true end end
    return NZ.ShopAllows(S.shop.id, id, GetVehicleClass(veh), unlocked)
end

local wheelCache = {}
local function wheelCount(wtype)
    if wheelCache[wtype] then return wheelCache[wtype][1], wheelCache[wtype][2] end
    local curType, curIdx, var = GetVehicleWheelType(veh), GetVehicleMod(veh, 23), GetVehicleModVariation(veh, 23)
    SetVehicleWheelType(veh, wtype)
    local n = GetNumVehicleMods(veh, 23)
    local labels = {}
    for i = 0, n - 1 do
        local lbl = GetModTextLabel(veh, 23, i)
        local t = lbl and GetLabelText(lbl) or 'NULL'
        labels[i] = (t == 'NULL' or t == '') and ('Rim %d'):format(i + 1) or t
    end
    SetVehicleWheelType(veh, curType)
    SetVehicleMod(veh, 23, curIdx, var)
    wheelCache[wtype] = { n, labels }
    return n, labels
end

local function wheelTypes()
    local out = {}
    for _, wt in ipairs(Config.WheelTypes) do
        local id = wt[1]
        local ok = true
        if isBike() and Config.Ownership.MotorcycleWheelsOnly then ok = id == 6
        elseif not isBike() and id == 6 then ok = false end
        if ok then
            local n = wheelCount(id)
            if n > 0 then out[#out + 1] = { id = id, label = wt[2], icon = wt[3], count = n } end
        end
    end
    return out
end

local stanceClassOk = function()
    return not Config.Stance.BlockedClasses[GetVehicleClass(veh)] and Config.Stance.ModelLimits[S.model or ''] ~= false
end

-- is the item offered for this car at all?
local function available(id)
    local part = Config.Parts[id]
    if not part or not allowed(id) then return false end
    local k, class = part.kind, GetVehicleClass(veh)
    if k == 'mod' then return modCount(part.slot) > 0 end
    if k == 'toggle' then return true end
    if k == 'rearWheels' then return isBike() end
    if k == 'livery' then return GetVehicleLiveryCount(veh) > 0 or modCount(48) > 0 end
    if k == 'roofLivery' then return GetVehicleRoofLiveryCount(veh) > 0 end
    if k == 'extras' then for i = 0, 20 do if DoesExtraExist(veh, i) then return true end end return false end
    if k == 'neon' or k == 'neonPattern' then return class ~= 8 and class ~= 13 end
    if k == 'stance' or k == 'height' or k == 'airride' then return stanceClassOk() end
    if k == 'swap' then return #(S.swaps or {}) > 0 end
    if k == 'drift' then return GetGameBuildNumber() >= 2372 and class ~= 8 end
    if k == 'service' then return origExtras.wear ~= nil end
    if k == 'wheels' or k == 'tyres' then return class ~= 13 end
    if k == 'drivetrain' then return not Config.Drivetrain.BlockedClasses[class] end
    if k == 'driftKit' or k == 'gearbox' then return class ~= 8 and class ~= 13 end
    if k == 'sound' then return #Config.SoundPacks.List > 0 end
    return true
end

--------------------------------------------------------------------- stats

local function wearFx(ex)
    local fx = {}
    for part, e in pairs(Config.Wear.Effects) do
        local cond = ex.wear and ex.wear[part] or 100
        fx[part] = cond < e.at and (e.floor + (1 - e.floor) * (cond / e.at)) or 1.0
    end
    return fx
end

local function computeStats(get, ex)
    local model = GetEntityModel(veh)
    local top = GetVehicleModelEstimatedMaxSpeed(model)
    local acc = GetVehicleModelAcceleration(model)
    local brk = GetVehicleModelMaxBraking(model)
    local tra = GetVehicleModelMaxTraction(model)
    local lv = function(id) local v = get(id) return (type(v) == 'number' and v or -1) + 1 end

    acc = acc * (1 + 0.055 * lv('mod_11')) * (get('mod_18') == true and 1.08 or 1) * (1 + 0.03 * lv('mod_13'))
    top = top * (1 + 0.012 * lv('mod_11'))
    brk = brk * (1 + 0.08 * lv('mod_12'))
    tra = tra * (1 + 0.02 * lv('mod_15'))

    local ecu = ex.ecu or {}
    acc = acc * (1 + (ecu.power or 0) / 100 - (ecu.gearing or 0) / 200)
    top = top * (1 + (ecu.power or 0) / 200 + (ecu.gearing or 0) / 100)
    brk = brk * (1 + (ecu.brake or 0) / 100)
    tra = tra * (1 + (ecu.grip or 0) / 100)
    local sw = ex.swap and NZ.SwapBySound[ex.swap]
    if sw then acc = acc * sw.power top = top * (1 + (sw.power - 1) / 2) end
    if ex.drift then tra = tra * 0.78 end
    local fx = wearFx(ex)
    acc, brk, tra = acc * fx.engine * fx.turbo, brk * fx.brakes, tra * fx.tyres

    local mph = top * 2.236936
    local mass = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fMass')
    local z60 = math.max(1.8, 1.524 / math.max(acc, 0.05) - 1.119)
    return {
        top = NZ.Round(mph, 0), zero60 = NZ.Round(z60, 2), hp = math.floor(acc * mass * 0.9),
        bars = {
            speed = NZ.Clamp((mph - 60) / 170, 0, 1), accel = NZ.Clamp(acc / 0.55, 0, 1),
            brake = NZ.Clamp(brk / 1.6, 0, 1), grip = NZ.Clamp(tra / 3.4, 0, 1),
        },
        nitrous = ex.nitrous and ex.nitrous.level or 0,
    }
end

local function stats()
    local base = computeStats(inst, origExtras)
    local ex = currentExtras()
    local prev = computeStats(valueOf, ex)
    local wear = origExtras.wear
    return { base = base, preview = prev, wear = wear, km = origExtras.km }
end

--------------------------------------------------------------------- cart

local function snapshot()
    local s = json.encode({ cart = cart, order = order })
    if hist[histIdx] == s then return end
    for i = #hist, histIdx + 1, -1 do hist[i] = nil end
    hist[#hist + 1] = s
    histIdx = #hist
    if #hist > 60 then table.remove(hist, 1) histIdx = #hist end
end

local function describeValue(id, v)
    local part = Config.Parts[id]
    local k = part.kind
    if k == 'mod' then return v == -1 and 'Stock' or modLabel(id, part.slot, v) end
    if type(v) == 'boolean' then return v and 'Install' or 'Remove' end
    if k == 'nitrous' then
        if v == 'refill' then return 'Refill' end
        return v == 0 and 'Remove' or (Config.Nitrous.Levels[v] or {}).label
    end
    if k == 'swap' then return v and NZ.SwapBySound[v] and NZ.SwapBySound[v].label or 'Factory engine' end
    if k == 'wheels' then
        if v.index == -1 then return 'Stock rims' end
        local _, labels = wheelCount(v.type)
        return labels[v.index] or ('Rim %d'):format(v.index + 1)
    end
    if k == 'color' or k == 'xenonColor' then
        if v.mode == 'rgb' then return ('#%02X%02X%02X'):format(v.r, v.g, v.b) end
        for _, g in ipairs(Config.Paints) do for _, c in ipairs(g.colors) do if c[1] == v.index then return g.label .. ' ' .. c[2] end end end
        for _, c in ipairs(Config.XenonColors) do if c[1] == v.index then return c[2] end end
        return 'Colour ' .. tostring(v.index)
    end
    if k == 'tint' then for _, t in ipairs(Config.WindowTints) do if t[1] == v then return t[2] end end end
    if k == 'plateIndex' then for _, t in ipairs(Config.PlateStyles) do if t[1] == v then return t[2] end end end
    if k == 'plateText' then return v end
    if k == 'neonPattern' then for _, p in ipairs(Config.NeonPatterns) do if p[1] == v.id then return p[2] end end end
    if k == 'height' then return v == 0 and 'Stock' or ('%s%d mm'):format(v > 0 and '-' or '+', math.floor(math.abs(v) * 1000 + 0.5)) end
    if k == 'stance' then return ('%+d / %+d mm, %.1f° / %.1f°'):format(math.floor((v.oF or 0) * 1000), math.floor((v.oR or 0) * 1000), v.cF or 0, v.cR or 0) end
    if k == 'ecu' then return v and 'Programmable ECU' or 'Factory ECU' end
    if k == 'livery' or k == 'roofLivery' then return v == -1 and 'None' or ('Style %d'):format(v + 1) end
    if k == 'tyres' then return (NZ.TyreById[v] or {}).label end
    if k == 'drivetrain' then return (NZ.DriveById[v] or {}).label end
    if k == 'gearbox' then return v == 'manual' and 'Manual (H-pattern)' or 'Automatic' end
    if k == 'sound' then return v and (NZ.SoundByAudio[v] or {}).label or 'Factory note' end
    return nil
end

local function lines()
    local out, raw = {}, {}
    for _, id in ipairs(order) do
        local v = cart[id]
        if v ~= nil then
            local p = S.role == 'admin' and 0 or (NZ.ItemPrice(id, v, S.vehPrice, { extras = origExtras, wear = origExtras.wear }) or 0)
            raw[#raw + 1] = { id = id, price = p }
            out[#out + 1] = { id = id, label = Config.Parts[id].label, icon = Config.Parts[id].icon, desc = describeValue(id, v),
                price = S.showPrices and math.floor(p * (1 + (S.margin or 0) / 100) + 0.5) or nil, value = v }
        end
    end
    local surcharge = 0
    if mode == 'self' and NZ.InList(S.modes or {}, 'order') then surcharge = S.surcharge or 0 end
    local totals = S.role == 'admin' and { subtotal = 0, labour = 0, discount = 0, tax = 0, total = 0 }
        or NZ.Totals(raw, codePct, S.margin, { labour = S.labour, surcharge = surcharge })
    if not S.showPrices then totals = nil end
    return out, totals
end

local function cartState()
    local l, t = lines()
    return { lines = l, totals = t, stats = stats(), canUndo = histIdx > 1, canRedo = histIdx < #hist, code = code, codePct = codePct,
        mode = mode, count = #l }
end

-- rebuild the whole preview from original + cart (undo, builds, compare off)
local function reapply()
    Bridge.SetProps(veh, original)
    for _, id in ipairs(order) do
        if cart[id] ~= nil and not NZ.ExtrasKinds[Config.Parts[id].kind] then Apply.Item(veh, id, cart[id]) end
    end
    Apply.SetPreview(veh, currentExtras())
end

local same = NZ.Equal

local function setCart(id, value)
    local installed = inst(id)
    local kind = Config.Parts[id].kind
    local actionable = kind == 'repair' or kind == 'clean' or kind == 'service' or (kind == 'nitrous' and value == 'refill')
    if value == nil or (not actionable and same(value, installed)) then
        cart[id] = nil
        for i, x in ipairs(order) do if x == id then table.remove(order, i) break end end
        if not NZ.ExtrasKinds[kind] and installed ~= nil and kind ~= 'repair' and kind ~= 'clean' then Apply.Item(veh, id, installed) end
    else
        if cart[id] == nil then order[#order + 1] = id end
        cart[id] = value
        if not NZ.ExtrasKinds[kind] then Apply.Item(veh, id, value) end
    end
    Apply.SetPreview(veh, currentExtras())
    snapshot()
end

--------------------------------------------------------------------- item details for the UI

local function optionList(id)
    local part = Config.Parts[id]
    local k = part.kind
    local cur = valueOf(id)
    local d = { id = id, kind = k, label = part.label, icon = part.icon, value = cur, installed = inst(id), cam = part.cam,
        category = NZ.CategoryOf[id] }

    if k == 'mod' then
        local opts = { { value = -1, label = 'Stock', price = priceOf(id, -1) } }
        for i = 0, modCount(part.slot) - 1 do
            if not isArmed(part.slot, i) then
                opts[#opts + 1] = { value = i, label = modLabel(id, part.slot, i), price = priceOf(id, i) }
            end
        end
        d.options = opts
        d.horn = part.slot == 14
    elseif k == 'ecu' then
        d.options = {
            { value = false, label = 'Factory ECU', price = priceOf(id, false), desc = 'Sealed. No calibration possible.' },
            { value = true, label = 'Programmable ECU', price = priceOf(id, true), desc = 'Calibrated by a mechanic on the tuning tablet (ECU Studio).' },
        }
    elseif k == 'toggle' or k == 'customTires' or k == 'drift' or k == 'bulletproof' or k == 'antilag'
        or k == 'launch' or k == 'airride' or k == 'locator' then
        d.options = { { value = false, label = 'None', price = priceOf(id, false) }, { value = true, label = 'Installed', price = priceOf(id, true) } }
        if k == 'airride' then d.presets = Config.AirRide.Presets end
    elseif k == 'color' then
        d.target = part.target
        d.prices = { index = priceOf(id, { mode = 'index', index = 0 }), rgb = priceOf(id, { mode = 'rgb', r = 0, g = 0, b = 0, finish = 0 }),
            chameleon = Config.ChameleonPaints.Enabled and priceOf(id, { mode = 'index', index = 161 }) or nil }
        d.rgb = part.target == 'primary' or part.target == 'secondary'
    elseif k == 'wheels' then
        d.types = wheelTypes()
        d.price = priceOf(id, { type = 0, index = 0 })
        d.stockPrice = priceOf(id, { type = 0, index = -1 })
    elseif k == 'rearWheels' then
        local n, labels = GetNumVehicleMods(veh, 24), {}
        local opts = { { value = -1, label = 'Stock', price = priceOf(id, -1) } }
        for i = 0, n - 1 do opts[#opts + 1] = { value = i, label = labels[i] or ('Rim %d'):format(i + 1), price = priceOf(id, i) } end
        d.options = opts
    elseif k == 'smoke' then
        d.presets = Config.SmokePresets
        d.price = priceOf(id, { r = 0, g = 0, b = 0 })
    elseif k == 'wheelSize' or k == 'wheelWidth' then
        local c = k == 'wheelSize' and Config.WheelDimensions.Size or Config.WheelDimensions.Width
        d.slider = { min = c.min, max = c.max, step = c.step }
        d.price = priceOf(id, c.min)
        d.disabled = GetVehicleMod(veh, 23) == -1 and L('need_custom_rims') or nil
    elseif k == 'stance' then
        local lim = Config.Stance.ModelLimits[S.model or ''] or {}
        d.offset = lim.Offset or Config.Stance.Offset
        d.camber = lim.Camber or Config.Stance.Camber
        d.price = priceOf(id, { oF = 0, oR = 0, cF = 0, cR = 0 })
    elseif k == 'height' then
        d.slider = { min = Config.RideHeight.min, max = Config.RideHeight.max, step = Config.RideHeight.step }
        d.price = priceOf(id, 0.0)
        d.disabled = origExtras.airride and L('airride_overrides') or nil
    elseif k == 'neon' then
        d.presets = Config.NeonPresets
        d.price = priceOf(id, cur)
    elseif k == 'neonPattern' then
        d.patterns = Config.NeonPatterns
        d.price = priceOf(id, { id = 'pulse', speed = 5 })
    elseif k == 'xenonColor' then
        d.colors = Config.XenonColors
        d.rgbAllowed = Config.XenonCustomRGB
        d.prices = { index = priceOf(id, { mode = 'index', index = 0 }), rgb = priceOf(id, { mode = 'rgb', r = 0, g = 0, b = 0 }) }
        d.needsXenon = not IsToggleModOn(veh, 22) and cart.mod_22 ~= true
    elseif k == 'plateText' then
        d.price = priceOf(id, 'AAAA')
        d.min, d.max = Config.Plates.MinLength, Config.Plates.MaxLength
    elseif k == 'plateIndex' then
        d.options = {}
        for _, p in ipairs(Config.PlateStyles) do d.options[#d.options + 1] = { value = p[1], label = p[2], price = priceOf(id, p[1]) } end
    elseif k == 'tint' then
        d.options = {}
        for _, t in ipairs(Config.WindowTints) do d.options[#d.options + 1] = { value = t[1], label = t[2], price = priceOf(id, t[1]) } end
    elseif k == 'extras' then
        d.extras = {}
        for i = 0, 20 do if DoesExtraExist(veh, i) then d.extras[#d.extras + 1] = i end end
        d.price = priceOf(id, {})
    elseif k == 'livery' then
        local opts = {}
        if GetVehicleLiveryCount(veh) > 0 then
            for i = 0, GetVehicleLiveryCount(veh) - 1 do
                local n = GetLabelText(GetLiveryName(veh, i) or '')
                opts[#opts + 1] = { value = i, label = (n ~= 'NULL' and n ~= '') and n or ('Livery %d'):format(i + 1), price = priceOf(id, i) }
            end
        else
            opts[1] = { value = -1, label = 'None', price = priceOf(id, -1) }
            for i = 0, modCount(48) - 1 do opts[#opts + 1] = { value = i, label = modLabel(id, 48, i), price = priceOf(id, i) } end
        end
        d.options = opts
    elseif k == 'roofLivery' then
        local opts = {}
        for i = 0, GetVehicleRoofLiveryCount(veh) - 1 do opts[#opts + 1] = { value = i, label = ('Roof %d'):format(i + 1), price = priceOf(id, i) } end
        d.options = opts
    elseif k == 'nitrous' then
        local opts = { { value = 0, label = 'None', price = priceOf(id, 0) } }
        for i, lvl in ipairs(Config.Nitrous.Levels) do
            opts[#opts + 1] = { value = i, label = lvl.label, desc = ('%d units - %.0f%% boost'):format(lvl.capacity, (lvl.power - 1) * 100), price = priceOf(id, i) }
        end
        if origExtras.nitrous then
            local lvl = Config.Nitrous.Levels[origExtras.nitrous.level] or {}
            opts[#opts + 1] = { value = 'refill', label = 'Refill Bottles', desc = ('%d / %d'):format(math.floor(origExtras.nitrous.amount or 0), lvl.capacity or 100), price = priceOf(id, 'refill') }
        end
        d.options = opts
    elseif k == 'swap' then
        local opts = { { value = false, label = 'Factory Engine', price = priceOf(id, false) } }
        for _, sound in ipairs(S.swaps or {}) do
            local sw = NZ.SwapBySound[sound]
            if sw then opts[#opts + 1] = { value = sound, label = sw.label, desc = sw.power > 1 and ('+%d%% power'):format(math.floor((sw.power - 1) * 100 + 0.5)) or nil, price = priceOf(id, sound) } end
        end
        d.options = opts
    elseif k == 'tyres' then
        d.options = {}
        for _, t in ipairs(Config.Tyres.List) do
            d.options[#d.options + 1] = { value = t.id, label = t.label, price = priceOf(id, t.id),
                desc = ('Grip %+d%%  ·  Off-road %s'):format(math.floor((t.grip - 1) * 100 + 0.5), t.offroad <= 0.6 and 'great' or t.offroad <= 1.0 and 'normal' or 'poor') }
        end
    elseif k == 'drivetrain' then
        d.options = {}
        for _, t in ipairs(Config.Drivetrain.List) do
            d.options[#d.options + 1] = { value = t.id, label = t.label, price = priceOf(id, t.id),
                desc = t.bias and ('%d%% front / %d%% rear'):format(math.floor(t.bias * 100 + 0.5), math.floor((1 - t.bias) * 100 + 0.5)) or 'As the car left the factory' }
        end
    elseif k == 'gearbox' then
        d.options = {
            { value = 'auto', label = 'Automatic', price = priceOf(id, 'auto') },
            { value = 'manual', label = 'Manual (H-pattern)', price = priceOf(id, 'manual'), desc = 'Shift with ↑ / ↓, toggle with K. Money shifts hurt.' },
        }
    elseif k == 'ceramic' or k == 'driftKit' then
        d.options = { { value = false, label = 'None', price = priceOf(id, false) }, { value = true, label = 'Installed', price = priceOf(id, true),
            desc = k == 'ceramic' and ('+%d%% stopping power, half the brake wear'):format(math.floor((Config.CeramicBrakes.BrakeForce - 1) * 100 + 0.5))
                or 'Steering lock, rear-biased power and a loose tail' } }
    elseif k == 'sound' then
        d.options = { { value = false, label = 'Factory Note', price = priceOf(id, false) } }
        for _, sp in ipairs(Config.SoundPacks.List) do d.options[#d.options + 1] = { value = sp.audio, label = sp.label, price = priceOf(id, sp.audio) } end
        d.listen = true
    elseif k == 'repair' or k == 'clean' or k == 'service' then
        d.action = true
        d.price = priceOf(id, true)
        if k == 'repair' then d.health = { engine = math.floor(GetVehicleEngineHealth(veh) / 10), body = math.floor(GetVehicleBodyHealth(veh) / 10) } end
        if k == 'clean' then d.dirt = math.floor(GetVehicleDirtLevel(veh) / 15 * 100) end
        if k == 'service' then d.wear = origExtras.wear end
    end
    return d
end

--------------------------------------------------------------------- open / close

local function categories()
    local out = {}
    for _, cat in ipairs(Config.Categories) do
        local items = {}
        for _, id in ipairs(cat.items) do
            if available(id) then
                local p = Config.Parts[id]
                items[#items + 1] = { id = id, label = p.label, icon = p.icon, kind = p.kind }
            end
        end
        if #items > 0 then out[#out + 1] = { id = cat.id, label = cat.label, icon = cat.icon, items = items } end
    end
    return out
end

local function setDoors(list)
    for _, d in ipairs(openDoors) do SetVehicleDoorShut(veh, d, false) end
    openDoors = {}
    for _, d in ipairs(list or {}) do
        SetVehicleDoorOpen(veh, d, false, false)
        openDoors[#openDoors + 1] = d
    end
end

--------------------------------------------------------------------- camera hotspots

-- clickable circles on the car (bone -> item or category). Only the side facing the camera is shown.
local HOTSPOTS = {
    { bones = { 'bonnet' },                 item = 'mod_7',   icon = 'fa-car' },
    { bones = { 'engine' },                 cat = 'performance', icon = 'fa-gears', up = 0.25 },
    { bones = { 'boot' },                   item = 'mod_0',   icon = 'fa-plane-up', up = 0.2 },
    { bones = { 'bumper_f' },               item = 'mod_1',   icon = 'fa-car-rear' },
    { bones = { 'bumper_r' },               item = 'mod_2',   icon = 'fa-car-rear' },
    { bones = { 'exhaust', 'exhaust_2' },   item = 'mod_4',   icon = 'fa-wind' },
    { bones = { 'wheel_lf' },               item = 'wheels',  icon = 'fa-circle-dot' },
    { bones = { 'wheel_rf' },               item = 'wheels',  icon = 'fa-circle-dot' },
    { bones = { 'wheel_lr' },               cat = 'stance',   icon = 'fa-arrows-left-right-to-line' },
    { bones = { 'wheel_rr' },               cat = 'stance',   icon = 'fa-arrows-left-right-to-line' },
    { bones = { 'seat_dside_f' },           cat = 'interior', icon = 'fa-chair', up = 0.35, cam = 'interior' },
    { bones = { 'headlight_l' },            cat = 'lights',   icon = 'fa-lightbulb' },
    { bones = { 'headlight_r' },            cat = 'lights',   icon = 'fa-lightbulb' },
    { bones = { 'roof', 'roof2' },          item = 'mod_10',  icon = 'fa-car-tunnel', up = 0.05, cam = 'top' },
}

local function hotspotLoop()
    local list = {}
    local catOk = {}
    for _, c in ipairs(categories()) do catOk[c.id] = true end
    for i, h in ipairs(HOTSPOTS) do
        local ok = (h.item and available(h.item)) or (h.cat and catOk[h.cat])
        if ok then
            for _, b in ipairs(h.bones) do
                local idx = GetEntityBoneIndexByName(veh, b)
                if idx ~= -1 then list[#list + 1] = { i = i, idx = idx, h = h } break end
            end
        end
    end
    if #list == 0 then return end
    CreateThread(function()
        local last = ''
        while Menu.open and veh and DoesEntityExist(veh) do
            local cam = GetFinalRenderedCamCoord()
            local center = GetEntityCoords(veh)
            local out = {}
            for _, e in ipairs(list) do
                local p = GetWorldPositionOfEntityBone(veh, e.idx) + vec3(0.0, 0.0, e.h.up or 0.0)
                local facing = #(cam - p) < #(cam - center) + 0.35
                if facing then
                    local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
                    if on then out[#out + 1] = { k = e.i, x = math.floor(x * 1000) / 1000, y = math.floor(y * 1000) / 1000, item = e.h.item, cat = e.h.cat, icon = e.h.icon } end
                end
            end
            local sig = json.encode(out)
            if sig ~= last then
                last = sig
                UI.Send('menu:hotspots', out)
            end
            Wait(60)
        end
        UI.Send('menu:hotspots', {})
    end)
end

function Menu.Open(shopId, asMechanic, resume)
    if Menu.open then return end
    local vehicle
    if asMechanic then vehicle = VehUtil.Closest(5.0) else vehicle = cache.vehicle end
    if not vehicle or vehicle == 0 then return Notify(L('no_vehicle'), 'error') end
    if not asMechanic and cache.seat ~= -1 then return Notify(L('must_drive'), 'error') end

    if not resume then
        local ok, res = lib.callback.await('nayzeee-tuning:open', false, shopId, VehToNet(vehicle), GetVehicleClass(vehicle), asMechanic)
        if not ok then return Notify(res or L('cannot_open'), 'error') end
        S, veh = res, vehicle
        S.model = S.model or select(3, VehUtil.Label(veh))
        original = Bridge.GetProps(veh)
        origExtras = S.extras or {}
        cart, order, hist, histIdx, code, codePct = {}, {}, {}, 0, nil, 0
        wheelCache, installed = {}, {}
        mode = S.modes and S.modes[1] or 'self'
        snapshot()
    end

    Menu.open = true
    if not resume then
        -- read every installed value once, before anything is previewed on the car
        for _, cat in ipairs(Config.Categories) do
            for _, id in ipairs(cat.items) do if Config.Parts[id] then inst(id) end end
        end
    end
    if NetworkHasControlOfEntity(veh) then
        FreezeEntityPosition(veh, true)
        frozeIt = true
        SetVehicleEngineOn(veh, true, true, false)
    end
    Apply.SetPreview(veh, currentExtras())
    Bridge.HideHud(true)
    Cam.Start(veh)

    local label, make = VehUtil.Label(veh)
    S.label = (make ~= '' and (make .. ' ') or '') .. label
    UI.Send('menu:open', {
        shop = S.shop, role = S.role, canBuy = S.canBuy, reason = S.reason, showPrices = S.showPrices,
        payments = S.payments, components = S.components, money = S.money, openOrder = S.openOrder,
        mechanics = S.mechanics, version = S.version, modes = S.modes, mode = mode, surcharge = S.surcharge,
        labour = S.labour, partsMode = S.partsMode,
        vehicle = { label = label, make = make, plate = S.plate, class = GetVehicleClass(veh), model = S.model },
        categories = categories(), state = cartState(), resume = resume == true,
    })
    UI.Focus(true)
    hotspotLoop()
end

local function restoreVehicle()
    if not veh or not DoesEntityExist(veh) then return end
    setDoors({})
    if lightsOn then SetVehicleLights(veh, 0) lightsOn = false end
    if doorsOpen then SetVehicleDoorsShut(veh, false) doorsOpen = false end
end

function Menu.Close(keepPreview, skipServer)
    if not Menu.open and not testDriving then return end
    Menu.open = false
    UI.Send('menu:close')
    UI.Focus(false)
    Cam.Stop()
    Bridge.HideHud(false)
    if veh and DoesEntityExist(veh) then
        restoreVehicle()
        if not keepPreview then
            Bridge.SetProps(veh, original)
        end
        Apply.ClearPreview(veh)
        if frozeIt then FreezeEntityPosition(veh, false) frozeIt = false end
    end
    if not skipServer then TriggerServerEvent('nayzeee-tuning:closed') end
    veh, S = nil, nil
end

AddEventHandler('nayzeee-tuning:uiClosed', function()
    if Menu.open then Menu.Close(false) end
end)

RegisterNetEvent('nayzeee-tuning:openAdmin', function()
    if not cache.vehicle then return Notify(L('no_vehicle'), 'error') end
    Menu.Open(nil, false)
end)

-- leaving the car / vehicle vanished closes the menu
CreateThread(function()
    while true do
        if Menu.open and (not veh or not DoesEntityExist(veh) or (S and S.role ~= 'mechanic' and S.role ~= 'admin' and cache.vehicle ~= veh)) then
            Menu.Close(false)
        end
        Wait(Menu.open and 500 or 2000)
    end
end)

--------------------------------------------------------------------- NUI callbacks

UI.On('item', function(d)
    if not Menu.open or not Config.Parts[d.id] then return false end
    local part = Config.Parts[d.id]
    Cam.Focus(part.cam or 'full')
    setDoors(part.doors)
    return optionList(d.id)
end)

UI.On('leaveItem', function()
    if Menu.open then setDoors({}) Cam.Focus('full') end
    return true
end)

-- every list-style option on this car, for the search bar (Category › Option)
local CATALOG_KINDS = { mod = true, rearWheels = true, plateIndex = true, tint = true, livery = true, roofLivery = true, nitrous = true,
    swap = true, ecu = true, tyres = true, drivetrain = true, gearbox = true, sound = true }
UI.On('catalog', function()
    if not Menu.open then return {} end
    local out = {}
    for _, cat in ipairs(Config.Categories) do
        for _, id in ipairs(cat.items) do
            local part = Config.Parts[id]
            if part and CATALOG_KINDS[part.kind] and available(id) then
                local d = optionList(id)
                local opts = {}
                for i, o in ipairs(d.options or {}) do opts[i] = { label = o.label, price = o.price } end
                out[id] = opts
            end
        end
    end
    return out
end)

UI.On('wheelList', function(d)
    if not Menu.open then return false end
    local n, labels = wheelCount(d.type)
    local opts = { { value = { type = d.type, index = -1 }, label = 'Stock', price = priceOf('wheels', { type = d.type, index = -1 }) } }
    for i = 0, n - 1 do opts[#opts + 1] = { value = { type = d.type, index = i }, label = labels[i], price = priceOf('wheels', { type = d.type, index = i }) } end
    return opts
end)

-- temporary preview while hovering / dragging (does not touch the cart)
UI.On('preview', function(d)
    if not Menu.open or not Config.Parts[d.id] then return false end
    local part = Config.Parts[d.id]
    if NZ.ExtrasKinds[part.kind] then
        local ex = currentExtras()
        if d.value ~= nil then NZ.ApplyToExtras(ex, d.id, d.value) end
        Apply.SetPreview(veh, ex)
    elseif d.value ~= nil then
        Apply.Item(veh, d.id, d.value)
        if part.slot == 14 then StartVehicleHorn(veh, 1500, joaat('HELDDOWN'), false) end
    end
    return true
end)

-- put the cart value (or the installed value) back on the car for one item
UI.On('restore', function(d)
    if not Menu.open or not Config.Parts[d.id] then return false end
    local part = Config.Parts[d.id]
    if NZ.ExtrasKinds[part.kind] then Apply.SetPreview(veh, currentExtras())
    else
        local v = valueOf(d.id)
        if v ~= nil then Apply.Item(veh, d.id, v) end
    end
    return true
end)

UI.On('setCart', function(d)
    if not Menu.open or not Config.Parts[d.id] then return false end
    local v = d.value
    if v == json.null then v = nil end           -- only nil / null removes; false is a real value (toggle off)
    if v ~= nil and not NZ.Validate(d.id, v) then return false end
    setCart(d.id, v)
    local st = cartState()
    st.added = v ~= nil and cart[d.id] ~= nil and Config.Parts[d.id].label or nil
    return st
end)

UI.On('setMode', function(d)
    if not Menu.open or not NZ.InList(S.modes or {}, d.mode) then return false end
    mode = d.mode
    return cartState()
end)

UI.On('clearCart', function()
    if not Menu.open then return false end
    cart, order = {}, {}
    reapply()
    snapshot()
    return cartState()
end)

UI.On('undo', function(d)
    if not Menu.open then return false end
    local target = d.redo and histIdx + 1 or histIdx - 1
    if not hist[target] then return cartState() end
    histIdx = target
    local s = json.decode(hist[histIdx])
    cart, order = s.cart or {}, s.order or {}
    reapply()
    return cartState()
end)

UI.On('compare', function(d)
    if not Menu.open then return false end
    if d.on then
        Bridge.SetProps(veh, original)
        Apply.SetPreview(veh, NZ.Copy(origExtras))
    else
        reapply()
    end
    return true
end)

UI.On('camera', function(d)
    if not Menu.open then return false end
    if d.dx or d.dy then Cam.Rotate(d.dx or 0, d.dy or 0) end
    if d.zoom then Cam.Zoom(d.zoom) end
    if d.focus then Cam.Focus(d.focus) end
    if d.turntable ~= nil then Cam.Turntable(d.turntable) end
    if d.spot then
        local h = HOTSPOTS[tonumber(d.spot) or 0]
        if h and veh then
            local kind = h.cam or ((h.item == 'wheels' or h.cat == 'stance') and 'wheel') or nil
            for _, b in ipairs(h.bones) do
                local idx = GetEntityBoneIndexByName(veh, b)
                if idx ~= -1 then Cam.FocusSpot(idx, kind) break end
            end
        end
    end
    return true
end)

UI.On('toggle', function(d)
    if not Menu.open then return false end
    if d.what == 'lights' then
        lightsOn = not lightsOn
        SetVehicleLights(veh, lightsOn and 2 or 0)
        return lightsOn
    elseif d.what == 'doors' then
        doorsOpen = not doorsOpen
        if doorsOpen then for i = 0, 5 do SetVehicleDoorOpen(veh, i, false, false) end
        else SetVehicleDoorsShut(veh, false) end
        return doorsOpen
    elseif d.what == 'rev' then
        if cache.seat ~= -1 or cache.vehicle ~= veh then return false end
        CreateThread(function()
            SetVehicleEngineOn(veh, true, true, false)
            local stop = GetGameTimer() + 1700
            while GetGameTimer() < stop and Menu.open do
                SetControlNormal(0, 71, 1.0)
                Wait(0)
            end
        end)
        return true
    end
    return false
end)

UI.On('checkCode', function(d)
    if not Menu.open or S.role == 'admin' then return false end
    local ok, res = lib.callback.await('nayzeee-tuning:checkCode', false, S.shop.id, d.code)
    if ok then code, codePct = res.code, res.percent else code, codePct = nil, 0 end
    local st = cartState()
    st.ok, st.error = ok, not ok and res or nil
    return st
end)

UI.On('clearCode', function()
    code, codePct = nil, 0
    return cartState()
end)

local function cartItems()
    local items = {}
    for _, id in ipairs(order) do if cart[id] ~= nil then items[#items + 1] = { id = id, value = cart[id] } end end
    return items
end

UI.On('checkout', function(d)
    if not Menu.open then return false end
    local items = cartItems()
    if #items == 0 then return { ok = false, error = L('cart_empty') } end
    local props = Bridge.GetProps(veh)
    local ok, res = lib.callback.await('nayzeee-tuning:checkout', false, {
        netId = VehToNet(veh), items = items, props = props, payment = d.payment, code = code, mode = mode,
        class = GetVehicleClass(veh), label = S.label,
    })
    if not ok then return { ok = false, error = res } end

    if res.mode == 'self' then
        Apply.Service(veh, res.lines)
        Notify(L('purchase_done', res.total), 'success')
        Menu.Close(true)
    else
        Notify(L('order_placed', res.orderId), 'success')
        Menu.Close(false)
    end
    return { ok = true, mode = res.mode, orderId = res.orderId, total = res.total }
end)

UI.On('customers', function()
    if not Menu.open or S.role ~= 'mechanic' then return {} end
    return lib.callback.await('nayzeee-tuning:nearbyCustomers', false)
end)

local awaitingQuote = false
UI.On('sendQuote', function(d)
    if not Menu.open or S.role ~= 'mechanic' then return false end
    local items = cartItems()
    if #items == 0 then return { ok = false, error = L('cart_empty') } end
    local ok, res = lib.callback.await('nayzeee-tuning:sendQuote', false, {
        netId = VehToNet(veh), items = items, props = Bridge.GetProps(veh), target = d.target,
        class = GetVehicleClass(veh), label = S.label,
    })
    if not ok then return { ok = false, error = res } end
    awaitingQuote = true
    return { ok = true, total = res.total }
end)

RegisterNetEvent('nayzeee-tuning:quoteAnswered', function(accepted, orderId)
    if not awaitingQuote then return end
    awaitingQuote = false
    UI.Send('menu:quoteAnswer', { accepted = accepted, orderId = orderId })
    if accepted and Menu.open then
        Menu.Close(false)
        Wait(400)
        Install.Begin(orderId)
    end
end)

-------- builds / history / lab

UI.On('saveBuild', function(d)
    local items = cartItems()
    if #items == 0 then return { ok = false, error = L('cart_empty') } end
    local ok, res = lib.callback.await('nayzeee-tuning:saveBuild', false, d.name, S.model, items)
    return { ok = ok, code = ok and res or nil, error = not ok and res or nil }
end)

UI.On('builds', function() return lib.callback.await('nayzeee-tuning:myBuilds', false) end)

UI.On('deleteBuild', function(d) return lib.callback.await('nayzeee-tuning:deleteBuild', false, d.code) end)

local GENERIC_SLOTS = { [11] = true, [12] = true, [13] = true, [15] = true, [16] = true, [14] = true }
UI.On('loadBuild', function(d)
    if not Menu.open then return false end
    local ok, b = lib.callback.await('nayzeee-tuning:getBuild', false, d.code)
    if not ok then return { ok = false, error = b } end
    local sameModel = b.model == S.model
    local applied, skipped = 0, 0
    for _, it in ipairs(b.items) do
        local part = Config.Parts[it.id]
        local okItem = part and available(it.id) and NZ.Validate(it.id, it.value)
        if okItem and part.kind == 'mod' then
            if not sameModel and not GENERIC_SLOTS[part.slot] then okItem = false
            elseif it.value >= modCount(part.slot) then it.value = modCount(part.slot) - 1 end
        end
        if okItem and (part.kind == 'livery' or part.kind == 'roofLivery' or part.kind == 'extras') and not sameModel then okItem = false end
        if okItem then
            if cart[it.id] == nil then order[#order + 1] = it.id end
            cart[it.id] = it.value
            applied = applied + 1
        else skipped = skipped + 1 end
    end
    reapply()
    snapshot()
    local st = cartState()
    st.ok, st.applied, st.skipped, st.name, st.author = true, applied, skipped, b.name, b.author
    return st
end)

UI.On('history', function()
    if not Menu.open then return {} end
    return lib.callback.await('nayzeee-tuning:history', false, S.plate)
end)

UI.On('perfBoard', function(d)
    return lib.callback.await('nayzeee-tuning:perfBoard', false, d.test, d.scope == 'model' and S and S.model or nil)
end)

-------- quick builds

UI.On('maxPerformance', function()
    if not Menu.open then return false end
    for _, id in ipairs({ 'mod_11', 'mod_12', 'mod_13', 'mod_15', 'mod_16' }) do
        if available(id) then
            local n = modCount(Config.Parts[id].slot)
            if n > 0 then setCart(id, n - 1) end
        end
    end
    if available('mod_18') then setCart('mod_18', true) end
    return cartState()
end)

UI.On('randomize', function()
    if not Menu.open then return false end
    local body = { 'mod_0', 'mod_1', 'mod_2', 'mod_3', 'mod_4', 'mod_6', 'mod_7', 'mod_8', 'mod_9', 'mod_10', 'mod_44', 'mod_27' }
    for _, id in ipairs(body) do
        if available(id) and math.random() < 0.7 then
            local n = modCount(Config.Parts[id].slot)
            if n > 0 then setCart(id, math.random(-1, n - 1)) end
        end
    end
    local group = Config.Paints[math.random(1, 2)].colors
    setCart('color1', { mode = 'index', index = group[math.random(1, #group)][1] })
    local accent = Config.Paints[3].colors
    if available('pearl') then setCart('pearl', { mode = 'index', index = accent[math.random(1, #accent)][1] }) end
    if available('wheels') then
        local types = wheelTypes()
        if #types > 0 then
            local t = types[math.random(1, #types)]
            setCart('wheels', { type = t.id, index = math.random(0, t.count - 1) })
        end
    end
    if available('wheelColor') then setCart('wheelColor', { mode = 'index', index = accent[math.random(1, #accent)][1] }) end
    return cartState()
end)

-------- test drive

UI.On('testDrive', function()
    if not Menu.open or not Config.TestDrive.Enabled or S.role ~= 'customer' or cache.seat ~= -1 then return false end
    if #cartItems() == 0 then return { ok = false, error = L('cart_empty') } end
    testDriving = true
    Menu.open = false
    UI.Send('menu:close')
    UI.Focus(false)
    Cam.Stop()
    Bridge.HideHud(false)
    restoreVehicle()
    if frozeIt then FreezeEntityPosition(veh, false) frozeIt = false end
    local bay = GetEntityCoords(veh)
    local heading = GetEntityHeading(veh)
    TestDrive.Start(veh, bay, heading, function()
        testDriving = false
        if veh and DoesEntityExist(veh) and cache.vehicle == veh then
            Menu.Open(S.shop.id, false, true)
        else
            local v = veh
            Menu.open = true
            veh = v
            Menu.Close(false)
        end
    end)
    return { ok = true }
end)

function Menu.IsTestDriving() return testDriving end
function Menu.Vehicle() return veh end
