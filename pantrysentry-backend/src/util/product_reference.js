// Links an inventory item's product to a row in product_reference, which
// is what the data team's Iteration 3 reference data hangs off:
// emission_factors and quantity_conversions (Epic 8) and
// recipe_ingredients (Epic 6) are all keyed by reference_id.
//
// inventory_items only stores product_id, and most products were created
// on the fly from whatever name the user typed (see findOrCreateProductId
// in routes/inventory.js), so only catalogue products carry a direct
// product_reference.product_id link. Resolution order, most to least
// certain:
//   1. 'product_link' — product_reference.product_id = the item's product
//   2. 'exact_name'   — same product name (case-insensitive), same category preferred
//   3. 'keyword'      — product_keyword_mapping TEXT keyword equal to the
//                       normalised name, same category preferred
// No fuzzy matching: a wrong match would attach the wrong emission factor
// (or claim a recipe ingredient is in stock), which is worse than none.

/** Same normalisation as product_keyword_mapping.normalized_keyword
 * (and normalizeText in routes/recognition.js). */
function normaliseName(name) {
  return String(name || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Picks the candidate in the item's own category if there is one,
 * otherwise the lowest reference_id, so results are deterministic. */
function pickCandidate(candidates, categoryId) {
  if (candidates.length === 0) return null;
  const sameCategory = candidates.filter((c) => Number(c.category_id) === Number(categoryId));
  const pool = sameCategory.length > 0 ? sameCategory : candidates;
  return pool.reduce((best, c) => (Number(c.reference_id) < Number(best.reference_id) ? c : best));
}

/**
 * products: [{ productId, name, categoryId }]
 * Returns Map(productId -> { referenceId, method }) for the products
 * that could be resolved. [db] is the pool or a connection.
 */
async function resolveReferenceIds(db, products) {
  const result = new Map();
  const unique = [...new Map(products.map((p) => [String(p.productId), p])).values()];
  if (unique.length === 0) return result;

  // 1. Direct catalogue link.
  const [linked] = await db.query(
    'SELECT reference_id, product_id FROM product_reference WHERE is_active = 1 AND product_id IN (?)',
    [unique.map((p) => p.productId)]
  );
  for (const row of linked) {
    result.set(String(row.product_id), { referenceId: Number(row.reference_id), method: 'product_link' });
  }

  // 2. Exact name.
  let pending = unique.filter((p) => !result.has(String(p.productId)));
  if (pending.length > 0) {
    const names = [...new Set(pending.map((p) => normaliseName(p.name)).filter(Boolean))];
    if (names.length > 0) {
      const [rows] = await db.query(
        `SELECT reference_id, category_id, LOWER(TRIM(product_name)) AS norm_name
         FROM product_reference
         WHERE is_active = 1 AND LOWER(TRIM(product_name)) IN (?)`,
        [names]
      );
      for (const p of pending) {
        const match = pickCandidate(rows.filter((r) => normaliseName(r.norm_name) === normaliseName(p.name)), p.categoryId);
        if (match) result.set(String(p.productId), { referenceId: Number(match.reference_id), method: 'exact_name' });
      }
    }
  }

  // 3. Keyword mapping.
  pending = unique.filter((p) => !result.has(String(p.productId)));
  if (pending.length > 0) {
    const names = [...new Set(pending.map((p) => normaliseName(p.name)).filter(Boolean))];
    if (names.length > 0) {
      const [rows] = await db.query(
        `SELECT pkm.reference_id, pkm.normalized_keyword, pr.category_id
         FROM product_keyword_mapping pkm
         JOIN product_reference pr ON pr.reference_id = pkm.reference_id
         WHERE pkm.match_type = 'TEXT' AND pkm.is_active = 1 AND pr.is_active = 1
           AND pkm.normalized_keyword IN (?)`,
        [names]
      );
      for (const p of pending) {
        const match = pickCandidate(rows.filter((r) => r.normalized_keyword === normaliseName(p.name)), p.categoryId);
        if (match) result.set(String(p.productId), { referenceId: Number(match.reference_id), method: 'keyword' });
      }
    }
  }
  return result;
}

/**
 * Folds simple English plurals on the last word so "Tomatoes", "tomato"
 * and "tomatos" compare equal ("berries" -> "berry", "milks" -> "milk").
 * Deliberately simple: only the last word, only regular endings.
 */
function foldPlural(name) {
  const n = normaliseName(name);
  const words = n.split(' ');
  let w = words[words.length - 1];
  if (w.length > 4 && w.endsWith('ies')) w = `${w.slice(0, -3)}y`;
  else if (w.length > 4 && w.endsWith('oes')) w = w.slice(0, -2);
  else if (w.length > 4 && /(ches|shes|sses|xes)$/.test(w)) w = w.slice(0, -2);
  else if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) w = w.slice(0, -1);
  words[words.length - 1] = w;
  return words.join(' ');
}

function nameVariants(name) {
  const n = normaliseName(name);
  const f = foldPlural(n);
  return [...new Set([n, f, `${f}s`, `${f}es`, f.endsWith('y') ? `${f.slice(0, -1)}ies` : null].filter(Boolean))];
}

/**
 * Epic 6 — everything an inventory item could be called in the recipe
 * data: ALL references reachable from it (its catalogue link, exact-name
 * references, and every reference whose keyword equals its name or a
 * singular/plural variant), plus plural-folded names. Recipe ingredients
 * mostly point at generic references ("Tomatoes", 6981) while catalogue
 * items have their own ("Tomato", 134); the keyword table links both to
 * "tomato", which is what makes them match.
 *
 * items: [{ id, productId, name }]
 * Returns Map(itemId -> { referenceIds: Set<number>, foldedNames: Set<string> })
 */
async function matchKeysForItems(db, items) {
  const result = new Map(items.map((i) => [i.id, { referenceIds: new Set(), foldedNames: new Set([foldPlural(i.name)]) }]));
  if (items.length === 0) return result;

  const productIds = [...new Set(items.map((i) => i.productId))];
  const [linked] = await db.query(
    'SELECT reference_id, product_id, product_name FROM product_reference WHERE is_active = 1 AND product_id IN (?)',
    [productIds]
  );
  const variantsByItem = new Map(items.map((i) => [i.id, nameVariants(i.name)]));
  const allVariants = [...new Set([...variantsByItem.values()].flat())];

  const [byName] = await db.query(
    `SELECT reference_id, LOWER(TRIM(product_name)) AS norm_name FROM product_reference
     WHERE is_active = 1 AND LOWER(TRIM(product_name)) IN (?)`,
    [allVariants]
  );
  const [byKeyword] = await db.query(
    `SELECT pkm.reference_id, pkm.normalized_keyword FROM product_keyword_mapping pkm
     JOIN product_reference pr ON pr.reference_id = pkm.reference_id
     WHERE pkm.match_type = 'TEXT' AND pkm.is_active = 1 AND pr.is_active = 1 AND pkm.normalized_keyword IN (?)`,
    [allVariants]
  );

  for (const item of items) {
    const keys = result.get(item.id);
    const variants = new Set(variantsByItem.get(item.id));
    for (const r of linked) {
      if (String(r.product_id) === String(item.productId)) {
        keys.referenceIds.add(Number(r.reference_id));
        keys.foldedNames.add(foldPlural(r.product_name));
      }
    }
    for (const r of byName) if (variants.has(normaliseName(r.norm_name))) keys.referenceIds.add(Number(r.reference_id));
    for (const r of byKeyword) if (variants.has(r.normalized_keyword)) keys.referenceIds.add(Number(r.reference_id));
  }
  return result;
}

module.exports = { resolveReferenceIds, matchKeysForItems, normaliseName, foldPlural };
