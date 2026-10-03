-- ============================================================
-- PantrySentry - Household Inventory Reminder System
-- Iteration 3
-- MySQL Database Schema (schema.sql)
--
-- Target database : MySQL 8.0+ / TiDB (InnoDB, utf8mb4)
-- Tables          : 28
--   Iteration 1 (12): users, teams, team_members, join_requests,
--                     product_categories, products, storage_types,
--                     inventory_items, inventory_transactions,
--                     shelf_life_rules, reminders, notification_recipients
--   Iteration 2 (5) : security_questions, product_reference,
--                     product_keyword_mapping, price_item_reference,
--                     price_observations
--   Iteration 3 (11): recipes, recipe_ingredients, recipe_cook_sessions,
--                     recipe_cook_session_items, donation_centres,
--                     donation_centre_accepted_foods, donation_records,
--                     donation_record_items, emission_factors,
--                     quantity_conversions, waste_impact_assessments
--
-- Iteration 3 is incremental: the 17 Iteration 1 and Iteration 2 tables are
-- reproduced here with exactly the same columns, types, defaults, enums,
-- indexes, unique keys, foreign keys and constraint names, and the 11 new
-- Iteration 3 tables are appended after them. No existing table is changed.
--
-- Epic 6: recipes and cooking sessions (4 tables)
-- Epic 7: food donation (4 tables)
-- Epic 8: environmental impact (3 tables)
--
-- This script is idempotent: it drops the 28 tables (reverse dependency
-- order) and recreates them from scratch.
-- ============================================================

CREATE DATABASE IF NOT EXISTS `Real_ProjectV3.0_TM06`
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `Real_ProjectV3.0_TM06`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Drop tables in reverse dependency order (Iteration 3 tables first,
-- then the Iteration 2 and Iteration 1 tables).

DROP TABLE IF EXISTS waste_impact_assessments;
DROP TABLE IF EXISTS quantity_conversions;
DROP TABLE IF EXISTS emission_factors;
DROP TABLE IF EXISTS donation_record_items;
DROP TABLE IF EXISTS donation_records;
DROP TABLE IF EXISTS donation_centre_accepted_foods;
DROP TABLE IF EXISTS donation_centres;
DROP TABLE IF EXISTS recipe_cook_session_items;
DROP TABLE IF EXISTS recipe_cook_sessions;
DROP TABLE IF EXISTS recipe_ingredients;
DROP TABLE IF EXISTS recipes;
DROP TABLE IF EXISTS price_observations;
DROP TABLE IF EXISTS price_item_reference;
DROP TABLE IF EXISTS product_keyword_mapping;
DROP TABLE IF EXISTS security_questions;
DROP TABLE IF EXISTS product_reference;
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
  is_verified   BOOLEAN         NOT NULL DEFAULT FALSE,
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
  price             DECIMAL(10,2)    NULL,
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

