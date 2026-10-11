-- ═══════════════════════════════════════════════════════════
--  PHOTOS — in-game screenshots attached to any record
-- ═══════════════════════════════════════════════════════════

local function subjectAllowed(subject)
    for _, s in ipairs(Config.Photos.subjects or {}) do
        if s == subject then return true end
    end
    return false
end

--- Is the photo pipeline actually usable right now?
local function serviceReady()
    if not Config.Photos.enabled then
        return false, 'Photo capture is switched off in the config.'
    end
    if GetResourceState(Config.Photos.resource) ~= 'started' then
        return false, ('%s is not running.'):format(Config.Photos.resource)
    end

    local host = Config.Photos.host
    if host == 'fivemanage' then
        if (Config.Photos.fivemanage.apiKey or '') == '' then
            return false, 'No Fivemanage API key is set.'
        end
    elseif host == 'discord' then
        if (Config.Photos.discord.webhook or '') == '' then
            return false, 'No Discord webhook is set.'
        end
    elseif host == 'custom' then
        if (Config.Photos.custom.url or '') == '' then
            return false, 'No custom upload URL is set.'
        end
    else
        return false, ('Unknown photo host "%s".'):format(tostring(host))
    end

    return true
end

-- ═══════════════════════════════════════════════════════════
--  UPLOAD HOSTS
--  Each returns url, hostId — or nil plus a reason.
-- ═══════════════════════════════════════════════════════════

--- Pull a link out of whatever screenshot-basic handed back (raw body or table).
local function linkFrom(result, field)
    if not result then return nil end
    local body = type(result) == 'table' and (result.body or result) or result
    if type(body) == 'string' and body:match('^https?://') then return body end

    local data = type(body) == 'table' and body or MDT.decode(body, nil)
    if type(data) ~= 'table' then return nil end
    if data.data and type(data.data) == 'table' then data = data.data end

    local url = data[field or 'url'] or data.url or data.link
    if type(url) == 'string' and url:match('^https?://') then return url, data.id and tostring(data.id) or nil end
    return nil
end

--- Fivemanage hands out a presigned URL that the client uploads straight to.
--- A promise only carries one value, so the result travels as a table.
local function viaFivemanage(src)
    local done = promise.new()

    PerformHttpRequest('https://api.fivemanage.com/api/presigned-url?fileType=image',
        function(status, body)
            if status ~= 200 then return done:resolve({ err = 'Fivemanage refused the upload request.' }) end
            local data = MDT.decode(body, nil)
            local target = type(data) == 'table' and (data.presignedUrl or (data.data and data.data.presignedUrl))
            if not target then return done:resolve({ err = 'Fivemanage sent back no upload URL.' }) end
            done:resolve({ target = target })
        end, 'GET', '', {
            ['User-Agent']    = 'nayzeee-mdt',
            ['Authorization'] = Config.Photos.fivemanage.apiKey
        })

    local step = Citizen.Await(done)
    if step.err then return nil, step.err end

    local result = lib.callback.await('nz_mdt:photo:upload', src, step.target, 'file')
    if not result then return nil, 'The screenshot never reached the host.' end

    local url, id = linkFrom(result, 'url')
    if not url then return nil, 'Fivemanage accepted the file but sent back no link.' end
    return url, id
end

--- Discord takes the file directly on the webhook and gives back a CDN link.
local function viaDiscord(src)
    local result = lib.callback.await('nz_mdt:photo:upload', src,
        Config.Photos.discord.webhook .. '?wait=true', 'files[]')

    if not result then return nil, 'The screenshot never reached Discord.' end

    -- screenshot-basic returns the raw webhook response body
    local body = type(result) == 'table' and result.body or result
    local data = MDT.decode(body, nil)

    if type(data) == 'table' and data.attachments and data.attachments[1] then
        return data.attachments[1].url, tostring(data.id or '')
    end

    -- some builds already resolve the link for us
    if type(result) == 'string' and result:match('^https?://') then
        return result
    end

    return nil, 'Discord accepted the file but sent back no link.'
end

local function viaCustom(src)
    local result = lib.callback.await('nz_mdt:photo:upload', src,
        Config.Photos.custom.url, 'file', Config.Photos.custom.headers)

    if not result then return nil, 'The screenshot never reached your endpoint.' end

    local url, id = linkFrom(result, Config.Photos.custom.field or 'url')
    if url then return url, id end
    return nil, 'Your endpoint sent back no link.'
