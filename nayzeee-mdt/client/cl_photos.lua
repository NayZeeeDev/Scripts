-- ═══════════════════════════════════════════════════════════
--  PHOTO CAPTURE
--  The server asks for a screenshot; screenshot-basic uploads it
--  straight to whichever host is configured and we hand back the
--  response so the server can pull the link out of it.
-- ═══════════════════════════════════════════════════════════

lib.callback.register('nz_mdt:photo:upload', function(url, field, headers)
    if GetResourceState(Config.Photos.resource) ~= 'started' then return nil end

    local done = promise.new()
    local settled = false

    local function finish(value)
        if settled then return end
        settled = true
        done:resolve(value)
    end

    -- the MDT is covering the screen, so hide it for the shot
    local wasOpen = MDT.isOpen
    if wasOpen then SendNUIMessage({ action = 'shutter', on = true }) end
    Wait(60)

    local ok = pcall(function()
        exports[Config.Photos.resource]:requestScreenshotUpload(url, field or 'files[]', {
            encoding = 'jpg',
            quality  = Config.Photos.quality or 0.85,
            headers  = headers
        }, function(data)
            finish(data)
        end)
    end)

    if not ok then
        -- older builds of screenshot-basic take no options table
        pcall(function()
            exports[Config.Photos.resource]:requestScreenshotUpload(url, field or 'files[]', function(data)
                finish(data)
            end)
        end)
    end

    -- never hang the server callback
    SetTimeout(12000, function() finish(nil) end)

    local result = Citizen.Await(done)

    if wasOpen then SendNUIMessage({ action = 'shutter', on = false }) end

    return result
end)

--- Point the camera at what the officer is looking at, then shoot.
RegisterNetEvent('nz_mdt:photo:flash', function()
    PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
end)
