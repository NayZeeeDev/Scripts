-- nayzeee-squads schema — OPTIONAL.
-- The resource creates and upgrades these tables by itself on start, so you normally never run this.
-- It's here for servers whose database user can't create tables: run it once by hand, then restart.

CREATE TABLE IF NOT EXISTS `nz_squads` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`         VARCHAR(32)  NOT NULL,
  `tag`          VARCHAR(8)   DEFAULT NULL,
  `image`        VARCHAR(300) DEFAULT NULL,
  `description`  VARCHAR(160) DEFAULT NULL,
  `motd`         VARCHAR(255) DEFAULT NULL,
  `blip_color`   SMALLINT UNSIGNED NOT NULL DEFAULT 2,
  `blip_sprite`  SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `password`     VARCHAR(64)  DEFAULT NULL,
  `invite_only`  TINYINT(1)   NOT NULL DEFAULT 0,
  `member_limit` TINYINT UNSIGNED NOT NULL DEFAULT 8,
  `owner`        VARCHAR(64)  NOT NULL,
  `ranks`        TEXT         DEFAULT NULL,
  `elo`          SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
  `wins`         INT UNSIGNED NOT NULL DEFAULT 0,
  `losses`       INT UNSIGNED NOT NULL DEFAULT 0,
  `draws`        INT UNSIGNED NOT NULL DEFAULT 0,
  `kills`        INT UNSIGNED NOT NULL DEFAULT 0,
  `deaths`       INT UNSIGNED NOT NULL DEFAULT 0,
  `assists`      INT UNSIGNED NOT NULL DEFAULT 0,
  `created`      INT UNSIGNED NOT NULL,
  `last_active`  INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_name` (`name`),
  UNIQUE KEY `uq_tag` (`tag`),
  KEY `idx_elo` (`elo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_squad_members` (
  `squad_id`   INT UNSIGNED NOT NULL,
  `identifier` VARCHAR(64)  NOT NULL,
  `name`       VARCHAR(64)  NOT NULL,
  `nick`       VARCHAR(24)  DEFAULT NULL,
  `rank`       TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `kills`      INT UNSIGNED NOT NULL DEFAULT 0,
  `deaths`     INT UNSIGNED NOT NULL DEFAULT 0,
  `assists`    INT UNSIGNED NOT NULL DEFAULT 0,
  `revives`    INT UNSIGNED NOT NULL DEFAULT 0,
  `playtime`   INT UNSIGNED NOT NULL DEFAULT 0,
  `joined`     INT UNSIGNED NOT NULL,
  `last_seen`  INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`squad_id`, `identifier`),
  KEY `idx_identifier` (`identifier`),
  CONSTRAINT `fk_nz_member_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_squad_allies` (
  `squad_id` INT UNSIGNED NOT NULL,
  `ally_id`  INT UNSIGNED NOT NULL,
  `created`  INT UNSIGNED NOT NULL,
  PRIMARY KEY (`squad_id`, `ally_id`),
  KEY `idx_ally` (`ally_id`),
  CONSTRAINT `fk_nz_ally_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_nz_ally_other` FOREIGN KEY (`ally_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_squad_matches` (
  `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `squad_a`  INT UNSIGNED NOT NULL,
  `squad_b`  INT UNSIGNED NOT NULL,
  `name_a`   VARCHAR(32) NOT NULL,
  `name_b`   VARCHAR(32) NOT NULL,
  `kills_a`  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `kills_b`  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `delta_a`  SMALLINT NOT NULL DEFAULT 0,
  `delta_b`  SMALLINT NOT NULL DEFAULT 0,
  `winner`   INT UNSIGNED DEFAULT NULL,
  `ended`    INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_a` (`squad_a`),
  KEY `idx_b` (`squad_b`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_squad_log` (
  `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `squad_id` INT UNSIGNED NOT NULL,
  `kind`     VARCHAR(16)  NOT NULL,
  `text`     VARCHAR(200) NOT NULL,
  `at`       INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_squad` (`squad_id`, `id`),
  CONSTRAINT `fk_nz_log_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
