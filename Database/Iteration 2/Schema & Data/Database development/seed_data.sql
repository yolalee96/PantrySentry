-- ============================================================
-- PantryBuddy - Household Inventory Reminder System
-- Iteration 2
-- Seed Data (seed_data.sql)
--
-- Execution order : schema.sql -> insert_static_data.sql -> seed_data.sql
--
-- Prerequisite : run schema.sql and insert_static_data.sql first so that
--                every table exists and the static catalogue
--                (storage_types, product_categories, products,
--                shelf_life_rules) is already loaded.
--
-- Content      : small development seed data for the operational tables
--                only. The catalogue tables are NOT inserted again here,
--                because insert_static_data.sql already provides them:
--                200 products, 612 shelf_life_rules, 7881
--                product_reference rows, 24460 product_keyword_mapping
--                rows, 284 price_item_reference rows and 2000
--                price_observations rows.
--                This file adds only a handful of extra rows on top of
--                that static data, using identifiers above the static
--                range so that nothing collides.
-- ============================================================

USE `Real_ProjectV2.0_TM06`;
SET NAMES utf8mb4;

-- ------------------------------------------------------------
-- users
-- is_verified covers both TRUE and FALSE
-- ------------------------------------------------------------
INSERT INTO users (user_id, email, password_hash, display_name, avatar_id, is_verified) VALUES
  (1, 'alice.tan@example.com',  '$2b$12$SEED_HASH_ALICE_000000000000000000000000000000001', 'Alice Tan',  NULL, TRUE),
  (2, 'bob.lee@example.com',    '$2b$12$SEED_HASH_BOB_00000000000000000000000000000000002', 'Bob Lee',    NULL, FALSE),
  (3, 'carol.ng@example.com',   '$2b$12$SEED_HASH_CAROL_0000000000000000000000000000000003', 'Carol Ng',   NULL, TRUE),
  (4, 'david.wong@example.com', '$2b$12$SEED_HASH_DAVID_0000000000000000000000000000000004', 'David Wong', NULL, FALSE);

-- ------------------------------------------------------------
-- teams
-- ------------------------------------------------------------
INSERT INTO teams (team_id, team_name) VALUES
  (1, 'Lee Family Pantry'),
  (2, 'Hacker House Kitchen');

-- ------------------------------------------------------------
-- team_members
-- ------------------------------------------------------------
INSERT INTO team_members (team_id, user_id, role, status, joined_at) VALUES
  (1, 1, 'ADMIN',  'ACTIVE', '2026-07-01 09:00:00'),
  (1, 2, 'MEMBER', 'ACTIVE', '2026-07-02 10:00:00'),
  (2, 3, 'ADMIN',  'ACTIVE', '2026-07-05 11:00:00'),
  (2, 2, 'MEMBER', 'ACTIVE', '2026-07-08 12:00:00'),
  (2, 4, 'MEMBER', 'ACTIVE', '2026-07-15 13:00:00');

-- ------------------------------------------------------------
-- join_requests
-- ------------------------------------------------------------
INSERT INTO join_requests (request_id, team_id, user_id, status, requested_at, reviewed_at, reviewed_by) VALUES
  (1, 1, 3, 'PENDING',  '2026-08-20 10:00:00', NULL,                  NULL),
  (2, 2, 4, 'APPROVED', '2026-07-10 09:00:00', '2026-07-12 09:30:00', 3),
  (3, 1, 4, 'DECLINED', '2026-07-20 14:00:00', '2026-07-21 15:00:00', 1);

-- ------------------------------------------------------------
-- security_questions
-- Answers are stored as bcrypt-like hashes, never as plain text.
-- One row per (user_id, question); several questions per user allowed.
-- ------------------------------------------------------------
INSERT INTO security_questions (question_id, user_id, question, answer_hash) VALUES
  (1, 1, 'Name of first pet',           '$2b$12$ANSWER_HASH_ALICE_PET_0000000000000000000000001'),
  (2, 1, 'City where you were born',    '$2b$12$ANSWER_HASH_ALICE_CITY_000000000000000000000002'),
  (3, 2, 'Name of your primary school', '$2b$12$ANSWER_HASH_BOB_SCHOOL_00000000000000000000003'),
  (4, 3, 'Favourite childhood food',    '$2b$12$ANSWER_HASH_CAROL_FOOD_000000000000000000000004');

