-- Aicore database schema. The core also creates these automatically on
-- first start (see server/storage.lua ensureSchema), so this file is for
-- review and manual setup.

CREATE TABLE IF NOT EXISTS `players` (
    `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `user_id` int UNSIGNED DEFAULT NULL,
    `license` varchar(50) DEFAULT NULL,
    `name` varchar(100) DEFAULT NULL,
    `cash` int NOT NULL DEFAULT 0,
    `bank` int NOT NULL DEFAULT 0,
    `position` text,
    `vitals` text,
    `metadata` text,
    `job` text,
    `gang` text,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_citizenid` (`citizenid`),
    KEY `idx_license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bans` (
    `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` varchar(60) NOT NULL,
    `reason` varchar(255) DEFAULT NULL,
    `expire` int UNSIGNED NOT NULL DEFAULT 0,
    `banned_by` varchar(100) DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
