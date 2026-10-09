-- ═══════════════════════════════════════════════════════════════
--  ADMIN MENU (/bodyadmin) - every active body at a glance
-- ═══════════════════════════════════════════════════════════════
local kindIcons = { bodybag = 'bag-shopping', crate = 'box', coffin = 'cross', barrel = 'fire', trunk = 'car', grave = 'trowel', tombstone = 'cross' }

local function openEntry(e)
    local options = {
        { title = 'Teleport To It', icon = 'location-dot', onSelect = function()
            SetEntityCoords(cache.ped, e.coords.x, e.coords.y, e.coords.z + 1.0, false, false, false, false)
        end },
    }
    options[#options + 1] = {
        title = e.type == 'grave' and 'Delete Grave' or 'Free Victim & Remove',
        description = e.type == 'grave' and 'Removes the grave prop and its database record'
            or 'The victim is released alive - nothing is CKed',
        icon = 'unlock', onSelect = function()
            TriggerServerEvent('nayzeee-bodybag:server:adminAction', 'free', e.type, e.key)
        end,
    }
    lib.registerContext({ id = 'nz_admin_entry', title = ('%s - %s'):format(e.kind, e.name), menu = 'nz_admin', options = options })
    lib.showContext('nz_admin_entry')
end

RegisterNetEvent('nayzeee-bodybag:client:openAdmin', function()
    local list = lib.callback.await('nayzeee-bodybag:admin:list', false)
    if not list then return Config.Notify('No permission', 'error') end

    local me = GetEntityCoords(cache.ped)
    table.sort(list, function(a, b) return #(me - a.coords) < #(me - b.coords) end)

    local options = {}
    for _, e in ipairs(list) do
        options[#options + 1] = {
            title = ('%s  •  %s'):format(e.name, e.kind),
            description = ('Stage: %s  •  %s  •  %.0fm away'):format(e.stage, e.online and 'victim ONLINE' or 'victim offline',
                #(me - e.coords)),
            icon = kindIcons[e.kind] or 'skull', arrow = true,
            onSelect = function() openEntry(e) end,
        }
    end
    if #options == 0 then
        options[1] = { title = 'No active bodies', icon = 'check', disabled = true }
    else
        options[#options + 1] = {
            title = 'Clear ALL Bodies', description = 'Frees every bagged victim (graves are kept)', icon = 'triangle-exclamation',
            onSelect = function()
                local confirm = lib.alertDialog({ header = 'Clear all bodies?', centered = true, cancel = true,
                    content = 'Every bag, crate, coffin, barrel and trunk body is removed and the victims are released.' })
                if confirm == 'confirm' then TriggerServerEvent('nayzeee-bodybag:server:adminAction', 'clearAll') end
            end,
        }
    end

    lib.registerContext({ id = 'nz_admin', title = Config.UI.Title .. ' • Body Admin', options = options })
    lib.showContext('nz_admin')
end)
