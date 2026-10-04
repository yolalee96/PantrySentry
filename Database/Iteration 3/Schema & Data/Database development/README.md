# PantrySentry - Household Inventory Reminder System (Iteration 3)

Iteration 3 extends the PantrySentry database with the food-waste-reduction features of the third project iteration: recipe suggestions (Epic 6), food donation (Epic 7) and environmental impact reporting (Epic 8). The database now holds **29 tables**: the 17 tables of Iteration 1 and Iteration 2 plus 12 new tables.

## Project Background and Iteration 3 Goals

PantrySentry helps households track pantry stock, notice food that is about to expire and act before it is wasted. Iteration 1 delivered the inventory core, Iteration 2 added recognition, security questions and public price references. Iteration 3 closes the loop with three goals:

1. **Epic 6 - cook what expires first:** suggest recipes that consume the stock closest to expiry, show which ingredients are available or missing, and record the cooking session with a safe stock deduction.
2. **Epic 7 - donate instead of discarding:** find donation centres, submit a donation request without changing stock, and only deduct stock (and write a `DONATE` transaction) when the donation is actually completed.
3. **Epic 8 - measure the impact:** convert discarded quantities into kilograms, apply emission factors and store the resulting CO2e footprint per discarded inventory transaction, then report it by category, week and month.

## Relationship with Iteration 1 and Iteration 2

- Iteration 1 and Iteration 2 folders are **read-only**. Nothing in Iteration 3 modifies, renames or reformats any earlier file.
- Iteration 3 is **incremental, not a rewrite**. The 17 existing tables are reproduced in `schema.sql` with exactly the same columns, types, lengths, nullability, defaults, enum values, charset, collation, engine, indexes, unique keys, foreign keys and constraint names. Only new tables are appended.
- No Iteration 3 statement alters, drops or redefines an Iteration 1 or Iteration 2 table.
- `insert_static_data.sql` is a byte-for-byte copy of the Iteration 2 file, so the production data model stays compatible with the deployed Iteration 2 static data.

## The 12 New Tables

### Epic 6 - Recipe suggestions (5 tables)

| # | Table | Purpose |
| --- | --- | --- |
| 18 | `recipes` | Recipe catalogue: title, description, servings, timing, difficulty, cuisine, JSON instructions and source metadata. |
| 19 | `recipe_ingredients` | Ingredient lines of a recipe. `reference_id` and `category_id` are optional so free-text ingredients can be stored and matched later. |
| 20 | `recipe_cook_sessions` | One cooking attempt per team, with `UNIQUE (team_id, idempotency_key)` for safe client retries and a `DRAFT / CONFIRMED / CANCELLED` status. |
| 21 | `recipe_cook_session_items` | Which stock was used by a session, the planned versus used quantity and the resulting `CONSUME` transaction. `UNIQUE (session_id, inventory_item_id)` prevents double counting. |
| 22 | `recipe_ai_generations` | Caches Gemini AI-generated recipe suggestions per household to avoid repeated API calls. Fields: team_id, model, input_item_ids (JSON), recipe_ids (JSON), created_by. |

AI generation relationships (dashed edges in the ERD):

- `teams` 1 - N `recipe_ai_generations`: has AI generations (dashed)
- `users` 1 - N `recipe_ai_generations`: triggers AI generation (dashed)

### Epic 7 - Food donation (4 tables)

| # | Table | Purpose |
| --- | --- | --- |
| 23 | `donation_centres` | Donation drop-off points with address, coordinates, contact details, opening hours and verification source. |
| 24 | `donation_centre_accepted_foods` | Food types a centre accepts, linked to `product_categories`. |
| 25 | `donation_records` | One donation request per team and centre, with a `PENDING / COMPLETED / CANCELLED` status and drop-off window. |
| 26 | `donation_record_items` | The stock rows included in a donation, with `UNIQUE (donation_id, inventory_item_id)` and an optional `transaction_id` filled only when the donation is completed. |

### Epic 8 - Environmental impact (3 tables)

| # | Table | Purpose |
| --- | --- | --- |
| 27 | `emission_factors` | CO2e factors per kilogram of food, attached to a category, a specific reference or neither, with source, version and validity window. |
| 28 | `quantity_conversions` | Per-reference conversions for all 7,881 product references: l -> kg, ml -> kg, pcs -> kg, dozen -> kg. Global: g -> kg, kg -> kg, mg -> kg. Epic 6 adds cup/tbsp/tsp. |
| 29 | `waste_impact_assessments` | One assessment per discarded inventory transaction, with conversion, factor snapshots and the resulting footprint. `transaction_id` is `UNIQUE`. |

