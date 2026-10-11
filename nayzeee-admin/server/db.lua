local schema = {
[[CREATE TABLE IF NOT EXISTS `nz_admin_groups` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `label` VARCHAR(64) NOT NULL,
  `color` VARCHAR(9) NOT NULL DEFAULT '#08afa2',
  `hierarchy` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `permissions` LONGTEXT NOT NULL,
  `discord_role` VARCHAR(32) DEFAULT NULL,
  `outfit` LONGTEXT DEFAULT NULL,
  `sprite` INT UNSIGNED NOT NULL DEFAULT 280,
  PRIMARY KEY (`id`), UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_members` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `license` VARCHAR(64) NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `nickname` VARCHAR(64) DEFAULT NULL,
  `group_name` VARCHAR(64) NOT NULL,
  `discord` VARCHAR(32) DEFAULT NULL,
  `total_duty` INT UNSIGNED NOT NULL DEFAULT 0,
  `last_seen` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), UNIQUE KEY `license` (`license`), KEY `group_name` (`group_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_duty` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `license` VARCHAR(64) NOT NULL,
  `started` DATETIME NOT NULL,
  `ended` DATETIME NOT NULL,
  `seconds` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`), KEY `lic_start` (`license`, `started`), KEY `started` (`started`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_bans` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(128) NOT NULL,
  `license` VARCHAR(64) NOT NULL,
  `identifiers` LONGTEXT NOT NULL,
  `tokens` LONGTEXT NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `staff_name` VARCHAR(64) NOT NULL DEFAULT 'System',
  `staff_license` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `license` (`license`), KEY `active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_warnings` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `license` VARCHAR(64) NOT NULL,
  `name` VARCHAR(128) NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `staff_name` VARCHAR(64) NOT NULL,
  `staff_license` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_notes` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `license` VARCHAR(64) NOT NULL,
  `text` TEXT NOT NULL,
  `staff_name` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_flags` (
  `license` VARCHAR(64) NOT NULL,
  `flag` VARCHAR(32) NOT NULL,
  `staff_name` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`license`, `flag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_jail` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `char_id` VARCHAR(64) NOT NULL,
  `license` VARCHAR(64) NOT NULL,
  `name` VARCHAR(128) NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `cell` VARCHAR(64) NOT NULL,
  `last_coords` VARCHAR(128) DEFAULT NULL,
  `time_mode` VARCHAR(10) NOT NULL DEFAULT 'playtime',
  `duration` INT UNSIGNED NOT NULL,
  `remaining` INT UNSIGNED NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `staff_name` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), UNIQUE KEY `char_id` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `category` VARCHAR(24) NOT NULL,
  `action` VARCHAR(48) NOT NULL,
  `staff_name` VARCHAR(64) DEFAULT NULL,
  `staff_license` VARCHAR(64) DEFAULT NULL,
  `target_name` VARCHAR(128) DEFAULT NULL,
  `target_license` VARCHAR(64) DEFAULT NULL,
  `message` TEXT NOT NULL,
  `x` FLOAT DEFAULT NULL, `y` FLOAT DEFAULT NULL, `z` FLOAT DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `cat_time` (`category`, `created_at`), KEY `target` (`target_license`), KEY `staff` (`staff_license`), KEY `created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_chats` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `label` VARCHAR(96) NOT NULL,
  `is_report` TINYINT(1) NOT NULL DEFAULT 0,
  `category` VARCHAR(48) DEFAULT NULL,
  `author_license` VARCHAR(64) DEFAULT NULL,
  `author_name` VARCHAR(128) DEFAULT NULL,
  `status` VARCHAR(12) NOT NULL DEFAULT 'open',
  `claimed_license` VARCHAR(64) DEFAULT NULL,
  `claimed_name` VARCHAR(64) DEFAULT NULL,
  `groups` LONGTEXT DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `report_status` (`is_report`, `status`), KEY `author` (`author_license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_messages` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `chat_id` INT UNSIGNED NOT NULL,
  `author_license` VARCHAR(64) NOT NULL,
  `author_name` VARCHAR(128) NOT NULL,
  `is_staff` TINYINT(1) NOT NULL DEFAULT 0,
  `message` TEXT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `chat` (`chat_id`),
  CONSTRAINT `nz_admin_msg_chat` FOREIGN KEY (`chat_id`) REFERENCES `nz_admin_chats` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_players` (
  `license` VARCHAR(64) NOT NULL,
  `name` VARCHAR(128) NOT NULL,
  `discord` VARCHAR(32) DEFAULT NULL,
  `first_seen` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `playtime` INT UNSIGNED NOT NULL DEFAULT 0,
  `sessions` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`license`), KEY `first_seen` (`first_seen`), KEY `last_seen` (`last_seen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_stats` (
  `ts` INT UNSIGNED NOT NULL,
  `players` SMALLINT UNSIGNED NOT NULL,
  `staff` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_props` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `type` VARCHAR(8) NOT NULL DEFAULT 'object',
  `model` VARCHAR(64) NOT NULL,
  `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
  `rx` FLOAT NOT NULL DEFAULT 0, `ry` FLOAT NOT NULL DEFAULT 0, `rz` FLOAT NOT NULL DEFAULT 0,
  `frozen` TINYINT(1) NOT NULL DEFAULT 1,
  `collision` TINYINT(1) NOT NULL DEFAULT 1,
  `anim` VARCHAR(96) DEFAULT NULL,
  `created_by` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_zones` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `points` LONGTEXT NOT NULL,
  `thickness` FLOAT NOT NULL DEFAULT 10,
  `handler` VARCHAR(48) DEFAULT NULL,
  `color` VARCHAR(9) NOT NULL DEFAULT '#08afa2',
  `debug` TINYINT(1) NOT NULL DEFAULT 0,
  `options` LONGTEXT DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_blips` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `label` VARCHAR(64) NOT NULL,
  `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
  `sprite` INT UNSIGNED NOT NULL DEFAULT 1,
  `color` INT UNSIGNED NOT NULL DEFAULT 0,
  `scale` FLOAT NOT NULL DEFAULT 0.8,
  `display` TINYINT UNSIGNED NOT NULL DEFAULT 4,
  `short_range` TINYINT(1) NOT NULL DEFAULT 1,
  `category` VARCHAR(48) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS `nz_admin_events` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(96) NOT NULL,
  `description` TEXT NOT NULL,
  `date` DATETIME NOT NULL,
  `author` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

function NZ.InstallSchema()
    if not Config.AutoInstallSQL then return end
    for _, q in ipairs(schema) do
        local ok, err = pcall(MySQL.query.await, q)
        if not ok then print('^1[nayzeee-admin] SQL error:^7 ' .. tostring(err)) end
    end
    -- seed default groups once
    if (MySQL.scalar.await('SELECT COUNT(*) FROM nz_admin_groups') or 0) == 0 then
        for _, g in ipairs(Config.DefaultGroups) do
            MySQL.insert.await('INSERT INTO nz_admin_groups (name, label, color, hierarchy, permissions) VALUES (?, ?, ?, ?, ?)',
                { g.name, g.label, g.color, g.hierarchy, json.encode(g.permissions) })
        end
        print('^6[nayzeee-admin]^7 default staff groups created')
    end
end
