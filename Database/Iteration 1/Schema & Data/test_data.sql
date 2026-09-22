-- ============================================================
-- Household Inventory Reminder System
-- Test Script (test_data.sql)
--
-- Prerequisite : run schema.sql and seed_data.sql first.
--
-- How to run (a human executes and inspects the output):
--   mysql -u <user> -p --force pantry_buddy < test_data.sql
--
-- Notes:
--   * Some blocks intentionally raise errors (marked
--     [EXPECTED ERROR]). Use --force so the script does not stop.
--   * Every block runs inside a transaction and rolls back, so the
--     script is repeatable without leaving test data behind.
--   * Consume/discard operations lock rows with SELECT ... FOR UPDATE
--     to simulate concurrent-safe stock updates.
--   * Shelf-life lookup tests (scenarios 13-15) verify the rule
--     priority and fallback behavior of shelf_life_rules.
--   * Scenario 36 is the only block without a transaction because
--     DDL statements cause implicit commits in MySQL.
-- ============================================================

USE Real_ProjectV1.0_TM06;
SET NAMES utf8mb4;

-- ============================================================
-- SCENARIO 1: User creation
-- Verify that a new user can be inserted and read back.
-- ============================================================
START TRANSACTION;

INSERT INTO users (email, password_hash, display_name)
VALUES ('test.user1@example.com', '$2b$12$TEST_HASH_PLACEHOLDER_0001', 'Test User One');

SET @test_user1 = LAST_INSERT_ID();

SELECT user_id, email, display_name, created_at
FROM users
WHERE user_id = @test_user1;
-- Expected: exactly 1 row with email 'test.user1@example.com'

ROLLBACK;

-- ============================================================
-- SCENARIO 2: Duplicate email rejection
-- The unique index uq_users_email must reject a second user with
-- an email that already exists in the seed data.
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key 'uq_users_email' (error 1062)
INSERT INTO users (email, password_hash, display_name)
VALUES ('alice.tan@example.com', '$2b$12$DUPLICATE_HASH_0000', 'Duplicate Alice');

ROLLBACK;

-- ============================================================
-- SCENARIO 3: Team creation
-- Verify that a new team can be created.
-- ============================================================
START TRANSACTION;

INSERT INTO teams (team_name)
VALUES ('Test Team Alpha');

SET @test_team = LAST_INSERT_ID();

SELECT team_id, team_name, created_at
FROM teams
WHERE team_id = @test_team;
-- Expected: 1 row, team_name 'Test Team Alpha'

ROLLBACK;

-- ============================================================
-- SCENARIO 4: Admin creation
-- Verify that a user can be added to a team as an ADMIN.
-- ============================================================
START TRANSACTION;

INSERT INTO team_members (team_id, user_id, role, status)
VALUES (2, 1, 'ADMIN', 'ACTIVE');

SELECT team_id, user_id, role, status, joined_at
FROM team_members
WHERE team_id = 2 AND user_id = 1;
-- Expected: 1 row with role 'ADMIN' and status 'ACTIVE'

ROLLBACK;

-- ============================================================
-- SCENARIO 5: Join request
-- Verify that a user can request to join a team.
-- ============================================================
START TRANSACTION;

INSERT INTO join_requests (team_id, user_id, status)
VALUES (1, 4, 'PENDING');

SET @test_request = LAST_INSERT_ID();

SELECT request_id, team_id, user_id, status, requested_at
FROM join_requests
WHERE request_id = @test_request;
-- Expected: 1 row with status 'PENDING'

ROLLBACK;

-- ============================================================
-- SCENARIO 6: Duplicate pending join request prevention
-- MySQL has no partial unique index, so the application layer must
-- reject a second PENDING request for the same (team_id, user_id).
-- The guarded INSERT below simulates that application check.
-- ============================================================
START TRANSACTION;

-- Seed already has a PENDING request from Carol (user 3) for team 1.
INSERT INTO join_requests (team_id, user_id, status, requested_at)
SELECT 1, 3, 'PENDING', NOW()
WHERE NOT EXISTS (
  SELECT 1
  FROM join_requests
  WHERE team_id = 1 AND user_id = 3 AND status = 'PENDING'
);

SELECT COUNT(*) AS pending_requests
FROM join_requests
WHERE team_id = 1 AND user_id = 3 AND status = 'PENDING';
-- Expected: 1 (the guarded INSERT was skipped, no duplicate created)

ROLLBACK;

-- ============================================================
-- SCENARIO 7: Approve join request
-- Verify that an admin can approve a PENDING join request.
-- ============================================================
START TRANSACTION;

UPDATE join_requests
SET status = 'APPROVED', reviewed_at = NOW(), reviewed_by = 1
WHERE team_id = 1 AND user_id = 3 AND status = 'PENDING';

