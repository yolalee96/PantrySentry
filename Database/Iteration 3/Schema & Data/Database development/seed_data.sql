-- ============================================================
-- PantrySentry - Household Inventory Reminder System
-- Iteration 3
-- Seed Data (seed_data.sql)
--
-- Execution order : schema.sql -> insert_static_data.sql -> seed_data.sql
--
-- Prerequisite : run schema.sql and insert_static_data.sql first so that
--                every table exists and the static catalogue
--                (storage_types, product_categories, products,
--                shelf_life_rules) is already loaded.
--
-- Content      : Iteration 2 development seed data (kept unchanged) followed
--                by the Iteration 3 seed data for Epic 6, Epic 7 and Epic 8.
--                Original Iteration 2 content: 
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

USE `Real_ProjectV3.0_TM06`;
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
  (1,    'Seed Sample Starfruit Label', 'seed sample starfruit label', 'TEXT', 'PantrySentry seed data',
   'https://example.com/pantrysentry/seed/starfruit', 'seed/starfruit/text', TRUE),
  (7882, 'Seed Sample Chili Paste Jar', 'seed sample chili paste jar', 'TEXT', 'PantrySentry seed data',
   'https://example.com/pantrysentry/seed/chili-paste', 'seed/chili-paste/text', TRUE),
  (7883, 'Seed Sample Anchovy Pack',    'seed sample anchovy pack',    'TEXT', 'PantrySentry seed data',
   'https://example.com/pantrysentry/seed/anchovy', 'seed/anchovy/text', FALSE);

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
   12.50, 12.80, 12.50, 50.0000, 3, '2026-09-03', 'https://example.com/pantrysentry/seed/prices'),
  (900002, 1,    'SEED STARFRUIT 1KG',        '1kg',   1.0000,   'kg',
   8.90,  9.10,  8.90,  8.9000,  2, '2026-09-03', 'https://example.com/pantrysentry/seed/prices');

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

-- ============================================================
-- ITERATION 3 DEVELOPMENT SEED DATA
-- Epic 6 (recipes and cooking), Epic 7 (food donation) and
-- Epic 8 (environmental impact).
--
-- Identifier ranges used here stay clear of the Iteration 2 seed data:
--   inventory_items       101-105   (Iteration 2 uses 1-9)
--   inventory_transactions 101-108  (Iteration 2 uses 1-13)
--   recipes                1-3, recipe_ingredients 1-12
--   recipe_cook_sessions   1-2, recipe_cook_session_items 1-3
--   donation_centres       1-3, donation_centre_accepted_foods 1-6
--   donation_records       1, donation_record_items 1-2
--   emission_factors       1-4, quantity_conversions 1-5
--   waste_impact_assessments 1-3
-- ============================================================

-- ------------------------------------------------------------
-- inventory_items (Iteration 3 additions)
-- Items used by the recipe, donation and impact scenarios.
-- ------------------------------------------------------------
INSERT INTO inventory_items
  (inventory_item_id, team_id, product_id, storage_type_id, created_by, quantity,
   unit, notes, price, production_date, purchase_date, entry_date, shelf_life_days,
   expiry_date, expiry_date_source, checkout_date, status, discard_reason, consumed_amount)
