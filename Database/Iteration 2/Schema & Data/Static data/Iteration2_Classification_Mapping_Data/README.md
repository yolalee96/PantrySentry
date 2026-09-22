# PantryBuddy Iteration 2 — SQL Data Handover

This package contains data prepared by the data team. It does not replace the database team's schema or application migration process.

## Files

1. `product_reference.csv` — reference food names mapped to the existing PantryBuddy categories. Existing catalogue products retain their original `product_id`; broader reference terms leave `product_id` blank.
2. `product_keyword_mapping.csv` — English keywords and Open Food Facts taxonomy terms used to resolve OCR text, manual text and barcode metadata to a reference product or category.

## How to read the CSV columns

### `product_reference.csv`

| Column | Meaning |
|---|---|
| reference_key | Temporary import key connecting the two CSV files; it is not user-facing |
| product_id | Existing PantryBuddy product ID; blank means a category reference rather than one of the original 200 products |
| category_id | Existing PantryBuddy category ID |
| product_name | Canonical English reference name |
| barcode | Optional known barcode; blank values must become SQL NULL |
| description | Explanation of the reference row |
| is_active | Whether the row can be used |
| source_item_code | Original catalogue ID or Open Food Facts tag retained for provenance |

### `product_keyword_mapping.csv`

| Column | Meaning |
|---|---|
| reference_key | Temporary join key pointing to one row in `product_reference.csv` |
| category_id | PantryBuddy category assigned by the project crosswalk |
| product_name | Canonical English name returned as a candidate |
| keyword | Text or taxonomy tag that can trigger this candidate |
| normalized_keyword | Lower-case comparison form used by the backend |
| match_type | `TEXT` for manual/OCR/image-label text; `OFF_TAG` for an exact Open Food Facts category tag |
| source_name | Dataset or organisation from which the term came |
| source_url | Direct provenance URL |
| source_locator | Exact source tag and the PantryBuddy anchor used for routing |
| is_active | `1` means the mapping is enabled |

`OFF` means Open Food Facts. Prefix `en:` means an English Open Food Facts taxonomy tag. The final CSV intentionally excludes canonical tags beginning with other language codes.

## Existing table

Hank's Iteration 2 schema already contains `product_reference`. Do not create a second copy of that table. Load the CSV into a temporary staging table, then insert or upsert its production fields into the existing table.

`reference_key` and `source_item_code` are staging/provenance fields in the CSV. They do not have to become production columns. `reference_key` is required during import so rows in the second CSV can be connected to the correct generated `reference_id`.

## Final database relationship

```text
product_categories (existing)
        1
        |
        | category_id
        N
product_reference (existing Iteration 2 table)
        1
        |
        | reference_id
        N
product_keyword_mapping (one new table)
```

The database teammate only needs to add `product_keyword_mapping`. No change is required to the original `products` or `shelf_life_rules` data.

## New table required

Please add one table named `product_keyword_mapping` using the project's normal migration style.

| Column | Suggested MySQL type | Required | Meaning |
|---|---|---:|---|
| mapping_id | BIGINT UNSIGNED AUTO_INCREMENT | Yes | Primary key |
| reference_id | BIGINT UNSIGNED | Yes | Foreign key to `product_reference.reference_id` |
| keyword | VARCHAR(255) | Yes | Original English label or keyword |
| normalized_keyword | VARCHAR(255) | Yes | Lower-case normalized value used for matching |
| match_type | ENUM('TEXT','OFF_TAG') or VARCHAR(30) | Yes | Text matching or exact Open Food Facts taxonomy-tag matching |
| source_name | VARCHAR(255) | Yes | Source organisation or dataset |
| source_url | VARCHAR(1000) | Yes | Direct provenance URL |
| source_locator | VARCHAR(1000) | No | Source tag, record or transformation note |
| is_active | BOOLEAN | Yes | Enables or disables the mapping |
| created_at | DATETIME | Yes | Database-generated timestamp |
| updated_at | DATETIME | Yes | Database-managed update timestamp |

Required constraints and indexes:

- Primary key on `mapping_id`.
- Foreign key from `reference_id` to `product_reference.reference_id`.
- Unique key on `(reference_id, normalized_keyword, match_type)`.
- Index on `normalized_keyword` for lookup.
- Index on `reference_id` for joins.
- `source_url` must not be NULL or blank.
- Database timestamps should use `CURRENT_TIMESTAMP`; do not import fixed CSV timestamps.

## Import sequence

1. Keep the existing 16 PantryBuddy categories and their current IDs unchanged.
2. Create a temporary staging table matching the columns in `product_reference.csv` and load that CSV.
3. Insert or upsert `product_id`, `category_id`, `product_name`, `barcode`, `description` and `is_active` into the existing `product_reference` table. Convert blank `product_id` and `barcode` values to SQL NULL.
4. Build a temporary lookup of `reference_key -> reference_id` by joining the staging rows back to `product_reference` on the existing unique identity, normally `(category_id, product_name)`.
5. Create `product_keyword_mapping` through the database team's migration process.
6. Load `product_keyword_mapping.csv` into a second temporary staging table.
7. Insert `reference_id`, `keyword`, `normalized_keyword`, `match_type`, `source_name`, `source_url`, `source_locator` and `is_active` into the new table by joining the second staging table to the temporary key lookup.
8. Validate foreign keys, duplicate normalized terms, blank source URLs and invalid category IDs, then remove the temporary staging tables.

The `category_id` and `product_name` columns in `product_keyword_mapping.csv` are included for human review and import validation. They do not need to be duplicated in the final `product_keyword_mapping` table because the same values are obtained through its `reference_id` foreign-key join.

## What the database teammate must deliver

- One migration adding `product_keyword_mapping` with the fields and constraints above.
- One repeatable import/seed process for the two supplied CSV files.
- Validation output confirming row counts, valid category IDs, no orphan `reference_id` values, no blank source URLs and no duplicate unique keys.

Do not rerun or replace the full production schema. Do not modify the existing 200 catalogue products or 612 shelf-life rules.

## Matching query responsibility

The backend should normalize input text, search exact or phrase matches in `product_keyword_mapping`, join to `product_reference`, and return candidates for user confirmation. A generic keyword may return a category without a `product_id`; it must not be assigned to a nearby catalogue species automatically.
