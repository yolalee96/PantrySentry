const express = require('express');
const pool = require('../db');
const { assertMember } = require('../util/household_access');
const { ApiError, asyncHandler } = require('../util/errors');
const { eligibleItems, sanitiseRecipes, buildRecipes, round3 } = require('../util/recipe_matching');
// The only line that changes when the recipe dataset arrives (or a
// combined source that uses the dataset first and the LLM as fallback).
const recipeSource = require('../recipe_sources/gemini');

const router = express.Router();

const HOUR_MS = 60 * 60 * 1000;
const REUSE_FOR_MS = 12 * HOUR_MS;        // normal cache lifetime
const REUSE_EMPTY_FOR_MS = 0.5 * HOUR_MS; // "nothing matched" is retried sooner
const MIN_REFRESH_GAP_MS = 30 * 1000;     // stops refresh-button spam burning the free quota
const FULLY_USED_THRESHOLD = 0.01;        // same "effectively finished" rule as AppState.resolveItem

function todayFrom(query) {
  const serverToday = new Date().toISOString().slice(0, 10);
  const t = query.today;
  if (t === undefined) return serverToday;
  if (typeof t !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(t) || Number.isNaN(Date.parse(`${t}T00:00:00Z`))) {
    throw new ApiError(400, 'today must be a date in YYYY-MM-DD format.');
  }
  // The app sends the user's local date (expiry dates are calendar
  // dates). Anything more than a day or two off the server's date is a
  // wrong clock or a crafted request, not a real timezone difference.
  if (Math.abs(Date.parse(`${t}T00:00:00Z`) - Date.parse(`${serverToday}T00:00:00Z`)) > 2 * 24 * HOUR_MS) {
    throw new ApiError(400, 'today is too far from the current date.');
  }
  return t;
}

function parseJsonColumn(value, fallback) {
  if (value === null || value === undefined) return fallback;
  if (typeof value !== 'string') return value; // driver already parsed the JSON column
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

/** DATETIME string (UTC, dateStrings: true) -> ms since epoch. */
function dbTimeMs(s) {
  return Date.parse(`${String(s).replace(' ', 'T')}Z`);
}

async function loadEligibleItems(householdId, today) {
  const [rows] = await pool.query(
    `SELECT ii.inventory_item_id, ii.quantity, ii.unit, ii.expiry_date, ii.status,
            p.product_name, pc.category_name AS category
     FROM inventory_items ii
     JOIN products p ON p.product_id = ii.product_id
     JOIN product_categories pc ON pc.category_id = p.category_id
     WHERE ii.team_id = ? AND ii.status = 'IN_STOCK'`,
    [householdId]
  );
  return eligibleItems(rows, today);
}

// GET /households/:householdId/recipe-suggestions?today=YYYY-MM-DD&refresh=true
//
// User Story 6.1. Returns { status, source, generatedAt, expiringSoonCount, recipes }
//   status 'ready'       — recipes found
//   status 'noMatches'   — inventory exists but no recipe matched (AC 6.1.7)
//   status 'noInventory' — nothing eligible in stock (all used up/expired)
router.get('/households/:householdId/recipe-suggestions', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const today = todayFrom(req.query);
  const refresh = req.query.refresh === 'true';
  const items = await loadEligibleItems(req.params.householdId, today);
  const expiringSoonCount = items.filter((i) => i.expiringSoon).length;

  if (items.length === 0) {
    return res.json({ status: 'noInventory', source: recipeSource.name, generatedAt: null, expiringSoonCount: 0, recipes: [] });
  }

  const [setRows] = await pool.query(
    'SELECT * FROM recipe_suggestion_sets WHERE team_id = ? ORDER BY created_at DESC, set_id DESC LIMIT 1',
    [req.params.householdId]
  );
  let set = setRows[0] || null;

  // Reuse the cached recipes unless they're stale, the user asked for
  // new ones, or an item has started expiring soon that the cached
  // recipes were never given the chance to use.
  if (set) {
    const ageMs = Date.now() - dbTimeMs(set.created_at);
    const storedRecipes = parseJsonColumn(set.recipes_json, []);
    const offeredIds = new Set(parseJsonColumn(set.input_item_ids, []).map(String));
    const maxAge = storedRecipes.length === 0 ? REUSE_EMPTY_FOR_MS : REUSE_FOR_MS;
    const newUrgentItem = items.some((i) => i.expiringSoon && !offeredIds.has(i.id));
    const stillUsable = buildRecipes(storedRecipes, items, set.set_id).length > 0 || storedRecipes.length === 0;
    const reuse = refresh
      ? ageMs < MIN_REFRESH_GAP_MS
      : ageMs < maxAge && !newUrgentItem && stillUsable;
    if (!reuse) set = null;
  }

  if (!set) {
    const raw = await recipeSource.suggestRecipes(items);
    const recipes = sanitiseRecipes(raw, new Set(items.map((i) => i.id)));
    const [result] = await pool.query(
      `INSERT INTO recipe_suggestion_sets (team_id, source, input_item_ids, recipes_json, created_by)
       VALUES (?, ?, ?, ?, ?)`,
      [req.params.householdId, recipeSource.name, JSON.stringify(items.map((i) => i.id)), JSON.stringify(recipes), req.userId]
    );
    const [rows] = await pool.query('SELECT * FROM recipe_suggestion_sets WHERE set_id = ?', [result.insertId]);
    set = rows[0];
  }

  const recipes = buildRecipes(parseJsonColumn(set.recipes_json, []), items, set.set_id);
  res.json({
    status: recipes.length > 0 ? 'ready' : 'noMatches',
    source: set.source,
    generatedAt: new Date(dbTimeMs(set.created_at)).toISOString(),
    expiringSoonCount,
    recipes,
  });
}));

