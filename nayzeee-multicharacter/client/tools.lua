if not NAYZEEE_LOCK_OK then return end

-- /mc_coords (admin): copies your position and the gameplay camera, ready to paste into config/scenes.lua
RegisterNetEvent('nzm:client:coords', function()
    local ped = PlayerPedId()
    local p, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local c, r = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local text = ('coords = vec4(%.4f, %.4f, %.4f, %.4f),\ncamera = { coords = vec3(%.4f, %.4f, %.4f), rot = vec3(%.4f, 0.0, %.4f), fov = %.1f },')
        :format(p.x, p.y, p.z, h, c.x, c.y, c.z, r.x, r.z, GetGameplayCamFov())
    lib.setClipboard(text)
    ClientBridge.Notify('Copied position + camera to clipboard', 'success')
    print(text)
end)
