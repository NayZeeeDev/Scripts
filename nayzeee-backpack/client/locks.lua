-----------------------------------------------------------------
-- Padlocks (client)
--
-- The server decides everything; this only asks: what's the code,
-- did the lockpick minigame go through, did the cutting finish.
-----------------------------------------------------------------

local cfg = Config.Padlock
if not cfg or not cfg.enabled then return end

Locks = {}

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end

local function askCode(title, label)
    local r = lib.inputDialog(title, {
        { type = 'input', label = label, password = true, required = true,
          min = cfg.digits or 4, max = cfg.digits or 4, icon = 'lock' },
    })
    return r and r[1]
end

local function animated(a, fn)
    local ped = PlayerPedId()
    if a and Util.loadDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.clip, 3.0, -3.0, -1, 1, 0, false, false, false)
    end
    local result = fn()
    if a then StopAnimTask(ped, a.dict, a.clip, 2.0) end
    return result
end

local function pick()
    local lp = cfg.lockpick or {}
    if Sound then Sound.near('pick') end
    local ok = animated(lp.anim, function()
        return lib.skillCheck(lp.difficulty or { 'easy', 'medium', 'hard' }, lp.keys)
    end)
    TriggerServerEvent('nayzeee-backpack:lock:try', 'pick', ok == true)
end

local function cut()
    local c = cfg.cutter or {}
    local ok = lib.progressBar({
        duration = c.time or 6000,
        label = S('lk_cutting'),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = c.anim and { dict = c.anim.dict, clip = c.anim.clip, flag = 1 } or nil,
    })
    if ok then
        TriggerServerEvent('nayzeee-backpack:lock:try', 'cut')
    else
        TriggerServerEvent('nayzeee-backpack:lock:cancel')
    end
end

RegisterNetEvent('nayzeee-backpack:lock:prompt', function(data)
    data = data or {}
    lib.registerContext({
        id = 'nayzeee_backpack_lock',
        title = ('%s · %s'):format(S('lk_title'), data.label or ''),
        onExit = function() TriggerServerEvent('nayzeee-backpack:lock:cancel') end,
        options = {
            {
                title = S('lk_code'), icon = 'key',
                onSelect = function()
                    local code = askCode(data.label or S('lk_title'), S('lk_code'))
                    if code then
                        TriggerServerEvent('nayzeee-backpack:lock:try', 'code', code)
                    else
                        TriggerServerEvent('nayzeee-backpack:lock:cancel')
                    end
                end,
            },
            {
                title = S('lk_pick'), icon = 'screwdriver',
                description = not data.canPick and S('lk_no_pick') or nil,
                disabled = not data.canPick,
                onSelect = pick,
            },
            {
                title = S('lk_cut'), icon = 'scissors',
                description = not data.canCut and S('lk_no_cutter') or nil,
                disabled = not data.canCut,
                onSelect = cut,
            },
        },
    })
    lib.showContext('nayzeee_backpack_lock')
end)

-- used the padlock item
RegisterNetEvent('nayzeee-backpack:lock:set', function(label, digits)
    local code = askCode(S('lk_set_title', label or ''), S('lk_set_label', digits or cfg.digits or 4))
    if code then TriggerServerEvent('nayzeee-backpack:lock:apply', code) end
end)

--- Bag menu entries for your own bag's padlock.
function Locks.menuOptions()
    local st = lib.callback.await('nayzeee-backpack:lock:state', false)
    if not st then return {} end
    local options = {}

    if not st.locked then
        if st.hasPadlock then
            options[#options + 1] = {
                title = S('lk_menu_lock'), icon = 'lock',
                onSelect = function()
                    local code = askCode(S('lk_menu_lock'), S('lk_set_label', cfg.digits or 4))
                    if code then TriggerServerEvent('nayzeee-backpack:lock:apply', code) end
                end,
            }
        end
        return options
    end

    local function needOld()
        if st.trusted then return '' end
        return askCode(S('lk_title'), S('lk_code'))
    end

    options[#options + 1] = {
        title = S('lk_menu_change'), icon = 'key',
        onSelect = function()
            local old = needOld()
            if not old then return end
            local new = askCode(S('lk_menu_change'), S('lk_set_label', cfg.digits or 4))
            if new then TriggerServerEvent('nayzeee-backpack:lock:manage', 'change', old, new) end
        end,
    }
    options[#options + 1] = {
        title = S('lk_menu_remove'), icon = 'lock-open',
        onSelect = function()
            local old = needOld()
            if old then TriggerServerEvent('nayzeee-backpack:lock:manage', 'remove', old) end
        end,
    }
    return options
end
