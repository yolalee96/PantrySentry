-- ============================================================
-- PantrySentry - Household Inventory Reminder System
-- Iteration 2
-- Test Script (test_data.sql)
--
-- Execution order : schema.sql -> insert_static_data.sql -> seed_data.sql -> test_data.sql
--
-- How to run (a human executes and inspects the output):
--   mysql -u <user> -p --force < test_data.sql
--
-- Notes:
--   * Some blocks intentionally raise errors (marked [EXPECTED ERROR]).
--     Use --force so that execution does not stop at the first expected
--     error.
--   * Every block runs inside a transaction and rolls back, so the script
--     is repeatable and leaves no test data behind.
--   * Consume, discard and donate operations lock the target row with
--     SELECT ... FOR UPDATE to simulate concurrent-safe stock updates.
--   * Scenario 44 is the only block without a transaction because DDL
--     statements cause implicit commits in MySQL.
-- ============================================================

USE `Real_ProjectV3.0_TM06`;
SET NAMES utf8mb4;

-- ============================================================
-- SCENARIO 1: users.is_verified defaults to FALSE
-- Verify that omitting is_verified stores FALSE.
-- ============================================================
START TRANSACTION;

INSERT INTO users (email, password_hash, display_name)
VALUES ('test.default.verified@example.com', '$2b$12$TEST_HASH_DEFAULT_0001', 'Default Verified User');

SET @default_user = LAST_INSERT_ID();

SELECT user_id, email, is_verified
FROM users
WHERE user_id = @default_user;
-- Expected: is_verified = 0

ROLLBACK;

-- ============================================================
-- SCENARIO 2: users.is_verified stores TRUE
-- ============================================================
START TRANSACTION;

INSERT INTO users (email, password_hash, display_name, is_verified)
VALUES ('test.verified@example.com', '$2b$12$TEST_HASH_TRUE_0001', 'Verified Test User', TRUE);

SET @verified_user = LAST_INSERT_ID();

SELECT user_id, email, is_verified
FROM users
WHERE user_id = @verified_user;
-- Expected: is_verified = 1

ROLLBACK;

-- ============================================================
-- SCENARIO 3: security_questions stores a bcrypt-like answer hash
-- ============================================================
START TRANSACTION;

INSERT INTO security_questions (user_id, question, answer_hash)
VALUES (4, 'Name of first pet', '$2b$12$TEST_ANSWER_HASH_00000000000000000000000000001');

SET @question_id = LAST_INSERT_ID();

SELECT question_id, user_id, question, answer_hash
FROM security_questions
WHERE question_id = @question_id;
-- Expected: 1 row with the stored question and hash (never plain text)

ROLLBACK;

-- ============================================================
-- SCENARIO 4: UNIQUE(user_id, question) rejects a duplicate question
-- User 1 already has the question 'Name of first pet' in the seed data.
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key 'uq_security_questions_user_question' (error 1062)
INSERT INTO security_questions (user_id, question, answer_hash)
VALUES (1, 'Name of first pet', '$2b$12$DUPLICATE_ANSWER_HASH_00000000000000000000001');

ROLLBACK;

-- ============================================================
-- SCENARIO 5: the same question text is allowed for another user
-- ============================================================
START TRANSACTION;

INSERT INTO security_questions (user_id, question, answer_hash)
VALUES (3, 'Name of first pet', '$2b$12$THIRD_USER_ANSWER_HASH_0000000000000000000001');

SELECT user_id, question
FROM security_questions
WHERE question = 'Name of first pet'
ORDER BY user_id;
-- Expected: one row for user 1 and one row for user 3 (same question, different users)

ROLLBACK;

-- ============================================================
-- SCENARIO 6: security_questions FK uses ON DELETE CASCADE
-- Deleting a user removes that user's security questions.
-- ============================================================
START TRANSACTION;

INSERT INTO users (email, password_hash, display_name)
VALUES ('temp.cascade@example.com', '$2b$12$TEMP_CASCADE_HASH_0001', 'Temp Cascade User');
SET @cascade_user = LAST_INSERT_ID();

INSERT INTO security_questions (user_id, question, answer_hash)
VALUES (@cascade_user, 'Name of first pet', '$2b$12$TEMP_CASCADE_ANSWER_000000000000000000001');

SELECT COUNT(*) AS questions_before_delete
FROM security_questions
WHERE user_id = @cascade_user;
-- Expected: 1

DELETE FROM users WHERE user_id = @cascade_user;

SELECT COUNT(*) AS questions_after_delete
FROM security_questions
WHERE user_id = @cascade_user;
-- Expected: 0 (cascade deleted the question rows)

ROLLBACK;

-- ============================================================
-- SCENARIO 7: product_reference can link to a catalogue product
-- The static import links every one of the 200 catalogue products, so this
-- scenario verifies the existing links instead of inserting a new one.
-- ============================================================
START TRANSACTION;

SELECT pr.reference_id, pr.product_id, pr.category_id, pr.product_name, p.product_name AS catalogue_name
FROM product_reference pr
JOIN products p ON p.product_id = pr.product_id
WHERE pr.product_id = 200;
-- Expected: 1 row where product_id = 200 and catalogue_name = 'Beef Knuckle'

SELECT COUNT(*) AS linked_references FROM product_reference WHERE product_id IS NOT NULL;
-- Expected: 200, one linked reference per catalogue product

SELECT COUNT(*) AS category_level_references
FROM product_reference
WHERE product_id IS NULL;
-- Expected: 7681 static category-level references

ROLLBACK;

-- ============================================================
-- SCENARIO 8: UNIQUE(product_id) rejects a second row for the same product
-- Seed data already links product_id 1 (Starfruit).
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key 'uq_product_reference_product_id' (error 1062)
INSERT INTO product_reference (product_id, category_id, product_name, barcode)
VALUES (1, 5, 'Starfruit Duplicate Link', NULL);

ROLLBACK;

-- ============================================================
-- SCENARIO 9: multiple product_reference rows with NULL product_id are allowed
-- MySQL does not compare NULL values in a UNIQUE index, so the
-- UNIQUE(product_id) key still permits unlinked reference rows.
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (product_id, category_id, product_name, barcode) VALUES
  (NULL, 15, 'Test Unlinked Reference One', NULL),
  (NULL, 15, 'Test Unlinked Reference Two', NULL);

