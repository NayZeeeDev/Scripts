-- nayzeee-television
-- These tables are created automatically on first start (when oxmysql is running).
-- Import manually only if your DB user can't CREATE.

CREATE TABLE IF NOT EXISTS `nayzeee_tv_screens` (
  `id`         VARCHAR(16) NOT NULL PRIMARY KEY,
  `data`       LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_tv_favorites` (
  `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
  `data`       LONGTEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