SELECT request_id, team_id, user_id, status, reviewed_at, reviewed_by
FROM join_requests
WHERE team_id = 1 AND user_id = 3;
-- Expected: status 'APPROVED', reviewed_at NOT NULL, reviewed_by = 1

ROLLBACK;

-- ============================================================
-- SCENARIO 8: Decline join request
-- Verify that a join request can be declined.
-- ============================================================
START TRANSACTION;

UPDATE join_requests
SET status = 'DECLINED', reviewed_at = NOW(), reviewed_by = 1
WHERE team_id = 1 AND user_id = 3 AND status = 'PENDING';

SELECT request_id, team_id, user_id, status, reviewed_at, reviewed_by
FROM join_requests
WHERE team_id = 1 AND user_id = 3;
-- Expected: status 'DECLINED', reviewed_at NOT NULL, reviewed_by = 1

ROLLBACK;

-- ============================================================
-- SCENARIO 9: Product creation
-- Verify that a new product can be added to a category.
-- ============================================================
START TRANSACTION;

INSERT INTO products (category_id, product_name, barcode)
VALUES (1, 'Test Oat Milk', '9559999999001');

SET @test_product = LAST_INSERT_ID();

SELECT product_id, category_id, product_name, barcode
FROM products
WHERE product_id = @test_product;
-- Expected: 1 row, category 1, barcode '9559999999001'

ROLLBACK;

-- ============================================================
-- SCENARIO 10: Duplicate barcode rejection
-- The unique index uq_products_barcode must reject a second product
-- with a barcode already used in the seed data.
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Duplicate entry for key 'uq_products_barcode' (error 1062)
INSERT INTO products (category_id, product_name, barcode)
VALUES (1, 'Duplicate Barcode Milk', '9555123400012');

ROLLBACK;

-- ============================================================
-- SCENARIO 11: Inventory creation
-- Verify that an inventory item can be added to a team.
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date, expiry_date_source)
VALUES
  (1, 13, 3, 1, 2.00, 'pcs', NULL, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 90 DAY), 'PACKAGING');

SET @test_item = LAST_INSERT_ID();

SELECT inventory_item_id, team_id, product_id, storage_type_id,
       created_by, quantity, status, expiry_date_source
FROM inventory_items
WHERE inventory_item_id = @test_item;
-- Expected: 1 row, status 'IN_STOCK', expiry source 'PACKAGING'

ROLLBACK;

-- ============================================================
-- SCENARIO 12: Expiry source handling
-- Verify that all three expiry_date_source values can be stored:
-- PACKAGING (printed on package), USER_INPUT (typed by user) and
-- CALCULATED (production date + shelf life).
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   production_date, purchase_date, shelf_life_days, expiry_date, expiry_date_source)
VALUES
  (1, 13, 3, 1, 2.00, 'pcs', NULL, NULL, CURDATE(), NULL, DATE_ADD(CURDATE(), INTERVAL 90 DAY), 'PACKAGING'),
  (1, 11, 3, 1, 1.00, 'pcs', NULL, NULL, CURDATE(), NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY), 'USER_INPUT'),
  (1, 7,  1, 1, 1.00, 'pcs', NULL, DATE_SUB(CURDATE(), INTERVAL 2 DAY), DATE_SUB(CURDATE(), INTERVAL 2 DAY),
   5, DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 2 DAY), INTERVAL 5 DAY), 'CALCULATED');

SELECT inventory_item_id, product_id, expiry_date_source, expiry_date
FROM inventory_items
WHERE created_by = 1
ORDER BY inventory_item_id DESC
LIMIT 3;
-- Expected: three rows, one for each expiry_date_source value

ROLLBACK;

-- ============================================================
-- SCENARIO 13: Product-level rule priority over category-level rule
-- An inventory item whose product has a product-level rule must use
-- that rule (not the category fallback) when expiry_date_source is
-- CALCULATED. A PACKAGING or USER_INPUT date always wins over rules.
-- ============================================================
START TRANSACTION;

-- Product 9 (Cavendish Banana) has a product-level rule for FRIDGE.
-- Lock the rule row to simulate a concurrent-safe lookup.
SELECT rule_id, product_id, category_id, storage_type_id,
       min_days, max_days, recommended_days
FROM shelf_life_rules
WHERE product_id = 9 AND storage_type_id = 1
FOR UPDATE;

-- The lookup must order the product-level rule first (priority 0),
-- before the Fruits category-level fallback (priority 1).
SELECT rule_id, product_id, recommended_days,
       CASE WHEN product_id IS NOT NULL THEN 0 ELSE 1 END AS priority
FROM shelf_life_rules
WHERE (product_id = 9 OR (product_id IS NULL AND category_id = 5))
  AND storage_type_id = 1
