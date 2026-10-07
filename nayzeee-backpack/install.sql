-- Only needed if Config.Placement.persist = true

CREATE TABLE IF NOT EXISTS `nayzeee_placed_bags` (
    `id`        INT NOT NULL,
    `bag`       VARCHAR(64) NOT NULL,
    `metadata`  LONGTEXT DEFAULT NULL,
    `x`         FLOAT NOT NULL,
    `y`         FLOAT NOT NULL,
    `z`         FLOAT NOT NULL,
    `heading`   FLOAT NOT NULL DEFAULT 0,
    `owner`     VARCHAR(64) DEFAULT NULL,
    `variant`   INT DEFAULT 0,
    `access`    VARCHAR(16) NOT NULL DEFAULT 'private',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
