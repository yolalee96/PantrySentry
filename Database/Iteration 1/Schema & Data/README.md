# Household Inventory Reminder System - MySQL Database

This folder contains the complete MySQL implementation for the Household Inventory Reminder System. It defines a 12-table relational schema for managing households/teams, memberships, join requests, products, storage locations, inventory, shelf-life rules, expiry reminders and notification recipients.

## Files

| File | Purpose |
| --- | --- |
| `schema.sql` | Creates the `pantry_buddy` database and all 12 tables with indexes, constraints and foreign keys. |
| `seed_data.sql` | Loads representative English seed data (users, teams, products, inventory, rules, reminders, recipients). |
| `test_data.sql` | Contains 36 executable test scenarios for manual verification. |
| `README.md` | This documentation. |

## Prerequisites

- MySQL 8.0 or newer (CHECK constraints are enforced from 8.0.16 onward).
- InnoDB storage engine (the default in MySQL).
- `utf8mb4` character set, which every table uses.

## Schema Overview

The schema contains exactly 12 tables and no additional summary, ML or prediction tables.

| # | Table | Purpose |
| --- | --- | --- |
| 1 | `users` | Registered users of the system. |
| 2 | `teams` | Households/teams that share inventory. |
| 3 | `team_members` | Membership of users in teams, with `ADMIN` or `MEMBER` role. |
| 4 | `join_requests` | Requests from users to join a team. |
| 5 | `product_categories` | Product categories such as Dairy, Meat, Vegetables. |
| 6 | `products` | Product catalogue; barcode is optional but unique. |
| 7 | `storage_types` | Storage locations: FRIDGE, FREEZER, PANTRY. |
| 8 | `inventory_items` | Stock entries owned by a team for a product at a storage location, with statuses IN_STOCK / CONSUMED / EXPIRED / DISCARDED / DONATED. |
| 9 | `inventory_transactions` | Audit trail of ADD / CONSUME / DISCARD / DONATE operations. |
| 10 | `shelf_life_rules` | Shelf-life rules with evidence metadata; supports product-level rules and category-level fallbacks. |
| 11 | `reminders` | Expiry reminders for inventory items. |
| 12 | `notification_recipients` | Users notified for a reminder, with per-user read state. |

### `inventory_items` Extra Fields

The `inventory_items` table stores fields for item quantities, notes and disposal tracking:

- **`unit`** (`VARCHAR(20)`, `NOT NULL`, default `'pcs'`) - Unit of measurement for the item (e.g. `pcs`, `kg`, `g`, `L`, `ml`, `dozen`). The column is placed immediately after `quantity`.
- **`notes`** (`VARCHAR(500)`, nullable) - Optional user notes about the item (e.g. opened status, partial consumption notes). The column is placed immediately after `unit`.
- **`discard_reason`** (`VARCHAR(30)`, nullable) - Reason the item left stock, e.g. `EXPIRED`, `USER_DISCARDED` or `DONATED`. The column is placed immediately after `status`.
- **`consumed_amount`** (`VARCHAR(20)`, nullable) - Optional human-readable amount consumed, e.g. `0.50` or `2.00`. The column is placed immediately after `discard_reason`.
- **`status`** accepts `IN_STOCK`, `CONSUMED`, `EXPIRED`, `DISCARDED` and `DONATED` (default `IN_STOCK`).

**Migration note for existing databases** (for the backend team; do not run these on a fresh database where the columns already exist):

```sql
ALTER TABLE inventory_items
  ADD COLUMN unit VARCHAR(20) NOT NULL DEFAULT 'pcs' AFTER quantity;

ALTER TABLE inventory_items
  ADD COLUMN notes VARCHAR(500) NULL AFTER unit;
```

**Donation migration note for existing databases** (for the backend team; the fresh schema already contains these changes):

```sql
ALTER TABLE inventory_items
  MODIFY COLUMN status
    ENUM('IN_STOCK','CONSUMED','EXPIRED','DISCARDED','DONATED')
    NOT NULL DEFAULT 'IN_STOCK';

ALTER TABLE inventory_transactions
  MODIFY COLUMN transaction_type
    ENUM('ADD','CONSUME','DISCARD','DONATE') NOT NULL;

ALTER TABLE inventory_items
  ADD COLUMN discard_reason VARCHAR(30) NULL AFTER status;

ALTER TABLE inventory_items
  ADD COLUMN consumed_amount VARCHAR(20) NULL AFTER discard_reason;
```