SELECT COUNT(*) AS null_product_references
FROM product_reference
WHERE product_id IS NULL;
-- Expected: 7685 (7681 static category-level rows + 2 seed rows + 2 inserted here)

ROLLBACK;

-- ============================================================
-- SCENARIO 10: UNIQUE(category_id, product_name) rejects a duplicate
-- Seed data already contains (category 5, 'Starfruit').
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key 'uq_product_reference_category_name' (error 1062)
INSERT INTO product_reference (product_id, category_id, product_name, barcode)
VALUES (NULL, 5, 'Starfruit', NULL);

ROLLBACK;

-- ============================================================
-- SCENARIO 11: the same product_name is allowed in another category
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (product_id, category_id, product_name, barcode) VALUES
  (NULL, 7,  'Mango Drink', NULL),
  (NULL, 15, 'Mango Drink', NULL);

SELECT category_id, product_name, COUNT(*) AS row_count
FROM product_reference
WHERE product_name = 'Mango Drink'
GROUP BY category_id, product_name
ORDER BY category_id;
-- Expected: two rows, one for category 7 and one for category 15

ROLLBACK;

-- ============================================================
-- SCENARIO 12: UNIQUE barcode rejects a duplicate barcode
-- All static product_reference barcodes are NULL, so this scenario creates
-- its own barcode inside the transaction and then duplicates it.
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (product_id, category_id, product_name, barcode)
VALUES (NULL, 15, 'Temp Barcode Reference One', '9999000000001');

SELECT reference_id, product_name, barcode
FROM product_reference
WHERE barcode = '9999000000001';
-- Expected: 1 row with the created barcode

-- [EXPECTED ERROR] Duplicate entry for key 'uq_product_reference_barcode' (error 1062)
INSERT INTO product_reference (product_id, category_id, product_name, barcode)
VALUES (NULL, 15, 'Temp Barcode Reference Two', '9999000000001');

ROLLBACK;

-- ============================================================
-- SCENARIO 13: multiple NULL barcodes are allowed
-- Empty barcodes must be stored as NULL, never as an empty string.
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (product_id, category_id, product_name, barcode) VALUES
  (NULL, 15, 'Null Barcode Reference One', NULL),
  (NULL, 15, 'Null Barcode Reference Two', NULL),
  (NULL, 15, 'Null Barcode Reference Three', '');

SELECT SUM(barcode IS NULL) AS null_barcodes, SUM(barcode = '') AS empty_string_barcodes
FROM product_reference
WHERE product_name LIKE 'Null Barcode Reference%';
-- Expected: null_barcodes = 2 (the row inserted with '') is stored as an empty string
--           and shows why the application must convert '' to NULL before inserting

ROLLBACK;

-- ============================================================
-- SCENARIO 14: product_reference.is_active defaults to TRUE
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (product_id, category_id, product_name, barcode)
VALUES (NULL, 15, 'Default Active Reference', NULL);

SET @active_reference = LAST_INSERT_ID();

SELECT reference_id, product_name, is_active
FROM product_reference
WHERE reference_id = @active_reference;
-- Expected: is_active = 1

ROLLBACK;

-- ============================================================
-- SCENARIO 15: product_reference.product_id FK uses ON DELETE RESTRICT
-- Product 200 (Beef Knuckle) is linked by the static product_reference data
-- and is not used by any inventory item, so the delete failure below is
-- caused by the product_reference foreign key.
-- ============================================================
START TRANSACTION;

SELECT product_id, product_name
FROM products
WHERE product_id = 200;
-- Expected: 1 catalogue row

SELECT COUNT(*) AS referencing_rows
FROM product_reference
WHERE product_id = 200;
-- Expected: 1 static reference row

-- [EXPECTED ERROR] Cannot delete or update a parent row: product_reference
-- references products (error 1451)
DELETE FROM products WHERE product_id = 200;

ROLLBACK;

-- ============================================================
-- SCENARIO 16: product_reference.category_id FK uses ON DELETE RESTRICT
-- Category 13 (Condiments, Sauces & Canned Goods) has no products in the
-- static catalogue, so the failure comes from a reference-side FK. In
-- Iteration 3 that can be reported by product_reference or by
-- donation_centre_accepted_foods; both use ON DELETE RESTRICT.
-- ============================================================
START TRANSACTION;

SELECT COUNT(*) AS products_in_category_13
FROM products
WHERE category_id = 13;
-- Expected: 0 (only product_reference rows use this category)

-- [EXPECTED ERROR] Cannot delete or update a parent row: product_reference
-- references product_categories (error 1451)
DELETE FROM product_categories WHERE category_id = 13;

ROLLBACK;

-- ============================================================
-- SCENARIO 17: inventory_items.status accepts DONATED and rejects others
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit,
   purchase_date, expiry_date_source, expiry_date, status, discard_reason)
VALUES (1, 12, 1, 1, 2.00, 'pcs', CURDATE(), 'USER_INPUT',
        DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'DONATED', 'DONATED');

SET @donated_item = LAST_INSERT_ID();

SELECT inventory_item_id, status, discard_reason
FROM inventory_items
WHERE inventory_item_id = @donated_item;
-- Expected: status 'DONATED' and discard_reason 'DONATED'

-- [EXPECTED ERROR] Data truncated for column 'status' (error 1265):
-- 'RETURNED' is not a legal enum value
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit,
   purchase_date, expiry_date_source, status)
VALUES (1, 12, 1, 1, 1.00, 'pcs', CURDATE(), 'USER_INPUT', 'RETURNED');

ROLLBACK;

-- ============================================================
-- SCENARIO 18: inventory_transactions.transaction_type accepts DONATE
-- and rejects others
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (1, 1, 'DONATE', 1.00, 'Donated to a neighbour', NULL);

SET @donate_transaction = LAST_INSERT_ID();

SELECT transaction_id, transaction_type, quantity, discard_reason
FROM inventory_transactions
WHERE transaction_id = @donate_transaction;
-- Expected: transaction_type 'DONATE' and discard_reason NULL

-- [EXPECTED ERROR] Data truncated for column 'transaction_type' (error 1265):
-- 'RETURN' is not a legal enum value
INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity)
VALUES (1, 1, 'RETURN', 1.00);

ROLLBACK;