ORDER BY priority, rule_id;
-- Expected: product-level rule (product_id = 9, recommended_days = 9.0)
--           first, category fallback (product_id IS NULL) second

-- Calculate the expiry from the product-level rule
-- (recommended_days = 9.0 -> 9 days from production).
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   production_date, purchase_date, shelf_life_days, expiry_date, expiry_date_source)
SELECT 1, 9, 1, 1, 1.00, 'pcs', NULL,
       CURDATE(), CURDATE(),
       CAST(recommended_days AS UNSIGNED),
       DATE_ADD(CURDATE(), INTERVAL CAST(recommended_days AS UNSIGNED) DAY),
       'CALCULATED'
FROM shelf_life_rules
WHERE product_id = 9 AND storage_type_id = 1;

SET @priority_item = LAST_INSERT_ID();

SELECT inventory_item_id, product_id, shelf_life_days, expiry_date, expiry_date_source
FROM inventory_items
WHERE inventory_item_id = @priority_item;
-- Expected: shelf_life_days = 9, expiry_date = CURDATE() + 9 days,
--           source CALCULATED (values from the product-level rule)

-- A PACKAGING item must ignore all rules and use the printed date.
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date, expiry_date_source)
VALUES (1, 9, 1, 1, 1.00, 'pcs', NULL, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 20 DAY), 'PACKAGING');

SET @packaging_item = LAST_INSERT_ID();

SELECT inventory_item_id, expiry_date, expiry_date_source, shelf_life_days
FROM inventory_items
WHERE inventory_item_id = @packaging_item;
-- Expected: expiry_date = CURDATE() + 20 days (printed date wins,
--           rules ignored, shelf_life_days NULL)

ROLLBACK;

-- ============================================================
-- SCENARIO 14: Category-level fallback when no product-level rule exists
-- If a product has no product-level rule, the lookup must fall back
-- to the category-level rule (product_id IS NULL).
-- ============================================================
START TRANSACTION;

-- Create a brand-new product in the Fruits category; it has no
-- product-level rule in shelf_life_rules.
INSERT INTO products (category_id, product_name, barcode)
VALUES (5, 'Test Dragon Fruit', NULL);

SET @fallback_product = LAST_INSERT_ID();

SELECT COUNT(*) AS product_rules
FROM shelf_life_rules
WHERE product_id = @fallback_product;
-- Expected: 0 (no product-level rule for the new product)

-- Lock the category-level fallback row (Fruits + FRIDGE).
SELECT rule_id, product_id, category_id, storage_type_id,
       min_days, max_days, recommended_days
FROM shelf_life_rules
WHERE product_id IS NULL AND category_id = 5 AND storage_type_id = 1
FOR UPDATE;

-- The lookup returns only the category fallback for this product.
SELECT rule_id, product_id, recommended_days,
       CASE WHEN product_id IS NOT NULL THEN 0 ELSE 1 END AS priority
FROM shelf_life_rules
WHERE (product_id = @fallback_product OR (product_id IS NULL AND category_id = 5))
  AND storage_type_id = 1
ORDER BY priority, rule_id;
-- Expected: exactly 1 row, the category fallback (product_id IS NULL,
--           recommended_days = 6.0)

-- Calculate the expiry from the category fallback rule
-- (recommended_days = 6.0 -> 6 days from production).
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   production_date, purchase_date, shelf_life_days, expiry_date, expiry_date_source)
SELECT 1, @fallback_product, 1, 1, 1.00, 'pcs', NULL,
       CURDATE(), CURDATE(),
       CAST(recommended_days AS UNSIGNED),
       DATE_ADD(CURDATE(), INTERVAL CAST(recommended_days AS UNSIGNED) DAY),
       'CALCULATED'
FROM shelf_life_rules
WHERE product_id IS NULL AND category_id = 5 AND storage_type_id = 1;

SET @fallback_item = LAST_INSERT_ID();

SELECT inventory_item_id, product_id, shelf_life_days, expiry_date, expiry_date_source
FROM inventory_items
WHERE inventory_item_id = @fallback_item;
-- Expected: shelf_life_days = 6, expiry_date = CURDATE() + 6 days,
--           source CALCULATED (values from the category fallback rule)

ROLLBACK;

-- ============================================================
-- SCENARIO 15: Non-fresh items ignore rules even when expiry is missing
-- Items in non-fresh categories (is_fresh_food = FALSE) must never
-- receive a calculated expiry date. Their categories only contain
-- NOT_RECOMMENDED placeholder rules (0/0 days).
-- ============================================================
START TRANSACTION;