VALUES
  (101, 1, 2,   1, 1, 3.00, 'pcs', 'Ripe papaya for the breakfast bowl recipe', 7.50, NULL,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY), 5,
   DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'CALCULATED', NULL, 'IN_STOCK', NULL, NULL),
  (102, 1, 60,  1, 1, 0.25, 'kg', 'Anchovy stock after the sambal session', 6.80, NULL,
   DATE_SUB(CURDATE(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY), 2,
   DATE_ADD(CURDATE(), INTERVAL 1 DAY), 'CALCULATED', NULL, 'IN_STOCK', NULL, '0.25'),
  (103, 1, 4,   3, 2, 2.00, 'pcs', 'Sapodilla (Ciku) reserved for the pending donation', 5.00, NULL,
   DATE_SUB(CURDATE(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY), 6,
   DATE_ADD(CURDATE(), INTERVAL 4 DAY), 'CALCULATED', NULL, 'IN_STOCK', NULL, NULL),
  (104, 2, 150, 1, 3, 1.00, 'kg', 'Lotus root that wilted before cooking', 9.90, NULL,
   DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY), 7,
   DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'CALCULATED', DATE_SUB(NOW(), INTERVAL 1 DAY),
   'DISCARDED', 'USER_DISCARDED', NULL),
  (105, 1, 101, 1, 1, 0.50, 'kg', 'Water spinach left after the stir fry recipe', 4.20, NULL,
   CURDATE(), NOW(), 3, DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'USER_INPUT', NULL,
   'IN_STOCK', NULL, '0.50');

-- ------------------------------------------------------------
-- inventory_transactions (Iteration 3 additions)
-- ADD rows for the new stock, one DISCARD for the impact exclusion case and
-- two CONSUME rows produced by the confirmed cooking session.
-- ------------------------------------------------------------
INSERT INTO inventory_transactions
  (transaction_id, inventory_item_id, user_id, transaction_type, quantity, transaction_time, note, discard_reason)
VALUES
  (101, 101, 1, 'ADD',     3.00, DATE_SUB(NOW(), INTERVAL 1 DAY), 'Initial stock entry', NULL),
  (102, 102, 1, 'ADD',     0.50, DATE_SUB(NOW(), INTERVAL 1 DAY), 'Initial stock entry', NULL),
  (103, 103, 2, 'ADD',     2.00, DATE_SUB(NOW(), INTERVAL 2 DAY), 'Initial stock entry', NULL),
  (104, 104, 3, 'ADD',     1.00, DATE_SUB(NOW(), INTERVAL 3 DAY), 'Initial stock entry', NULL),
  (105, 105, 1, 'ADD',     1.00, NOW(), 'Initial stock entry', NULL),
  (106, 104, 3, 'DISCARD', 1.00, DATE_SUB(NOW(), INTERVAL 1 DAY), 'Wilted lotus root discarded', 'USER_DISCARDED'),
  (107, 102, 1, 'CONSUME', 0.25, DATE_SUB(NOW(), INTERVAL 1 DAY), 'Used for the anchovy sambal session', NULL),
  (108, 105, 1, 'CONSUME', 0.50, DATE_SUB(NOW(), INTERVAL 1 DAY), 'Used for the stir fry session', NULL);

-- ------------------------------------------------------------
-- recipes
-- ------------------------------------------------------------
INSERT INTO recipes
  (recipe_id, title, description, servings, serving_unit, prep_time_minutes, cook_time_minutes,
   total_time_minutes, difficulty, cuisine, instructions_json, source_name, source_url, image_url, is_active)
VALUES
  (1, 'Papaya and Starfruit Breakfast Bowl',
   'A no-cook breakfast bowl that uses ripe tropical fruit and yogurt.',
   2.00, 'bowl', 10, 0, 10, 'EASY', 'Malaysian',
   '["Scoop the papaya and slice the starfruit.", "Toss the fruit with lime juice.", "Spoon over the yogurt and serve chilled."]',
   'PantrySentry test kitchen', 'https://example.com/pantrysentry/recipes/breakfast-bowl', NULL, TRUE),
  (2, 'Anchovy Sambal with Water Spinach',
   'Spicy anchovy sambal served with quickly blanched water spinach.',
   4.00, 'serving', 15, 20, 35, 'MEDIUM', 'Malaysian',
   '["Pound the chilli paste and fry it with the anchovy.", "Blanch the water spinach for one minute.", "Fold the sambal through the greens and serve."]',
   'PantrySentry test kitchen', 'https://example.com/pantrysentry/recipes/anchovy-sambal', NULL, TRUE),
  (3, 'Lotus Root, Beef and Water Spinach Stir Fry',
   'A home-style stir fry that uses up root vegetables and beef strips.',
   3.00, 'serving', 20, 15, 35, 'MEDIUM', 'Chinese',
   '["Slice the lotus root and beef thinly.", "Sear the beef, then add the lotus root.", "Add the water spinach and oyster sauce and serve."]',
   'PantrySentry test kitchen', 'https://example.com/pantrysentry/recipes/lotus-root-stir-fry', NULL, TRUE);

-- ------------------------------------------------------------
-- recipe_ingredients
-- reference_id points at the static product_reference rows, so
-- reference_id 2 = Papaya, 1 = Starfruit, 60 = Indian Anchovy,
-- 101 = Water Spinach, 150 = Lotus Root and 199 = Beef Striploin.
-- Ingredients without a catalogue match keep reference_id NULL and are
-- reported as missing by the recipe availability query.
-- ------------------------------------------------------------
INSERT INTO recipe_ingredients
  (ingredient_id, recipe_id, ingredient_name, normalized_ingredient_name, reference_id, category_id,
   quantity, unit, is_optional, group_name, sort_order, notes)
VALUES
  (1,  1, 'Papaya',            'papaya',            2,    5,  1.000, 'pcs',  FALSE, 'Main',    1, 'Use ripe fruit.'),
  (2,  1, 'Starfruit',         'starfruit',         1,    5,  2.000, 'pcs',  FALSE, 'Main',    2, NULL),
  (3,  1, 'Lime juice',        'lime juice',        NULL, 5,  1.000, 'pcs',  FALSE, 'Topping', 3, 'Free-text ingredient without a catalogue match.'),
  (4,  1, 'Greek yogurt',      'greek yogurt',      NULL, 1,  100.000, 'g',  FALSE, 'Topping', 4, NULL),
  (5,  2, 'Indian anchovy',    'indian anchovy',    60,   3,  0.250, 'kg',   FALSE, 'Main',    1, 'Rinse and pat dry.'),
  (6,  2, 'Water spinach',     'water spinach',     101,  4,  0.750, 'kg',   FALSE, 'Main',    2, 'Recipe needs more than the stock on hand.'),
  (7,  2, 'Dried chilli paste','dried chilli paste',NULL, 13, 2.000, 'tbsp', FALSE, 'Sauce',   3, 'Free-text ingredient without a catalogue match.'),
  (8,  2, 'Cooking oil',       'cooking oil',       NULL, 15, 2.000, 'tbsp', TRUE,  'Sauce',   4, NULL),
  (9,  3, 'Lotus root',        'lotus root',        150,  4,  0.500, 'kg',   FALSE, 'Main',    1, NULL),
  (10, 3, 'Beef striploin',    'beef striploin',    199,  2,  0.300, 'kg',   FALSE, 'Main',    2, NULL),
  (11, 3, 'Water spinach',     'water spinach',     101,  4,  0.500, 'kg',   FALSE, 'Main',    3, NULL),
  (12, 3, 'Oyster sauce',      'oyster sauce',      NULL, 13, 1.500, 'tbsp', TRUE,  'Sauce',   4, NULL);

-- ------------------------------------------------------------
-- recipe_cook_sessions
-- Session 1 is a confirmed cooking session for team 1; session 2 is still a
-- draft, which is why it has no transactions attached.
-- ------------------------------------------------------------
INSERT INTO recipe_cook_sessions
  (session_id, team_id, recipe_id, user_id, idempotency_key, status, cooked_at, confirmed_at, notes)
VALUES
  (1, 1, 2, 1, 'seed-cook-2026-09-20-001', 'CONFIRMED',
   DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY), 'Anchovy sambal cooked for dinner.'),
  (2, 1, 1, 2, 'seed-cook-2026-09-25-001', 'DRAFT', NULL, NULL, 'Breakfast bowl planned, not cooked yet.');