-- ============================================================
-- SCENARIO 19: donation lifecycle and discard_reason CHECK constraint
-- A DONATE row must keep the transaction-level discard_reason NULL,
-- while a DISCARD row must provide one.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 1
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (1, 1, 'DONATE', 5.00, 'Full case donated', NULL);

UPDATE inventory_items
SET status = 'DONATED',
    discard_reason = 'DONATED',
    checkout_date = NOW(),
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 1;

SELECT i.inventory_item_id, i.status, i.discard_reason,
       t.transaction_type, t.discard_reason AS txn_discard_reason
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 1
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: item status 'DONATED', item discard_reason 'DONATED',
--           transaction type 'DONATE', transaction discard_reason NULL

-- [EXPECTED ERROR] Check constraint 'chk_inventory_transactions_discard_reason'
-- is violated (error 3819): a DONATE row must not carry a discard_reason
INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, discard_reason)
VALUES (1, 1, 'DONATE', 1.00, 'EXPIRED');

ROLLBACK;

-- ============================================================
-- SCENARIO 20: new inventory_items columns round-trip
-- Covers unit (explicit and default), notes, discard_reason and
-- consumed_amount.
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date_source, expiry_date, status, discard_reason, consumed_amount)
VALUES (1, 3, 1, 1, 0.75, 'kg', 'Half a packet left', CURDATE(), 'USER_INPUT',
        DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'CONSUMED', NULL, '0.75');

SET @unit_item = LAST_INSERT_ID();

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity,
   purchase_date, expiry_date_source, expiry_date)
VALUES (1, 3, 1, 1, 1.00, CURDATE(), 'USER_INPUT', DATE_ADD(CURDATE(), INTERVAL 2 DAY));

SET @default_unit_item = LAST_INSERT_ID();

SELECT inventory_item_id, unit, notes, consumed_amount
FROM inventory_items
WHERE inventory_item_id = @unit_item;
-- Expected: unit 'kg', notes 'Half a packet left', consumed_amount '0.75'

SELECT inventory_item_id, unit, notes
FROM inventory_items
WHERE inventory_item_id = @default_unit_item;
-- Expected: unit 'pcs' (column default) and notes NULL

ROLLBACK;

-- ============================================================
-- SCENARIO 21: static data and seed data loading check
-- insert_static_data.sql must be executed before seed_data.sql.
-- ============================================================
START TRANSACTION;

SELECT 'storage_types' AS table_name, COUNT(*) AS row_count FROM storage_types
UNION ALL SELECT 'product_categories', COUNT(*) FROM product_categories
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'shelf_life_rules', COUNT(*) FROM shelf_life_rules
UNION ALL SELECT 'users', COUNT(*) FROM users
UNION ALL SELECT 'teams', COUNT(*) FROM teams
UNION ALL SELECT 'security_questions', COUNT(*) FROM security_questions
UNION ALL SELECT 'product_reference', COUNT(*) FROM product_reference
UNION ALL SELECT 'product_keyword_mapping', COUNT(*) FROM product_keyword_mapping
UNION ALL SELECT 'price_item_reference', COUNT(*) FROM price_item_reference
UNION ALL SELECT 'price_observations', COUNT(*) FROM price_observations
UNION ALL SELECT 'inventory_items', COUNT(*) FROM inventory_items
UNION ALL SELECT 'inventory_transactions', COUNT(*) FROM inventory_transactions
UNION ALL SELECT 'reminders', COUNT(*) FROM reminders
UNION ALL SELECT 'notification_recipients', COUNT(*) FROM notification_recipients
ORDER BY table_name;

SELECT IF(COUNT(*) = 3, 'PASS', 'FAIL') AS storage_types_check FROM storage_types;
SELECT IF(COUNT(*) = 16, 'PASS', 'FAIL') AS categories_check FROM product_categories;
SELECT IF(COUNT(*) = 200, 'PASS', 'FAIL') AS static_products_check FROM products;
SELECT IF(COUNT(*) = 612, 'PASS', 'FAIL') AS static_rules_check FROM shelf_life_rules;
SELECT IF(COUNT(*) >= 4, 'PASS', 'FAIL') AS seed_users_check FROM users;
SELECT IF(SUM(is_verified) >= 1 AND SUM(is_verified = 0) >= 1, 'PASS', 'FAIL') AS verified_flags_check FROM users;
SELECT IF(COUNT(*) >= 4, 'PASS', 'FAIL') AS security_questions_check FROM security_questions;
SELECT IF(SUM(product_id IS NOT NULL) >= 1 AND SUM(product_id IS NULL) >= 2, 'PASS', 'FAIL') AS reference_link_check
FROM product_reference;
SELECT IF(SUM(status = 'DONATED') >= 1, 'PASS', 'FAIL') AS donated_items_check FROM inventory_items;
SELECT IF(SUM(transaction_type = 'DONATE') >= 1, 'PASS', 'FAIL') AS donate_txn_check FROM inventory_transactions;
SELECT IF(SUM(discard_reason IS NOT NULL) >= 1 AND SUM(consumed_amount IS NOT NULL) >= 1,
          'PASS', 'FAIL') AS disposal_columns_check FROM inventory_items;
SELECT IF(COUNT(*) = 7883, 'PASS', 'FAIL') AS product_reference_check FROM product_reference;
SELECT IF(COUNT(*) = 24463, 'PASS', 'FAIL') AS keyword_mapping_check FROM product_keyword_mapping;
SELECT IF(COUNT(*) = 286, 'PASS', 'FAIL') AS price_item_check FROM price_item_reference;
SELECT IF(COUNT(*) = 2003, 'PASS', 'FAIL') AS price_observation_check FROM price_observations;
SELECT IF(SUM(price IS NOT NULL) >= 1 AND SUM(price IS NULL) >= 1, 'PASS', 'FAIL') AS item_price_check
FROM inventory_items;
SELECT IF(COUNT(DISTINCT item_code) = 284, 'PASS', 'FAIL') AS priced_item_coverage_check
FROM price_observations WHERE item_code < 900000;
SELECT IF(COUNT(*) = 0, 'PASS', 'FAIL') AS orphan_reference_check
FROM product_keyword_mapping km
LEFT JOIN product_reference pr ON pr.reference_id = km.reference_id
WHERE pr.reference_id IS NULL;
-- Expected: every check PASS

ROLLBACK;

