# PantryBuddy - Household Inventory Reminder System (Iteration 2)

This folder contains the complete database implementation for PantryBuddy Iteration 2: 17 tables, the Iteration 1 static catalogue, the recognition keyword data, the PriceCatcher price reference data and a 2000-row price observation sample.

Iteration 1 is the read-only source of truth for the original 12 tables. Nothing in this folder modifies Iteration 1.

## Deployment Model

Iteration 2 runs in TiDB Cloud with **two files only**:

| File | Runs in TiDB Cloud | Purpose |
| --- | --- | --- |
| `schema.sql` | Yes | Full clean schema for all 17 tables. |
| `insert_static_data.sql` | Yes | All production data: Iteration 1 catalogue plus recognition and price data. |
| `seed_data.sql` | Local only | Small development sample for local testing. |
| `test_data.sql` | Local only | Constraint and edge-case tests. |
| `README.md` | - | This documentation. |

Because only two files are executed in TiDB Cloud, `insert_static_data.sql` carries every row the application needs and must not depend on staging tables, temporary tables, user-defined variables, prepared statements or application-side joins.

## Execution Order

Local development:

```bash
mysql -u root -p < schema.sql
mysql -u root -p "Real_ProjectV2.0_TM06" < insert_static_data.sql
mysql -u root -p < seed_data.sql
mysql -u root -p --force < test_data.sql
```

TiDB Cloud:

1. run `schema.sql`;
2. run `insert_static_data.sql` against the same database.

Notes:

- `schema.sql` creates the database `Real_ProjectV2.0_TM06` and all 17 tables, so it runs first.
- `insert_static_data.sql` starts with the Iteration 1 file and contains no `USE` statement, so select the database first or pass the database name on the command line.
- `seed_data.sql` and `test_data.sql` are for local use only. `test_data.sql` ends by dropping all 17 tables, so re-import the earlier scripts afterwards if needed.

## The 17 Tables

Iteration 1 tables (12), preserved exactly - columns, types, lengths, nullability, defaults, enum values, charset, collation, engine, indexes, unique keys, foreign keys and constraint names - except for the documented Iteration 2 changes:

| # | Table | Purpose |
| --- | --- | --- |
| 1 | `users` | Registered users. Iteration 2 adds `is_verified`. |
| 2 | `teams` | Households/teams that share inventory. |
| 3 | `team_members` | User membership in teams (`ADMIN` / `MEMBER`). |
| 4 | `join_requests` | Requests from users to join a team. |
| 5 | `product_categories` | Fixed category list (16 rows, IDs 1-8 and 11-18). |
| 6 | `products` | PantryBuddy catalogue (200 products). |
| 7 | `storage_types` | FRIDGE, FREEZER, PANTRY. |
| 8 | `inventory_items` | Household stock entries. Iteration 2 adds `unit`, `notes`, `price`, `discard_reason`, `consumed_amount` and the `DONATED` status. |
| 9 | `inventory_transactions` | Audit trail: `ADD`, `CONSUME`, `DISCARD`, `DONATE`. |
| 10 | `shelf_life_rules` | Shelf-life rules with evidence metadata (612 rows). |
| 11 | `reminders` | Expiry reminders per inventory item. |
| 12 | `notification_recipients` | Reminder recipients with per-user read state. |

Iteration 2 additions (5):

| # | Table | Purpose |
| --- | --- | --- |
| 13 | `security_questions` | Account recovery questions with bcrypt-hashed answers. |
| 14 | `product_reference` | Recognition reference rows, optionally linked to `products`. |
| 15 | `product_keyword_mapping` | Text and Open Food Facts keywords that resolve to a reference. |
| 16 | `price_item_reference` | PriceCatcher item, its package unit and its calculated reference prices. |
| 17 | `price_observations` | Dated premise-level price observations (2000-row Iteration 2 sample). |

## Iteration 2 Changes

### `users.is_verified`

```sql
is_verified BOOLEAN NOT NULL DEFAULT FALSE
```

Placed after `avatar_id`. Existing rows in an upgraded database default to unverified.

### `inventory_items`

```sql
quantity         DECIMAL(10,2) NOT NULL
unit             VARCHAR(20)   NOT NULL DEFAULT 'pcs'   -- after quantity
notes            VARCHAR(500)  NULL                     -- after unit
price            DECIMAL(10,2) NULL                     -- after notes
...
status           ENUM('IN_STOCK','CONSUMED','EXPIRED','DISCARDED','DONATED') NOT NULL DEFAULT 'IN_STOCK'
discard_reason   VARCHAR(30)   NULL                     -- after status
consumed_amount  VARCHAR(20)   NULL                     -- after discard_reason
```

`unit` stays `VARCHAR(20)` on purpose: it is not an `ENUM` and there is no `CHECK` constraint on it, so the allowed values can evolve without a migration. `price` stores the price the household actually paid for that inventory entry.

