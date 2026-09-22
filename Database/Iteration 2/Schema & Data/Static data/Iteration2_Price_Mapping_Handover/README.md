# PantryBuddy Iteration 2 Price Data — Database Handover

## Read this first

This handover has been aligned with Hank's current Iteration 2 `schema.sql`, `insert_static_data.sql` and database README.

The current schema has 14 tables. It already contains `product_reference`, but it does not contain `product_keyword_mapping` or either price table.

## Final database scope

Three new tables are required for the complete recognition and price design:

15. `product_keyword_mapping` — recognition keywords;
16. `price_item_reference` — link between PriceCatcher items, units and PantryBuddy references;
17. `price_observations` — dated premise-level price observations.

Final total: 17 tables. Do not create a second `product_reference` table.

## Supplied files and destinations

| File | Use | Database destination |
|---|---|---|
| `product_reference_additions.csv` | New PriceCatcher-derived canonical references | Upsert into the existing `product_reference` |
| `product_keyword_mapping_additions.csv` | Exact English PriceCatcher names for matching | Upsert into the new `product_keyword_mapping` |
| `price_item_mapping.csv` | All 284 priced items, units, reference keys and price summaries | Populate the new `price_item_reference` |
| `price_observations_sample_2000.csv` | Iteration 2 structural and query test sample | Populate the new `price_observations` |

The complete `food_price.csv` contains 561,441 observations. It is retained in the shared data archive and is not imported into the free cloud database during Iteration 2.

## Confirmed answers to the database review

### 1. Observation sample

Importing only 2,000 observations is acceptable for Iteration 2 because of the free cloud database limit.

`price_observations_sample_2000.csv` contains:

- exactly 2,000 observations;
- at least one observation for each of the 284 priced `item_code` values;
- additional observations selected with fixed random seed `5120`;
- no duplicate `(date, premise_code, item_code)` keys;
- no non-positive prices.

All 284 rows in `price_item_mapping.csv` should still be loaded because these rows contain the calculated reference prices used by the application.

### 2. `reference_key`

`reference_key` is a staging field only. It does not enter a production table.

During import, resolve:

```text
reference_key -> product_reference.reference_id
```

All production foreign keys use `reference_id`.

### 3. Price and inventory units

The two unit fields can remain separate because they have different purposes:

- `inventory_items.unit VARCHAR(20)` stores user-facing values such as `kg`, `g`, `L`, `ml`, `pcs` and `dozen`.
- `price_item_reference.base_unit` stores the normalized price-comparison unit using the same spelling as the current inventory schema: `kg`, `L` or `pcs`.

The backend conversion map is:

| Inventory unit | Price base unit | Factor |
|---|---|---:|
| kg | kg | 1 |
| g | kg | 0.001 |
| L | L | 1 |
| ml | L | 0.001 |
| pcs | pcs | 1 |
| dozen | pcs | 12 |

Do not convert between dimensions, such as `pcs` to `kg`, without product-specific evidence. Use `base_unit VARCHAR(20)` with allowed values `kg`, `L` and `pcs`, matching the style of the existing `inventory_items.unit VARCHAR(20)` field.

### 4. Identifier relationship

`item_code`, `reference_id` and `product_id` are different identifiers:

```text
PriceCatcher item_code
        |
        v
price_item_reference.item_code
        |
        | reference_id (FK)
        v
product_reference.reference_id
        |
        | product_id (nullable FK)
        v
products.product_id
```

- `item_code` identifies one PriceCatcher-listed item and unit.
- `reference_id` identifies a PantryBuddy recognition reference.
- `product_id` identifies one of the PantryBuddy catalogue products.

A price item may link to a reference whose `product_id` is NULL. It can support recognition, category selection and reference pricing, but it must not automatically receive a product-level shelf-life rule.

### 5. One `product_reference` table

The existing `product_reference` table is created once.

- The earlier classification `product_reference.csv` is upserted into it.
- `product_reference_additions.csv` is then upserted into the same table after duplicate checking.