-- ============================================================
-- SCENARIO 22: product_keyword_mapping insert and unique key
-- The unique key is (reference_id, normalized_keyword, match_type).
-- ============================================================
START TRANSACTION;

INSERT INTO product_keyword_mapping
  (reference_id, keyword, normalized_keyword, match_type, source_name, source_url, source_locator, is_active)
VALUES
  (1, 'Test Keyword Mangosteen', 'test keyword mangosteen', 'TEXT', 'Edge case test',
   'https://example.com/pantrysentry/tests/keyword-insert', 'test/keyword/insert', TRUE);

SET @mapping_id = LAST_INSERT_ID();

SELECT mapping_id, reference_id, keyword, normalized_keyword, match_type, is_active
FROM product_keyword_mapping
WHERE mapping_id = @mapping_id;
-- Expected: 1 row with the stored keyword and is_active = 1

-- [EXPECTED ERROR] Duplicate entry for key
-- 'uq_product_keyword_mapping_reference_keyword_type' (error 1062): the
-- normalized keyword and match_type already exist for this reference
INSERT INTO product_keyword_mapping
  (reference_id, keyword, normalized_keyword, match_type, source_name, source_url)
VALUES
  (1, 'Test Keyword Mangosteen Copy', 'test keyword mangosteen', 'TEXT', 'Edge case test',
   'https://example.com/pantrysentry/tests/keyword-duplicate');

ROLLBACK;

-- ============================================================
-- SCENARIO 23: product_keyword_mapping FK uses ON DELETE RESTRICT
-- A temporary reference row is used so the failure comes from the
-- product_keyword_mapping foreign key.
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (reference_id, product_id, category_id, product_name, barcode, description, is_active)
VALUES (7891, NULL, 15, 'Temp Keyword Reference', NULL, 'Edge case test reference.', TRUE);

INSERT INTO product_keyword_mapping
  (reference_id, keyword, normalized_keyword, match_type, source_name, source_url)
VALUES (7891, 'Temp Restrict Keyword', 'temp restrict keyword', 'TEXT', 'Edge case test',
        'https://example.com/pantrysentry/tests/restrict-keyword');

-- [EXPECTED ERROR] Cannot delete or update a parent row:
-- product_keyword_mapping references product_reference (error 1451)
DELETE FROM product_reference WHERE reference_id = 7891;

ROLLBACK;

-- ============================================================
-- SCENARIO 24: price_item_reference insert and FK ON DELETE RESTRICT
-- item_code identifies one PriceCatcher item and unit; reference_id links
-- it to a PantrySentry recognition reference.
-- ============================================================
START TRANSACTION;

INSERT INTO product_reference (reference_id, product_id, category_id, product_name, barcode, description, is_active)
VALUES (7892, NULL, 15, 'Temp Price Reference', NULL, 'Edge case test reference.', TRUE);

INSERT INTO price_item_reference
  (item_code, reference_id, source_item_name, source_unit, package_quantity_in_base_unit,
   base_unit, median_package_price, mean_package_price, latest_day_median_price,
   median_price_per_base_unit, price_observation_count, latest_observation_date, source_url)
VALUES
  (900003, 7892, 'TEST PRICE ITEM', '1 kg', 1.0000, 'kg', 5.50, 5.60, 5.50, 5.5000,
   1, '2026-09-03', 'https://example.com/pantrysentry/tests/price-item');

SELECT item_code, reference_id, base_unit, median_package_price
FROM price_item_reference
WHERE item_code = 900003;
-- Expected: 1 row with reference_id 7892 and base_unit 'kg'

-- [EXPECTED ERROR] Cannot delete or update a parent row:
-- price_item_reference references product_reference (error 1451)
DELETE FROM product_reference WHERE reference_id = 7892;

ROLLBACK;

-- ============================================================
-- SCENARIO 25: price_observations insert and unique key
-- The unique key is (observation_date, premise_code, item_code).
-- ============================================================
START TRANSACTION;

INSERT INTO price_observations (observation_date, premise_code, item_code, price_myr)
VALUES ('2026-09-04', 9101, 900001, 12.00);

SELECT observation_id, observation_date, premise_code, item_code, price_myr
FROM price_observations
WHERE premise_code = 9101 AND item_code = 900001;
-- Expected: 1 row with price_myr 12.00

-- [EXPECTED ERROR] Duplicate entry for key
-- 'uq_price_observations_date_premise_item' (error 1062)
INSERT INTO price_observations (observation_date, premise_code, item_code, price_myr)
VALUES ('2026-09-04', 9101, 900001, 13.00);

ROLLBACK;

-- ============================================================
-- SCENARIO 26: price_observations FK uses ON DELETE RESTRICT
-- ============================================================
START TRANSACTION;

INSERT INTO price_item_reference
  (item_code, reference_id, source_item_name, source_unit, package_quantity_in_base_unit,
   base_unit, median_package_price, mean_package_price, latest_day_median_price,
   median_price_per_base_unit, price_observation_count, latest_observation_date, source_url)
VALUES
  (900004, 1, 'TEST OBSERVED PRICE ITEM', '1 kg', 1.0000, 'kg', 4.50, 4.60, 4.50, 4.5000,
   1, '2026-09-05', 'https://example.com/pantrysentry/tests/price-observation');

INSERT INTO price_observations (observation_date, premise_code, item_code, price_myr)
VALUES ('2026-09-05', 9102, 900004, 4.50);

-- [EXPECTED ERROR] Cannot delete or update a parent row:
-- price_observations references price_item_reference (error 1451)
DELETE FROM price_item_reference WHERE item_code = 900004;

ROLLBACK;

-- ============================================================
-- SCENARIO 27: price_observations CHECK price_myr > 0
-- MySQL 8.0.16+ enforces the CHECK constraint. TiDB may not enforce
-- CHECK constraints, so on TiDB this block can succeed and must be
-- reviewed manually.
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR on MySQL] Check constraint
-- 'chk_price_observations_price_myr' is violated (error 3819)
INSERT INTO price_observations (observation_date, premise_code, item_code, price_myr)
VALUES ('2026-09-06', 9103, 900001, 0.00);

ROLLBACK;

-- ============================================================
-- SCENARIO 28: inventory_items.price and the identifier chain
-- Covers the new price column and shows how item_code resolves through
-- reference_id to an optional catalogue product_id.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, unit, notes, price
FROM inventory_items
WHERE inventory_item_id = 1;
-- Expected: the seeded row with unit 'pcs' and price 12.50

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, purchase_date, expiry_date_source)
VALUES (1, 12, 1, 1, 1.00, CURDATE(), 'USER_INPUT');