end

--- Ask the client for a screenshot and push it to whichever host is set.
local function capture(src)
    local host = Config.Photos.host
    if host == 'fivemanage' then return viaFivemanage(src) end
    if host == 'discord' then return viaDiscord(src) end
    return viaCustom(src)
end

-- ═══════════════════════════════════════════════════════════
--  QUERIES
-- ═══════════════════════════════════════════════════════════
function MDT.getPhotos(subject, subjectId)
    if not Config.Photos.enabled then return {} end

    local rows = MySQL.query.await([[
        SELECT id, url, description, is_avatar, taken_by,
               DATE_FORMAT(created_at, '%d %b %Y · %H:%i') AS stamp
        FROM nz_mdt_photos WHERE subject = ? AND subject_id = ?
        ORDER BY is_avatar DESC, id DESC LIMIT 20
    ]], { subject, tostring(subjectId) }) or {}

    local out = {}
    for _, p in ipairs(rows) do
        out[#out + 1] = {
            id = p.id, url = p.url, description = p.description,
            avatar = MDT.bool(p.is_avatar), takenBy = p.taken_by, stamp = p.stamp
        }
    end
    return out
end

--- The picture shown on a record card, if one has been marked.
function MDT.avatarFor(subject, subjectId)
    if not Config.Photos.enabled then return nil end
    return MySQL.scalar.await(
        'SELECT url FROM nz_mdt_photos WHERE subject = ? AND subject_id = ? AND is_avatar = 1 LIMIT 1',
        { subject, tostring(subjectId) })
end

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('nz_mdt:photo:list', function(src, subject, subjectId)
    local session = MDT.getSession(src)
    if not session then return { ok = false, rows = {} } end
    return { ok = true, rows = MDT.getPhotos(subject, subjectId) }
end)

local shooting = {}   -- one capture at a time per officer