-- ------------------------------------------------------------
-- product_reference
-- insert_static_data.sql already loads 7881 product_reference rows with
-- explicit reference_id values 1-7881, so this development seed only adds
-- two extra user-created references above that range:
--   * 7882 is an active reference with product_id NULL (a user-added
--     reference that is not linked to the products catalogue yet).
--   * 7883 is an inactive reference with product_id NULL.
-- Multiple NULL product_id values are allowed because NULL values are not
-- compared by the UNIQUE(product_id) key.
-- ------------------------------------------------------------
INSERT INTO product_reference (reference_id, product_id, category_id, product_name, barcode, description, is_active) VALUES
  (7882, NULL, 13, 'Homemade Chili Paste (seed)', NULL, 'Seed reference: user added, not linked to the catalogue yet.', TRUE),
  (7883, NULL, 15, 'Dried Anchovy Snack (seed)',  NULL, 'Seed reference: user added and currently disabled.',            FALSE);

-- ------------------------------------------------------------
-- product_keyword_mapping
-- A few development keywords on top of the 24460 static rows. References
-- 7882 and 7883 come from the seed rows above; reference 1 is the first
-- static catalogue reference (Starfruit). The normalized keywords are
-- unique per (reference_id, match_type), so they do not clash with the
-- static import.
-- ------------------------------------------------------------
INSERT INTO product_keyword_mapping
  (reference_id, keyword, normalized_keyword, match_type, source_name, source_url, source_locator, is_active)
VALUES
  (1,    'Seed Sample Starfruit Label', 'seed sample starfruit label', 'TEXT', 'PantryBuddy seed data',
   'https://example.com/pantrybuddy/seed/starfruit', 'seed/starfruit/text', TRUE),
  (7882, 'Seed Sample Chili Paste Jar', 'seed sample chili paste jar', 'TEXT', 'PantryBuddy seed data',
   'https://example.com/pantrybuddy/seed/chili-paste', 'seed/chili-paste/text', TRUE),
  (7883, 'Seed Sample Anchovy Pack',    'seed sample anchovy pack',    'TEXT', 'PantryBuddy seed data',
   'https://example.com/pantrybuddy/seed/anchovy', 'seed/anchovy/text', FALSE);

-- ------------------------------------------------------------
-- price_item_reference
-- Two development priced items on top of the 284 static rows. item_code
-- 900001 links to seed reference 7882; item_code 900002 links to static
-- reference 1 (Starfruit) so that a static reference is covered too.
-- base_unit uses the same spelling as inventory_items.unit: kg, L or pcs.
-- ------------------------------------------------------------
INSERT INTO price_item_reference
  (item_code, reference_id, source_item_name, source_unit, package_quantity_in_base_unit,
   base_unit, median_package_price, mean_package_price, latest_day_median_price,
   median_price_per_base_unit, price_observation_count, latest_observation_date, source_url)
VALUES
  (900001, 7882, 'SEED CHILI PASTE JAR 250G', '250 g', 250.0000, 'kg',
   12.50, 12.80, 12.50, 50.0000, 3, '2026-09-03', 'https://example.com/pantrybuddy/seed/prices'),
  (900002, 1,    'SEED STARFRUIT 1KG',        '1kg',   1.0000,   'kg',
   8.90,  9.10,  8.90,  8.9000,  2, '2026-09-03', 'https://example.com/pantrybuddy/seed/prices');

-- ------------------------------------------------------------
-- price_observations
-- Three development observations for seed item_code 900001. The unique
-- key is (observation_date, premise_code, item_code).
-- ------------------------------------------------------------
INSERT INTO price_observations (observation_date, premise_code, item_code, price_myr) VALUES
  ('2026-09-01', 9001, 900001, 12.50),
  ('2026-09-02', 9001, 900001, 12.90),
  ('2026-09-03', 9002, 900001, 11.90);