SET @no_price_item = LAST_INSERT_ID();

SELECT inventory_item_id, unit, notes, price
FROM inventory_items
WHERE inventory_item_id = @no_price_item;
-- Expected: unit 'pcs' (column default), notes NULL and price NULL because
-- no purchase price was supplied yet

SELECT pir.item_code, pir.reference_id, pr.product_name AS reference_name,
       pr.product_id, p.product_name AS catalogue_name
FROM price_item_reference pir
JOIN product_reference pr ON pr.reference_id = pir.reference_id
LEFT JOIN products p ON p.product_id = pr.product_id
WHERE pir.item_code = 1;
-- Expected: 1 row showing the chain item_code -> reference_id -> product_id;
-- catalogue_name is NULL when the reference is a category-level reference

ROLLBACK;

-- ============================================================
-- SCENARIO 29: Iteration 3 seed data loading check
-- Verifies that the Iteration 3 seed data for Epic 6, Epic 7 and Epic 8
-- was loaded on top of the Iteration 2 seed data.
-- ============================================================
START TRANSACTION;

SELECT 'recipes' AS table_name, COUNT(*) AS row_count FROM recipes
UNION ALL SELECT 'recipe_ingredients', COUNT(*) FROM recipe_ingredients
UNION ALL SELECT 'recipe_cook_sessions', COUNT(*) FROM recipe_cook_sessions
UNION ALL SELECT 'recipe_cook_session_items', COUNT(*) FROM recipe_cook_session_items
UNION ALL SELECT 'donation_centres', COUNT(*) FROM donation_centres
UNION ALL SELECT 'donation_centre_accepted_foods', COUNT(*) FROM donation_centre_accepted_foods
UNION ALL SELECT 'donation_records', COUNT(*) FROM donation_records
UNION ALL SELECT 'donation_record_items', COUNT(*) FROM donation_record_items
UNION ALL SELECT 'emission_factors', COUNT(*) FROM emission_factors
UNION ALL SELECT 'quantity_conversions', COUNT(*) FROM quantity_conversions
UNION ALL SELECT 'waste_impact_assessments', COUNT(*) FROM waste_impact_assessments
ORDER BY table_name;

SELECT IF(COUNT(*) >= 3, 'PASS', 'FAIL') AS recipes_check FROM recipes;
SELECT IF(COUNT(*) >= 12, 'PASS', 'FAIL') AS ingredients_check FROM recipe_ingredients;
SELECT IF(COUNT(*) >= 3, 'PASS', 'FAIL') AS donation_centres_check FROM donation_centres;
SELECT IF(COUNT(*) >= 6, 'PASS', 'FAIL') AS accepted_foods_check FROM donation_centre_accepted_foods;
SELECT IF(COUNT(*) = 1, 'PASS', 'FAIL') AS pending_donation_check FROM donation_records WHERE status = 'PENDING';
SELECT IF(COUNT(*) = 2, 'PASS', 'FAIL') AS donation_items_check FROM donation_record_items;
SELECT IF(COUNT(*) >= 4, 'PASS', 'FAIL') AS emission_factors_check FROM emission_factors;
SELECT IF(COUNT(*) >= 5, 'PASS', 'FAIL') AS conversions_check FROM quantity_conversions;
SELECT IF(SUM(assessment_status = 'ASSESSED') = 2 AND SUM(assessment_status = 'EXCLUDED') = 1,
          'PASS', 'FAIL') AS assessment_mix_check FROM waste_impact_assessments;
SELECT IF(COUNT(*) = 5, 'PASS', 'FAIL') AS epic6_stock_check FROM inventory_items WHERE inventory_item_id BETWEEN 101 AND 105;
SELECT IF(COUNT(*) = 8, 'PASS', 'FAIL') AS epic6_txn_check FROM inventory_transactions WHERE transaction_id BETWEEN 101 AND 108;
-- Expected: every check PASS

ROLLBACK;

-- ============================================================
-- SCENARIO 30: AC 6.1 - recipes sorted by soonest-expiring ingredients
-- Recipes are ranked by the nearest expiry date of the matching stock rows
-- of the requesting team (team 1 here).
-- ============================================================
START TRANSACTION;

SELECT r.recipe_id, r.title,
       COUNT(i.inventory_item_id) AS matched_stock_rows,
       MIN(i.expiry_date) AS soonest_expiry_date,
       DATEDIFF(MIN(i.expiry_date), CURDATE()) AS days_until_expiry
FROM recipes r
JOIN recipe_ingredients ri ON ri.recipe_id = r.recipe_id
LEFT JOIN product_reference pr ON pr.reference_id = ri.reference_id
LEFT JOIN inventory_items i
       ON i.team_id = 1
      AND i.product_id = pr.product_id
      AND i.status = 'IN_STOCK'
WHERE r.is_active = TRUE
GROUP BY r.recipe_id, r.title
ORDER BY days_until_expiry IS NULL, days_until_expiry, r.recipe_id;
-- Expected order: recipe 2 first (anchovy stock expires in 1 day), then
-- recipe 1 and recipe 3, which both match stock expiring in 2 days; the tie
-- is broken by recipe_id. The Iteration 2 seed data also holds anchovy and
-- water spinach, so recipes 2 and 3 match stock from both iterations.

ROLLBACK;

-- ============================================================
-- SCENARIO 31: AC 6.2 - recipe detail with available, partial and missing
-- ingredients plus the required-versus-available quantity comparison.
-- ============================================================
START TRANSACTION;

SELECT ri.sort_order, ri.ingredient_name, ri.quantity AS required_quantity, ri.unit AS required_unit,
       ri.is_optional, i.inventory_item_id, i.quantity AS available_quantity,
       i.unit AS available_unit, i.expiry_date,
       CASE WHEN i.inventory_item_id IS NULL THEN 'MISSING'
            WHEN i.quantity >= ri.quantity THEN 'AVAILABLE'
            ELSE 'PARTIAL' END AS availability
FROM recipe_ingredients ri
LEFT JOIN product_reference pr ON pr.reference_id = ri.reference_id
LEFT JOIN inventory_items i
       ON i.team_id = 1
      AND i.product_id = pr.product_id
      AND i.status = 'IN_STOCK'
