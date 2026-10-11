if not NAYZEEE_LOCK_OK then return end

-- Relog points: blips + ox_lib points (no threads of our own while playing)
local cfg = Config.Relog
if not cfg.points or #cfg.points == 0 then return end

local function relog() TriggerServerEvent('nzm:server:relog') end

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
            local shown = false
            lib.points.new({
                coords = p.coords,
                distance = cfg.distance,
                onEnter = function() shown = true lib.showTextUI(NZ.T('relog_prompt'), { icon = 'people-arrows' }) end,
                onExit = function() if shown then lib.hideTextUI() shown = false end end,
                nearby = function()
                    if IsControlJustReleased(0, 38) and not Main.open then
                        lib.hideTextUI()
                        shown = false
                        relog()
                    end
                end,
            })
        end
    end
end)