SELECT c.category_name, r.rule_status, r.min_days, r.max_days, r.recommended_days
FROM product_categories c
JOIN shelf_life_rules r ON r.category_id = c.category_id AND r.product_id IS NULL
WHERE c.is_fresh_food = FALSE
ORDER BY c.category_name, r.storage_type_id;
-- Expected: only NOT_RECOMMENDED placeholder rules with 0/0 days

-- Simulate a snack item with no expiry date (source CALCULATED but no
-- production date or shelf-life days provided).
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date_source, expiry_date)
VALUES (1, 11, 3, 1, 1.00, 'pcs', NULL, CURDATE(), 'CALCULATED', NULL);

-- The lookup for the Snacks category returns only the placeholder rule,
-- so the application must NOT calculate an expiry date.
SELECT r.rule_status, r.min_days, r.max_days
FROM shelf_life_rules r
WHERE r.category_id = (SELECT category_id FROM products WHERE product_id = 11)
  AND r.product_id IS NULL
  AND r.storage_type_id = 3;
-- Expected: 1 row with rule_status 'NOT_RECOMMENDED'

ROLLBACK;

-- ============================================================
-- SCENARIO 16: Static shelf-life calculation support
-- Verify that CALCULATED expiry dates equal
-- production_date + shelf_life_days, both for a new insert and
-- for seed items.
-- ============================================================
START TRANSACTION;

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   production_date, purchase_date, shelf_life_days, expiry_date, expiry_date_source)
VALUES
  (1, 5, 1, 1, 1.00, 'pcs', NULL,
   DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_SUB(CURDATE(), INTERVAL 3 DAY),
   6, DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 3 DAY), INTERVAL 6 DAY), 'CALCULATED');

SELECT inventory_item_id, production_date, shelf_life_days, expiry_date,
       DATE_ADD(production_date, INTERVAL shelf_life_days DAY) AS expected_expiry
FROM inventory_items
WHERE inventory_item_id = LAST_INSERT_ID();
-- Expected: expiry_date equals expected_expiry

-- Same check against seed items with CALCULATED expiry.
SELECT inventory_item_id, production_date, shelf_life_days, expiry_date,
       DATE_ADD(production_date, INTERVAL shelf_life_days DAY) AS expected_expiry
FROM inventory_items
WHERE expiry_date_source = 'CALCULATED';
-- Expected: expiry_date equals expected_expiry on every row

ROLLBACK;

-- ============================================================
-- SCENARIO 17: Partial consumption
-- Lock the row, record a CONSUME transaction for part of the stock
-- and reduce the quantity. The transaction is rolled back afterwards.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 1
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note)
VALUES (1, 1, 'CONSUME', 0.50, 'Partial consumption test');

UPDATE inventory_items
SET quantity = quantity - 0.50,
    consumed_amount = '0.50',
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 1;

SELECT i.inventory_item_id, i.quantity,
       t.transaction_id, t.transaction_type, t.quantity AS consumed_qty
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 1
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: quantity = 1.50, latest transaction type 'CONSUME', qty 0.50

ROLLBACK;

-- ============================================================
-- SCENARIO 18: Full consumption
-- Consume the entire stock of an item and mark it CONSUMED.
-- ============================================================
START TRANSACTION;

SELECT quantity INTO @full_qty
FROM inventory_items
WHERE inventory_item_id = 5
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note)
VALUES (5, 1, 'CONSUME', @full_qty, 'Full consumption test');

UPDATE inventory_items
SET status = 'CONSUMED',
    checkout_date = NOW(),
    consumed_amount = @full_qty,
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 5;

SELECT inventory_item_id, quantity, status, checkout_date
FROM inventory_items
WHERE inventory_item_id = 5;
-- Expected: status 'CONSUMED', checkout_date NOT NULL,
--           quantity unchanged (the CHECK constraint requires > 0)

ROLLBACK;

-- ============================================================
-- SCENARIO 19: Over-consumption rejection
-- Consuming more than the available quantity must be rejected.
-- The conditional UPDATE affects 0 rows, which is how the
-- application layer detects and rejects over-consumption.
-- ============================================================
START TRANSACTION;

SELECT quantity INTO @available_qty
FROM inventory_items
WHERE inventory_item_id = 5
FOR UPDATE;

-- Requested quantity (999.00) exceeds available stock.
UPDATE inventory_items
SET quantity = quantity - 999.00
WHERE inventory_item_id = 5 AND quantity >= 999.00;

SELECT ROW_COUNT() AS over_consume_attempts;
-- Expected: 0 (the UPDATE matched no rows, so the request is rejected)

SELECT inventory_item_id, quantity
FROM inventory_items
WHERE inventory_item_id = 5;
-- Expected: quantity unchanged (12.00)

ROLLBACK;