WHERE ri.recipe_id = 2
ORDER BY ri.sort_order;
-- Expected: one row per matching stock row -> two anchovy rows (both
-- AVAILABLE), one water spinach row AVAILABLE and one PARTIAL, plus the two
-- free-text ingredients reported as MISSING. The optional cooking oil is
-- still listed and flagged with is_optional = 1.

-- Aggregated view of the same recipe: total stock per ingredient.
SELECT ri.sort_order, ri.ingredient_name, ri.quantity AS required_quantity, ri.unit AS required_unit,
       COUNT(i.inventory_item_id) AS stock_rows,
       SUM(i.quantity) AS total_available_quantity,
       CASE WHEN COUNT(i.inventory_item_id) = 0 THEN 'MISSING'
            WHEN SUM(i.quantity) >= ri.quantity THEN 'AVAILABLE'
            ELSE 'PARTIAL' END AS availability
FROM recipe_ingredients ri
LEFT JOIN product_reference pr ON pr.reference_id = ri.reference_id
LEFT JOIN inventory_items i
       ON i.team_id = 1
      AND i.product_id = pr.product_id
      AND i.status = 'IN_STOCK'
WHERE ri.recipe_id = 2
GROUP BY ri.sort_order, ri.ingredient_name, ri.quantity, ri.unit
ORDER BY ri.sort_order;
-- Expected: 4 rows -> anchovy AVAILABLE (0.75 kg across 2 stock rows),
-- water spinach AVAILABLE (1.50 kg across 2 stock rows), dried chilli paste
-- MISSING and cooking oil MISSING

ROLLBACK;

-- ============================================================
-- SCENARIO 32: AC 6.3 - record cooking usage, deduct stock and link the
-- CONSUME transaction to the cook session item.
-- ============================================================
START TRANSACTION;

SET @idem_key = 'test-cook-2026-10-02-001';

INSERT INTO recipe_cook_sessions
  (team_id, recipe_id, user_id, idempotency_key, status, cooked_at, confirmed_at, notes)
VALUES (1, 2, 1, @idem_key, 'CONFIRMED', NOW(), NOW(), 'AC 6.3 cooking session');
SET @session_id = LAST_INSERT_ID();

SELECT inventory_item_id, quantity
FROM inventory_items
WHERE inventory_item_id = 102
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (102, 1, 'CONSUME', 0.10, 'AC 6.3 cooking deduction', NULL);
SET @txn_id = LAST_INSERT_ID();

INSERT INTO recipe_cook_session_items
  (session_id, inventory_item_id, ingredient_id, planned_quantity, used_quantity, unit, is_selected, transaction_id)
VALUES (@session_id, 102, 5, 0.250, 0.100, 'kg', TRUE, @txn_id);

UPDATE inventory_items
SET quantity = quantity - 0.10,
    consumed_amount = '0.10',
    updated_at = NOW()
WHERE inventory_item_id = 102;

SELECT s.session_id, s.status, s.idempotency_key, si.inventory_item_id,
       si.planned_quantity, si.used_quantity, si.unit,
       i.quantity AS remaining_quantity, t.transaction_type, t.quantity AS txn_quantity
FROM recipe_cook_sessions s
JOIN recipe_cook_session_items si ON si.session_id = s.session_id
JOIN inventory_items i ON i.inventory_item_id = si.inventory_item_id
JOIN inventory_transactions t ON t.transaction_id = si.transaction_id
WHERE s.session_id = @session_id;
-- Expected: 1 row; CONSUME 0.10 kg recorded, remaining quantity 0.15 kg

ROLLBACK;

-- ============================================================
-- SCENARIO 33: AC 6.3 - idempotent cook session and duplicate item guard
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key
-- 'uq_recipe_cook_sessions_team_idempotency' (error 1062): the same team
-- already used this idempotency key
INSERT INTO recipe_cook_sessions
  (team_id, recipe_id, user_id, idempotency_key, status)
VALUES (1, 1, 1, 'seed-cook-2026-09-20-001', 'CONFIRMED');

-- [EXPECTED ERROR] Duplicate entry for key
-- 'uq_recipe_cook_session_items_session_inventory' (error 1062): inventory
-- item 102 is already part of session 1
INSERT INTO recipe_cook_session_items
  (session_id, inventory_item_id, planned_quantity, used_quantity, unit)
VALUES (1, 102, 0.250, 0.250, 'kg');

SELECT COUNT(*) AS sessions_with_key
FROM recipe_cook_sessions
WHERE team_id = 1 AND idempotency_key = 'seed-cook-2026-09-20-001';
-- Expected: 1 (no duplicate session was created)

ROLLBACK;

-- ============================================================
-- SCENARIO 34: AC 7.1 / 7.2 - donation centre search, distance ordering
-- and a search with no results. Distance uses the haversine formula so no
-- spatial extension is required on MySQL or TiDB.
-- ============================================================
START TRANSACTION;

SELECT centre_id, name, city, postcode, organisation_type,
       ROUND(6371 * ACOS(
         LEAST(1, GREATEST(-1,
           COS(RADIANS(3.1390000)) * COS(RADIANS(latitude))
             * COS(RADIANS(longitude) - RADIANS(101.6869000))
           + SIN(RADIANS(3.1390000)) * SIN(RADIANS(latitude))
         ))
       ), 2) AS distance_km
FROM donation_centres
WHERE is_active = TRUE
  AND (name LIKE '%food%' OR city LIKE '%kuala%' OR description LIKE '%food%')
ORDER BY distance_km
LIMIT 5;
-- Expected: the Kuala Lumpur food bank is the closest centre to the
-- Kuala Lumpur reference point, followed by the Petaling Jaya care home

SELECT COUNT(*) AS no_result_matches
FROM donation_centres
WHERE is_active = TRUE
  AND (name LIKE '%zzzz%' OR city LIKE '%zzzz%' OR description LIKE '%zzzz%');
-- Expected: 0 (a search with no results must return an empty list, not an error)

ROLLBACK;

-- ============================================================
-- SCENARIO 35: AC 7.2 - submitting a donation request does not move stock
-- A PENDING donation only reserves the items logically.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 103
FOR UPDATE;

SELECT quantity AS quantity_before
FROM inventory_items
WHERE inventory_item_id = 103;
-- Expected: 2.00 pcs before the request

