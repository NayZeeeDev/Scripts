--[[ Persistence: oxmysql when available, JSON files otherwise ]]

Storage = { mode = 'json' }

local RES = GetCurrentResourceName()
local screensJson, favoritesJson = {}, {}
local dirtyScreens, dirtyFavs = false, false

local function readJson(path)
    local raw = LoadResourceFile(RES, path)
    if not raw or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    return ok and data or {}
end

local function writeJson(path, data)
    SaveResourceFile(RES, path, json.encode(data, { indent = true }), -1)
end

local function sqlAwait(query, params)
    local p = promise.new()
    exports.oxmysql:query(query, params or {}, function(result) p:resolve(result or {}) end)
    return Citizen.Await(p)
end

function Storage.init()
    local mode = Config.Storage
    if mode == 'auto' then mode = GetResourceState('oxmysql') == 'started' and 'oxmysql' or 'json' end
    Storage.mode = mode

    if mode == 'oxmysql' then
        sqlAwait([[CREATE TABLE IF NOT EXISTS `nayzeee_tv_screens` (
            `id` VARCHAR(16) NOT NULL PRIMARY KEY,
            `data` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )]])
        sqlAwait([[CREATE TABLE IF NOT EXISTS `nayzeee_tv_favorites` (
            `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
            `data` LONGTEXT NOT NULL
        )]])
    else
        screensJson = readJson('data/screens.json')
        favoritesJson = readJson('data/favorites.json')
    end
    print(('^2[nayzeee-television]^7 storage: ^5%s^7'):format(mode))
end

function Storage.loadScreens()
    local out = {}
    if Storage.mode == 'oxmysql' then
        for _, row in ipairs(sqlAwait('SELECT `data` FROM `nayzeee_tv_screens`')) do
            local ok, data = pcall(json.decode, row.data)
            if ok and data and data.id then out[#out + 1] = data end
        end
    else
        for _, data in pairs(screensJson) do out[#out + 1] = data end
    end
    return out
end

function Storage.saveScreen(record)
    if Storage.mode == 'oxmysql' then
        exports.oxmysql:query('INSERT INTO `nayzeee_tv_screens` (`id`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
            { record.id, json.encode(record) })
    else
        screensJson[record.id] = record
        dirtyScreens = true
    end
end

function Storage.deleteScreen(id)
    if Storage.mode == 'oxmysql' then
        exports.oxmysql:query('DELETE FROM `nayzeee_tv_screens` WHERE `id` = ?', { id })
    else
        screensJson[id] = nil
        dirtyScreens = true
    end
end

local favCache = {}
function Storage.getFavorites(identifier)
    if favCache[identifier] then return favCache[identifier] end
    local list = {}
    if Storage.mode == 'oxmysql' then
        local rows = sqlAwait('SELECT `data` FROM `nayzeee_tv_favorites` WHERE `identifier` = ?', { identifier })
        if rows[1] then
            local ok, data = pcall(json.decode, rows[1].data)
            if ok and type(data) == 'table' then list = data end
        end
    else
        list = favoritesJson[identifier] or {}
    end
    favCache[identifier] = list
    return list
end

function Storage.setFavorites(identifier, list)
    favCache[identifier] = list
    if Storage.mode == 'oxmysql' then
        exports.oxmysql:query('INSERT INTO `nayzeee_tv_favorites` (`identifier`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
            { identifier, json.encode(list) })
    else
        favoritesJson[identifier] = list
        dirtyFavs = true
    end
end

function Storage.loadCalibration()
    return readJson('data/calibration.json')
end

function Storage.saveCalibration(data)
    writeJson('data/calibration.json', data)
end

-- debounced JSON writes
CreateThread(function()
    while true do
        Wait(4000)
        if dirtyScreens then dirtyScreens = false writeJson('data/screens.json', screensJson) end
        if dirtyFavs then dirtyFavs = false writeJson('data/favorites.json', favoritesJson) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES or Storage.mode ~= 'json' then return end
    if dirtyScreens then writeJson('data/screens.json', screensJson) end
    if dirtyFavs then writeJson('data/favorites.json', favoritesJson) end
end)
