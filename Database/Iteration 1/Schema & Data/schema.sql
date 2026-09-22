-- ============================================================
-- Household Inventory Reminder System
-- MySQL Database Schema (schema.sql)
--
-- Target database : MySQL 8.0+ (InnoDB, utf8mb4)
-- Tables          : 12 (users, teams, team_members, join_requests,
--                    product_categories, products, storage_types,
--                    inventory_items, inventory_transactions,
--                    shelf_life_rules, reminders, notification_recipients)
--
-- This script is idempotent: it drops existing tables (reverse
-- dependency order) and recreates them from scratch.
-- ============================================================

CREATE DATABASE IF NOT EXISTS `Real_ProjectV1.0_TM06`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `Real_ProjectV1.0_TM06`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Drop tables in reverse dependency order for a clean rebuild.
DROP TABLE IF EXISTS notification_recipients;
DROP TABLE IF EXISTS reminders;
DROP TABLE IF EXISTS shelf_life_rules;
DROP TABLE IF EXISTS inventory_transactions;
DROP TABLE IF EXISTS inventory_items;
DROP TABLE IF EXISTS storage_types;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS product_categories;
DROP TABLE IF EXISTS join_requests;
DROP TABLE IF EXISTS team_members;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS users;

SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------
-- 1. users
--    Registered users of the system.
-- ------------------------------------------------------------
CREATE TABLE users (
  user_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)    NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,
  display_name  VARCHAR(100)    NOT NULL,
  avatar_id     INT UNSIGNED    NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 2. teams