INSERT INTO donation_records
  (team_id, centre_id, user_id, status, drop_off_window_start, drop_off_window_end, declaration_agreed, notes)
VALUES (1, 1, 1, 'PENDING', NOW(), DATE_ADD(NOW(), INTERVAL 8 HOUR), TRUE, 'AC 7.2 donation request');
SET @donation_id = LAST_INSERT_ID();

INSERT INTO donation_record_items
  (donation_id, inventory_item_id, quantity, unit, `condition`, expiry_date_at_donation, transaction_id)
VALUES (@donation_id, 103, 1.00, 'pcs', 'GOOD', DATE_ADD(CURDATE(), INTERVAL 4 DAY), NULL);

SELECT i.quantity AS quantity_after, i.status AS item_status, d.status AS donation_status,
       (SELECT COUNT(*) FROM inventory_transactions t
         WHERE t.inventory_item_id = 103 AND t.transaction_type = 'DONATE') AS donate_transactions
FROM inventory_items i
JOIN donation_records d ON d.donation_id = @donation_id
WHERE i.inventory_item_id = 103;
-- Expected: quantity unchanged (2.00), item IN_STOCK, donation PENDING and
-- 0 DONATE transactions

ROLLBACK;

-- ============================================================
-- SCENARIO 36: AC 7.3 - completing a donation deducts inventory and writes
-- DONATE transactions for every donated item.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity
FROM inventory_items
WHERE inventory_item_id IN (101, 103)
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (101, 1, 'DONATE', 1.00, 'AC 7.3 donation completed', NULL);
SET @txn_101 = LAST_INSERT_ID();

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (103, 2, 'DONATE', 1.00, 'AC 7.3 donation completed', NULL);
SET @txn_103 = LAST_INSERT_ID();

UPDATE donation_record_items SET transaction_id = @txn_101 WHERE donation_id = 1 AND inventory_item_id = 101;
UPDATE donation_record_items SET transaction_id = @txn_103 WHERE donation_id = 1 AND inventory_item_id = 103;

UPDATE inventory_items
SET quantity = quantity - 1.00, updated_at = NOW()
WHERE inventory_item_id = 101;

UPDATE inventory_items
SET quantity = quantity - 1.00, updated_at = NOW()
WHERE inventory_item_id = 103;

UPDATE donation_records
SET status = 'COMPLETED', donated_at = NOW()
WHERE donation_id = 1;

SELECT d.donation_id, d.status, d.donated_at,
       dri.inventory_item_id, dri.quantity AS donated_quantity,
       i.quantity AS remaining_quantity,
       t.transaction_type, t.quantity AS txn_quantity, t.discard_reason
FROM donation_records d
JOIN donation_record_items dri ON dri.donation_id = d.donation_id
JOIN inventory_items i ON i.inventory_item_id = dri.inventory_item_id
JOIN inventory_transactions t ON t.transaction_id = dri.transaction_id
WHERE d.donation_id = 1
ORDER BY dri.inventory_item_id;
-- Expected: donation COMPLETED with 2 rows; item 101 keeps 2.00 pcs and item
-- 103 keeps 1.00 pcs; both transactions are DONATE with discard_reason NULL

ROLLBACK;

-- ============================================================
-- SCENARIO 37: donation constraint checks
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key
-- 'uq_donation_record_items_donation_inventory' (error 1062)
INSERT INTO donation_record_items (donation_id, inventory_item_id, quantity, unit)
VALUES (1, 101, 1.00, 'pcs');

-- [EXPECTED ERROR] Cannot delete or update a parent row: donation_records
-- references donation_centres (error 1451)
DELETE FROM donation_centres WHERE centre_id = 900001;

-- [EXPECTED ERROR] Cannot delete or update a parent row:
-- donation_record_items references inventory_items (error 1451)
DELETE FROM inventory_items WHERE inventory_item_id = 101;

SELECT COUNT(*) AS items_in_donation
FROM donation_record_items
WHERE donation_id = 1;
-- Expected: 2 (the rejected duplicate was not stored)

ROLLBACK;

-- ============================================================
-- SCENARIO 38: recipe cascade and cook-session RESTRICT behaviour
-- ============================================================
START TRANSACTION;

INSERT INTO recipes (title, servings, is_active) VALUES ('Temp Cascade Recipe', 1.00, TRUE);
SET @temp_recipe = LAST_INSERT_ID();

INSERT INTO recipe_ingredients
  (recipe_id, ingredient_name, normalized_ingredient_name, sort_order)
VALUES (@temp_recipe, 'Temp ingredient', 'temp ingredient', 1);

SELECT COUNT(*) AS ingredients_before_delete
FROM recipe_ingredients
WHERE recipe_id = @temp_recipe;
-- Expected: 1

DELETE FROM recipes WHERE recipe_id = @temp_recipe;

SELECT COUNT(*) AS ingredients_after_delete
FROM recipe_ingredients
WHERE recipe_id = @temp_recipe;
-- Expected: 0 (recipe_ingredients cascades with the recipe)

-- [EXPECTED ERROR] Cannot delete or update a parent row:
-- recipe_cook_session_items references inventory_items (error 1451)
DELETE FROM inventory_items WHERE inventory_item_id = 102;

ROLLBACK;

-- ============================================================
-- SCENARIO 39: AC 8.1 - environmental impact estimation
-- The stored footprint must equal converted weight x emission factor.
-- ============================================================
START TRANSACTION;

SELECT w.assessment_id, w.discarded_quantity, w.discarded_unit, w.converted_weight_kg,
       f.factor_kg_co2e_per_kg, w.footprint_kg_co2e,
       ROUND(w.converted_weight_kg * f.factor_kg_co2e_per_kg, 6) AS recomputed_footprint
FROM waste_impact_assessments w
JOIN emission_factors f ON f.factor_id = w.factor_id
WHERE w.assessment_status = 'ASSESSED'
ORDER BY w.assessment_id;
-- Expected: recomputed_footprint equals footprint_kg_co2e for every row

SELECT ROUND(SUM(footprint_kg_co2e), 6) AS total_assessed_footprint
FROM waste_impact_assessments
WHERE assessment_status = 'ASSESSED';
-- Expected: 0.460000 (0.400000 + 0.060000)

ROLLBACK;