## Relationships

- `users` and `teams` are related many-to-many through `team_members`. A team admin is identified by `team_members.role = 'ADMIN'`; there is deliberately no `teams.created_by` column.
- `join_requests` connects `teams` and `users`; the reviewer is tracked with `reviewed_by -> users`.
- `products` belongs to exactly one `product_categories`.
- `inventory_items` belongs to one `teams`, one `products` and one `storage_types`; it is created by one `users`.
- `inventory_transactions` is the history of one `inventory_items` entry and is performed by one `users`.
- `shelf_life_rules` always belongs to one `product_categories` and one `storage_types`, and optionally to one `products`. A row with `product_id IS NULL` is a category-level fallback rule; a row with `product_id NOT NULL` is a product-level rule.
- `reminders` references one `inventory_items`, one `teams` and one `users` (creator).
- `notification_recipients` connects `reminders` with `users`; each recipient has an independent read state.

## Foreign Key Delete Behavior

| Constraint | Parent | Child | On Delete |
| --- | --- | --- | --- |
| `fk_team_members_team` | `teams` | `team_members` | CASCADE |
| `fk_team_members_user` | `users` | `team_members` | CASCADE |
| `fk_join_requests_team` | `teams` | `join_requests` | CASCADE |
| `fk_join_requests_user` | `users` | `join_requests` | CASCADE |
| `fk_join_requests_reviewed_by` | `users` | `join_requests.reviewed_by` | SET NULL |
| `fk_products_category` | `product_categories` | `products` | RESTRICT |
| `fk_inventory_items_product` | `products` | `inventory_items` | RESTRICT |
| `fk_inventory_items_storage` | `storage_types` | `inventory_items` | RESTRICT |
| `fk_inventory_items_team` | `teams` | `inventory_items` | CASCADE |
| `fk_inventory_items_created_by` | `users` | `inventory_items.created_by` | RESTRICT |
| `fk_inventory_transactions_item` | `inventory_items` | `inventory_transactions` | CASCADE |
| `fk_inventory_transactions_user` | `users` | `inventory_transactions` | RESTRICT |
| `fk_shelf_life_rules_category` | `product_categories` | `shelf_life_rules` | CASCADE |
| `fk_shelf_life_rules_product` | `products` | `shelf_life_rules` | CASCADE |
| `fk_shelf_life_rules_storage` | `storage_types` | `shelf_life_rules` | CASCADE |
| `fk_reminders_inventory_item` | `inventory_items` | `reminders` | CASCADE |
| `fk_reminders_team` | `teams` | `reminders` | CASCADE |
| `fk_reminders_created_by` | `users` | `reminders.created_by` | RESTRICT |
| `fk_notification_recipients_reminder` | `reminders` | `notification_recipients` | CASCADE |
| `fk_notification_recipients_user` | `users` | `notification_recipients` | CASCADE |

## Key Constraints and Business Rules

- `users.email` is unique (`uq_users_email`).
- `products.barcode` is unique (`uq_products_barcode`) and nullable; it is stored as `VARCHAR(50)`, never as an integer.
- `inventory_items.quantity` must be greater than 0 (`CHECK`).
- `inventory_items.shelf_life_days` must be greater than or equal to 0 when provided.
- `inventory_items.status` is one of `IN_STOCK`, `CONSUMED`, `EXPIRED`, `DISCARDED` or `DONATED`.
- `inventory_items.discard_reason` stores the reason an item left stock (e.g. `EXPIRED`, `USER_DISCARDED`, `DONATED`); `consumed_amount` stores an optional readable amount consumed.
- `expiry_date_source` is one of `PACKAGING` (printed on the package), `USER_INPUT` (entered by the user) or `CALCULATED` (production date + shelf life).
- `inventory_transactions.transaction_type` is one of `ADD`, `CONSUME`, `DISCARD` or `DONATE`.
- `inventory_transactions.discard_reason` may be non-NULL only when `transaction_type = 'DISCARD'`; otherwise it must be NULL.
- `shelf_life_rules.min_days` must be >= 0 and `max_days` must be >= `min_days` (`CHECK` constraints).
- `shelf_life_rules` has a unique key on `(product_id, storage_type_id)`: at most one product-level rule per product and storage type. Multiple category-level rules (`product_id IS NULL`) are allowed because MySQL does not compare NULLs in unique indexes.
- `shelf_life_rules.rule_status` is one of `AVAILABLE`, `QUALITATIVE_ONLY` or `NOT_RECOMMENDED`; `confidence` is one of `HIGH`, `MEDIUM` or `LOW`. Non-fresh categories are seeded with `NOT_RECOMMENDED` placeholder rules so the lookup logic never calculates an expiry for them.
- `reminders.lead_time_days` defaults to 3 but supports any value greater than or equal to 0; reminders are not hard-coded to 3 days.
- Roles are `ADMIN` and `MEMBER` only; there is no OWNER role.
- The rule "one PENDING join request per (team, user)" is enforced by the application layer before insertion, because MySQL does not support partial unique indexes. No naive `UNIQUE(team_id, user_id, status)` constraint is added.
- No ML, prediction, model or summary tables exist in this schema.