-- ============================================================
-- SCENARIO 20: Discard
-- Discard an item and record the DISCARD transaction with a
-- non-NULL discard_reason.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 6
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (6, 1, 'DISCARD', 4.00, 'Discard test', 'USER_DISCARDED');

UPDATE inventory_items
SET status = 'DISCARDED',
    checkout_date = NOW(),
    discard_reason = 'USER_DISCARDED',
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 6;

SELECT i.inventory_item_id, i.status, i.checkout_date,
       i.discard_reason, t.transaction_type, t.discard_reason
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 6
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: item status 'DISCARDED' and item discard_reason 'USER_DISCARDED',
--           transaction 'DISCARD' with discard_reason 'USER_DISCARDED'

ROLLBACK;

-- ============================================================
-- SCENARIO 21: Expired discard
-- Discard an item because it was found expired.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 8
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (8, 1, 'DISCARD', 6.00, 'Found expired during fridge check', 'EXPIRED');

UPDATE inventory_items
SET status = 'DISCARDED',
    checkout_date = NOW(),
    discard_reason = 'EXPIRED',
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 8;

SELECT i.inventory_item_id, i.status, i.checkout_date,
       i.discard_reason, t.transaction_type, t.discard_reason
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 8
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: item status 'DISCARDED' and item discard_reason 'EXPIRED',
--           transaction 'DISCARD' with discard_reason 'EXPIRED'

ROLLBACK;

-- ============================================================
-- SCENARIO 22: User-discarded item
-- Discard an item because the user no longer wants it.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 13
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (13, 3, 'DISCARD', 1.00, 'No longer wanted', 'USER_DISCARDED');

UPDATE inventory_items
SET status = 'DISCARDED',
    checkout_date = NOW(),
    discard_reason = 'USER_DISCARDED',
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 13;

SELECT i.inventory_item_id, i.status, i.checkout_date,
       i.discard_reason, t.transaction_type, t.discard_reason
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 13
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: item status 'DISCARDED' and item discard_reason 'USER_DISCARDED',
--           transaction 'DISCARD' with discard_reason 'USER_DISCARDED'

ROLLBACK;

-- ============================================================
-- SCENARIO 23: Item donation (DONATE / DONATED)
-- Verify that an item can be donated: a DONATE transaction is
-- recorded and the item status becomes DONATED with an item-level
-- discard_reason. The transaction-level discard_reason stays NULL
-- because that field is reserved for DISCARD transactions.
-- ============================================================
START TRANSACTION;

SELECT inventory_item_id, quantity, status
FROM inventory_items
WHERE inventory_item_id = 5
FOR UPDATE;

INSERT INTO inventory_transactions
  (inventory_item_id, user_id, transaction_type, quantity, note, discard_reason)
VALUES (5, 1, 'DONATE', 12.00, 'Donated unopened case to a food bank', NULL);

UPDATE inventory_items
SET status = 'DONATED',
    checkout_date = NOW(),
    discard_reason = 'DONATED',
    updated_at = CURRENT_TIMESTAMP
WHERE inventory_item_id = 5;

SELECT i.inventory_item_id, i.status, i.checkout_date, i.discard_reason,
       t.transaction_type, t.discard_reason AS txn_discard_reason
FROM inventory_items i
JOIN inventory_transactions t USING (inventory_item_id)
WHERE i.inventory_item_id = 5
ORDER BY t.transaction_id DESC
LIMIT 1;
-- Expected: item status 'DONATED', item discard_reason 'DONATED',
--           transaction type 'DONATE', transaction discard_reason NULL

ROLLBACK;

-- ============================================================
-- SCENARIO 24: Invalid FK rejection
-- Inserting an inventory item with a non-existent team, product or
-- creator must fail because of the foreign key constraints.
-- ============================================================
START TRANSACTION;

-- [EXPECTED ERROR] Cannot add or update a child row: a foreign key
-- constraint fails (invalid team_id, error 1452)
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date_source)
VALUES (999999, 1, 1, 1, 1.00, 'pcs', NULL, CURDATE(), 'PACKAGING');

ROLLBACK;

START TRANSACTION;

-- [EXPECTED ERROR] Cannot add or update a child row: a foreign key
-- constraint fails (invalid product_id, error 1452)
INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date_source)
VALUES (1, 999999, 1, 1, 1.00, 'pcs', NULL, CURDATE(), 'PACKAGING');

ROLLBACK;

-- ============================================================
-- SCENARIO 25: Product search
-- Verify that products can be searched by name (case-insensitive
-- thanks to the utf8mb4_unicode_ci collation).
-- ============================================================
START TRANSACTION;

SELECT product_id, product_name, barcode
FROM products
WHERE LOWER(product_name) LIKE '%milk%'
ORDER BY product_id;

