-- ═══════════════════════════════════════════════════════════════
--  GAS MASK - wearable toggle. Use the item to put it on,
--  use it again to take it off. Acid checks the WORN state.
-- ═══════════════════════════════════════════════════════════════
local maskOn = false
local toggling = false
local maskProp = nil
local savedComponent = nil   -- { drawable, texture } to restore on removal

function IsMaskOn() return maskOn end

local function playToggleAnim()
    local cfg = Config.Gasmask.Anim
    if not cfg or not cfg.Dict then return end
    lib.requestAnimDict(cfg.Dict, 3000)
    TaskPlayAnim(cache.ped, cfg.Dict, cfg.Clip, 8.0, -8.0, cfg.Duration or 1500, cfg.Flag or 48, 0, false, false, false)
    Wait(cfg.Duration or 1500)
    ClearPedTasks(cache.ped)
end

local function attachMaskProp()
    local p = Config.Gasmask.Prop
    if not IsModelInCdimage(p.Model) then
        Config.Notify('Gas mask prop missing', 'error')
        return false
    end
    LoadModel(p.Model)
    local c = GetEntityCoords(cache.ped)
    -- networked so other players see the mask on your face
    maskProp = CreateObject(p.Model, c.x, c.y, c.z, p.Networked ~= false, false, false)
    AttachEntityToEntity(maskProp, cache.ped, GetPedBoneIndex(cache.ped, p.Bone),
        p.Offset.x, p.Offset.y, p.Offset.z, p.Rot.x, p.Rot.y, p.Rot.z,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(p.Model)
    return true
end

local function applyComponent()
    local ped = cache.ped
    savedComponent = { drawable = GetPedDrawableVariation(ped, 1), texture = GetPedTextureVariation(ped, 1) }
    local cfg = GetEntityModel(ped) == `mp_m_freemode_01` and Config.Gasmask.Component.Male or Config.Gasmask.Component.Female
    SetPedComponentVariation(ped, 1, cfg.Drawable, cfg.Texture, 0)
end

-- removes the mask visuals (prop or clothing) without any animation
local function removeMaskVisual()
    if Config.Gasmask.Method == 'component' then
        if savedComponent then
            SetPedComponentVariation(cache.ped, 1, savedComponent.drawable, savedComponent.texture, 0)
            savedComponent = nil
        end
    else
        if maskProp and DoesEntityExist(maskProp) then DeleteEntity(maskProp) end
        maskProp = nil
    end
end

local function setMaskState(on)
    maskOn = on
    LocalPlayer.state:set('nzMaskOn', on, true)
end

function ToggleGasmask()
    if toggling then return end
    toggling = true
    if maskOn then
        -- ── TAKE OFF ──
        playToggleAnim()
        removeMaskVisual()
        setMaskState(false)
        Config.Notify('You take the gas mask off.', 'inform')
    elseif not HasItem(Config.Items.gasmask) then
        Config.Notify('You don\'t have a gas mask', 'error')
    else
        -- ── PUT ON ──
        playToggleAnim()
        local ok = true
        if Config.Gasmask.Method == 'component' then applyComponent() else ok = attachMaskProp() end
        if ok then
            setMaskState(true)
            Config.Notify('Gas mask on. You can breathe safely.', 'success')
        end
    end
    toggling = false
end

RegisterNetEvent('nayzeee-bodybag:client:toggleGasmask', ToggleGasmask)

-- drop the mask if the item leaves your inventory or you die
CreateThread(function()
    while true do
        Wait(5000)
        if maskOn and (not HasItem(Config.Items.gasmask) or IsPedDeadOrDying(cache.ped, true)) then
            removeMaskVisual()
            setMaskState(false)
        end
    end
end)

-- exports['nayzeee-bodybag']:IsMaskOn() -> true while the gas mask is worn
exports('IsMaskOn', IsMaskOn)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if maskOn then removeMaskVisual() end
end)
