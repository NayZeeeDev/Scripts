--[[
    Growth math. Nothing ticks on a timer: the state stores when it was last advanced and is
    brought up to date whenever someone looks at it. Plants only grow while watered; water
    drains whether or not something is planted.

    state = { soil, soilQ, seed, strain, growth (0..1), water (0..1), t, q, yb, used = {}, rs }
      soil   harvests left in the soil       q    quality change (fertilizer, PGR, speed)
      yb     yield bonus (PGR)               used additives already applied
      rs     per-plant random seed: the bud count is fixed when the seed goes in
]]

Grow = {}

local function strain(st)
    return Config.Strains[st.strain or ''] or Config.Strains.ogkush
end

--- seconds from seed to harvest at boost 1
function Grow.total(st)
    return Config.Grow.minutes * 60.0 * (strain(st).grow or 1.0)
end

--- advance `st` to `now` in place. boost = growth multiplier (lights / tent)
function Grow.tick(st, now, boost)
    if not st.t then st.t = now return st end
    local dt = now - st.t
    if dt <= 0 then return st end
    st.t = now
    local waterSecs = Config.Grow.water * 60.0
    local w = st.water or 0.0
    if st.seed and (st.growth or 0) < 1.0 then
        local wet = math.min(dt, w * waterSecs)
        st.growth = math.min(1.0, (st.growth or 0.0) + wet * (boost or 1.0) / Grow.total(st))
    end
    st.water = math.max(0.0, w - dt / waterSecs)
    return st
end

--- ticked copy (for display), leaves `st` alone
function Grow.view(st, now, boost)
    local c = {}
    for k, v in pairs(st) do c[k] = v end
    return Grow.tick(c, now, boost)
end

--- 0 empty, 1 sprout, 2 young, 3 grown, 4 ready to harvest
function Grow.stage(st)
    if not st.seed then return 0 end
    local g = st.growth or 0
    if g >= 1.0 then return 4 end
    if g < 0.34 then return 1 end
    if g < 0.67 then return 2 end
    return 3
end

--- seconds left until harvest at the current boost, nil if dry
function Grow.eta(st, boost)
    if not st.seed or (st.growth or 0) >= 1 then return 0 end
    if (st.water or 0) <= 0 then return nil end
    return math.ceil((1.0 - st.growth) * Grow.total(st) / (boost or 1.0))
end

--- buds at harvest. Deterministic per plant so the client shows as many buds as the server pays.
function Grow.harvestCount(st, yieldMult)
    local y = strain(st).yield or { 6, 9 }
    local n = y[1] + ((st.rs or 0) % (y[2] - y[1] + 1))
    return math.max(1, math.floor(n * (1.0 + (st.yb or 0.0)) * (yieldMult or 1.0) + 0.5))
end

function Grow.quality(st)
    return Utils.clamp((st.soilQ or 1) + (st.q or 0), 0, 4)
end