--    Households or teams that share inventory.
--    There is deliberately no created_by column; the team admin
--    is identified by team_members.role = 'ADMIN'.
-- ------------------------------------------------------------
CREATE TABLE teams (
  team_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_name  VARCHAR(100)    NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (team_id),
  KEY idx_teams_team_name (team_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 3. team_members
--    Membership of users in teams. Roles are ADMIN or MEMBER only.
-- ------------------------------------------------------------
CREATE TABLE team_members (
  team_id   BIGINT UNSIGNED NOT NULL,
  user_id   BIGINT UNSIGNED NOT NULL,
  role      ENUM('ADMIN','MEMBER') NOT NULL DEFAULT 'MEMBER',
  status    ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (team_id, user_id),
  KEY idx_team_members_user_id (user_id),
  CONSTRAINT fk_team_members_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_team_members_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 4. join_requests
--    Requests from users to join a team.
--    MySQL has no partial unique index, so the rule "one PENDING
--    request per (team_id, user_id)" is enforced by the application
--    layer before insertion, not by a database constraint.
-- ------------------------------------------------------------
CREATE TABLE join_requests (
  request_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id      BIGINT UNSIGNED NOT NULL,
  user_id      BIGINT UNSIGNED NOT NULL,
  status       ENUM('PENDING','APPROVED','DECLINED') NOT NULL DEFAULT 'PENDING',
  requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at  DATETIME NULL,
  reviewed_by  BIGINT UNSIGNED NULL,
  PRIMARY KEY (request_id),
  KEY idx_join_requests_team_status (team_id, status),
  KEY idx_join_requests_user_status (user_id, status),
  KEY idx_join_requests_requested_at (requested_at),
  CONSTRAINT fk_join_requests_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_join_requests_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_join_requests_reviewed_by FOREIGN KEY (reviewed_by)
    REFERENCES users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 5. product_categories
--    Fixed set of categories that products belong to.
-- ------------------------------------------------------------
CREATE TABLE product_categories (
  category_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_name VARCHAR(100) NOT NULL,
  is_fresh_food BOOLEAN      NOT NULL DEFAULT FALSE,
  description   VARCHAR(500) NULL,
  PRIMARY KEY (category_id),
  UNIQUE KEY uq_product_categories_name (category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 6. products
--    Catalogue of products. Barcode is optional but unique.
-- ------------------------------------------------------------
CREATE TABLE products (
  product_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id   INT UNSIGNED    NOT NULL,
  product_name  VARCHAR(255)    NOT NULL,
  barcode       VARCHAR(50)     NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (product_id),
  UNIQUE KEY uq_products_barcode (barcode),
  KEY idx_products_name (product_name),
  CONSTRAINT fk_products_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 7. storage_types
--    Where items are stored: fridge, freezer or pantry.
-- ------------------------------------------------------------
CREATE TABLE storage_types (
  storage_type_id TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  storage_name    ENUM('FRIDGE','FREEZER','PANTRY') NOT NULL,
  description     VARCHAR(500) NULL,
  PRIMARY KEY (storage_type_id),
  UNIQUE KEY uq_storage_types_name (storage_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 8. inventory_items
--    Stock entries owned by a team for a product at a storage place.
-- ------------------------------------------------------------
CREATE TABLE inventory_items (
  inventory_item_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id           BIGINT UNSIGNED NOT NULL,
  product_id        BIGINT UNSIGNED NOT NULL,
  storage_type_id   TINYINT UNSIGNED NOT NULL,
  created_by        BIGINT UNSIGNED NOT NULL,
  quantity          DECIMAL(10,2)    NOT NULL,
  unit              VARCHAR(20)      NOT NULL DEFAULT 'pcs',
  notes             VARCHAR(500)     NULL,
  production_date   DATE             NULL,
  purchase_date     DATE             NOT NULL,
  entry_date        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  shelf_life_days   INT UNSIGNED     NULL,
  expiry_date       DATE             NULL,
  expiry_date_source ENUM('PACKAGING','USER_INPUT','CALCULATED') NOT NULL,
  checkout_date     DATETIME         NULL,
  status            ENUM('IN_STOCK','CONSUMED','EXPIRED','DISCARDED','DONATED') NOT NULL DEFAULT 'IN_STOCK',
  discard_reason    VARCHAR(30)      NULL,
  consumed_amount   VARCHAR(20)      NULL,
  created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (inventory_item_id),
  CONSTRAINT chk_inventory_items_quantity CHECK (quantity > 0),
  CONSTRAINT chk_inventory_items_shelf_life_days CHECK (shelf_life_days >= 0),
  KEY idx_inventory_items_team (team_id),
  KEY idx_inventory_items_team_status (team_id, status),
  KEY idx_inventory_items_team_expiry (team_id, expiry_date),
  KEY idx_inventory_items_team_storage (team_id, storage_type_id),
  KEY idx_inventory_items_team_product (team_id, product_id),
  KEY idx_inventory_items_created_by (created_by),
  KEY idx_inventory_items_entry_date (entry_date),
  CONSTRAINT fk_inventory_items_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_inventory_items_product FOREIGN KEY (product_id)
    REFERENCES products (product_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_items_storage FOREIGN KEY (storage_type_id)
    REFERENCES storage_types (storage_type_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_items_created_by FOREIGN KEY (created_by)
    REFERENCES users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 9. inventory_transactions
--    Audit trail of ADD / CONSUME / DISCARD operations.
--    discard_reason must be non-NULL only for DISCARD transactions.
-- ------------------------------------------------------------
CREATE TABLE inventory_transactions (
  transaction_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inventory_item_id BIGINT UNSIGNED NOT NULL,
  user_id           BIGINT UNSIGNED NOT NULL,
  transaction_type  ENUM('ADD','CONSUME','DISCARD','DONATE') NOT NULL,
  quantity          DECIMAL(10,2)   NOT NULL,
  transaction_time  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  note              VARCHAR(500)    NULL,
  discard_reason    ENUM('EXPIRED','USER_DISCARDED') NULL,
  PRIMARY KEY (transaction_id),
  CONSTRAINT chk_inventory_transactions_quantity CHECK (quantity > 0),
  CONSTRAINT chk_inventory_transactions_discard_reason CHECK (
    (transaction_type = 'DISCARD' AND discard_reason IS NOT NULL)
    OR (transaction_type <> 'DISCARD' AND discard_reason IS NULL)
  ),
  KEY idx_inventory_transactions_item_time (inventory_item_id, transaction_time),
  KEY idx_inventory_transactions_user_time (user_id, transaction_time),
  CONSTRAINT fk_inventory_transactions_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items (inventory_item_id) ON DELETE CASCADE,
  CONSTRAINT fk_inventory_transactions_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 10. shelf_life_rules
--     Shelf-life rules with evidence metadata. Supports both
--     product-level rules (product_id NOT NULL) and category-level
--     fallback rules (product_id IS NULL).
-- ------------------------------------------------------------
CREATE TABLE shelf_life_rules (
  rule_id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id             INT UNSIGNED    NOT NULL,
  product_id              BIGINT UNSIGNED NULL,
  storage_type_id         TINYINT UNSIGNED NOT NULL,
  min_days                INT UNSIGNED    NOT NULL,
  max_days                INT UNSIGNED    NOT NULL,
  recommended_days        DECIMAL(5,1)    NULL,
  rule_status             ENUM('AVAILABLE','QUALITATIVE_ONLY','NOT_RECOMMENDED') NOT NULL DEFAULT 'AVAILABLE',
  confidence              ENUM('HIGH','MEDIUM','LOW') NULL,
  evidence_classification VARCHAR(50)     NULL,
  source_name             VARCHAR(255)    NOT NULL,
  source_url              VARCHAR(500)    NULL,
  source_locator          VARCHAR(500)    NULL,
  source_value_text       TEXT            NULL,
  handling_notes          TEXT            NULL,
  created_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (rule_id),
  UNIQUE KEY unique_product_storage (product_id, storage_type_id),
  CONSTRAINT chk_shelf_life_rules_min_days CHECK (min_days >= 0),
  CONSTRAINT chk_shelf_life_rules_max_days CHECK (max_days >= min_days),
  CONSTRAINT fk_shelf_life_rules_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE CASCADE,
  CONSTRAINT fk_shelf_life_rules_product FOREIGN KEY (product_id)
    REFERENCES products (product_id) ON DELETE CASCADE,
  CONSTRAINT fk_shelf_life_rules_storage FOREIGN KEY (storage_type_id)
    REFERENCES storage_types (storage_type_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 11. reminders
--     Expiry reminders for inventory items. lead_time_days is not
--     hard-coded; it defaults to 3 but supports any value >= 0.
-- ------------------------------------------------------------
CREATE TABLE reminders (
  reminder_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inventory_item_id BIGINT UNSIGNED NOT NULL,
  team_id           BIGINT UNSIGNED NOT NULL,
  created_by        BIGINT UNSIGNED NOT NULL,
  lead_time_days    INT UNSIGNED    NOT NULL DEFAULT 3,
  reminder_at       DATETIME        NOT NULL,
  status            ENUM('PENDING','TRIGGERED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cancelled_at      DATETIME        NULL,
  PRIMARY KEY (reminder_id),
  CONSTRAINT chk_reminders_lead_time_days CHECK (lead_time_days >= 0),
  KEY idx_reminders_team_status_time (team_id, status, reminder_at),
  KEY idx_reminders_inventory_item (inventory_item_id),
  KEY idx_reminders_reminder_at (reminder_at),
  CONSTRAINT fk_reminders_inventory_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items (inventory_item_id) ON DELETE CASCADE,
  CONSTRAINT fk_reminders_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_reminders_created_by FOREIGN KEY (created_by)
    REFERENCES users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 12. notification_recipients
--     Users notified for a reminder, with per-user read state.
-- ------------------------------------------------------------
CREATE TABLE notification_recipients (
  reminder_id BIGINT UNSIGNED NOT NULL,
  user_id     BIGINT UNSIGNED NOT NULL,
  is_read     BOOLEAN         NOT NULL DEFAULT FALSE,
  read_at     DATETIME        NULL,
  PRIMARY KEY (reminder_id, user_id),
  KEY idx_notification_recipients_user_read (user_id, is_read),
  CONSTRAINT fk_notification_recipients_reminder FOREIGN KEY (reminder_id)
    REFERENCES reminders (reminder_id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_recipients_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- MIGRATION NOTE (existing databases only)
-- The fresh schema above already includes the unit and notes
-- columns. Backend teams upgrading a database created before this
-- change should execute the following ALTER statements once:
--
--   ALTER TABLE inventory_items
--     ADD COLUMN unit VARCHAR(20) NOT NULL DEFAULT 'pcs' AFTER quantity;
--
--   ALTER TABLE inventory_items
--     ADD COLUMN notes VARCHAR(500) NULL AFTER unit;
--
-- These statements must NOT be re-run on a database that already
-- contains the columns, because duplicate columns would be rejected.
-- ============================================================

-- ============================================================
-- MIGRATION NOTE (existing databases only) - DONATION FIELDS
-- The fresh schema above already includes the DONATED status, the
-- DONATE transaction type and the two extra inventory_item columns.
-- Backend teams upgrading a database created before this change
-- should execute the following ALTER statements once:
--
--   ALTER TABLE inventory_items
--     MODIFY COLUMN status
--       ENUM('IN_STOCK','CONSUMED','EXPIRED','DISCARDED','DONATED')
--       NOT NULL DEFAULT 'IN_STOCK';
--
--   ALTER TABLE inventory_transactions
--     MODIFY COLUMN transaction_type
--       ENUM('ADD','CONSUME','DISCARD','DONATE') NOT NULL;
--
--   ALTER TABLE inventory_items
--     ADD COLUMN discard_reason VARCHAR(30) NULL AFTER status;
--
--   ALTER TABLE inventory_items
--     ADD COLUMN consumed_amount VARCHAR(20) NULL AFTER discard_reason;
--
-- These statements must NOT be re-run on a database that already
-- contains the changes, because duplicate columns or identical
-- MODIFY statements would be rejected or be unnecessary.
-- ============================================================
