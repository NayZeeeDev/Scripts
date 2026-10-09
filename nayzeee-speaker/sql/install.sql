-- Tables are also created automatically on first start.
CREATE TABLE IF NOT EXISTS `nayzeee_speaker_tracks` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(80)  NOT NULL,
    `list`       ENUM('fav','recent') NOT NULL,
    `track_key`  VARCHAR(180) NOT NULL,
    `data`       LONGTEXT     NOT NULL,
    `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_track` (`identifier`, `list`, `track_key`),
    KEY `idx_owner` (`identifier`, `list`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nayzeee_speaker_carplay` (
    `plate`        VARCHAR(16) NOT NULL,
    `installed_by` VARCHAR(80) NULL,
    `installed_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nayzeee_speaker_vinyls` (
    `item`       VARCHAR(64) NOT NULL,
    `data`       LONGTEXT    NOT NULL,
    `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nayzeee_speaker_playlists` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner`      VARCHAR(80)  NOT NULL,
    `owner_name` VARCHAR(80)  NULL,
    `name`       VARCHAR(60)  NOT NULL,
    `shared`     TINYINT(1)   NOT NULL DEFAULT 0,
    `tracks`        LONGTEXT     NOT NULL,
    `kind`          VARCHAR(16)  NOT NULL DEFAULT 'normal',
    `collaborators` LONGTEXT     NULL,
    `mixed`         TINYINT(1)   NOT NULL DEFAULT 0,
    `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_owner` (`owner`),
    KEY `idx_shared` (`shared`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