-- ------------------------------------------------------------
-- recipe_cook_session_items
-- Session 1 links to the CONSUME transactions 107 and 108.
-- ------------------------------------------------------------
INSERT INTO recipe_cook_session_items
  (session_item_id, session_id, inventory_item_id, ingredient_id, planned_quantity, used_quantity,
   unit, is_selected, transaction_id)
VALUES
  (1, 1, 102, 5, 0.250, 0.250, 'kg',  TRUE, 107),
  (2, 1, 105, 6, 0.750, 0.500, 'kg',  TRUE, 108),
  (3, 2, 101, 1, 1.000, 1.000, 'pcs', TRUE, NULL);

-- ------------------------------------------------------------
-- donation_centres
-- Simplified Iteration 3 shape: no address_line2, no country, no
-- accepts_food_donations and no accepted_categories columns.
-- ------------------------------------------------------------
INSERT INTO donation_centres
  (centre_id, name, organisation_type, description, address_line1, city, state, postcode,
   latitude, longitude, phone, email, website_url, operating_hours, verification_source_url,
   donation_requirements, is_active)
VALUES
  (900001, 'Sri Murni Care Home', 'CARE_HOME',
   'Residential care home that accepts fresh and shelf-stable food for its kitchen.',
   'No. 12, Jalan SS2/24', 'Petaling Jaya', 'Selangor', '47300',
   3.1178000, 101.6220000, '+60 3-7876 1234', 'donations@srimurni-care.example',
   'https://example.com/pantrysentry/centres/sri-murni', 'Mon-Sat 09:00-17:00',
   'https://example.com/pantrysentry/verify/sri-murni',
   'Fresh fruit and vegetables, sealed dry goods. No opened packaging.', TRUE),
  (900002, 'Kuala Lumpur Community Food Bank', 'FOOD_BANK',
   'City-wide food bank with a weekly community distribution.',
   'Jalan Tun Razak', 'Kuala Lumpur', 'Wilayah Persekutuan', '50400',
   3.1730000, 101.7030000, '+60 3-2110 5678', 'hello@klfoodbank.example',
   'https://example.com/pantrysentry/centres/kl-food-bank', 'Mon-Fri 10:00-18:00',
   'https://example.com/pantrysentry/verify/kl-food-bank',
   'Canned and packaged food only. Check the expiry date on arrival.', TRUE),
  (900003, 'Penang Community Fridge', 'COMMUNITY_FRIDGE',
   'Open community fridge where neighbours share surplus food.',
   'Lebuh Campbell', 'George Town', 'Penang', '10100',
   5.4141000, 100.3292000, NULL, 'penangfridge@example.com',
   'https://example.com/pantrysentry/centres/penang-fridge', 'Daily 08:00-22:00',
   'https://example.com/pantrysentry/verify/penang-fridge',
   'Whole fruit, bread and unopened chilled items.', TRUE);

