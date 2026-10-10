--[[
    Empire app: NUI callbacks shared by every phone (lb-phone / YSeries / qs) and the
    on-screen phone (/empire). The app page posts here; we forward to the server.
]]

Phone = { open = false }

local CP = Config.Phone

local function reply(cb, ok, res)
    cb({ ok = ok == true, res = res })
end

RegisterNUICallback('phoneData', function(_, cb)
    cb(lib.callback.await('nzde:phone:data', false) or {})
end)

RegisterNUICallback('phoneRead', function(d, cb)
    lib.callback.await('nzde:phone:read', false, d and d.thread)
    cb(1)
end)

RegisterNUICallback('phoneTab', function(d, cb)
    lib.callback.await('nzde:phone:tab', false, d and d.tab)
    cb(1)
end)

RegisterNUICallback('dealRespond', function(d, cb)
    reply(cb, lib.callback.await('nzde:deal:respond', false, d.id, d.answer, d.price))
end)

RegisterNUICallback('sampleTarget', function(d, cb)
    reply(cb, lib.callback.await('nzde:cust:sampleTarget', false, d.cid or false))
end)

RegisterNUICallback('productPrice', function(d, cb)
    reply(cb, lib.callback.await('nzde:product:price', false, d.pid, d.price))
end)

RegisterNUICallback('dealerHire', function(d, cb)
    reply(cb, lib.callback.await('nzde:dealer:hire', false, d.id, d.account))
end)

RegisterNUICallback('dealerFire', function(d, cb)
    reply(cb, lib.callback.await('nzde:dealer:fire', false, d.id))
end)

RegisterNUICallback('dealerAssign', function(d, cb)
    reply(cb, lib.callback.await('nzde:dealer:assign', false, d.id, d.cid, d.on == true))
end)

RegisterNUICallback('orderPlace', function(d, cb)
    reply(cb, lib.callback.await('nzde:order:place', false, d.shop, d.cart, d.drop, d.account))
end)

RegisterNUICallback('rvTow', function(d, cb)
    reply(cb, lib.callback.await('nzde:rv:tow', false, d.account))
end)

RegisterNUICallback('waypoint', function(d, cb)
    if d and d.x and d.y then
        SetNewWaypoint(d.x + 0.0, d.y + 0.0)
        UI.notify('Waypoint set', 'success')
    end
    cb(1)
end)

--[[ on-screen phone ]]
function Phone.show()
    if Phone.open then return end
    if not Main.state.app then
        return UI.notify('You don\'t have that app.', 'error')
    end
    Phone.open = true
    UI.setFocus(true, true)
    UI.send('phone', { open = true })
end

function Phone.close()
    if not Phone.open then return end
    Phone.open = false
    UI.send('phone', { open = false })
    UI.setFocus(false)
end

if CP.Command then
    RegisterCommand(CP.Command, function()
        if Phone.open then Phone.close() else Phone.show() end
    end, false)
    if CP.Keybind then
        RegisterKeyMapping(CP.Command, 'Drug empire: open the ' .. CP.AppName .. ' app', 'keyboard', CP.Keybind)
    end
end

--- server pushes: refresh an open app
RegisterNetEvent('nzde:phone:refresh', function(what)
    if GetInvokingResource() then return end
    PhoneBridge.Send({ type = 'refresh', what = what })
end)

--- new text: phone banner + our own toast when the phone isn't open
RegisterNetEvent('nzde:text', function(t)
    if GetInvokingResource() then return end
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    if t.app and PhoneBridge.installed and PhoneBridge.name ~= 'standalone' and PhoneBridge.name ~= 'none' then
        PhoneBridge.Notify(t.from, t.text)
    else
        UI.send('sms', { from = t.from, text = t.text })
    end
    PhoneBridge.Send({ type = 'refresh', what = 'messages' })
end)
