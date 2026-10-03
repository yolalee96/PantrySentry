# Recipe Data Handover

## Files and import order

1. `recipes.csv`: 7,258 rows, mapped to `recipes`.
2. `recipe_ingredients.csv`: 59,518 rows, mapped to `recipe_ingredients`.
3. `quantity_conversions.csv`: 6 rows, mapped to `quantity_conversions`.

CSV encoding: UTF-8 **without BOM**. Import empty cells as SQL NULL. Headers follow the agreed column order; use explicit column mappings and let the database populate timestamp defaults. No new tables are needed.

## IDs and completed checks

- `recipe_id`: 1000049–1539115
- `ingredient_id`: 100049001–639115004
- `conversion_id`: 1000000–1000005

Verified unique IDs, ingredient-to-recipe relationships, JSON instruction arrays, sequential ingredient sort order, boolean values, and no ID overlap with the repository's seed rows. Removed 50,084 `[QUANTIFIED]` prefixes; descriptive text and other missing-amount notes are preserved. All three CSV files were checked for absence of a BOM.

Nonempty reference and category IDs were checked against this checkout's `insert_static_data.sql` (7,881 product references). Invalid IDs were cleared: reference_id=0, category_id=0.

Ingredient rows with NULL `reference_id`: **27,582**. Rows with NULL `category_id`: **27,582**. These counts can overlap. An unmatched reference does not mean the user lacks that ingredient; reference matches also do not guarantee a linked inventory product.

**Live target validation remains required:** no connection to the team's database was available. Before import, compare every nonempty reference/category ID with the target, confirm identity as well as existence, clear absent references to NULL, and check all three tables for ID collisions. This package has not been imported into the team's live database.

## Existing data and cooking history

Back up the target before importing. This is a replacement release, not a batch to append blindly. Do not bulk-delete recipes or ingredient rows: recipe cooking sessions use `ON DELETE RESTRICT`, and deleting ingredients sets historical ingredient links to NULL. Reconcile by stable IDs, update matching records, insert new records, and retain historical rows. Recipes removed from this release can be deactivated after review. Preserve cooking sessions and session items; perform the reviewed migration in a transaction. Do not rerun the original schema.sql on an existing database.

## Units and display rules

The six conversions implement the team's requested policy: g→kg=0.001, ml→L=0.001, dozen→pcs=12, cup→ml=240, tbsp→ml=15, tsp→ml=5. They are global (NULL reference_id), active, and marked is_assumed=1 as requested. Cooking-volume conventions vary; these are project assumptions, not universally applicable measured values. No external citation has been invented; source_url is NULL.

**These six rows cannot convert all foods to kg.** Volumes need food-specific density, and pieces need food-specific weight. Conversion chains and identity conversions (kg→kg) must be handled by the backend. Checking only whether a unit occurs in from_unit is insufficient. Missing conversion paths or emission factors must produce EXCLUDED assessments, not zero impact. Emission factors are not included in this recipe package.

Keep missing times and difficulty as NULL. Label preparation, cooking, and total times separately; do not infer total time from preparation time. Unknown ingredient quantities remain NULL with their original details in notes.

## Sources and images

Sources: [Food.com Recipes and Reviews](https://www.kaggle.com/datasets/irkaal/foodcom-recipes-and-reviews) and [RecipeNLG original dataset terms](https://huggingface.co/datasets/mbien/recipe_nlg). Ingredient supplementation required matching source IDs, titles, all steps, and quantities. Every recipe retains source metadata; source-page availability was not individually checked.

Image links passed HTTPS retrieval, full decoding, and fresh Chrome cross-origin img loading tests on 2026-10-03. URLs are encoded; images are not bundled. Configure frontend CSP img-src and a failure placeholder. Availability may change; actual deployed-app behavior and pictured-dish identity were not individually verified. This revision does not repeat image network tests.

The combined dataset is intended for noncommercial teaching/research; this is not a blanket redistribution or image-use license. Check upstream terms before publication or other reuse. Image rights have not been secured, and the entire package must not be treated as CC0.

Detailed workflow and validation evidence are kept separately by the data maintainer for the data management plan.
