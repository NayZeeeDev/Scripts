--[[ Persistence: one JSON document per character + the shared product registry ]]

DB = {}

local ready = promise.new()

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_drugempire` (
            `identifier` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NOT NULL,
            `updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_drugempire_products` (
            `id` VARCHAR(16) NOT NULL,
            `mixkey` VARCHAR(255) NOT NULL,
            `base` VARCHAR(32) NOT NULL,
            `name` VARCHAR(64) NOT NULL,
            `effects` TEXT NOT NULL,
            `creator` VARCHAR(64) NULL,
            `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `mixkey` (`mixkey`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    ready:resolve(true)
end)

function DB.await()
    Citizen.Await(ready)
end

function DB.load(identifier)
    DB.await()
    local row = MySQL.single.await('SELECT `data` FROM `nayzeee_drugempire` WHERE `identifier` = ?', { identifier })
    if not row then return nil end
    local ok, data = pcall(json.decode, row.data)
    return ok and data or nil
end

function DB.save(identifier, data)
    MySQL.prepare('INSERT INTO `nayzeee_drugempire` (`identifier`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
        { identifier, json.encode(data) })
end

function DB.delete(identifier)
    MySQL.prepare('DELETE FROM `nayzeee_drugempire` WHERE `identifier` = ?', { identifier })
end

function DB.products()
    DB.await()
    return MySQL.query.await('SELECT `id`, `mixkey`, `base`, `name`, `effects`, `creator` FROM `nayzeee_drugempire_products`') or {}
end

function DB.addProduct(p)
    MySQL.insert('INSERT IGNORE INTO `nayzeee_drugempire_products` (`id`, `mixkey`, `base`, `name`, `effects`, `creator`) VALUES (?, ?, ?, ?, ?, ?)',
        { p.id, p.key, p.base, p.name, json.encode(p.effects), p.creator })
end
