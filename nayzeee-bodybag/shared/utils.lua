-- ═══════════════════════════════════════════════════════════════
--  SHARED HELPERS (client + server)
-- ═══════════════════════════════════════════════════════════════

-- What players see for each container type
KindLabels = {
    bodybag = 'Body Bag',
    crate   = 'Military Crate',
    coffin  = 'Coffin',
    barrel  = 'Burn Barrel',
}

function KindLabel(kind) return KindLabels[kind] or 'Container' end

-- How many bodies / which containers fit in this vehicle model
function TrunkRules(model)
    local o = Config.Trunk.Overrides and Config.Trunk.Overrides[model]
    return {
        MaxBodies    = (o and o.MaxBodies) or Config.Trunk.MaxBodies,
        AllowedKinds = (o and o.AllowedKinds) or Config.Trunk.AllowedKinds,
    }
end

-- 125 -> "02:05"
function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return ('%02d:%02d'):format(seconds // 60, seconds % 60)
end

-- casket spot = 2m in front of a plot's headstone
function PlotCasketCoords(plot)
    local rad = math.rad(plot.heading or 0.0)
    return vector3(plot.coords.x - math.sin(rad) * 2.0, plot.coords.y + math.cos(rad) * 2.0, plot.coords.z)
end

function FuneralEnabled()
    return Config.Funeral and Config.Funeral.Enabled
end