## Expiry Date Lookup Logic

When the application needs an expiry date for an inventory item, it uses the following order:

1. If `expiry_date_source` is `PACKAGING` or `USER_INPUT`, use the OCR-read or user-entered date and ignore all shelf-life rules.
2. If `expiry_date_source` is `CALCULATED` and the product has a product-level rule in `shelf_life_rules` (`product_id` matches, `storage_type_id` matches), use that rule.
3. If no product-level rule matches, fall back to the category-level rule for the product's category (`product_id IS NULL`, `storage_type_id` matches).
4. If no rule is found, prompt the user to enter the expiry date manually.

Additional rule: non-fresh items (`product_categories.is_fresh_food = FALSE`) must never use calculated rules, even when no expiry date is found. Their categories only have `NOT_RECOMMENDED` placeholder rules, so the lookup returns no usable calculation and the item is treated as manual-expiry only.

## Seed Data

`seed_data.sql` loads representative data with English names and descriptions:

| Table | Row count | Notes |
| --- | --- | --- |
| `users` | 4 | Alice, Bob, Carol, David. |
| `teams` | 2 | Lee Family Pantry, Hacker House Kitchen. |
| `team_members` | 5 | Admins and members, both ACTIVE. |
| `join_requests` | 3 | One PENDING, one APPROVED, one DECLINED. |
| `product_categories` | 9 | Dairy, Meat, Seafood, Vegetables, Fruits, Snacks, Beverages, Frozen Food, Household Items. |
| `products` | 114 | 50 Fruits and 50 Seafood products (e.g. Starfruit, Papaya, Cempedak, Sapodilla, Dokong, Mango, Salmon, Tuna), plus the original product set. |
| `storage_types` | 3 | FRIDGE, FREEZER, PANTRY. |
| `inventory_items` | 18 | Mixed statuses: IN_STOCK, CONSUMED, EXPIRED, DISCARDED, DONATED. |
| `inventory_transactions` | 22 | ADD / CONSUME / DISCARD / DONATE history, including an EXPIRED discard and a donation. |
| `shelf_life_rules` | 318 | 300 product-level rules (100 products x 3 storage types), 6 category-level fallbacks (Fruits and Seafood), 12 NOT_RECOMMENDED placeholders for non-fresh categories. |
| `reminders` | 7 | Lead times of 1, 2, 3 and 5 days; PENDING, TRIGGERED and CANCELLED. |
| `notification_recipients` | 12 | Multiple recipients per reminder with independent read state. |

Product-level shelf-life rules use `source_name = 'USDA FoodKeeper'` with realistic `min_days`, `max_days` and `recommended_days` values for FRIDGE, FREEZER and PANTRY. Expiry dates in the inventory seed data are computed relative to `CURDATE()` so the sample data remains useful when the script is re-run at a later date.

## Initialization

Run the scripts in order from the MySQL client:

```bash
mysql -u root -p < schema.sql
mysql -u root -p < seed_data.sql
```

Both scripts contain a `USE pantry_buddy;` statement, so the database is selected automatically.

## Testing

`test_data.sql` contains 36 scenarios for manual verification. Because several blocks intentionally raise errors (duplicate email, duplicate barcode, invalid foreign keys, over-consumption rejection), run the script with `--force` so that execution does not stop at the first expected error:

```bash
mysql -u root -p --force pantry_buddy < test_data.sql
```

Alternatively, copy individual scenario blocks into a MySQL client and inspect each result set.

### Test Conventions