-- ------------------------------------------------------------
-- donation_centre_accepted_foods
-- Simplified from the earlier needs-style draft to the
-- donation_centre_accepted_foods table with the 8 agreed columns.
-- ------------------------------------------------------------
INSERT INTO donation_centre_accepted_foods
  (need_id, centre_id, category_id, item_name, notes, is_active)
VALUES
  (900001, 900001, 5,  'Fresh fruit',        'Whole fruit only, no cut fruit.', TRUE),
  (900002, 900001, 4,  'Leafy vegetables',   'Delivered chilled where possible.', TRUE),
  (900003, 900002, 13, 'Canned goods',       'Cans must be undented and in date.', TRUE),
  (900004, 900002, 15, 'Rice and dry staples', 'Sealed packets of rice, flour and noodles.', TRUE),
  (900005, 900003, 5,  'Whole fruit',        'Any ripe whole fruit is welcome.', TRUE),
  (900006, 900003, 12, 'Bread and baked goods', 'Same-day bread only.', FALSE);

-- ------------------------------------------------------------
-- donation_records (one PENDING request for the Epic 7 tests)
-- A PENDING record reserves stock logically but does not move inventory.
-- ------------------------------------------------------------
INSERT INTO donation_records
  (donation_id, team_id, centre_id, user_id, status, drop_off_window_start, drop_off_window_end,
   declaration_agreed, donated_at, notes)
VALUES
  (1, 1, 900001, 1, 'PENDING',
   DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 9 HOUR),
   DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 17 HOUR),
   TRUE, NULL, 'Seed donation request waiting for drop-off.');

-- ------------------------------------------------------------
-- donation_record_items
-- transaction_id stays NULL until the donation is completed, which is how
-- the application keeps PENDING donations out of the stock ledger.
-- `condition` is quoted because CONDITION is a reserved MySQL keyword.
-- ------------------------------------------------------------
INSERT INTO donation_record_items
  (donation_item_id, donation_id, inventory_item_id, quantity, unit, `condition`,
   expiry_date_at_donation, photo_url, transaction_id)
VALUES
  (1, 1, 101, 1.00, 'pcs', 'GOOD', DATE_ADD(CURDATE(), INTERVAL 2 DAY), NULL, NULL),
  (2, 1, 103, 1.00, 'pcs', 'GOOD', DATE_ADD(CURDATE(), INTERVAL 4 DAY), NULL, NULL);

-- ------------------------------------------------------------
-- emission_factors
-- Category-level factors. Category 4 (Vegetables) is intentionally absent so
-- that the Epic 8 exclusion case can be demonstrated.
-- ------------------------------------------------------------
INSERT INTO emission_factors
  (factor_id, factor_name, category_id, reference_id, food_type, factor_kg_co2e_per_kg,
   source_name, source_url, source_version, publication_date, valid_from, valid_to, region, is_active)