lib.callback.register('nz_mdt:photo:take', MDT.guard('photo.take', function(session, subject, subjectId, description)
    if not subjectAllowed(subject) then
        return { ok = false, msg = 'Photos cannot be attached to that.' }
    end
    if shooting[session.source] then return { ok = false, msg = 'Hold on — the last photo is still uploading.' } end

    local ready, why = serviceReady()
    if not ready then return { ok = false, msg = why } end

    local count = MySQL.scalar.await(
        'SELECT COUNT(*) FROM nz_mdt_photos WHERE subject = ? AND subject_id = ?',
        { subject, tostring(subjectId) }) or 0

    if count >= Config.Photos.maxPer then
        return { ok = false, msg = ('That record already holds %s photos.'):format(Config.Photos.maxPer) }
    end

    shooting[session.source] = true
    local ok, url, hostId = pcall(capture, session.source)
    shooting[session.source] = nil
    if not ok then url, hostId = nil, 'The photo did not go through.' end
    if not url then
        return { ok = false, msg = hostId or 'The photo did not go through.' }
    end

    MySQL.insert.await([[
        INSERT INTO nz_mdt_photos (subject, subject_id, url, host_id, description, taken_by, taker_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { subject, tostring(subjectId), url, hostId,
          MDT.clean(description, 200), session.name, session.identifier })

    MDT.audit(session, 'photo.take', subject, subjectId, MDT.clean(description, 60))

    return { ok = true, msg = 'Photo attached.', rows = MDT.getPhotos(subject, subjectId) }
end))

--- Attach a photo by pasting a link, for servers without screenshot-basic.
lib.callback.register('nz_mdt:photo:link', MDT.guard('photo.take', function(session, subject, subjectId, url, description)
    if not subjectAllowed(subject) then
        return { ok = false, msg = 'Photos cannot be attached to that.' }
    end

    url = MDT.clean(url, 400)
    if not url:match('^https?://[%w%-%.]+') then
        return { ok = false, msg = 'Photos need a full https link.' }
    end

    local count = MySQL.scalar.await(
        'SELECT COUNT(*) FROM nz_mdt_photos WHERE subject = ? AND subject_id = ?',
        { subject, tostring(subjectId) }) or 0

    if count >= (Config.Photos.maxPer or 8) then
        return { ok = false, msg = ('That record already holds %s photos.'):format(Config.Photos.maxPer) }
    end

    MySQL.insert.await([[
        INSERT INTO nz_mdt_photos (subject, subject_id, url, description, taken_by, taker_id)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { subject, tostring(subjectId), url, MDT.clean(description, 200), session.name, session.identifier })

    MDT.audit(session, 'photo.link', subject, subjectId, 'Photo linked')
    return { ok = true, msg = 'Photo attached.', rows = MDT.getPhotos(subject, subjectId) }
end))

lib.callback.register('nz_mdt:photo:describe', MDT.guard('photo.take', function(session, id, description)
    local p = MySQL.single.await('SELECT subject, subject_id FROM nz_mdt_photos WHERE id = ?', { tonumber(id) })
    if not p then return { ok = false, msg = 'That photo is gone.' } end

    MySQL.update.await('UPDATE nz_mdt_photos SET description = ? WHERE id = ?',
        { MDT.clean(description, 200), tonumber(id) })

    return { ok = true, msg = 'Caption saved.', rows = MDT.getPhotos(p.subject, p.subject_id) }
end))

--- Mark one photo as the record's picture — a mugshot, a plate shot, a headshot.
lib.callback.register('nz_mdt:photo:avatar', MDT.guard('photo.avatar', function(session, id)
    local p = MySQL.single.await('SELECT subject, subject_id, is_avatar FROM nz_mdt_photos WHERE id = ?',
        { tonumber(id) })
    if not p then return { ok = false, msg = 'That photo is gone.' } end

    if MDT.bool(p.is_avatar) then
        MySQL.update.await('UPDATE nz_mdt_photos SET is_avatar = 0 WHERE id = ?', { tonumber(id) })
        MDT.audit(session, 'photo.avatar.clear', p.subject, p.subject_id, 'Record picture cleared')
        return { ok = true, msg = 'Record picture cleared.', rows = MDT.getPhotos(p.subject, p.subject_id) }
    end

    MySQL.update.await('UPDATE nz_mdt_photos SET is_avatar = 0 WHERE subject = ? AND subject_id = ?',
        { p.subject, p.subject_id })
    MySQL.update.await('UPDATE nz_mdt_photos SET is_avatar = 1 WHERE id = ?', { tonumber(id) })

    -- keep the citizen mugshot column in step so record cards stay quick
    if p.subject == 'citizen' then
        local url = MySQL.scalar.await('SELECT url FROM nz_mdt_photos WHERE id = ?', { tonumber(id) })
        MySQL.update.await('UPDATE nz_mdt_citizens SET mugshot = ? WHERE citizen_id = ?', { url, p.subject_id })
    elseif p.subject == 'vehicle' then
        local url = MySQL.scalar.await('SELECT url FROM nz_mdt_photos WHERE id = ?', { tonumber(id) })
        MySQL.update.await('UPDATE nz_mdt_vehicles SET photo = ? WHERE plate = ?', { url, p.subject_id })
    end

    MDT.audit(session, 'photo.avatar', p.subject, p.subject_id, 'Record picture set')
    return { ok = true, msg = 'Set as the record picture.', rows = MDT.getPhotos(p.subject, p.subject_id) }
end))

lib.callback.register('nz_mdt:photo:delete', MDT.guard('photo.delete', function(session, id)
    local p = MySQL.single.await('SELECT subject, subject_id, is_avatar FROM nz_mdt_photos WHERE id = ?',
        { tonumber(id) })
    if not p then return { ok = false, msg = 'That photo is gone already.' } end

    MySQL.update.await('DELETE FROM nz_mdt_photos WHERE id = ?', { tonumber(id) })

    if MDT.bool(p.is_avatar) then
        if p.subject == 'citizen' then
            MySQL.update.await('UPDATE nz_mdt_citizens SET mugshot = NULL WHERE citizen_id = ?', { p.subject_id })
        elseif p.subject == 'vehicle' then
            MySQL.update.await('UPDATE nz_mdt_vehicles SET photo = NULL WHERE plate = ?', { p.subject_id })
        end
    end

    MDT.audit(session, 'photo.delete', p.subject, p.subject_id, 'Photo removed')
    return { ok = true, msg = 'Photo removed.', rows = MDT.getPhotos(p.subject, p.subject_id) }
end))

--- So the UI can grey the button out with a reason instead of failing silently.
lib.callback.register('nz_mdt:photo:status', function(src)
    local ready, why = serviceReady()
    return { ok = true, ready = ready, reason = why }
end)