### Data-team feedback applied to Epic 7

- The earlier **`donation_centre_needs`** draft was **renamed to `donation_centre_accepted_foods`** and simplified to exactly **8 columns**: `need_id`, `centre_id`, `category_id`, `item_name`, `notes`, `is_active`, `created_at`, `updated_at`.
- **`donation_centres`** was simplified as requested: `address_line2`, `country`, `accepts_food_donations` and `accepted_categories` were **removed**, **`verification_source_url` was added**, and `requires_declaration` was **removed in the final data-team review**. The table has 19 columns.
- Accepted foods are stored per centre in `donation_centre_accepted_foods`, so a centre can accept several categories without duplicating them inside `donation_centres`.

## Files

| File | Runs in production | Purpose |
| --- | --- | --- |
| `schema.sql` | Yes | Creates the database and all 29 tables (17 existing plus 12 new). |
| `insert_static_data.sql` | Yes | Byte-for-byte copy of the Iteration 2 static data file. |
| `seed_data.sql` | Local only | Iteration 2 development seed data plus Iteration 3 seed data for the new tables. |
| `test_data.sql` | Local only | Iteration 2 constraint tests plus Iteration 3 acceptance-criteria and constraint tests. |
| `README.md` | - | This documentation. |

## Execution Order

Local development:

```bash
mysql -u root -p < schema.sql
mysql -u root -p "Real_ProjectV3.0_TM06" < insert_static_data.sql
mysql -u root -p < seed_data.sql
mysql -u root -p --force < test_data.sql
```

Production (TiDB or MySQL 8.0):

1. run `schema.sql`;
2. run `insert_static_data.sql` against the same database;
3. run `seed_data.sql` and `test_data.sql` only on a local or staging database.

Notes:

- `schema.sql` creates and selects `Real_ProjectV3.0_TM06`, so it must run first.
- `insert_static_data.sql` contains no `USE` statement, so select the database first or pass the database name on the command line.
- `test_data.sql` intentionally raises errors, so run it with `--force`. Its final scenario drops all 29 tables; re-import the previous scripts afterwards.

## Database Naming, Character Set and Engine

- Database name: **`Real_ProjectV3.0_TM06`** (Iteration 1 uses `Real_ProjectV1.0_TM06`, Iteration 2 uses `Real_ProjectV2.0_TM06`, so all three can be loaded side by side).
- Character set and collation: `utf8mb4` / `utf8mb4_unicode_ci`.
- Storage engine: `InnoDB` for every table, including the 11 new ones.
- No user-defined variables, prepared statements, temporary tables or CTEs are required by `schema.sql` or `insert_static_data.sql`.

## Static Data Status

`insert_static_data.sql` now contains **both the Iteration 2 static data (byte-for-byte copy) and the Iteration 3 static data delivered by the data team**: 7,258 recipes, 59,518 recipe ingredients, 27 donation centres, 190 accepted foods, 1,782 emission factors and 31,530 quantity conversions (31,527 per-reference Epic 8 rows plus 3 Epic 6 cooking conversions). All data has been verified against the source CSVs and loaded into the TiDB Cloud production database `Real_ProjectV3.0_TM06`.

## Epic 7 Inventory Flow (important business rule)

Donations must not look like consumption or waste:

1. **Submitting a donation request** (`donation_records.status = 'PENDING'`) only reserves the items logically through `donation_record_items`. `inventory_items.quantity` and `inventory_items.status` stay unchanged and **no `inventory_transactions` row is written**.
2. **Completing the donation** (`donation_records.status = 'COMPLETED'`) is the only moment stock moves:
   - write one `inventory_transactions` row with `transaction_type = 'DONATE'` per donated item (the transaction-level `discard_reason` stays `NULL`, because the existing `chk_inventory_transactions_discard_reason` CHECK only allows a reason on `DISCARD`);
   - store the returned `transaction_id` in `donation_record_items.transaction_id`;
   - decrease `inventory_items.quantity` and set `donated_at`;
   - mark the item `DONATED` through the inventory status flow defined in Iteration 2.
3. Cancelling a request (`CANCELLED`) releases the reservation without touching stock.

Donated items are therefore **not counted as consumed food and not counted as waste**, and they never produce a `waste_impact_assessments` row.

## Epic 8 Calculation Rules