SELECT COUNT(*) AS milk_products
FROM products
WHERE LOWER(product_name) LIKE '%milk%';
-- Expected: at least 'Fresh Whole Milk'; count matches the rows above

ROLLBACK;

-- ============================================================
-- SCENARIO 26: Inventory filtering
-- Verify that inventory can be filtered by team, status and storage.
-- ============================================================
START TRANSACTION;

SELECT i.inventory_item_id, p.product_name, s.storage_name, i.status, i.expiry_date
FROM inventory_items i
JOIN products p USING (product_id)
JOIN storage_types s USING (storage_type_id)
WHERE i.team_id = 1
  AND i.status = 'IN_STOCK'
  AND i.storage_type_id = 1
ORDER BY i.expiry_date;
-- Expected: only IN_STOCK fridge items of team 1, ordered by expiry

ROLLBACK;

-- ============================================================
-- SCENARIO 27: Home summary queries
-- Verify aggregate queries used by the home screen: totals per team,
-- status counts and items expiring within the next 7 days.
-- ============================================================
START TRANSACTION;

SELECT team_id,
       COUNT(*) AS total_items,
       SUM(status = 'IN_STOCK') AS in_stock,
       SUM(status = 'CONSUMED') AS consumed,
       SUM(status = 'EXPIRED') AS expired,
       SUM(status = 'DISCARDED') AS discarded,
       SUM(status = 'IN_STOCK'
           AND expiry_date IS NOT NULL
           AND expiry_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY)) AS expiring_in_7_days
FROM inventory_items
GROUP BY team_id
ORDER BY team_id;

-- Expiring-soon detail list for team 1.
SELECT p.product_name, i.expiry_date, s.storage_name
FROM inventory_items i
JOIN products p USING (product_id)
JOIN storage_types s USING (storage_type_id)
WHERE i.team_id = 1
  AND i.status = 'IN_STOCK'
  AND i.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY i.expiry_date;
-- Expected: summary per team plus a non-empty expiring-soon list

ROLLBACK;

-- ============================================================
-- SCENARIO 28: Reminder creation
-- Verify that a reminder can be created for an inventory item.
-- ============================================================
START TRANSACTION;