// POST /households/:householdId/recipe-usage
// { submissionId, recipeId?, recipeTitle, ingredients: [{ inventoryItemId, quantityUsed }] }
//
// User Story 6.3. All-or-nothing: either every selected ingredient is
// deducted, or (on any validation error) none are.
router.post('/households/:householdId/recipe-usage', asyncHandler(async (req, res) => {
  const householdId = String(req.params.householdId);
  await assertMember(req.userId, householdId);

  const { submissionId, recipeId, recipeTitle, ingredients } = req.body || {};
  if (typeof submissionId !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(submissionId)) {
    throw new ApiError(400, 'submissionId must be 8-64 letters, digits, - or _.');
  }
  const title = typeof recipeTitle === 'string' ? recipeTitle.trim().slice(0, 200) : '';
  if (!title) throw new ApiError(400, 'recipeTitle is required.');
  if (!Array.isArray(ingredients) || ingredients.length === 0) {
    throw new ApiError(400, 'Select at least one ingredient that was used.');
  }
  if (ingredients.length > 30) throw new ApiError(400, 'Too many ingredients in one update.');

  const uses = ingredients.map((ing) => ({
    inventoryItemId: String(ing && ing.inventoryItemId),
    quantityUsed: Number(ing && ing.quantityUsed),
  }));
  if (new Set(uses.map((u) => u.inventoryItemId)).size !== uses.length) {
    throw new ApiError(400, 'Each inventory item can only appear once — combine the amounts.');
  }
  // AC 6.3.3 — zero or negative is rejected here; "more than available"
  // is checked against the locked rows below.
  for (const u of uses) {
    if (!/^\d+$/.test(u.inventoryItemId)) throw new ApiError(400, 'Invalid inventory item.');
    if (!Number.isFinite(u.quantityUsed) || u.quantityUsed <= 0) {
      throw new ApiError(400, 'Each quantity used must be more than zero.');
    }
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // AC 6.3.7 — claim the submission id first. A retry (or a concurrent
    // double-tap) with the same id hits the primary key and gets the
    // original result instead of deducting again.
    try {
      await conn.query(
        `INSERT INTO recipe_usage_submissions (submission_id, team_id, user_id, recipe_id, recipe_title)
         VALUES (?, ?, ?, ?, ?)`,
        [submissionId, householdId, req.userId, typeof recipeId === 'string' ? recipeId.slice(0, 40) : null, title]
      );
    } catch (err) {
      if (err && (err.code === 'ER_DUP_ENTRY' || err.errno === 1062)) {
        await conn.rollback();
        const [rows] = await pool.query('SELECT * FROM recipe_usage_submissions WHERE submission_id = ?', [submissionId]);
        if (rows.length === 0 || String(rows[0].team_id) !== householdId) {
          throw new ApiError(409, 'This submission id has already been used.');
        }
        const stored = parseJsonColumn(rows[0].result_json, { updated: [] });
        return res.json({ alreadyRecorded: true, ...stored });
      }
      throw err;
    }

    const ids = uses.map((u) => u.inventoryItemId);
    const [itemRows] = await conn.query(
      `SELECT ii.inventory_item_id, ii.team_id, ii.quantity, ii.unit, ii.status, p.product_name
       FROM inventory_items ii
       JOIN products p ON p.product_id = ii.product_id
       WHERE ii.inventory_item_id IN (?)
       FOR UPDATE`,
      [ids]
    );
    const rowsById = new Map(itemRows.map((r) => [String(r.inventory_item_id), r]));

    const updated = [];
    for (const u of uses) {
      const item = rowsById.get(u.inventoryItemId);
      if (!item || String(item.team_id) !== householdId) throw new ApiError(404, 'One of the ingredients is no longer in your inventory.');
      if (item.status !== 'IN_STOCK') {
        throw new ApiError(409, `${item.product_name} has already been used up or removed. Refresh and try again.`);
      }
      const available = Number(item.quantity);
      if (u.quantityUsed > available + 1e-9) {
        throw new ApiError(400, `You only have ${available} ${item.unit || 'pcs'} of ${item.product_name}.`);
      }

      const remaining = round3(Math.max(0, available - u.quantityUsed));
      const fullyUsed = remaining <= FULLY_USED_THRESHOLD;
      const note = `Used in recipe: ${title.slice(0, 100)}${fullyUsed ? '' : ` — ${remaining} ${item.unit || 'pcs'} left`}`;

      if (fullyUsed) {
        // AC 6.3.4 — fully used: consumed, same as "Mark fully consumed".
        await conn.query(
          "UPDATE inventory_items SET status = 'CONSUMED', checkout_date = NOW(), consumed_amount = 'full' WHERE inventory_item_id = ?",
          [u.inventoryItemId]
        );
        // AC 6.3.6 — its reminders no longer apply.
        await conn.query(
          `UPDATE reminders SET status = 'CANCELLED', cancelled_at = NOW()
           WHERE inventory_item_id = ? AND status IN ('PENDING', 'TRIGGERED')`,
          [u.inventoryItemId]
        );
      } else {
        // AC 6.3.4 — partly used: keep the remainder in stock.
        await conn.query(
          "UPDATE inventory_items SET quantity = ?, consumed_amount = 'partial' WHERE inventory_item_id = ?",
          [remaining, u.inventoryItemId]
        );
      }
      // AC 6.3.6 — consumption record, logging the amount actually used.
      await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'CONSUME', ?, ?)`,
        [u.inventoryItemId, req.userId, fullyUsed ? available : u.quantityUsed, note]
      );
      updated.push({
        inventoryItemId: u.inventoryItemId,
        name: item.product_name,
        quantityUsed: fullyUsed ? available : u.quantityUsed,
        remainingQuantity: fullyUsed ? 0 : remaining,
        unit: item.unit || 'pcs',
        fullyUsed,
      });
    }

    const result = { updated };
    await conn.query('UPDATE recipe_usage_submissions SET result_json = ? WHERE submission_id = ?', [JSON.stringify(result), submissionId]);
    await conn.commit();
    res.json({ alreadyRecorded: false, ...result });
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}));

module.exports = router;