### `inventory_transactions`

```sql
transaction_type ENUM('ADD','CONSUME','DISCARD','DONATE') NOT NULL
```

### New recognition and price tables

- `product_keyword_mapping` links recognition keywords to `product_reference` through `reference_id`, with `UNIQUE (reference_id, normalized_keyword, match_type)`.
- `price_item_reference` links a PriceCatcher `item_code` and package unit to a `product_reference` row and stores the calculated package-level and per-base-unit reference prices.
- `price_observations` stores dated premise-level prices and is linked to `price_item_reference.item_code`, with `UNIQUE (observation_date, premise_code, item_code)` and `CHECK (price_myr > 0)`.

## Identifier Chain and Staging Fields

`item_code`, `reference_id` and `product_id` are three different identifiers:

```text
PriceCatcher item_code
        |
        v
price_item_reference.item_code
        |
        | reference_id (FK, ON DELETE RESTRICT)
        v
product_reference.reference_id
        |
        | product_id (nullable FK, ON DELETE RESTRICT)
        v
products.product_id
```

- `item_code` identifies one PriceCatcher-listed item and unit.
- `reference_id` identifies one PantryBuddy recognition reference.
- `product_id` identifies one of the 200 catalogue products, and may be `NULL` for a category-level reference.

`reference_key` is a **staging-only** key that exists in the data team CSVs. It is never stored in a production table. Because `insert_static_data.sql` runs standalone in TiDB Cloud, the import assigns one explicit `reference_id` per unique `reference_key` and uses those explicit values in `product_keyword_mapping` and `price_item_reference`. `AUTO_INCREMENT` remains on the column, and explicit values are allowed.

Reference ID assignment for this import:

1. rows of `product_reference.csv` in file order: `reference_id` 1-7634;
2. rows of `product_reference_additions.csv` in file order: `reference_id` 7635-7881;
3. `reference_key` values that appear only in `price_item_mapping.csv` are already covered by the two files above, so no extra IDs are needed.

## Static Data Loaded by `insert_static_data.sql`

| Section | Content | Rows |
| --- | --- | --- |
| 1 | Iteration 1 static data, copied unchanged (3 storage types, 16 product categories, 200 products, 612 shelf-life rules) | 831 |
| 2 | `product_categories`: comment only, no new categories | 0 |
| 3 | `product_reference` with explicit `reference_id` | 7881 |
| 4 | `product_keyword_mapping` from `product_keyword_mapping.csv` (24213) and `product_keyword_mapping_additions.csv` (247) | 24460 |
| 5 | `price_item_reference` from `price_item_mapping.csv` | 284 |
| 6 | `price_observations` from `price_observations_sample_2000.csv` | 2000 |

Section 1 is byte-for-byte identical to `Iteration 1/insert_static_data.sql`. It is followed by the new sections, which run inside one transaction and are committed at the end. Large tables use batched multi-row `INSERT` statements so that no single statement becomes too large for TiDB Cloud.

`price_observations` holds the 2000-row Iteration 2 sample only. PriceCatcher publishes 561,441 observations for September 2026; the full archive stays in the CSV archive and is not loaded into the free cloud database. All 284 `price_item_reference` rows are still loaded, because they carry the calculated reference prices used by the application.

## Category Rule

- The 16 category IDs are fixed: 1-8 and 11-18. **IDs 9 and 10 do not exist.**
- No new categories are created in Iteration 2.
- The data team maps external categories onto these IDs, for example POULTRY/MEAT -> 2, SEAFOOD -> 3, VEGETABLES -> 4, FRUITS -> 5, EGGS -> 18.
- Every `category_id` in the supplied CSVs was validated against the Iteration 1 categories; invalid values would have stopped this import.

## Unit Rules

- `inventory_items.unit` stays `VARCHAR(20) NOT NULL DEFAULT 'pcs'`. There is no `ENUM` and no `CHECK` constraint, so the application layer enforces the allowed list.
- Frontend dropdown values: `pcs`, `g`, `kg`, `mg`, `mL`, `L`, `pack`, `box`, `bottle`, `can`, `dozen`.
- `price_item_reference.base_unit` uses the spelling `kg`, `L` or `pcs`.
- Conversion factors exist only for `kg`, `g`, `L`, `ml`, `pcs` and `dozen`:

| Inventory unit | Price base unit | Factor |
| --- | --- | ---: |
| kg | kg | 1 |
| g | kg | 0.001 |
| L | L | 1 |
| ml | L | 0.001 |
| pcs | pcs | 1 |
| dozen | pcs | 12 |

Units without a conversion factor (`mg`, `pack`, `box`, `bottle`, `can`) fall back to asking the user for a price. Never convert between dimensions, such as `pcs` to `kg`, without product-specific evidence.

## Price Selection Order

