-- Optional: the resource creates these itself on start when oxmysql is running.
CREATE TABLE IF NOT EXISTS `cutup_players` (
    `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `data` LONGTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `cutup_crews` (
    `id` INT NOT NULL PRIMARY KEY,
    `data` LONGTEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS `cutup_runs` (
    `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(64) NOT NULL,
    `points` BIGINT NOT NULL,
    `crew_run` TINYINT(1) NOT NULL DEFAULT 0,
    `data` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`identifier`),
    INDEX (`points`)
);
