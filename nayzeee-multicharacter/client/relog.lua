if not NAYZEEE_LOCK_OK then return end

-- Relog points: blips + ox_lib points (no threads of our own while playing)
local cfg = Config.Relog
if not cfg.points or #cfg.points == 0 then return end

local function relog() TriggerServerEvent('nzm:server:relog') end

local inside = 0
local key
if cfg.interact ~= 'target' or GetResourceState('ox_target') == 'missing' then
    key = lib.addKeybind({
        name = 'nzm_relog',
        description = NZ.T('relog_target'),
        defaultKey = 'E',
        disabled = true,
        onReleased = function()
            if inside == 0 or Main.open then return end
            lib.hideTextUI()
            relog()
        end,
    })
    key:disable(true)
end

CreateThread(function()
    for i, p in ipairs(cfg.points) do
        if p.blip then
            local b = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z)
            SetBlipSprite(b, cfg.blip.sprite)
            SetBlipColour(b, cfg.blip.color)
            SetBlipScale(b, cfg.blip.scale + 0.0)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(cfg.blip.name)
            EndTextCommandSetBlipName(b)
        end

        if cfg.interact == 'target' and GetResourceState('ox_target') ~= 'missing' then
            exports.ox_target:addSphereZone({
                coords = p.coords, radius = cfg.distance, debug = false,
                options = { { name = 'nzm_relog_' .. i, icon = 'fa-solid fa-people-arrows', label = p.label or NZ.T('relog_target'), onSelect = relog } },
            })
        else
            -- Enter/exit only: no per-frame "nearby" loop. E is a key mapping that is disabled away from the point.
            lib.points.new({
                coords = p.coords,
                distance = cfg.distance,
                onEnter = function()
                    inside = inside + 1
                    key:disable(false)
                    lib.showTextUI(NZ.T('relog_prompt'), { icon = 'people-arrows' })
                end,
                onExit = function()
                    inside = math.max(inside - 1, 0)
                    if inside == 0 then key:disable(true) lib.hideTextUI() end
                end,
            })
        end
    end
end)