- Every scenario runs inside a transaction and rolls back afterwards, so the script is repeatable and leaves no test data behind.
- Consume and discard scenarios lock the target row with `SELECT ... FOR UPDATE` before updating stock, simulating concurrent-safe operations.
- Scenarios 13-15 verify the shelf-life rule lookup: product-level priority, category-level fallback, and the non-fresh exclusion.
- Scenario 36 (clean schema recreation) is the only block without a transaction, because DDL statements cause implicit commits in MySQL. After it runs, re-import `schema.sql` and `seed_data.sql`.

### The 36 Scenarios

| # | Scenario | What it verifies |
| --- | --- | --- |
| 1 | User creation | A new user can be inserted and read back. |
| 2 | Duplicate email rejection | The unique email index rejects duplicates. |
| 3 | Team creation | A new team can be created. |
| 4 | Admin creation | A user can be added to a team as ADMIN. |
| 5 | Join request | A user can request to join a team. |
| 6 | Duplicate pending join request prevention | The application-layer guard prevents duplicate PENDING requests. |
| 7 | Approve join request | A request can be approved with reviewer information. |
| 8 | Decline join request | A request can be declined. |
| 9 | Product creation | A new product can be added. |
| 10 | Duplicate barcode rejection | The unique barcode index rejects duplicates. |
| 11 | Inventory creation | An inventory item can be added to a team. |
| 12 | Expiry source handling | PACKAGING, USER_INPUT and CALCULATED sources are all stored. |
| 13 | Product-level rule priority over category-level rule | The lookup chooses the product-level rule first. |
| 14 | Category-level fallback | The lookup falls back to the category rule when no product rule exists. |
| 15 | Non-fresh items ignore rules | Non-fresh categories only have NOT_RECOMMENDED placeholders; no expiry is calculated. |
| 16 | Static shelf-life calculation support | CALCULATED expiry equals production date + shelf life. |
| 17 | Partial consumption | Part of the stock is consumed and the quantity reduced. |
| 18 | Full consumption | The whole stock is consumed and the item marked CONSUMED. |
| 19 | Over-consumption rejection | Consuming more than available stock is rejected. |
| 20 | Discard | An item is discarded with a valid discard reason. |
| 21 | Expired discard | An expired item is discarded with reason EXPIRED. |
| 22 | User-discarded item | An item is discarded with reason USER_DISCARDED. |
| 23 | Item donation (DONATE / DONATED) | A DONATE transaction is recorded and the item status becomes DONATED. |
| 24 | Invalid FK rejection | Inserts with non-existent parents fail. |
| 25 | Product search | Products can be searched by name. |
| 26 | Inventory filtering | Inventory can be filtered by team, status and storage. |
| 27 | Home summary queries | Aggregates per team and expiring-soon lists work. |
| 28 | Reminder creation | A reminder can be created. |
| 29 | Default 3-day reminder | lead_time_days defaults to 3. |
| 30 | Custom reminder lead time | A custom lead time such as 7 days is supported. |
| 31 | Reminder cancellation | A reminder can be cancelled with cancelled_at set. |
| 32 | Multiple notification recipients | A reminder can notify several users. |
| 33 | Independent read/unread state | Each recipient's read state is independent. |
| 34 | Foreign-key delete behavior | CASCADE, SET NULL and RESTRICT all behave as designed, including product-rule cascade. |
| 35 | Seed data loading | Every table is populated, including 100+ products, 300+ shelf-life rules and donation samples. |
| 36 | Clean schema recreation | All tables can be dropped and recreated from scratch. |

## Design Notes

- All tables use the InnoDB engine and the `utf8mb4` character set with `utf8mb4_unicode_ci` collation.
- CHECK constraints are included and are enforced by MySQL 8.0.16+.
- `barcode` is always `VARCHAR(50)`; integer barcodes are not supported by design.
- `shelf_life_rules` extends the original category-only design to support product-level rules (`product_id NOT NULL`) while keeping category-level fallback rules (`product_id IS NULL`). The unique key `(product_id, storage_type_id)` guarantees at most one product-level rule per product and storage type; category-level rules coexist because NULLs are not compared.
- Expiry reminders support multiple lead times; 3 is only the default.
- The application layer is responsible for the duplicate-PENDING-join-request check, for rejecting over-consumption, and for applying the lookup order described in "Expiry Date Lookup Logic", since those are not representable as pure database constraints here.
