Config = {}

-- Prop / item identifiers ------------------------------------------------------
Config.Model    = 'nz_prop_cpu_chip'   -- archetype name streamed by this resource
Config.ItemName = 'cpu_chip'           -- inventory item name (ox_inventory / qb-core / esx)

-- Debug commands (/cpuchip spawn | hold | drop | clear). Turn off on production.
Config.Debug = true

-- Framework used for the "usable item" hook. 'auto' picks whichever of
-- ox_inventory / qb-core / es_extended is started; 'none' disables it.
Config.Framework = 'auto'

-- How the chip sits in the hand when inspected / held -----------------------------
-- Bone 28422 (PH_R_Hand) is the standard right-hand prop bone.
Config.Hold = {
    bone = 28422,
    offset = vector3(0.01, 0.0, 0.0),
    rotation = vector3(0.0, 0.0, 0.0),
    anim = { dict = 'cellphone@', name = 'cellphone_text_read_base', flag = 49 },
    duration = 4000, -- ms the inspect animation plays when the item is used
}

-- Where the debug spawn command drops the chip: in front of the player at this
-- distance; the prop has real collision, so it falls onto whatever is underneath.
Config.SpawnDistance = 0.8

-- Notification hook. Swap the body for your own UI / notification system.
function Config.Notify(msg, kind)
    if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
        lib.notify({ title = 'CPU Chip', description = msg, type = kind or 'inform' })
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end