1. Take the discarded transaction, its inventory item, its product, its reference and its category.
2. Convert `discarded_quantity` into kilograms. Use the direct per-reference conversion (`ml -> kg`, `pcs -> kg`, `dozen -> kg`) when the row's reference has one, otherwise a global unit conversion (`g -> kg`, `kg -> kg`, `mg -> kg`). The older chained form (ml -> L -> kg) is no longer needed because the Epic 8 dataset now stores the per-reference result directly.
3. Look up an active `emission_factors` row for the reference first and fall back to the category.
4. Persist the factor value and its source into the snapshot columns, then store `footprint_kg_co2e = converted_weight_kg * factor_kg_co2e_per_kg`.
5. If the conversion or the factor is missing, store the row as `assessment_status = 'EXCLUDED'` with an `exclusion_reason` and a `NULL` footprint. **Never guess a factor**; excluded rows are reported separately and are not silently treated as zero-impact food.

## TiDB Compatibility Notes

- **CHECK constraints:** TiDB may accept but not enforce `CHECK` clauses. Iteration 3 adds no `CHECK` constraints of its own, so all new validation (positive quantities, valid factors, exclusion rules) must be enforced by the application. The existing Iteration 1 and Iteration 2 `CHECK` clauses keep their MySQL semantics.
- **`SAVEPOINT` is avoided.** The scripts use plain `START TRANSACTION` / `ROLLBACK` blocks only, because savepoints behave differently across TiDB versions.
- **Auto-increment values** are not guaranteed to be gap-free or sequential on TiDB. Iteration 3 seed data therefore uses explicit high id ranges (inventory items 101-105, transactions 101-108, recipes 1-3, donation ids 1-3, factors 1-4, conversions 1-5, assessments 1-3) that cannot collide with the Iteration 2 seed data.
- **JSON columns** (`recipes.instructions_json`) are supported by MySQL 8.0 and TiDB, but TiDB validates JSON less strictly; the application should still validate the stored structure.
- **Distance search** in the donation tests uses the haversine formula in plain SQL, so no spatial extension or `ST_Distance_Sphere` support is required.
- **Reserved keyword:** `donation_record_items.condition` is a reserved MySQL keyword and must always be quoted as `` `condition` ``.
- **Unique keys with NULL:** `waste_impact_assessments.transaction_id` is `UNIQUE`, and MySQL/TiDB allow several `NULL` values in a unique index, which is what the exclusion case relies on.

## Migration and Audit Recommendations

- **Do not modify Iteration 1 or Iteration 2 files.** Iteration 3 is applied as an additive migration: create the 12 new tables and leave the 17 existing ones untouched.
- Apply the migration on a clone first, compare `SHOW CREATE TABLE` output for the 17 existing tables against the Iteration 2 database, and only then promote it.
- Keep an audit trail of every stock movement. `inventory_transactions` is the single source of truth for consumption, discard and donation; `recipe_cook_session_items.transaction_id`, `donation_record_items.transaction_id` and `waste_impact_assessments.transaction_id` all point back to it.
- `waste_impact_assessments` stores factor snapshots (`factor_kg_co2e_per_kg_snapshot`, `factor_source_name_snapshot`, `factor_source_version_snapshot`, `calculation_method_version`). Re-running a report must not rewrite historical numbers when factors are updated.
- Add monitoring for orphan checks (`recipe_ingredients` without `recipes`, `donation_record_items` without `donation_records`, assessments without transactions) and for duplicate `idempotency_key` attempts, which indicate client retries.
- When new emission factors are published, insert a new `emission_factors` row with `valid_from` and set `is_active = FALSE` on the superseded row rather than editing the old values.

## Credentials and Data Safety

- Never commit database credentials, connection strings, `.env` files or API keys to the repository. Use environment variables or a secret manager.
- The seed and test files contain only fake data (example email addresses, placeholder password hashes, published public price data). Do not put real household data, real user emails or production passwords into them.
- Restrict TiDB Cloud credentials to the minimum required privileges, rotate them regularly, and prefer the read-only endpoint for reporting queries.
- `insert_static_data.sql` contains public open data (USDA FoodKeeper, Open Food Facts, Malaysia PriceCatcher under CC BY 4.0). Keep the attribution columns (`source_name`, `source_url`, `source_locator`) intact when re-importing.

## Project Rename to PantrySentry

The project name changed from **PantryBuddy** to **PantrySentry**. The Iteration 3 files use the new name everywhere they are free to do so:

- `README.md` (title, background, Epic descriptions, impact notes and attribution);
- SQL header comments and example URLs in `schema.sql`, `seed_data.sql` and `test_data.sql`;
- seed values such as `source_name = 'PantrySentry test kitchen'`, `'PantrySentry unit policy'` and `'PantrySentry seed data'`, plus the example URLs under `https://example.com/pantrysentry/`.

The rename needs **no database migration**:

- The database name `Real_ProjectV3.0_TM06` never contained the product name, and no table, column, index, unique key or foreign key name embeds it either.
- `insert_static_data.sql` is still the byte-for-byte copy of the Iteration 2 production file, so it still contains the 402 occurrences of the old product name that came from the data team's source values (for example `product_keyword_mapping.source_name = 'PantryBuddy approved catalogue; identity retained from USDA FSIS FoodKeeper Data'` and `product_reference.description = 'Existing PantryBuddy catalogue product; unchanged identity'`). Those are data values, not schema objects, so they do not affect lookup, pricing or reporting logic. Renaming them would break byte-identity with Iteration 2 and with the source CSVs; do it only with data-team agreement, and keep the CSV and SQL in step.
- Iteration 1 and Iteration 2 files are read-only and keep their original wording.

## Verification SQL

```sql
-- 1. All 29 tables exist
SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE();

-- 2. New table definitions
SHOW CREATE TABLE recipes;
SHOW CREATE TABLE recipe_ingredients;
SHOW CREATE TABLE recipe_cook_sessions;
SHOW CREATE TABLE recipe_cook_session_items;
SHOW CREATE TABLE donation_centres;
SHOW CREATE TABLE donation_centre_accepted_foods;
SHOW CREATE TABLE donation_records;
SHOW CREATE TABLE donation_record_items;
SHOW CREATE TABLE emission_factors;
SHOW CREATE TABLE quantity_conversions;
SHOW CREATE TABLE waste_impact_assessments;
SHOW CREATE TABLE recipe_ai_generations;

-- 3. Iteration 2 static data is unchanged
SELECT COUNT(*) FROM products;                -- 200
SELECT COUNT(*) FROM shelf_life_rules;        -- 612
SELECT COUNT(*) FROM product_reference;       -- 7881 (7883 after the local seed)
SELECT COUNT(*) FROM product_keyword_mapping; -- 24460 (24463 after the local seed)
SELECT COUNT(*) FROM price_item_reference;    -- 284 (286 after the local seed)
SELECT COUNT(*) FROM price_observations;      -- 2000 (2003 after the local seed)

-- 4. Iteration 3 static data + seed data (values are static + seed, because
--    seed_data.sql is loaded on top of insert_static_data.sql)
SELECT COUNT(*) FROM recipes;                                  -- 7258 static + 3 seed = 7261
SELECT COUNT(*) FROM recipe_ingredients;                       -- 59518 static + 12 seed = 59530
SELECT COUNT(*) FROM donation_centres;                         -- 27 static + 3 seed = 30
SELECT COUNT(*) FROM donation_centre_accepted_foods;           -- 190 static + 6 seed = 196
SELECT COUNT(*) FROM donation_records WHERE status = 'PENDING';-- 1 (seed only; static imports none)
SELECT COUNT(*) FROM emission_factors;                         -- 1782 static + 4 seed = 1786
SELECT COUNT(*) FROM quantity_conversions;                      -- 31,527 Epic 8 + 3 Epic 6 + 5 seed = 31,535
SELECT COUNT(*) FROM waste_impact_assessments;                 -- 3 seed (2 ASSESSED, 1 EXCLUDED; static imports none)

-- 5. Pending donations must not move stock
SELECT d.status, dri.inventory_item_id, i.quantity, dri.transaction_id
FROM donation_records d
JOIN donation_record_items dri ON dri.donation_id = d.donation_id
JOIN inventory_items i ON i.inventory_item_id = dri.inventory_item_id
WHERE d.status = 'PENDING';
-- Expected: transaction_id NULL and quantities unchanged

-- 6. Impact totals
SELECT assessment_status, COUNT(*) AS rows_count, ROUND(SUM(COALESCE(footprint_kg_co2e, 0)), 6) AS footprint
FROM waste_impact_assessments
GROUP BY assessment_status;
-- Expected: ASSESSED 2 rows / 0.460000 and EXCLUDED 1 row / 0.000000

-- 7. Impact by category
SELECT c.category_name, COUNT(*) AS assessments, ROUND(SUM(COALESCE(w.footprint_kg_co2e, 0)), 6) AS footprint
FROM waste_impact_assessments w
LEFT JOIN product_categories c ON c.category_id = w.category_id
GROUP BY c.category_name
ORDER BY footprint DESC;
```

## Reference

- Iteration 1 static data source: USDA FSIS FoodKeeper open data and the PantrySentry catalogue.
- Iteration 2 recognition and price data: Open Food Facts taxonomy plus Malaysia PriceCatcher (open.dosm.gov.my, CC BY 4.0).
- Iteration 3 emission factors in the seed data are illustrative values modelled on Poore and Nemecek (2018) as published by Our World in Data; replace them with the approved factor set before production use.