-- ------------------------------------------------------------
-- 13. security_questions  (Iteration 2)
--     Account recovery questions per user. Answers are stored as
--     bcrypt hashes, never as plain text.
--     A user can store at most one row per question text.
-- ------------------------------------------------------------
CREATE TABLE security_questions (
  question_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NOT NULL,
  question    VARCHAR(255)    NOT NULL,
  answer_hash VARCHAR(255)    NOT NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (question_id),
  UNIQUE KEY uq_security_questions_user_question (user_id, question),
  KEY idx_security_questions_user_id (user_id),
  CONSTRAINT fk_security_questions_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 14. product_reference  (Iteration 2)
--     Reference catalogue used by image/OCR product matching.
--     product_id links a reference row to the products catalogue
--     (one-to-one, optional). A row with product_id NULL is a
--     reference entry that is not linked to the catalogue yet.
--     barcode is VARCHAR and must store NULL instead of ''.
-- ------------------------------------------------------------
CREATE TABLE product_reference (
  reference_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id   BIGINT UNSIGNED NULL,
  category_id  INT UNSIGNED    NOT NULL,
  product_name VARCHAR(255)    NOT NULL,
  barcode      VARCHAR(50)     NULL,
  description  VARCHAR(500)    NULL,
  is_active    BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (reference_id),
  UNIQUE KEY uq_product_reference_product_id (product_id),
  UNIQUE KEY uq_product_reference_barcode (barcode),
  UNIQUE KEY uq_product_reference_category_name (category_id, product_name),
  KEY idx_product_reference_category_id (category_id),
  KEY idx_product_reference_product_name (product_name),
  CONSTRAINT fk_product_reference_product FOREIGN KEY (product_id)
    REFERENCES products (product_id) ON DELETE RESTRICT,
  CONSTRAINT fk_product_reference_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 15. product_keyword_mapping  (Iteration 2)
--     Recognition keywords or Open Food Facts taxonomy tags that
--     resolve OCR text, manual text and barcode metadata to a
--     product_reference row.
-- ------------------------------------------------------------
CREATE TABLE product_keyword_mapping (
  mapping_id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  reference_id       BIGINT UNSIGNED NOT NULL,
  keyword            VARCHAR(255)    NOT NULL,
  normalized_keyword VARCHAR(255)    NOT NULL,
  match_type         VARCHAR(30)     NOT NULL,
  source_name        VARCHAR(255)    NOT NULL,
  source_url         VARCHAR(1000)   NOT NULL,
  source_locator     VARCHAR(1000)   NULL,
  is_active          BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (mapping_id),
  UNIQUE KEY uq_product_keyword_mapping_reference_keyword_type (reference_id, normalized_keyword, match_type),
  KEY idx_product_keyword_mapping_normalized_keyword (normalized_keyword),
  KEY idx_product_keyword_mapping_reference_id (reference_id),
  CONSTRAINT fk_product_keyword_mapping_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 16. price_item_reference  (Iteration 2)
--     Link between a PriceCatcher priced item, its package unit and
--     a PantrySentry product_reference row, including the calculated
--     reference prices used by the application.
--     item_code identifies one PriceCatcher item and unit.
-- ------------------------------------------------------------
CREATE TABLE price_item_reference (
  item_code                      INT UNSIGNED    NOT NULL,
  reference_id                   BIGINT UNSIGNED NOT NULL,
  source_item_name               VARCHAR(255)    NOT NULL,
  source_unit                    VARCHAR(50)     NOT NULL,
  package_quantity_in_base_unit  DECIMAL(12,4)   NULL,
  base_unit                      VARCHAR(20)     NOT NULL,
  median_package_price           DECIMAL(10,2)   NULL,
  mean_package_price             DECIMAL(10,2)   NULL,
  latest_day_median_price        DECIMAL(10,2)   NULL,
  median_price_per_base_unit     DECIMAL(12,4)   NULL,
  price_observation_count        INT UNSIGNED    NOT NULL,
  latest_observation_date        DATE            NULL,
  source_url                     VARCHAR(1000)   NOT NULL,
  PRIMARY KEY (item_code),
  KEY idx_price_item_reference_reference_id (reference_id),
  KEY idx_price_item_reference_base_unit (base_unit),
  CONSTRAINT fk_price_item_reference_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 17. price_observations  (Iteration 2)
--     Dated premise-level price observations for a priced item.
--     Iteration 2 imports a 2000-row sample; the full archive of
--     561,441 observations stays in the CSV archive.
-- ------------------------------------------------------------
CREATE TABLE price_observations (
  observation_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  observation_date DATE            NOT NULL,
  premise_code     INT UNSIGNED    NOT NULL,
  item_code        INT UNSIGNED    NOT NULL,
  price_myr        DECIMAL(10,2)   NOT NULL,
  PRIMARY KEY (observation_id),
  UNIQUE KEY uq_price_observations_date_premise_item (observation_date, premise_code, item_code),
  KEY idx_price_observations_item_date (item_code, observation_date),
  CONSTRAINT chk_price_observations_price_myr CHECK (price_myr > 0),
  CONSTRAINT fk_price_observations_item FOREIGN KEY (item_code)
    REFERENCES price_item_reference (item_code) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 18. recipes  (Iteration 3 - Epic 6 cooking suggestions)
--     Recipe catalogue. Instructions are stored as JSON so the app can
--     keep ordered steps without another table.
-- ------------------------------------------------------------
CREATE TABLE recipes (
  recipe_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title              VARCHAR(255)    NOT NULL,
  description        VARCHAR(1000)   NULL,
  servings           DECIMAL(6,2)    NOT NULL DEFAULT 1,
  serving_unit       VARCHAR(50)     NULL,
  prep_time_minutes  INT UNSIGNED    NULL,
  cook_time_minutes  INT UNSIGNED    NULL,
  total_time_minutes INT UNSIGNED    NULL,
  difficulty         ENUM('EASY','MEDIUM','HARD') NULL,
  cuisine            VARCHAR(100)    NULL,
  instructions_json  JSON            NULL,
  source_name        VARCHAR(255)    NULL,
  source_url         VARCHAR(1000)   NULL,
  image_url          VARCHAR(1000)   NULL,
  is_active          BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (recipe_id),
  KEY idx_recipes_title (title),
  KEY idx_recipes_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 19. recipe_ingredients  (Iteration 3 - Epic 6)
--     Ingredient lines of a recipe. reference_id and category_id are
--     optional so free-text ingredients can still be stored, and they are
--     cleared (SET NULL) if the referenced row disappears.
-- ------------------------------------------------------------
CREATE TABLE recipe_ingredients (
  ingredient_id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipe_id                  BIGINT UNSIGNED NOT NULL,
  ingredient_name            VARCHAR(255)    NOT NULL,
  normalized_ingredient_name VARCHAR(255)    NOT NULL,
  reference_id               BIGINT UNSIGNED NULL,
  category_id                INT UNSIGNED    NULL,
  quantity                   DECIMAL(10,3)   NULL,
  unit                       VARCHAR(20)     NULL,
  is_optional                BOOLEAN         NOT NULL DEFAULT FALSE,
  group_name                 VARCHAR(100)    NULL,
  sort_order                 INT UNSIGNED    NOT NULL DEFAULT 0,
  notes                      VARCHAR(500)    NULL,
  created_at                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (ingredient_id),
  KEY idx_recipe_ingredients_recipe_id (recipe_id),
  KEY idx_recipe_ingredients_reference_id (reference_id),
  KEY idx_recipe_ingredients_category_id (category_id),
  KEY idx_recipe_ingredients_normalized_name (normalized_ingredient_name),
  CONSTRAINT fk_recipe_ingredients_recipe FOREIGN KEY (recipe_id)
    REFERENCES recipes (recipe_id) ON DELETE CASCADE,
  CONSTRAINT fk_recipe_ingredients_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE SET NULL,
  CONSTRAINT fk_recipe_ingredients_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 20. recipe_cook_sessions  (Iteration 3 - Epic 6)
--     One cooking attempt per team. idempotency_key makes the client
--     retry safe: UNIQUE (team_id, idempotency_key) rejects duplicates.
-- ------------------------------------------------------------
CREATE TABLE recipe_cook_sessions (
  session_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id         BIGINT UNSIGNED NOT NULL,
  recipe_id       BIGINT UNSIGNED NOT NULL,
  user_id         BIGINT UNSIGNED NOT NULL,
  idempotency_key VARCHAR(100)    NOT NULL,
  status          ENUM('DRAFT','CONFIRMED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  cooked_at       DATETIME        NULL,
  confirmed_at    DATETIME        NULL,
  notes           VARCHAR(500)    NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (session_id),
  UNIQUE KEY uq_recipe_cook_sessions_team_idempotency (team_id, idempotency_key),
  KEY idx_recipe_cook_sessions_team_cooked_at (team_id, cooked_at),
  KEY idx_recipe_cook_sessions_recipe_id (recipe_id),
  KEY idx_recipe_cook_sessions_user_id (user_id),
  CONSTRAINT fk_recipe_cook_sessions_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_recipe_cook_sessions_recipe FOREIGN KEY (recipe_id)
    REFERENCES recipes (recipe_id) ON DELETE RESTRICT,
  CONSTRAINT fk_recipe_cook_sessions_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 21. recipe_cook_session_items  (Iteration 3 - Epic 6)
--     Which inventory stock was used by a cooking session, and the
--     resulting CONSUME transaction when the session is confirmed.
--     UNIQUE (session_id, inventory_item_id) stops the same stock row from
--     being counted twice inside one session.
-- ------------------------------------------------------------
CREATE TABLE recipe_cook_session_items (
  session_item_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id        BIGINT UNSIGNED NOT NULL,
  inventory_item_id BIGINT UNSIGNED NOT NULL,
  ingredient_id     BIGINT UNSIGNED NULL,
  planned_quantity  DECIMAL(10,3)   NULL,
  used_quantity     DECIMAL(10,3)   NOT NULL,
  unit              VARCHAR(20)     NOT NULL,
  is_selected       BOOLEAN         NOT NULL DEFAULT TRUE,
  transaction_id    BIGINT UNSIGNED NULL,
  created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (session_item_id),
  UNIQUE KEY uq_recipe_cook_session_items_session_inventory (session_id, inventory_item_id),
  KEY idx_recipe_cook_session_items_session_id (session_id),
  KEY idx_recipe_cook_session_items_inventory_item_id (inventory_item_id),
  KEY idx_recipe_cook_session_items_transaction_id (transaction_id),
  CONSTRAINT fk_recipe_cook_session_items_session FOREIGN KEY (session_id)
    REFERENCES recipe_cook_sessions (session_id) ON DELETE CASCADE,
  CONSTRAINT fk_recipe_cook_session_items_inventory FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items (inventory_item_id) ON DELETE RESTRICT,
  CONSTRAINT fk_recipe_cook_session_items_ingredient FOREIGN KEY (ingredient_id)
    REFERENCES recipe_ingredients (ingredient_id) ON DELETE SET NULL,
  CONSTRAINT fk_recipe_cook_session_items_transaction FOREIGN KEY (transaction_id)
    REFERENCES inventory_transactions (transaction_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 22. donation_centres  (Iteration 3 - Epic 7 food donation)
--     Donation drop-off points. Simplified after data-team review:
--     no address_line2, no country, no accepts_food_donations and no
--     accepted_categories; verification_source_url is included and
--     requires_declaration is not part of this table.
-- ------------------------------------------------------------
CREATE TABLE donation_centres (
  centre_id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name                    VARCHAR(255)    NOT NULL,
  organisation_type       ENUM('CARE_HOME','NGO','FOOD_BANK','COMMUNITY_CENTRE',
                               'RELIGIOUS_ORG','PANTRY_DROP_OFF','COMMUNITY_FRIDGE','OTHER') NOT NULL,
  description             VARCHAR(1000)   NULL,
  address_line1           VARCHAR(255)    NOT NULL,
  city                    VARCHAR(100)    NULL,
  state                   VARCHAR(100)    NULL,
  postcode                VARCHAR(20)     NULL,
  latitude                DECIMAL(10,7)   NULL,
  longitude               DECIMAL(10,7)   NULL,
  phone                   VARCHAR(50)     NULL,
  email                   VARCHAR(255)    NULL,
  website_url             VARCHAR(1000)   NULL,
  operating_hours         VARCHAR(500)    NULL,
  verification_source_url VARCHAR(1000)   NULL,
  donation_requirements   TEXT            NULL,
  is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (centre_id),
  KEY idx_donation_centres_name (name),
  KEY idx_donation_centres_postcode (postcode),
  KEY idx_donation_centres_city (city),
  KEY idx_donation_centres_location (latitude, longitude),
  KEY idx_donation_centres_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 23. donation_centre_accepted_foods  (Iteration 3 - Epic 7)
--     Renamed and simplified from the earlier donation_centre_needs draft:
--     8 columns only, one row per accepted food type of a centre.
-- ------------------------------------------------------------
CREATE TABLE donation_centre_accepted_foods (
  need_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  centre_id   BIGINT UNSIGNED NOT NULL,
  category_id INT UNSIGNED    NOT NULL,
  item_name   VARCHAR(255)    NOT NULL,
  notes       VARCHAR(500)    NULL,
  is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (need_id),
  KEY idx_donation_centre_accepted_foods_centre_active (centre_id, is_active),
  KEY idx_donation_centre_accepted_foods_category_id (category_id),
  CONSTRAINT fk_donation_centre_accepted_foods_centre FOREIGN KEY (centre_id)
    REFERENCES donation_centres (centre_id) ON DELETE CASCADE,
  CONSTRAINT fk_donation_centre_accepted_foods_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 24. donation_records  (Iteration 3 - Epic 7)
--     One donation request per team and centre. A PENDING record is only a
--     reservation: stock is not moved until the record becomes COMPLETED.
-- ------------------------------------------------------------
CREATE TABLE donation_records (
  donation_id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id                BIGINT UNSIGNED NOT NULL,
  centre_id              BIGINT UNSIGNED NOT NULL,
  user_id                BIGINT UNSIGNED NOT NULL,
  status                 ENUM('PENDING','COMPLETED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  drop_off_window_start  DATETIME        NULL,
  drop_off_window_end    DATETIME        NULL,
  declaration_agreed     BOOLEAN         NOT NULL DEFAULT FALSE,
  donated_at             DATETIME        NULL,
  notes                  VARCHAR(500)    NULL,
  created_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (donation_id),
  KEY idx_donation_records_team_status (team_id, status),
  KEY idx_donation_records_centre_id (centre_id),
  KEY idx_donation_records_user_id (user_id),
  CONSTRAINT fk_donation_records_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_donation_records_centre FOREIGN KEY (centre_id)
    REFERENCES donation_centres (centre_id) ON DELETE RESTRICT,
  CONSTRAINT fk_donation_records_user FOREIGN KEY (user_id)
    REFERENCES users (user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 25. donation_record_items  (Iteration 3 - Epic 7)
--     Stock rows donated in one donation record. transaction_id is filled
--     only when the donation is completed and the DONATE transaction is
--     written.
--     `condition` is a reserved MySQL keyword, so it is always quoted.
-- ------------------------------------------------------------
CREATE TABLE donation_record_items (
  donation_item_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  donation_id           BIGINT UNSIGNED NOT NULL,
  inventory_item_id     BIGINT UNSIGNED NOT NULL,
  quantity              DECIMAL(10,2)   NOT NULL,
  unit                  VARCHAR(20)     NOT NULL,
  `condition`           VARCHAR(100)    NULL,
  expiry_date_at_donation DATE          NULL,
  photo_url             VARCHAR(1000)   NULL,
  transaction_id        BIGINT UNSIGNED NULL,
  created_at            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (donation_item_id),
  UNIQUE KEY uq_donation_record_items_donation_inventory (donation_id, inventory_item_id),
  KEY idx_donation_record_items_inventory_item_id (inventory_item_id),
  KEY idx_donation_record_items_transaction_id (transaction_id),
  CONSTRAINT fk_donation_record_items_donation FOREIGN KEY (donation_id)
    REFERENCES donation_records (donation_id) ON DELETE CASCADE,
  CONSTRAINT fk_donation_record_items_inventory FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items (inventory_item_id) ON DELETE RESTRICT,
  CONSTRAINT fk_donation_record_items_transaction FOREIGN KEY (transaction_id)
    REFERENCES inventory_transactions (transaction_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 26. emission_factors  (Iteration 3 - Epic 8 environmental impact)
--     Greenhouse-gas factors per kilogram of food. A row can point at a
--     category, at a specific product_reference, or stay generic.
-- ------------------------------------------------------------
CREATE TABLE emission_factors (
  factor_id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  factor_name            VARCHAR(255)    NOT NULL,
  category_id            INT UNSIGNED    NULL,
  reference_id           BIGINT UNSIGNED NULL,
  food_type              VARCHAR(255)    NULL,
  factor_kg_co2e_per_kg  DECIMAL(12,6)   NOT NULL,
  source_name            VARCHAR(255)    NOT NULL,
  source_url             VARCHAR(1000)   NULL,
  source_version         VARCHAR(50)     NOT NULL,
  publication_date       DATE            NULL,
  valid_from             DATE            NULL,
  valid_to               DATE            NULL,
  region                 VARCHAR(100)    NULL,
  is_active              BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (factor_id),
  KEY idx_emission_factors_category_id (category_id),
  KEY idx_emission_factors_reference_id (reference_id),
  KEY idx_emission_factors_is_active (is_active),
  CONSTRAINT fk_emission_factors_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE RESTRICT,
  CONSTRAINT fk_emission_factors_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 27. quantity_conversions  (Iteration 3 - Epic 8)
--     Unit conversions used to turn a household quantity into kilograms.
--     A row with reference_id NULL is generic, a row with reference_id is
--     product specific, and is_assumed marks estimated factors.
-- ------------------------------------------------------------
CREATE TABLE quantity_conversions (
  conversion_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  reference_id  BIGINT UNSIGNED NULL,
  from_unit     VARCHAR(20)     NOT NULL,
  to_unit       VARCHAR(20)     NOT NULL,
  factor        DECIMAL(18,8)   NOT NULL,
  is_assumed    BOOLEAN         NOT NULL DEFAULT TRUE,
  source_name   VARCHAR(255)    NULL,
  source_url    VARCHAR(1000)   NULL,
  notes         VARCHAR(500)    NULL,
  is_active     BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (conversion_id),
  KEY idx_quantity_conversions_reference_id (reference_id),
  KEY idx_quantity_conversions_units (from_unit, to_unit),
  CONSTRAINT fk_quantity_conversions_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 28. waste_impact_assessments  (Iteration 3 - Epic 8)
--     Carbon footprint of one discarded inventory transaction. Factor
--     values are copied into snapshot columns so an old assessment keeps
--     the numbers it was calculated with. transaction_id is UNIQUE:
--     one transaction has at most one assessment.
-- ------------------------------------------------------------
CREATE TABLE waste_impact_assessments (
  assessment_id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id                          BIGINT UNSIGNED NOT NULL,
  inventory_item_id                BIGINT UNSIGNED NOT NULL,
  transaction_id                   BIGINT UNSIGNED NULL,
  product_id                       BIGINT UNSIGNED NULL,
  reference_id                     BIGINT UNSIGNED NULL,
  category_id                      INT UNSIGNED    NULL,
  discarded_quantity               DECIMAL(10,3)   NOT NULL,
  discarded_unit                   VARCHAR(20)     NOT NULL,
  converted_weight_kg              DECIMAL(12,6)   NULL,
  conversion_id                    BIGINT UNSIGNED NULL,
  factor_id                        BIGINT UNSIGNED NULL,
  factor_kg_co2e_per_kg_snapshot   DECIMAL(12,6)   NULL,
  factor_source_name_snapshot      VARCHAR(255)    NULL,
  factor_source_version_snapshot   VARCHAR(50)     NULL,
  calculation_method_version       VARCHAR(50)     NULL,
  footprint_kg_co2e                DECIMAL(12,6)   NULL,
  assessment_status                ENUM('ASSESSED','EXCLUDED') NOT NULL,
  exclusion_reason                 VARCHAR(255)    NULL,
  calculation_notes                VARCHAR(1000)   NULL,
  discarded_at                     DATETIME        NOT NULL,
  assessed_at                      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at                       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (assessment_id),
  UNIQUE KEY uq_waste_impact_assessments_transaction_id (transaction_id),
  KEY idx_waste_impact_assessments_team_discarded_at (team_id, discarded_at),
  KEY idx_waste_impact_assessments_team_category (team_id, category_id),
  KEY idx_waste_impact_assessments_status (assessment_status),
  KEY idx_waste_impact_assessments_transaction_id (transaction_id),
  CONSTRAINT fk_waste_impact_assessments_team FOREIGN KEY (team_id)
    REFERENCES teams (team_id) ON DELETE CASCADE,
  CONSTRAINT fk_waste_impact_assessments_inventory FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items (inventory_item_id) ON DELETE RESTRICT,
  CONSTRAINT fk_waste_impact_assessments_transaction FOREIGN KEY (transaction_id)
    REFERENCES inventory_transactions (transaction_id) ON DELETE RESTRICT,
  CONSTRAINT fk_waste_impact_assessments_product FOREIGN KEY (product_id)
    REFERENCES products (product_id) ON DELETE SET NULL,
  CONSTRAINT fk_waste_impact_assessments_reference FOREIGN KEY (reference_id)
    REFERENCES product_reference (reference_id) ON DELETE SET NULL,
  CONSTRAINT fk_waste_impact_assessments_category FOREIGN KEY (category_id)
    REFERENCES product_categories (category_id) ON DELETE SET NULL,
  CONSTRAINT fk_waste_impact_assessments_conversion FOREIGN KEY (conversion_id)
    REFERENCES quantity_conversions (conversion_id) ON DELETE SET NULL,
  CONSTRAINT fk_waste_impact_assessments_factor FOREIGN KEY (factor_id)
    REFERENCES emission_factors (factor_id) ON DELETE SET NULL
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

-- ============================================================
-- ITERATION 2 MIGRATION NOTE (existing Iteration 1 databases only)
-- The fresh schema above already contains all Iteration 2 changes.
-- Backend teams upgrading an existing Iteration 1 database should
-- execute the following statements once, in this order:
--
--   ALTER TABLE users
--     ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE AFTER avatar_id;
--
--   CREATE TABLE security_questions (
--     question_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
--     user_id     BIGINT UNSIGNED NOT NULL,
--     question    VARCHAR(255)    NOT NULL,
--     answer_hash VARCHAR(255)    NOT NULL,
--     created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
--     PRIMARY KEY (question_id),
--     UNIQUE KEY uq_security_questions_user_question (user_id, question),
--     KEY idx_security_questions_user_id (user_id),
--     CONSTRAINT fk_security_questions_user FOREIGN KEY (user_id)
--       REFERENCES users (user_id) ON DELETE CASCADE
--   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
--
--   CREATE TABLE product_reference (
--     reference_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
--     product_id   BIGINT UNSIGNED NULL,
--     category_id  INT UNSIGNED    NOT NULL,
--     product_name VARCHAR(255)    NOT NULL,
--     barcode      VARCHAR(50)     NULL,
--     description  VARCHAR(500)    NULL,
--     is_active    BOOLEAN         NOT NULL DEFAULT TRUE,
--     created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
--     PRIMARY KEY (reference_id),
--     UNIQUE KEY uq_product_reference_product_id (product_id),
--     UNIQUE KEY uq_product_reference_barcode (barcode),
--     UNIQUE KEY uq_product_reference_category_name (category_id, product_name),
--     KEY idx_product_reference_category_id (category_id),
--     KEY idx_product_reference_product_name (product_name),
--     CONSTRAINT fk_product_reference_product FOREIGN KEY (product_id)
--       REFERENCES products (product_id) ON DELETE RESTRICT,
--     CONSTRAINT fk_product_reference_category FOREIGN KEY (category_id)
--       REFERENCES product_categories (category_id) ON DELETE RESTRICT
--   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
--
-- Re-running these statements on a database that already contains
-- the Iteration 2 changes would fail with a duplicate column or
-- duplicate table error.
-- ============================================================

-- ============================================================
-- ITERATION 2 MIGRATION NOTE - PRICE AND RECOGNITION TABLES
-- (existing databases only)
-- The fresh schema above already contains all of these changes.
-- Existing databases that already have the 14-table Iteration 2
-- schema need the following statements once, in this order:
--
--   ALTER TABLE inventory_items
--     ADD COLUMN price DECIMAL(10,2) NULL AFTER notes;
--
--   -- Then create product_keyword_mapping, price_item_reference and
--   -- price_observations exactly as defined in sections 15, 16 and 17
--   -- of this file.
--
-- insert_static_data.sql loads the rows for these three tables. It must
-- run after the tables exist.
-- ============================================================

-- ============================================================
-- ITERATION 3 NOTE - NEW TABLES (existing Iteration 2 databases only)
-- The fresh schema above already creates all 28 tables. Backend teams
-- upgrading an existing Iteration 2 database only need to create the 11
-- tables of sections 18-28 (recipes, recipe_ingredients,
-- recipe_cook_sessions, recipe_cook_session_items, donation_centres,
-- donation_centre_accepted_foods, donation_records, donation_record_items,
-- emission_factors, quantity_conversions, waste_impact_assessments).
-- No Iteration 1 or Iteration 2 table is altered by Iteration 3.
--
-- Notes for the new tables:
--   * donation_record_items."condition" must always be quoted, because
--     CONDITION is a reserved MySQL keyword.
--   * waste_impact_assessments.transaction_id is UNIQUE, so one discarded
--     inventory transaction has at most one assessment.
--   * TiDB may not enforce CHECK constraints; Iteration 3 adds no CHECK
--     constraints, so all new business rules live in the application.
-- ============================================================