The keyword files do not go into `product_reference`:

- earlier `product_keyword_mapping.csv`;
- current `product_keyword_mapping_additions.csv`.

Both keyword files are upserted into the single new `product_keyword_mapping` table.

## Complete relationship

```text
product_categories
     |                    |
     v                    v
products            product_reference
     |                    |             |
     |                    v             v
     |        product_keyword_mapping  price_item_reference
     |                                      |
     v                                      v
inventory_items                       price_observations
```

Foreign-key detail:

```text
products.category_id -> product_categories.category_id
product_reference.category_id -> product_categories.category_id
product_reference.product_id -> products.product_id (nullable)
product_keyword_mapping.reference_id -> product_reference.reference_id
price_item_reference.reference_id -> product_reference.reference_id
price_observations.item_code -> price_item_reference.item_code
inventory_items.product_id -> products.product_id
```

## Minimum new table fields

Hank retains ownership of final SQL naming and constraint style.

### `product_keyword_mapping`

```text
mapping_id
reference_id
keyword
normalized_keyword
match_type
source_name
source_url
source_locator
is_active
created_at
updated_at
```

### `price_item_reference`

```text
item_code INT UNSIGNED PRIMARY KEY
reference_id BIGINT UNSIGNED FK -> product_reference.reference_id
source_item_name VARCHAR(255)
source_unit VARCHAR(50)
package_quantity_in_base_unit DECIMAL(12,4)
base_unit VARCHAR(20)
median_package_price DECIMAL(10,2)
mean_package_price DECIMAL(10,2)
latest_day_median_price DECIMAL(10,2)
median_price_per_base_unit DECIMAL(12,4)
price_observation_count INT UNSIGNED
latest_observation_date DATE
source_url VARCHAR(1000)
```

Review-only columns in `price_item_mapping.csv`, such as the source category and mapping note, may remain in staging instead of being duplicated in production.

### `price_observations`

```text
observation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY
observation_date DATE
premise_code INT UNSIGNED
item_code INT UNSIGNED FK -> price_item_reference.item_code
price_myr DECIMAL(10,2)
UNIQUE (observation_date, premise_code, item_code)
CHECK (price_myr > 0)
```

## Import order

1. Run Hank's current 14-table schema and static-data process.
2. Upsert the earlier classification `product_reference.csv` into the existing `product_reference`.
3. Upsert `product_reference_additions.csv` into the same table.
4. Resolve `reference_key` to `reference_id` using `(category_id, product_name)`.
5. Create `product_keyword_mapping` once.
6. Upsert the earlier `product_keyword_mapping.csv` and then `product_keyword_mapping_additions.csv`.
7. Create `price_item_reference` and load all 284 item mappings after resolving `reference_id`.
8. Create `price_observations` and load `price_observations_sample_2000.csv`.
9. Validate counts, foreign keys, unique keys, positive prices and fixed category IDs.

## Price use

1. Use the user's actual purchase price when available.
2. Otherwise use `median_package_price` when the item and package unit match.
3. Use `median_price_per_base_unit` only after converting a compatible inventory unit.
4. If no compatible public price exists, ask the user to enter a price.

The median is the recommended public fallback because it is less affected by unusually high or low premise prices. The mean is retained for comparison.

## Source

- Item lookup: https://storage.data.gov.my/pricecatcher/lookup_item.csv
- September 2026 observations: https://storage.data.gov.my/pricecatcher/pricecatcher_2026-09.csv
- Official catalogue: https://open.dosm.gov.my/data-catalogue/pricecatcher
- Licence: CC BY 4.0
- Currency: MYR

## Validation summary

- Priced items mapped: 284/284
- Price summary rows to load: 284
- Observation sample rows: 2,000
- Item codes represented in sample: 284
- Invalid category IDs: 0
- Duplicate sample observation keys: 0
- Non-positive sample prices: 0
- Blank generated source URLs: 0
