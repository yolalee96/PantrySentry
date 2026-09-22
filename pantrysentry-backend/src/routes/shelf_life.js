const express = require('express');
const pool = require('../db');
const { asyncHandler } = require('../util/errors');
const { CATEGORY_DB_NAMES, STORAGE_DB_NAMES } = require('../util/enums');

const router = express.Router();

// IMPORTANT: `source_value_text` is the real, user-facing sourced fact
// (e.g. "Maximum 2 hours at 25-30C; room-temperature storage is not
// recommended.") — this is what gets shown to users. `handling_notes` is
// an internal note to whoever builds the app (e.g. "Display a warning;
// do not calculate an endorsed expiry date.") and must NEVER be shown to
// end users — it reads like a dev instruction, not a recommendation.
function ruleRowToJson(row, matchedProductName) {
  return {
    status: row.rule_status === 'AVAILABLE'
      ? 'available'
      : row.rule_status === 'NOT_RECOMMENDED'
        ? 'notRecommended'
        : 'qualitativeOnly',
    minDays: row.min_days,
    maxDays: row.max_days,
    recommendedDays: row.recommended_days === null ? null : Number(row.recommended_days),
    sourceText: row.source_value_text,
    sourceName: row.source_name,
    matchedProductName: matchedProductName ?? null,
  };
}

/**
 * The real dataset (from insert_static_data.sql) is overwhelmingly
 * PRODUCT-specific — as of the last sync, only Seafood/Fruits/Meat/
 * Vegetables have any rules at all: ~150 named products each (e.g.
 * "Chicken Breast", "Chicken Thigh") plus just 3 generic category-level
 * fallback rows per category (one per storage type). The other 12
 * categories currently have NO rules of either kind.
 *
 * Since the app still takes a free-text item name rather than a real
 * product picker, this tries to match that typed name against a real
 * product in `products` first (much more accurate — different cuts of
 * the same category can have very different shelf lives), and only
 * falls back to the coarse category-level rule if there's no match.
 */
async function findProductMatch(categoryId, itemName) {
  if (!itemName || !itemName.trim()) return null;
  const trimmed = itemName.trim();

  const [exact] = await pool.query(
    `SELECT product_id, product_name FROM products
     WHERE category_id = ? AND LOWER(product_name) = LOWER(?)
     LIMIT 1`,
    [categoryId, trimmed]
  );
  if (exact.length > 0) return exact[0];

  const [loose] = await pool.query(
    `SELECT product_id, product_name FROM products
     WHERE category_id = ? AND (LOWER(product_name) LIKE LOWER(?) OR LOWER(?) LIKE CONCAT('%', LOWER(product_name), '%'))
     ORDER BY LENGTH(product_name) ASC
     LIMIT 1`,
    [categoryId, `%${trimmed}%`, trimmed]
  );
  return loose.length > 0 ? loose[0] : null;
}

/** Shared lookup for one (category, storage type) combo — used by both
 * routes below so there's exactly one place implementing the "product
 * match, then category fallback" logic. */
async function lookupSuggestion({ categoryId, storageTypeId, matchedProduct }) {
  if (matchedProduct) {
    const [productRuleRows] = await pool.query(
      'SELECT * FROM shelf_life_rules WHERE product_id = ? AND storage_type_id = ? LIMIT 1',
      [matchedProduct.product_id, storageTypeId]
    );
    if (productRuleRows.length > 0) {
      return ruleRowToJson(productRuleRows[0], matchedProduct.product_name);
    }
    // Matched a product, but no rule for this specific storage type —
    // fall through to the category-level rule rather than returning null.
  }

  const [categoryRuleRows] = await pool.query(
    `SELECT * FROM shelf_life_rules
     WHERE category_id = ? AND storage_type_id = ? AND product_id IS NULL
     ORDER BY rule_id ASC LIMIT 1`,
    [categoryId, storageTypeId]
  );
  if (categoryRuleRows.length > 0) {
    return ruleRowToJson(categoryRuleRows[0], null);
  }

  return null; // no data at all for this category/storage combo yet
}

// GET /shelf-life-suggestion?category=<ProductCategory enum>&storageLocation=<StorageLocation enum>&itemName=<free text, optional>
router.get('/shelf-life-suggestion', asyncHandler(async (req, res) => {
  const { category, storageLocation, itemName } = req.query;
  const categoryDbName = CATEGORY_DB_NAMES[category];
  const storageDbName = STORAGE_DB_NAMES[storageLocation];
  if (!categoryDbName || !storageDbName) return res.json(null);

  const [categoryRows] = await pool.query('SELECT category_id FROM product_categories WHERE category_name = ?', [categoryDbName]);
  if (categoryRows.length === 0) return res.json(null);
  const categoryId = categoryRows[0].category_id;

  const [storageRows] = await pool.query('SELECT storage_type_id FROM storage_types WHERE storage_name = ?', [storageDbName]);
  const storageTypeId = storageRows[0].storage_type_id;

  const matchedProduct = await findProductMatch(categoryId, itemName);
  const result = await lookupSuggestion({ categoryId, storageTypeId, matchedProduct });
  res.json(result);
}));

// GET /storage-suggestions?category=<ProductCategory enum>&itemName=<free text, optional>
//
// Same lookup as above, but for all 3 storage types at once — lets the
// app show "here's how this item fares in Fridge/Freezer/Pantry" before
// the user has picked a storage location, instead of requiring storage
// to be picked first just to find out it's a bad fit.
router.get('/storage-suggestions', asyncHandler(async (req, res) => {
  const { category, itemName } = req.query;
  const categoryDbName = CATEGORY_DB_NAMES[category];
  if (!categoryDbName) return res.json({ fridge: null, freezer: null, pantry: null });

  const [categoryRows] = await pool.query('SELECT category_id FROM product_categories WHERE category_name = ?', [categoryDbName]);
  if (categoryRows.length === 0) return res.json({ fridge: null, freezer: null, pantry: null });
  const categoryId = categoryRows[0].category_id;

  const matchedProduct = await findProductMatch(categoryId, itemName);

  const [storageRows] = await pool.query('SELECT storage_type_id, storage_name FROM storage_types');
  const result = {};
  for (const storageRow of storageRows) {
    const dartName = Object.entries(STORAGE_DB_NAMES).find(([, db]) => db === storageRow.storage_name)?.[0];
    if (!dartName) continue;
    result[dartName] = await lookupSuggestion({
      categoryId,
      storageTypeId: storageRow.storage_type_id,
      matchedProduct,
    });
  }
  res.json(result);
}));

module.exports = router;