-- ------------------------------------------------------------
-- inventory_items
-- Covers IN_STOCK, EXPIRED, CONSUMED, DONATED and DISCARDED, plus
-- unit, notes, price, discard_reason and consumed_amount.
-- storage_type_id : 1 = FRIDGE, 2 = FREEZER, 3 = PANTRY
-- ------------------------------------------------------------
INSERT INTO inventory_items
  (inventory_item_id, team_id, product_id, storage_type_id, created_by, quantity,
   unit, notes, price, production_date, purchase_date, entry_date, shelf_life_days,
   expiry_date, expiry_date_source, checkout_date, status, discard_reason,
   consumed_amount)
VALUES
  (1, 1, 1,  1, 1, 5.00, 'pcs', 'Bought at the night market', 12.50, NULL,
   DATE_SUB(CURDATE(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY), 7,
   DATE_ADD(CURDATE(), INTERVAL 5 DAY), 'PACKAGING', NULL, 'IN_STOCK', NULL, NULL),
  (2, 1, 12, 1, 1, 3.00, 'pcs', 'Ripening on the counter', 8.90,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_SUB(CURDATE(), INTERVAL 1 DAY),
   DATE_SUB(NOW(), INTERVAL 1 DAY), 5, DATE_ADD(CURDATE(), INTERVAL 4 DAY),
   'CALCULATED', NULL, 'IN_STOCK', NULL, NULL),
  (3, 1, 60, 1, 2, 0.50, 'kg', 'For sambal', 21.00,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_SUB(CURDATE(), INTERVAL 1 DAY),
   DATE_SUB(NOW(), INTERVAL 1 DAY), 2, DATE_ADD(CURDATE(), INTERVAL 1 DAY),
   'CALCULATED', NULL, 'IN_STOCK', NULL, NULL),
  (4, 1, 101, 1, 1, 1.00, 'kg', NULL, NULL, NULL,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY), NULL,
   DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'USER_INPUT', NULL, 'IN_STOCK', NULL, NULL),
  (5, 2, 175, 2, 3, 1.00, 'kg', 'Freezer batch 2', 34.90, NULL,
   DATE_SUB(CURDATE(), INTERVAL 10 DAY), DATE_SUB(NOW(), INTERVAL 10 DAY), 90,
   DATE_ADD(CURDATE(), INTERVAL 60 DAY), 'PACKAGING', NULL, 'IN_STOCK', NULL, NULL),
  (6, 2, 2,  3, 3, 2.00, 'pcs', NULL, NULL, NULL,
   DATE_SUB(CURDATE(), INTERVAL 6 DAY), DATE_SUB(NOW(), INTERVAL 6 DAY), NULL,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), 'USER_INPUT', DATE_SUB(NOW(), INTERVAL 1 DAY),
   'EXPIRED', 'EXPIRED', NULL),
  (7, 2, 150, 1, 3, 1.00, 'kg', 'Used for soup', 6.75,
   DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_SUB(CURDATE(), INTERVAL 3 DAY),
   DATE_SUB(NOW(), INTERVAL 3 DAY), 7, DATE_ADD(CURDATE(), INTERVAL 4 DAY),
   'CALCULATED', DATE_SUB(NOW(), INTERVAL 2 DAY), 'CONSUMED', NULL, '1.00'),
  (8, 1, 199, 1, 1, 0.80, 'kg', 'Shared with the neighbours', 24.90, NULL,
   DATE_SUB(CURDATE(), INTERVAL 4 DAY), DATE_SUB(NOW(), INTERVAL 4 DAY), 3,
   DATE_ADD(CURDATE(), INTERVAL 1 DAY), 'PACKAGING', DATE_SUB(NOW(), INTERVAL 1 DAY),
   'DONATED', 'DONATED', NULL),
  (9, 1, 4,  3, 2, 1.00, 'pcs', 'Overripe', NULL, NULL,
   DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(NOW(), INTERVAL 5 DAY), NULL,
   DATE_SUB(CURDATE(), INTERVAL 3 DAY), 'USER_INPUT', DATE_SUB(NOW(), INTERVAL 3 DAY),
   'DISCARDED', 'USER_DISCARDED', NULL);

