--[[
    Shared building blocks for heist configs. Not a heist itself (not listed in Config.Heists).
    Usage inside a heist file:  local C = lib.load('config.heists._common')
]]

local C = {}

C.models = {
    cashTrolley    = 'hei_prop_hei_cash_trolly_01',
    goldTrolley    = 'ch_prop_gold_trolly_01a',
    diamondTrolley = 'ch_prop_diamond_trolly_01a',
    emptyTrolley   = 'hei_prop_hei_cash_trolly_03',
    cashPile       = 'bkr_prop_bkr_cashpile_04',
    cashStack      = 'h4_prop_h4_cash_stack_01a',
    goldStack      = 'h4_prop_h4_gold_stack_01a',
    moneyWrapped   = 'bkr_prop_money_wrapped_01',
    cokeBlock      = 'bkr_prop_coke_block_01a',
    weedBlock      = 'hei_prop_heist_weed_block_01',
    milCrate       = 'prop_mil_crate_01',
    weaponCrate    = 'xm_prop_crates_weapon_mix_01a',
    carrierCrate   = 'hei_prop_carrier_crate_01a_s',
    painting       = 'ch_prop_vault_painting_01a',
    laptop         = 'prop_laptop_01a',
    safe           = 'prop_ld_int_safe_01',
    elecbox        = 'tr_prop_tr_elecbox_01a',
    handlerBox     = 'prop_contr_03b_ld',
    bigContainer   = 'prop_container_ld_d',
}

C.guardModels = { 's_m_m_highsec_01', 's_m_m_highsec_02', 's_m_y_blackops_01', 's_m_m_chemsec_01' }

--- vec4 list -> guard specs
function C.guards(list, opts)
    opts = opts or {}
    local out = {}
    for i = 1, #list do
        out[i] = {
            coords = list[i],
            model = opts.model or C.guardModels[(i - 1) % #C.guardModels + 1],
            weapon = opts.weapons and opts.weapons[(i - 1) % #opts.weapons + 1] or opts.weapon or 'WEAPON_CARBINERIFLE',
            group = opts.group or 'guards',
            armour = opts.armour,
            ground = opts.ground,
        }
    end
    return out
end

--- cash / gold / diamond trolley node
function C.trolley(id, coords, heading, kind, opts)
    opts = opts or {}
    kind = kind or 'cash'
    local model = kind == 'gold' and C.models.goldTrolley or (kind == 'diamond' and C.models.diamondTrolley or C.models.cashTrolley)
    return {
        id = id, type = 'trolley', kind = kind, label = opts.label or (kind == 'gold' and 'Load gold' or (kind == 'diamond' and 'Bag diamonds' or 'Grab cash')),
        icon = 'fas fa-sack-dollar', coords = coords, heading = heading, radius = 1.1,
        reward = opts.reward or ('trolley_' .. kind), requires = opts.requires, requiresFlag = opts.requiresFlag,
        prop = { model = model, heading = heading, swap = C.models.emptyTrolley },
        objective = 'Trolleys',
    }
end

--- grabbable pile (cash, coke, gold stacks)
function C.pile(id, coords, heading, model, reward, opts)
    opts = opts or {}
    return {
        id = id, type = 'interact', action = 'grab', label = opts.label or 'Grab', icon = 'fas fa-hand-holding-dollar',
        coords = coords, heading = heading, radius = opts.radius or 1.0, reward = reward, duration = opts.duration or 4500,
        requires = opts.requires, requiresFlag = opts.requiresFlag, ground = opts.ground,
        prop = model and { model = model, heading = heading, removeOnDone = true, ground = opts.ground } or nil,
    }
end

--- searchable spot (no prop)
function C.search(id, coords, reward, opts)
    opts = opts or {}
    return {
        id = id, type = 'interact', action = opts.action or 'search', label = opts.label or 'Search', icon = 'fas fa-magnifying-glass',
        coords = coords, radius = opts.radius or 1.0, reward = reward, duration = opts.duration or 5000,
        requires = opts.requires, requiresFlag = opts.requiresFlag, ground = opts.ground, noise = opts.noise,
    }
end

--- Rotate+translate a point recorded relative to one copy of an interior onto another copy.
--- base = { pos = vec3, yaw = deg } of the reference door, target = same for the other location.
function C.transform(base, target, p)
    local rel = vec3(p.x - base.pos.x, p.y - base.pos.y, p.z - base.pos.z)
    local a = math.rad(target.yaw - base.yaw)
    local ca, sa = math.cos(a), math.sin(a)
    return vec3(
        target.pos.x + rel.x * ca - rel.y * sa,
        target.pos.y + rel.x * sa + rel.y * ca,
        target.pos.z + rel.z
    )
end

function C.transformHeading(base, target, h)
    return (h + (target.yaw - base.yaw)) % 360.0
end

--- common loot tables
C.loot = {
    trolley_cash = { { item = 'money', min = 9000, max = 13500 } },
    trolley_gold = { { item = 'gold_bar', min = 3, max = 6 } },
    trolley_diamond = { { item = 'diamond', min = 4, max = 9 } },
    cash_pile = { { item = 'money', min = 2500, max = 4500 } },
    lockbox = {
        { item = 'money', min = 800, max = 1800 },
        { item = 'rolex', min = 1, max = 2, chance = 0.45 },
        { item = 'diamond_ring', min = 1, max = 1, chance = 0.25 },
        { item = 'gold_chain', min = 1, max = 3, chance = 0.5 },
    },
}

--- merge tables: C.with(C.loot, { extra = {...} })
function C.with(base, extra)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end

return C