-- ============================================================
-- SCENARIO 40: AC 8.1 - missing data must be excluded, not guessed
-- ============================================================
START TRANSACTION;

SELECT COUNT(*) AS active_factors_for_vegetables
FROM emission_factors
WHERE category_id = 4 AND is_active = TRUE;
-- Expected: 0 (no active factor exists for category 4 Vegetables)

SELECT assessment_id, category_id, assessment_status, exclusion_reason, factor_id, footprint_kg_co2e
FROM waste_impact_assessments
WHERE assessment_status = 'EXCLUDED';
-- Expected: 1 row with factor_id NULL, footprint NULL and a reason

INSERT INTO waste_impact_assessments
  (team_id, inventory_item_id, transaction_id, product_id, reference_id, category_id,
   discarded_quantity, discarded_unit, converted_weight_kg, assessment_status,
   exclusion_reason, calculation_notes, discarded_at)
VALUES (2, 104, NULL, 150, 150, 4, 0.500, 'kg', 0.500000, 'EXCLUDED',
        'No active emission factor for category 4 (Vegetables)',
        'AC 8.1 exclusion case', NOW());

SELECT assessment_status, footprint_kg_co2e, exclusion_reason
FROM waste_impact_assessments
WHERE calculation_notes = 'AC 8.1 exclusion case';
-- Expected: EXCLUDED with a NULL footprint

ROLLBACK;

-- ============================================================
-- SCENARIO 41: AC 8.2 - impact summary grouped by category
-- ============================================================
START TRANSACTION;

SELECT w.team_id, c.category_name,
       COUNT(*) AS assessments,
       SUM(w.assessment_status = 'ASSESSED') AS assessed_rows,
       SUM(w.assessment_status = 'EXCLUDED') AS excluded_rows,
       ROUND(SUM(COALESCE(w.footprint_kg_co2e, 0)), 6) AS total_footprint_kg_co2e
FROM waste_impact_assessments w
LEFT JOIN product_categories c ON c.category_id = w.category_id
GROUP BY w.team_id, c.category_name
ORDER BY w.team_id, total_footprint_kg_co2e DESC;
-- Expected: team 2 shows Fruits 0.400000 plus an EXCLUDED Vegetables row,
-- and team 1 shows Fruits 0.060000

ROLLBACK;

-- ============================================================
-- SCENARIO 42: AC 8.3 - weekly and monthly trend with a zero baseline
-- ============================================================
START TRANSACTION;

SELECT DATE_FORMAT(w.discarded_at, '%x-W%v') AS iso_week,
       DATE_FORMAT(w.discarded_at, '%Y-%m') AS month,
       w.assessment_status,
       COUNT(*) AS assessments,
       ROUND(SUM(COALESCE(w.footprint_kg_co2e, 0)), 6) AS footprint_kg_co2e
FROM waste_impact_assessments w
GROUP BY iso_week, month, w.assessment_status
ORDER BY iso_week, w.assessment_status;
-- Expected: one row per (ISO week, month, status) combination

SELECT
  ROUND(COALESCE(SUM(CASE WHEN w.discarded_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                          THEN w.footprint_kg_co2e END), 0), 6) AS last_7_days,
  ROUND(COALESCE(SUM(CASE WHEN w.discarded_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
                           AND w.discarded_at < DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                          THEN w.footprint_kg_co2e END), 0), 6) AS previous_7_days,
  0 AS zero_baseline
FROM waste_impact_assessments w
WHERE w.team_id = 1;
-- Expected: previous_7_days = 0 (the zero baseline) and last_7_days = 0.060000,
-- so a percentage change from a zero baseline must be reported as not comparable

ROLLBACK;

-- ============================================================
-- SCENARIO 43: Epic 6 AI recipe generation cache
-- Verifies the JSON columns, the CASCADE foreign key to teams and the
-- RESTRICT foreign key to users.
-- ============================================================
START TRANSACTION;

INSERT INTO users (email, password_hash, display_name)
VALUES ('temp.ai.generation@example.com', '$2b$12$TEMP_AI_GENERATION_HASH_000000000001', 'Temp AI User');
SET @temp_ai_user = LAST_INSERT_ID();

INSERT INTO teams (team_name) VALUES ('Temp AI Team');
SET @temp_ai_team = LAST_INSERT_ID();

INSERT INTO recipe_ai_generations (team_id, model, input_item_ids, recipe_ids, created_by)
VALUES (@temp_ai_team, 'gemini-flash-latest', '[101, 102]', '[1, 2]', @temp_ai_user);
SET @generation_id = LAST_INSERT_ID();

SELECT generation_id, model,
       JSON_VALID(input_item_ids) AS input_json_valid,
       JSON_VALID(recipe_ids) AS recipe_json_valid,
       JSON_LENGTH(input_item_ids) AS input_item_count,
       JSON_LENGTH(recipe_ids) AS recipe_count,
       JSON_CONTAINS(recipe_ids, '2') AS contains_recipe_2
FROM recipe_ai_generations
WHERE generation_id = @generation_id;
-- Expected: 1 row; both JSON flags 1, counts 2 and 2, contains_recipe_2 = 1

-- [EXPECTED ERROR] Cannot delete or update a parent row: recipe_ai_generations
-- references users (error 1451), because created_by is ON DELETE RESTRICT
DELETE FROM users WHERE user_id = @temp_ai_user;

-- CASCADE: deleting a team removes its cached AI generations
DELETE FROM teams WHERE team_id = @temp_ai_team;

SELECT COUNT(*) AS remaining_generations
FROM recipe_ai_generations
WHERE team_id = @temp_ai_team;
-- Expected: 0 (the team cascade removed the generation row)

ROLLBACK;

-- ============================================================
-- SCENARIO 44: clean schema recreation
-- Drop all 29 tables (reverse dependency order) so the schema can be
-- recreated from scratch. DDL causes implicit commits in MySQL, so this
-- block intentionally runs without a transaction.
--
-- After this block, re-import in order:
--   mysql -u <user> -p < schema.sql
--   mysql -u <user> -p < insert_static_data.sql
--   mysql -u <user> -p < seed_data.sql
-- ============================================================
SET FOREIGN_KEY_CHECKS = 0;

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
DROP TABLE IF EXISTS recipe_ai_generations;
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

SHOW TABLES;
-- Expected: empty result set (no tables remain)
