-- nayzeee-coinshop · tables are created automatically on first start. Run this only if your database user cannot CREATE tables.

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_wallets (
        identifier VARCHAR(80) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        spent INT NOT NULL DEFAULT 0,
        name VARCHAR(100) DEFAULT NULL,
        playtime_day DATE DEFAULT NULL,
        playtime_coins INT NOT NULL DEFAULT 0,
        updated TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_items (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description VARCHAR(500) NOT NULL DEFAULT '',
        category VARCHAR(16) NOT NULL DEFAULT 'item',
        tags TEXT,
        price INT NOT NULL DEFAULT 0,
        sale_price INT DEFAULT NULL,
        sale_ends TIMESTAMP NULL DEFAULT NULL,
        images TEXT,
        spawn_name VARCHAR(60) DEFAULT NULL,
        item_name VARCHAR(60) DEFAULT NULL,
        item_count INT NOT NULL DEFAULT 1,
        weapon_name VARCHAR(60) DEFAULT NULL,
        trending TINYINT(1) NOT NULL DEFAULT 0,
        custom_category VARCHAR(60) DEFAULT NULL,
        stock INT DEFAULT NULL,
        player_limit INT DEFAULT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        sort INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_categories (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        icon VARCHAR(500) NOT NULL DEFAULT '',
        type VARCHAR(16) DEFAULT NULL,
        sort INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_deals (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description VARCHAR(500) NOT NULL DEFAULT '',
        price INT NOT NULL DEFAULT 0,
        image VARCHAR(500) NOT NULL DEFAULT '',
        items TEXT,
        stock INT DEFAULT NULL,
        player_limit INT DEFAULT NULL,
        cash INT NOT NULL DEFAULT 0,
        featured TINYINT(1) NOT NULL DEFAULT 1,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        sort INT NOT NULL DEFAULT 0,
        expires_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_codes (
        id INT NOT NULL AUTO_INCREMENT,
        tbx_id VARCHAR(120) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'pending',
        source VARCHAR(16) NOT NULL DEFAULT 'tebex',
        redeemed_by VARCHAR(80) DEFAULT NULL,
        redeemed_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_tbx (tbx_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_promos (
        code VARCHAR(40) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        max_uses INT NOT NULL DEFAULT 0,
        uses INT NOT NULL DEFAULT 0,
        expires_at TIMESTAMP NULL DEFAULT NULL,
        created_by VARCHAR(100) DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_promo_uses (
        code VARCHAR(40) NOT NULL,
        identifier VARCHAR(80) NOT NULL,
        used_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (code, identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_purchases (
        id INT NOT NULL AUTO_INCREMENT,
        identifier VARCHAR(80) NOT NULL,
        player VARCHAR(100) DEFAULT NULL,
        kind VARCHAR(8) NOT NULL DEFAULT 'item',
        item_id VARCHAR(60) NOT NULL,
        item_name VARCHAR(100) DEFAULT NULL,
        quantity INT NOT NULL DEFAULT 1,
        price INT NOT NULL,
        gifted_to VARCHAR(80) DEFAULT NULL,
        gifted_name VARCHAR(100) DEFAULT NULL,
        plate VARCHAR(12) DEFAULT NULL,
        refunded TINYINT(1) NOT NULL DEFAULT 0,
        purchased_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_identifier (identifier, purchased_at),
        KEY k_item (item_id),
        KEY k_date (purchased_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_ledger (
        id INT NOT NULL AUTO_INCREMENT,
        identifier VARCHAR(80) NOT NULL,
        delta INT NOT NULL,
        balance INT NOT NULL,
        reason VARCHAR(24) NOT NULL,
        note VARCHAR(160) DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_identifier (identifier, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_favorites (
        identifier VARCHAR(80) NOT NULL,
        item_id VARCHAR(60) NOT NULL,
        PRIMARY KEY (identifier, item_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nayzeee_coinshop_settings (
        `key` VARCHAR(50) NOT NULL,
        `value` TEXT NOT NULL,
        PRIMARY KEY (`key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
