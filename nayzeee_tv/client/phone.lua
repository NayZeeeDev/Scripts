--[[ Phone apps: lb-phone and yseries — control nearby screens when the remote is lost ]]

local RES = NZ.res
local P = Config.Phone
local UI = RES .. '/html/phone/index.html'
local ICON = ('https://cfx-nui-%s/html/phone/icon.svg'):format(RES)

local function waitFor(res, timeout)
    local t = GetGameTimer() + (timeout or 60000)
    while GetResourceState(res) ~= 'started' do
        if GetGameTimer() > t or GetResourceState(res) == 'missing' then return false end
        Wait(1000)
    end
    return true
end

-- lb-phone custom app
CreateThread(function()
    if not P.LbPhone or not waitFor('lb-phone') then return end
    Wait(1000)
    local ok, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier  = P.Identifier,
            name        = P.Name,
            description = P.Description,
            developer   = P.Developer,
            defaultApp  = true,
            size        = 4096,
            ui          = UI,
            icon        = ICON,
            fixBlur     = true,
        })
    end)
    if not ok then print('^3[nayzeee_tv]^7 lb-phone app not registered: ' .. tostring(err)) end
end)

-- yseries custom app (export names vary by version — adjust Config.Phone.YSeriesResource if needed)
CreateThread(function()
    local res = P.YSeriesResource
    if not P.YSeries or not waitFor(res) then return end
    Wait(1000)
    local app = {
        id = P.Identifier, key = P.Identifier, identifier = P.Identifier,
        name = P.Name, label = P.Name, description = P.Description, developer = P.Developer,
        ui = UI, url = ('https://cfx-nui-%s/html/phone/index.html'):format(RES), icon = ICON, defaultApp = true,
    }
    local ok, err = pcall(function() return exports[res]:AddCustomApp(app) end)
    if not ok then print('^3[nayzeee_tv]^7 yseries app not registered (check your yseries custom-app export): ' .. tostring(err)) end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= RES then return end
    if P.LbPhone and GetResourceState('lb-phone') == 'started' then
        pcall(function() exports['lb-phone']:RemoveCustomApp(P.Identifier) end)
    end
end)

-- ─── app backend ──────────────────────────────────────────────
RegisterNUICallback('phone:list', function(_, cb)
    local pc = GetEntityCoords(PlayerPedId())
    local out = {}
    for _, tv in pairs(NZ.tvs) do
        local d = #(pc - NZ.center(tv))
        if d <= P.Range then
            local m = tv.media
            out[#out + 1] = {
                id = tv.id, label = tv.label, dist = math.floor(d * 10) / 10, power = tv.power, volume = tv.volume, muted = tv.muted,
                locked = tv.locked, style = tv.style, loop = tv.loop,
                media = m and { title = m.title or Utils.fallbackTitle(m), kind = m.kind, brand = m.brand, thumb = m.thumb, live = m.live, paused = m.paused,
                    startedAt = m.startedAt, pausedAt = m.pausedAt, duration = m.duration } or false,
                remoteLost = tv.remote ~= nil and tv.remoteHolder ~= nil and tv.remoteHolder ~= NZ.me,
            }
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    cb({ tvs = out, now = NZ.serverNow(), channels = NZ.channels, brand = Config.Brand })
end)