VALUES
  (900001, 'Meat and processed meat average', 2, NULL, 'Meat (average)', 27.000000,
   'Poore and Nemecek (2018), via Our World in Data',
   'https://ourworldindata.org/food-choice-vs-eating-local', '2018-v1', '2018-06-01',
   '2018-06-01', NULL, 'GLOBAL', TRUE),
  (900002, 'Seafood average', 3, NULL, 'Seafood (average)', 6.100000,
   'Poore and Nemecek (2018), via Our World in Data',
   'https://ourworldindata.org/food-choice-vs-eating-local', '2018-v1', '2018-06-01',
   '2018-06-01', NULL, 'GLOBAL', TRUE),
  (900003, 'Tropical fruit average', 5, NULL, 'Fruit (tropical average)', 0.400000,
   'Poore and Nemecek (2018), via Our World in Data',
   'https://ourworldindata.org/food-choice-vs-eating-local', '2018-v1', '2018-06-01',
   '2018-06-01', NULL, 'GLOBAL', TRUE),
  (900004, 'Shelf-stable grains and dry staples', 15, NULL, 'Grains and dry staples', 1.400000,
   'Poore and Nemecek (2018), via Our World in Data',
   'https://ourworldindata.org/food-choice-vs-eating-local', '2018-v1', '2018-06-01',
   '2018-06-01', NULL, 'GLOBAL', TRUE);

-- ------------------------------------------------------------
-- quantity_conversions
-- Generic unit conversions plus two product-specific fruit weights.
-- ------------------------------------------------------------
INSERT INTO quantity_conversions
  (conversion_id, reference_id, from_unit, to_unit, factor, is_assumed, source_name, source_url, notes, is_active)
VALUES
  (900001, NULL, 'dozen', 'pcs', 12.00000000, TRUE,  'PantrySentry unit policy', NULL, 'Standard dozen conversion used by the app.', TRUE),
  (900002, NULL, 'g',     'kg',  0.00100000,  TRUE,  'PantrySentry unit policy', NULL, 'Metric mass conversion.', TRUE),
  (900003, NULL, 'ml',    'L',   0.00100000,  TRUE,  'PantrySentry unit policy', NULL, 'Metric volume conversion.', TRUE),
  (900004, 2,    'pcs',   'kg',  0.50000000,  FALSE, 'PantrySentry test kitchen',
   'https://example.com/pantrysentry/conversions/papaya', 'Average papaya fruit weighs 0.5 kg.', TRUE),
  (900005, 4,    'pcs',   'kg',  0.15000000,  TRUE,  'PantrySentry test kitchen',
   'https://example.com/pantrysentry/conversions/sapodilla', 'Assumed average sapodilla fruit weight.', TRUE);

-- ------------------------------------------------------------
-- waste_impact_assessments
-- Assessment 1 and 2 are ASSESSED (factor and conversion available).
-- Assessment 3 is EXCLUDED because no active emission factor exists for
-- category 4 (Vegetables).
-- ------------------------------------------------------------
INSERT INTO waste_impact_assessments
  (assessment_id, team_id, inventory_item_id, transaction_id, product_id, reference_id, category_id,
   discarded_quantity, discarded_unit, converted_weight_kg, conversion_id, factor_id,
   factor_kg_co2e_per_kg_snapshot, factor_source_name_snapshot, factor_source_version_snapshot,
   calculation_method_version, footprint_kg_co2e, assessment_status, exclusion_reason,
   calculation_notes, discarded_at, assessed_at)
VALUES
  (1, 2, 6, 11, 2, 2, 5, 2.000, 'pcs', 1.000000, 900004, 900003,
   0.400000, 'Poore and Nemecek (2018), via Our World in Data', '2018-v1', 'v1',
   0.400000, 'ASSESSED', NULL,
   'Papaya weight converted from pieces with conversion 4.', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY)),
  (2, 1, 9, 12, 4, 4, 5, 1.000, 'pcs', 0.150000, 900005, 900003,
   0.400000, 'Poore and Nemecek (2018), via Our World in Data', '2018-v1', 'v1',
   0.060000, 'ASSESSED', NULL,
   'Sapodilla weight converted from pieces with conversion 5.', DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY)),
  (3, 2, 104, 106, 150, 150, 4, 1.000, 'kg', 1.000000, NULL, NULL,
   NULL, NULL, NULL, 'v1', NULL, 'EXCLUDED',
   'No active emission factor for category 4 (Vegetables)',
   'Weight already expressed in kilograms; only the factor is missing.', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY));
