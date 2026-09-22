# Pantry Buddy Fresh Food Reference Data

## Files to upload

Upload these five files together:

1. `storage_types.csv` — the three storage conditions used by the rule engine.
2. `product_categories.csv` — application product categories.
3. `products.csv` — 200 fresh-food catalogue products: 50 fruits, 50 seafood products, 50 vegetables and 50 meat products.
4. `shelf_life_rules.csv` — 612 rules: 600 product-level rules plus 12 category fallback rules.
5. `README.md` — this import and provenance guide.

## Database behaviour

For packaged products, a detected or user-entered printed expiry date takes priority. For fresh food, query `shelf_life_rules` by `product_id` and `storage_type_id`. When the exact product cannot be identified, use the row with the matching `category_id`, `storage_type_id` and a NULL `product_id` as the category fallback.

The application interface can display the recognized product, selected storage location, calculated shelf-life range, recommended number of days, estimated expiry date, confidence level and handling note. Shelf-life values are guidance under continuous stated storage conditions; printed manufacturer dates take priority.

All durations are stored in days. FoodKeeper weeks were multiplied by 7 and months by 30. Room temperature means the Malaysia project profile of 25–30°C, refrigerator means 0–4°C, and freezer means −18°C or below.

## Timestamp import rule

`products.csv` and `shelf_life_rules.csv` intentionally omit `created_at` and `updated_at`. Do not add fixed timestamps. Import the explicitly listed CSV columns and allow MySQL to apply `DEFAULT CURRENT_TIMESTAMP` and `ON UPDATE CURRENT_TIMESTAMP` from `schema.sql`. User purchase, inventory-entry and expiry times belong in `inventory_items`, not in the product catalogue.

## Import order

After running `schema.sql` on an empty database, import the CSV files in this order to satisfy foreign keys:

1. `storage_types.csv`
2. `product_categories.csv`
3. `products.csv`
4. `shelf_life_rules.csv`

Use explicit target columns when importing `products.csv` and `shelf_life_rules.csv`, because their database-managed timestamp columns are intentionally omitted.

## Evidence and source links

Every one of the 612 shelf-life rows contains a non-empty public `source_url`. FoodKeeper-matched records link to the official U.S. Government dataset catalogue and identify the exact FoodKeeper row in `source_locator`. The locator also records the official XLS and the public structured review CSV. Records that cannot be matched precisely to FoodKeeper retain their government, food-safety authority, university Extension or public-document URL.

- Official FoodKeeper catalogue: https://catalog.data.gov/dataset/fsis-foodkeeper-data
- Official FoodKeeper XLS: https://www.fsis.usda.gov/shared/data/EN/FoodKeeper-Data.xls
- Public structured review CSV: https://raw.githubusercontent.com/jelera/food-shelflife-db/master/lib/seeds/ingredients.csv

The review CSV is a third-party structured mirror and must not be described as an official USDA CSV. The official USDA formats are XLS and JSON; the official catalogue is the primary citation.

In this project, `confidence` records source authority. HIGH includes official structured FoodKeeper records, the published NCHFP storage table and direct authoritative product or safety evidence. MEDIUM indicates government, food-safety or university guidance with an unresolved numeric locator, product-group mapping or temperature limitation. LOW is reserved for non-authoritative, unidentified or missing sources. Match granularity is recorded separately in `evidence_classification` and `source_locator`.

## FoodKeeper replacement summary

- Product names and product IDs were not changed.
- 67 meat/vegetable products received at least one exact FoodKeeper cold-storage rule.
- 124 meat/vegetable shelf-life rows were replaced with FoodKeeper values: 82 meat rows and 42 vegetable rows.
- FoodKeeper does not provide suitable raw room-temperature storage values for most meat and many vegetables. Those rows retain their existing safety or handling references.

## Required schema changes already represented

The supplied schema must contain `product_id`, `rule_status`, `confidence`, `evidence_classification`, `source_name`, `source_url`, `source_locator`, `source_value_text` and `handling_notes` in `shelf_life_rules`. Product-specific rules take precedence; category rules have a NULL `product_id`.

## Validation expectations

- 200 products: exactly 50 in each of Fruits, Seafood, Vegetables and Meat.
- 600 product rules: exactly three storage rows per product.
- 12 category fallback rules: three each for the four fresh-food categories.
- 612 total rules and no blank source URL.
- Unique `(product_id, storage_type_id)` for product-level rules.
- `min_days >= 0`, `max_days >= min_days`, and valid enum/status values.