INSERT INTO reminders
  (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
VALUES (1, 1, 1, 3, DATE_ADD(CURDATE(), INTERVAL 12 HOUR));

SET @test_reminder = LAST_INSERT_ID();

SELECT reminder_id, inventory_item_id, team_id, created_by,
       lead_time_days, reminder_at, status
FROM reminders
WHERE reminder_id = @test_reminder;
-- Expected: 1 row, lead_time_days 3, status 'PENDING'

ROLLBACK;

-- ============================================================
-- SCENARIO 29: Default 3-day reminder
-- Verify that omitting lead_time_days uses the default value of 3
-- and that reminder_at is derived from the expiry date.
-- ============================================================
START TRANSACTION;

INSERT INTO reminders (inventory_item_id, team_id, created_by, reminder_at)
SELECT inventory_item_id, team_id, created_by,
       DATE_SUB(expiry_date, INTERVAL 3 DAY)
FROM inventory_items
WHERE inventory_item_id = 1;

SET @default_reminder = LAST_INSERT_ID();

SELECT lead_time_days, reminder_at,
       DATE_SUB(expiry_date, INTERVAL 3 DAY) AS expected_reminder_at
FROM reminders r
JOIN inventory_items i USING (inventory_item_id)
WHERE r.reminder_id = @default_reminder;
-- Expected: lead_time_days = 3 (column default),
--           reminder_at = expiry_date - 3 days

ROLLBACK;

-- ============================================================
-- SCENARIO 30: Custom reminder lead time
-- Verify that a reminder supports a custom lead time (e.g. 7 days).
-- ============================================================
START TRANSACTION;

INSERT INTO reminders (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
SELECT inventory_item_id, team_id, created_by, 7,
       DATE_SUB(expiry_date, INTERVAL 7 DAY)
FROM inventory_items
WHERE inventory_item_id = 5;

SET @custom_reminder = LAST_INSERT_ID();

SELECT lead_time_days, reminder_at,
       DATE_SUB(expiry_date, INTERVAL 7 DAY) AS expected_reminder_at
FROM reminders r
JOIN inventory_items i USING (inventory_item_id)
WHERE r.reminder_id = @custom_reminder;
-- Expected: lead_time_days = 7, reminder_at = expiry_date - 7 days

ROLLBACK;

-- ============================================================
-- SCENARIO 31: Reminder cancellation
-- Verify that a reminder can be cancelled and records cancelled_at.
-- ============================================================
START TRANSACTION;

INSERT INTO reminders
  (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
VALUES (6, 1, 2, 3, DATE_ADD(CURDATE(), INTERVAL 5 DAY));

SET @cancel_reminder = LAST_INSERT_ID();

UPDATE reminders
SET status = 'CANCELLED',
    cancelled_at = NOW()
WHERE reminder_id = @cancel_reminder;

SELECT reminder_id, status, cancelled_at
FROM reminders
WHERE reminder_id = @cancel_reminder;
-- Expected: status 'CANCELLED', cancelled_at NOT NULL

ROLLBACK;

-- ============================================================
-- SCENARIO 32: Multiple notification recipients
-- Verify that a reminder can notify several users at once.
-- ============================================================
START TRANSACTION;

INSERT INTO reminders
  (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
VALUES (1, 1, 1, 3, DATE_ADD(CURDATE(), INTERVAL 12 HOUR));

SET @multi_reminder = LAST_INSERT_ID();

INSERT INTO notification_recipients (reminder_id, user_id)
VALUES (@multi_reminder, 1), (@multi_reminder, 2);

SELECT r.reminder_id, COUNT(nr.user_id) AS recipient_count
FROM reminders r
JOIN notification_recipients nr USING (reminder_id)
WHERE r.reminder_id = @multi_reminder
GROUP BY r.reminder_id;
-- Expected: recipient_count = 2 (users 1 and 2)

ROLLBACK;

-- ============================================================
-- SCENARIO 33: Independent read/unread state
-- Verify that each recipient has its own read state; marking one
-- recipient as read must not affect the others.
-- ============================================================
START TRANSACTION;

INSERT INTO reminders
  (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
VALUES (1, 1, 1, 3, DATE_ADD(CURDATE(), INTERVAL 12 HOUR));

SET @read_reminder = LAST_INSERT_ID();

INSERT INTO notification_recipients (reminder_id, user_id)
VALUES (@read_reminder, 1), (@read_reminder, 2);

UPDATE notification_recipients
SET is_read = TRUE,
    read_at = NOW()
WHERE reminder_id = @read_reminder AND user_id = 1;

SELECT user_id, is_read, read_at
FROM notification_recipients
WHERE reminder_id = @read_reminder
ORDER BY user_id;
-- Expected: user 1 -> is_read TRUE, read_at NOT NULL;
--           user 2 -> is_read FALSE, read_at NULL (independent state)

ROLLBACK;

-- ============================================================
-- SCENARIO 34: Foreign-key delete behavior
-- Verify CASCADE (team deletion removes members, inventory,
-- reminders and recipients; product deletion removes product-level
-- shelf-life rules), SET NULL (deleting a reviewer keeps the request
-- but clears reviewed_by) and RESTRICT (deleting a referenced
-- category or user fails).
-- ============================================================
START TRANSACTION;

-- --- CASCADE: deleting a team removes its dependent rows ---------
INSERT INTO teams (team_name) VALUES ('Temp Cascade Team');
SET @temp_team = LAST_INSERT_ID();

INSERT INTO team_members (team_id, user_id, role, status)
VALUES (@temp_team, 1, 'ADMIN', 'ACTIVE');

INSERT INTO inventory_items
  (team_id, product_id, storage_type_id, created_by, quantity, unit, notes,
   purchase_date, expiry_date_source, expiry_date)
VALUES (@temp_team, 13, 3, 1, 1.00, 'pcs', NULL, CURDATE(), 'PACKAGING',
        DATE_ADD(CURDATE(), INTERVAL 10 DAY));
SET @temp_item = LAST_INSERT_ID();

INSERT INTO reminders
  (inventory_item_id, team_id, created_by, lead_time_days, reminder_at)
VALUES (@temp_item, @temp_team, 1, 3, DATE_ADD(CURDATE(), INTERVAL 12 HOUR));
SET @temp_reminder = LAST_INSERT_ID();

INSERT INTO notification_recipients (reminder_id, user_id)
VALUES (@temp_reminder, 1);

DELETE FROM teams WHERE team_id = @temp_team;

SELECT COUNT(*) AS remaining_members FROM team_members WHERE team_id = @temp_team;
SELECT COUNT(*) AS remaining_items FROM inventory_items WHERE team_id = @temp_team;
SELECT COUNT(*) AS remaining_reminders FROM reminders WHERE team_id = @temp_team;
SELECT COUNT(*) AS remaining_recipients
FROM notification_recipients WHERE reminder_id = @temp_reminder;
-- Expected: all counts are 0 (cascade chain works)

-- --- CASCADE: deleting a product removes its product-level rules --
SELECT COUNT(*) AS product_rules_before
FROM shelf_life_rules
WHERE product_id = 24;
-- Expected: 3 (FRIDGE, FREEZER, PANTRY)

DELETE FROM products WHERE product_id = 24;

SELECT COUNT(*) AS product_rules_after
FROM shelf_life_rules
WHERE product_id = 24;
-- Expected: 0 (product-level rules cascade with the product)

-- --- SET NULL: deleting a reviewer clears reviewed_by ------------
INSERT INTO users (email, password_hash, display_name)
VALUES ('temp.reviewer@example.com', '$2b$12$TEMP_REVIEWER_HASH_0000', 'Temp Reviewer');
SET @temp_reviewer = LAST_INSERT_ID();

INSERT INTO join_requests (team_id, user_id, status, requested_at, reviewed_at, reviewed_by)
VALUES (2, 4, 'APPROVED', NOW(), NOW(), @temp_reviewer);
SET @temp_request = LAST_INSERT_ID();

DELETE FROM users WHERE user_id = @temp_reviewer;

SELECT reviewed_by
FROM join_requests
WHERE request_id = @temp_request;
-- Expected: reviewed_by IS NULL (SET NULL)

-- --- RESTRICT: deleting a referenced category fails ---------------
-- [EXPECTED ERROR] Cannot delete or update a parent row: products
-- reference product_categories (error 1451)
DELETE FROM product_categories WHERE category_id = 1;

-- --- RESTRICT: deleting a user who created inventory fails --------
-- [EXPECTED ERROR] Cannot delete or update a parent row: inventory
-- items reference users.created_by (error 1451)
DELETE FROM users WHERE user_id = 1;

ROLLBACK;

-- ============================================================
-- SCENARIO 35: Seed data loading
-- Verify that seed_data.sql populated every table with the
-- expected minimum number of rows.
-- ============================================================
START TRANSACTION;

SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'teams', COUNT(*) FROM teams
UNION ALL SELECT 'team_members', COUNT(*) FROM team_members
UNION ALL SELECT 'join_requests', COUNT(*) FROM join_requests
UNION ALL SELECT 'product_categories', COUNT(*) FROM product_categories
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'storage_types', COUNT(*) FROM storage_types
UNION ALL SELECT 'inventory_items', COUNT(*) FROM inventory_items
UNION ALL SELECT 'inventory_transactions', COUNT(*) FROM inventory_transactions
UNION ALL SELECT 'shelf_life_rules', COUNT(*) FROM shelf_life_rules
UNION ALL SELECT 'reminders', COUNT(*) FROM reminders
UNION ALL SELECT 'notification_recipients', COUNT(*) FROM notification_recipients
ORDER BY table_name;

SELECT IF(COUNT(*) >= 3, 'PASS', 'FAIL') AS min_users_check FROM users;
SELECT IF(COUNT(*) >= 2, 'PASS', 'FAIL') AS min_teams_check FROM teams;
SELECT IF(COUNT(*) = 9, 'PASS', 'FAIL') AS categories_check FROM product_categories;
SELECT IF(COUNT(*) = 3, 'PASS', 'FAIL') AS storage_types_check FROM storage_types;
SELECT IF(COUNT(*) >= 100, 'PASS', 'FAIL') AS min_products_check FROM products;
SELECT IF(SUM(category_id = 5) >= 50 AND SUM(category_id = 3) >= 50, 'PASS', 'FAIL') AS fruit_seafood_check FROM products;
SELECT IF(COUNT(*) >= 10, 'PASS', 'FAIL') AS min_inventory_check FROM inventory_items;
SELECT IF(COUNT(*) >= 300, 'PASS', 'FAIL') AS min_shelf_life_rules_check FROM shelf_life_rules;
SELECT IF(SUM(product_id IS NOT NULL) >= 300, 'PASS', 'FAIL') AS product_level_rules_check FROM shelf_life_rules;
SELECT IF(SUM(product_id IS NULL) >= 18, 'PASS', 'FAIL') AS category_level_rules_check FROM shelf_life_rules;
SELECT IF(COUNT(*) >= 5, 'PASS', 'FAIL') AS min_reminders_check FROM reminders;
SELECT IF(SUM(status = 'DONATED') >= 1, 'PASS', 'FAIL') AS donated_items_check FROM inventory_items;
SELECT IF(SUM(transaction_type = 'DONATE') >= 1, 'PASS', 'FAIL') AS donate_txn_check FROM inventory_transactions;
-- Expected: every table non-empty; all checks PASS

ROLLBACK;

-- ============================================================
-- SCENARIO 36: Clean schema recreation
-- Drop every table (reverse dependency order) so the schema can be
-- recreated from scratch. DDL causes implicit commits in MySQL, so
-- this block intentionally runs without a transaction.
--
-- After this block, re-import:
--   mysql -u <user> -p < schema.sql
--   mysql -u <user> -p < seed_data.sql
-- ============================================================
SET FOREIGN_KEY_CHECKS = 0;

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