-- ------------------------------------------------------------
-- inventory_transactions
-- ADD for every seeded item, plus CONSUME, DISCARD and DONATE events.
-- discard_reason is non-NULL only for DISCARD transactions.
-- ------------------------------------------------------------
INSERT INTO inventory_transactions
  (transaction_id, inventory_item_id, user_id, transaction_type, quantity, transaction_time, note, discard_reason)
VALUES
  (1,  1, 1, 'ADD',     5.00, DATE_SUB(NOW(), INTERVAL 2 DAY),  'Initial stock entry', NULL),
  (2,  2, 1, 'ADD',     3.00, DATE_SUB(NOW(), INTERVAL 1 DAY),  'Initial stock entry', NULL),
  (3,  3, 2, 'ADD',     0.50, DATE_SUB(NOW(), INTERVAL 1 DAY),  'Initial stock entry', NULL),
  (4,  4, 1, 'ADD',     1.00, DATE_SUB(NOW(), INTERVAL 1 DAY),  'Initial stock entry', NULL),
  (5,  5, 3, 'ADD',     1.00, DATE_SUB(NOW(), INTERVAL 10 DAY), 'Initial stock entry', NULL),
  (6,  6, 3, 'ADD',     2.00, DATE_SUB(NOW(), INTERVAL 6 DAY),  'Initial stock entry', NULL),
  (7,  7, 3, 'ADD',     1.00, DATE_SUB(NOW(), INTERVAL 3 DAY),  'Initial stock entry', NULL),
  (8,  8, 1, 'ADD',     0.80, DATE_SUB(NOW(), INTERVAL 4 DAY),  'Initial stock entry', NULL),
  (9,  9, 2, 'ADD',     1.00, DATE_SUB(NOW(), INTERVAL 5 DAY),  'Initial stock entry', NULL),
  (10, 7, 3, 'CONSUME', 1.00, DATE_SUB(NOW(), INTERVAL 2 DAY),  'Eaten with dinner', NULL),
  (11, 6, 3, 'DISCARD', 2.00, DATE_SUB(NOW(), INTERVAL 1 DAY),  'Found expired in the pantry', 'EXPIRED'),
  (12, 9, 2, 'DISCARD', 1.00, DATE_SUB(NOW(), INTERVAL 3 DAY),  'Overripe and unappealing', 'USER_DISCARDED'),
  (13, 8, 1, 'DONATE',  0.80, DATE_SUB(NOW(), INTERVAL 1 DAY),  'Given to the neighbours', NULL);

-- ------------------------------------------------------------
-- reminders
-- ------------------------------------------------------------
INSERT INTO reminders
  (reminder_id, inventory_item_id, team_id, created_by, lead_time_days, reminder_at, status, created_at, cancelled_at)
VALUES
  (1, 2, 1, 1, 3, DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 9 HOUR), 'PENDING',   NOW(), NULL),
  (2, 3, 1, 2, 1, DATE_ADD(CURDATE(), INTERVAL 9 HOUR),                           'PENDING',   NOW(), NULL),
  (3, 5, 2, 3, 7, DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 53 DAY), INTERVAL 9 HOUR),'PENDING',   NOW(), NULL),
  (4, 6, 2, 3, 3, DATE_SUB(CURDATE(), INTERVAL 6 DAY),                            'CANCELLED', DATE_SUB(NOW(), INTERVAL 7 DAY), DATE_SUB(NOW(), INTERVAL 5 DAY));

-- ------------------------------------------------------------
-- notification_recipients
-- ------------------------------------------------------------
INSERT INTO notification_recipients (reminder_id, user_id, is_read, read_at) VALUES
  (1, 1, TRUE,  DATE_SUB(NOW(), INTERVAL 1 DAY)),
  (1, 2, FALSE, NULL),
  (2, 1, FALSE, NULL),
  (2, 2, TRUE,  DATE_SUB(NOW(), INTERVAL 2 HOUR)),
  (3, 3, FALSE, NULL),
  (3, 2, FALSE, NULL),
  (4, 3, TRUE,  DATE_SUB(NOW(), INTERVAL 5 DAY)),
  (4, 2, FALSE, NULL);