1. Use the user's actual purchase price (`inventory_items.price`).
2. Otherwise use `price_item_reference.median_package_price` when the item and package unit match.
3. Otherwise use `price_item_reference.median_price_per_base_unit` after converting a compatible inventory unit.
4. If no compatible public price exists, ask the user to enter a price.

The median is preferred over the mean because it is less affected by unusually high or low premise prices. Both are retained for comparison. `latest_day_median_price` is available when a recent single-day value is preferred.

## Verification SQL

```sql
-- 1. All 17 tables exist
SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE();

-- 2. New table definitions
SHOW CREATE TABLE product_reference;
SHOW CREATE TABLE product_keyword_mapping;
SHOW CREATE TABLE price_item_reference;
SHOW CREATE TABLE price_observations;

-- 3. Static data volumes
SELECT COUNT(*) FROM products;                -- 200
SELECT COUNT(*) FROM shelf_life_rules;        -- 612
SELECT COUNT(*) FROM product_reference;       -- 7881 (7883 after the local seed adds 2 rows)
SELECT COUNT(*) FROM product_keyword_mapping; -- 24460 (24463 after the local seed adds 3 rows)
SELECT COUNT(*) FROM price_item_reference;    -- 284 (286 after the local seed adds 2 rows)
SELECT COUNT(*) FROM price_observations;      -- 2000 (2003 after the local seed adds 3 rows)

-- 4. No orphan references and no invalid categories
SELECT COUNT(*) FROM product_keyword_mapping km
LEFT JOIN product_reference pr ON pr.reference_id = km.reference_id
WHERE pr.reference_id IS NULL;                -- 0

SELECT COUNT(*) FROM product_reference
WHERE category_id NOT IN (1,2,3,4,5,6,7,8,11,12,13,14,15,16,17,18);  -- 0

-- 5. Every priced item is represented in the observation sample
SELECT COUNT(DISTINCT item_code) FROM price_observations;   -- 284

-- 6. One reference row per linked product, multiple NULL product_id allowed
SELECT product_id, COUNT(*) FROM product_reference
WHERE product_id IS NOT NULL GROUP BY product_id HAVING COUNT(*) > 1;  -- empty

SELECT COUNT(*) FROM product_reference WHERE product_id IS NULL;        -- 7683 (7681 static + 2 seed)

-- 7. Identifier chain
SELECT pir.item_code, pir.reference_id, pr.product_name, pr.product_id, p.product_name AS catalogue_name
FROM price_item_reference pir
JOIN product_reference pr ON pr.reference_id = pir.reference_id
LEFT JOIN products p ON p.product_id = pr.product_id
ORDER BY pir.item_code
LIMIT 10;

-- 8. Donation and price coverage on inventory items
SELECT status, COUNT(*) FROM inventory_items GROUP BY status;
SELECT COUNT(*) FROM inventory_items WHERE price IS NOT NULL;
```

## TiDB and MySQL 8.0 Compatibility

- **MySQL 8.0.16+**: fully supported. All `CHECK` constraints are enforced, including `chk_price_observations_price_myr` and `chk_inventory_transactions_discard_reason`.
- **MySQL 8.0.0-8.0.15**: the script still runs, but `CHECK` clauses are parsed and ignored.
- **TiDB**: the DDL and DML are compatible (InnoDB-style DDL, `ENUM`, `BOOLEAN`, `DECIMAL`, `utf8mb4`). Keep these differences in mind:
  - **TiDB may not enforce `CHECK` constraints.** The positive-price rule, the quantity rule, the shelf-life rule and the transaction discard-reason rule must also be validated in the application.
  - Foreign key enforcement depends on the TiDB version and configuration; verify `RESTRICT` and `CASCADE` behaviour in the target cluster.
  - `UNIQUE` indexes treat `NULL` values the same way MySQL does, which is what `product_reference.product_id`, `product_reference.barcode` and `shelf_life_rules.product_id` rely on.
  - `AUTO_INCREMENT` values are not guaranteed to be gap-free or strictly sequential. `reference_id` values are explicit and stable, so `product_keyword_mapping` and `price_item_reference` stay correct regardless of the generated values.
  - Very large multi-row `INSERT` statements can exceed the server packet limit; this file batches rows to stay well below typical `max_allowed_packet` settings.

## Notes

- `insert_static_data.sql` section 1 is copied unchanged from Iteration 1, including its 200 products and 612 shelf-life rules and all of its comments.
- No new categories and no ML, prediction or model tables are added.
- `barcode` is always `VARCHAR(50)` and blank barcodes are stored as `NULL`, never as an empty string.
- Security answers are stored as bcrypt hashes only; plain answers are never stored.
- `seed_data.sql` adds rows only above the static identifier ranges (reference 7882-7883, item codes 900001-900002), so it can run directly after the static import.
- `test_data.sql` intentionally raises errors; run it with `--force` so that execution continues.
