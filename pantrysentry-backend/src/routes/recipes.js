const express = require('express');
const pool = require('../db');
const { assertMember } = require('../util/household_access');
const { ApiError, asyncHandler } = require('../util/errors');
const { matchKeysForItems } = require('../util/product_reference');
const { eligibleItems, rankRecipes, buildRecipe, RESULT_LIMIT, round3 } = require('../util/recipe_matching');
const { AI_SOURCE_NAME, sanitiseAiRecipes, saveAiRecipes } = require('../util/ai_recipes');
const gemini = require('../recipe_sources/gemini');

const router = express.Router();

// Epic 6 — recipe suggestions from two sources, shown together:
//   GET .../recipe-suggestions     the recipe dataset (recipes /
//                                  recipe_ingredients, 7,258 Food.com +
//                                  RecipeNLG recipes from the data team) —
//                                  fast, so the screen shows these first
//   GET .../recipe-suggestions/ai  a few AI ideas from Gemini — slower,
//                                  loaded separately so a Gemini delay or
//                                  free-tier limit never blocks the rest
// Both are matched, ranked and checked against the inventory by the same
// code (util/recipe_matching.js), and either kind can be recorded as a
// cooking session (recipe_cook_sessions / recipe_cook_session_items).

const HOUR_MS = 60 * 60 * 1000;
const PRELIMINARY_LIMIT = 300;      // recipes fully scored per request
const AI_REUSE_FOR_MS = 12 * HOUR_MS;      // reuse a household's AI ideas this long...
const AI_REUSE_EMPTY_FOR_MS = 0.5 * HOUR_MS; // ...or this long if Gemini found nothing
const AI_MIN_REFRESH_GAP_MS = 30 * 1000;   // stops refresh spam burning the free quota
const FULLY_USED_THRESHOLD = 0.01;  // same "effectively finished" rule as AppState.resolveItem

function todayFrom(query) {
  const serverToday = new Date().toISOString().slice(0, 10);
  const t = query.today;
  if (t === undefined) return serverToday;
  if (typeof t !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(t) || Number.isNaN(Date.parse(`${t}T00:00:00Z`))) {
    throw new ApiError(400, 'today must be a date in YYYY-MM-DD format.');
  }
  // The app sends the user's local date (expiry dates are calendar
  // dates). More than a day or two off the server's date is a wrong
  // clock or a crafted request, not a timezone difference.
  if (Math.abs(Date.parse(`${t}T00:00:00Z`) - Date.parse(`${serverToday}T00:00:00Z`)) > 2 * 24 * HOUR_MS) {
    throw new ApiError(400, 'today is too far from the current date.');
  }
  return t;
}

function groupByRecipe(rows) {
  const map = new Map();
  for (const r of rows) {
    const key = String(r.recipe_id);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(r);
  }
  return map;
}

/** Name spellings to look up in recipe_ingredients.normalized_ingredient_name. */
function sqlNameVariants(foldedNames) {
  const out = new Set();
  for (const f of foldedNames) {
    out.add(f);
    out.add(`${f}s`);
    out.add(`${f}es`);
    if (f.endsWith('y')) out.add(`${f.slice(0, -1)}ies`);
  }
  return [...out];
}

async function loadEligibleItems(householdId, today) {
  const [stockRows] = await pool.query(
    `SELECT ii.inventory_item_id, ii.product_id, ii.quantity, ii.unit, ii.expiry_date, ii.status,
            p.product_name, pc.category_name
     FROM inventory_items ii
     JOIN products p ON p.product_id = ii.product_id
     JOIN product_categories pc ON pc.category_id = p.category_id
     WHERE ii.team_id = ? AND ii.status = 'IN_STOCK'`,
    [householdId]
  );
  const categoryById = new Map(stockRows.map((r) => [String(r.inventory_item_id), r.category_name]));
  return eligibleItems(stockRows, today).map((i) => ({ ...i, category: categoryById.get(i.id) }));
}

/** Loads recipes by id and returns them built + ranked against [items]. */
async function buildRankedRecipes(recipeIds, items, keysByItem, origin) {
  if (recipeIds.length === 0) return [];
  const [allLines] = await pool.query(
    `SELECT ingredient_id, recipe_id, ingredient_name, normalized_ingredient_name, reference_id,
            quantity, unit, is_optional, sort_order, notes
     FROM recipe_ingredients WHERE recipe_id IN (?)`,
    [recipeIds]
  );
  const linesByRecipe = groupByRecipe(allLines);
  const ranked = rankRecipes(linesByRecipe, items, keysByItem).slice(0, RESULT_LIMIT);
  if (ranked.length === 0) return [];
  const [recipeRows] = await pool.query(
    `SELECT recipe_id, title, description, servings, serving_unit, prep_time_minutes, cook_time_minutes,
            total_time_minutes, difficulty, cuisine, instructions_json, source_name, source_url, image_url
     FROM recipes WHERE recipe_id IN (?)`,
    [ranked.map((r) => r.recipeId)]
  );
  const recipeById = new Map(recipeRows.map((r) => [String(r.recipe_id), r]));
  return ranked
    .map((r) => recipeById.get(String(r.recipeId)))
    .filter(Boolean)
    .map((recipe) => ({
      ...buildRecipe(recipe, linesByRecipe.get(String(recipe.recipe_id)) || [], items, keysByItem),
      origin,
    }));
}

function parseJsonColumn(value, fallback) {
  if (value === null || value === undefined) return fallback;
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return fallback; }
}

/** DATETIME string (UTC, dateStrings: true) -> ms since epoch. */
function dbTimeMs(s) {
  return Date.parse(`${String(s).replace(' ', 'T')}Z`);
}

// GET /households/:householdId/recipe-suggestions?today=YYYY-MM-DD
//
// User Story 6.1. { status, source, expiringSoonCount, recipes }
//   status 'ready'       — at least one recipe matched
//   status 'noMatches'   — inventory exists but no recipe matched (AC 6.1.7)
//   status 'noInventory' — nothing eligible in stock (used up / expired)
router.get('/households/:householdId/recipe-suggestions', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const today = todayFrom(req.query);

  const items = await loadEligibleItems(req.params.householdId, today);
  const expiringSoonCount = items.filter((i) => i.expiringSoon).length;
  if (items.length === 0) {
    return res.json({ status: 'noInventory', source: 'dataset', expiringSoonCount: 0, recipes: [] });
  }

  const keysByItem = await matchKeysForItems(pool, items);
  const referenceIds = [...new Set([...keysByItem.values()].flatMap((k) => [...k.referenceIds]))];
  const names = sqlNameVariants(new Set([...keysByItem.values()].flatMap((k) => [...k.foldedNames])));

  // Pass 1: only the ingredient lines that match something in stock —
  // cheap, and enough to rank by expiring items and matches.
  const [matchedLines] = await pool.query(
    `SELECT ri.recipe_id, ri.ingredient_id, ri.ingredient_name, ri.normalized_ingredient_name,
            ri.reference_id, ri.is_optional
     FROM recipe_ingredients ri
     JOIN recipes r ON r.recipe_id = ri.recipe_id
     WHERE r.is_active = 1
       AND (${referenceIds.length > 0 ? 'ri.reference_id IN (?) OR ' : ''}ri.normalized_ingredient_name IN (?))`,
    referenceIds.length > 0 ? [referenceIds, names] : [names]
  );
  const preliminary = rankRecipes(groupByRecipe(matchedLines), items, keysByItem).slice(0, PRELIMINARY_LIMIT);
  if (preliminary.length === 0) {
    return res.json({ status: 'noMatches', source: 'dataset', expiringSoonCount, recipes: [] });
  }

  // Pass 2: every line of the shortlisted recipes, so missing
  // ingredients count too, then the final ranking.
  const recipes = await buildRankedRecipes(preliminary.map((p) => p.recipeId), items, keysByItem, 'dataset');

  res.json({ status: recipes.length > 0 ? 'ready' : 'noMatches', source: 'dataset', expiringSoonCount, recipes });
}));

// GET /households/:householdId/recipe-suggestions/ai?today=YYYY-MM-DD&refresh=true
//
// A few AI recipe ideas (Gemini) for the same inventory, same response
// shape (recipes carry origin: 'ai'). Reuses the household's last ideas
// unless they're stale, an item has started expiring soon that they
// weren't given, none of them still matches the inventory, or the user
// asked for new ones (at most every 30 seconds).
router.get('/households/:householdId/recipe-suggestions/ai', asyncHandler(async (req, res) => {
  await assertMember(req.userId, req.params.householdId);
  const today = todayFrom(req.query);
  const refresh = req.query.refresh === 'true';
  const items = await loadEligibleItems(req.params.householdId, today);
  if (items.length === 0) {
    return res.json({ status: 'noInventory', source: 'ai', generatedAt: null, recipes: [] });
  }
  const keysByItem = await matchKeysForItems(pool, items);

  const [genRows] = await pool.query(
    'SELECT * FROM recipe_ai_generations WHERE team_id = ? ORDER BY created_at DESC, generation_id DESC LIMIT 1',
    [req.params.householdId]
  );
  let generation = genRows[0] || null;
  let recipes = [];
  if (generation) {
    const ids = parseJsonColumn(generation.recipe_ids, []);
    const offered = new Set(parseJsonColumn(generation.input_item_ids, []).map(String));
    const ageMs = Date.now() - dbTimeMs(generation.created_at);
    recipes = await buildRankedRecipes(ids, items, keysByItem, 'ai');
    const newUrgentItem = items.some((i) => i.expiringSoon && !offered.has(i.id));
    const fresh = ageMs < (ids.length === 0 ? AI_REUSE_EMPTY_FOR_MS : AI_REUSE_FOR_MS);
    const reuse = refresh
      ? ageMs < AI_MIN_REFRESH_GAP_MS
      : fresh && !newUrgentItem && (recipes.length > 0 || ids.length === 0);
    if (!reuse) generation = null;
  }

  if (!generation) {
    const raw = await gemini.suggestRecipes(items);
    const clean = sanitiseAiRecipes(raw, items, gemini.AI_RECIPE_LIMIT);
    const conn = await pool.getConnection();
    let ids;
    try {
      await conn.beginTransaction();
      ids = await saveAiRecipes(conn, clean, {
        teamId: req.params.householdId, userId: req.userId, model: gemini.modelName(), inputItemIds: items.map((i) => i.id),
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback().catch(() => {});
      throw err;
    } finally {
      conn.release();
    }
    recipes = await buildRankedRecipes(ids, items, keysByItem, 'ai');
    generation = { created_at: new Date().toISOString().slice(0, 19).replace('T', ' ') };
  }

  res.json({
    status: recipes.length > 0 ? 'ready' : 'noMatches',
    source: 'ai',
    generatedAt: new Date(dbTimeMs(generation.created_at)).toISOString(),
    recipes,
  });
}));

// Rebuilds the response for a session that was already confirmed, so a
// retried request gets the same answer without deducting anything.
async function confirmedSessionResult(sessionId) {
  const [rows] = await pool.query(
    `SELECT rsi.inventory_item_id, rsi.used_quantity, rsi.unit, ii.quantity, ii.status, p.product_name
     FROM recipe_cook_session_items rsi
     JOIN inventory_items ii ON ii.inventory_item_id = rsi.inventory_item_id
     JOIN products p ON p.product_id = ii.product_id
     WHERE rsi.session_id = ? AND rsi.is_selected = 1`,
    [sessionId]
  );
  return rows.map((r) => ({
    inventoryItemId: String(r.inventory_item_id),
    name: r.product_name,
    quantityUsed: Number(r.used_quantity),
    remainingQuantity: r.status === 'IN_STOCK' ? Number(r.quantity) : 0,
    unit: r.unit,
    fullyUsed: r.status !== 'IN_STOCK',
  }));
}

// POST /households/:householdId/recipe-cook-sessions
// { idempotencyKey, recipeId,
//   ingredients: [{ inventoryItemId, ingredientId?, plannedQuantity?, quantityUsed?, selected }] }
//
// User Story 6.3. All-or-nothing: either every selected ingredient is
// deducted and the session is CONFIRMED, or nothing changes.
router.post('/households/:householdId/recipe-cook-sessions', asyncHandler(async (req, res) => {
  const householdId = String(req.params.householdId);
  await assertMember(req.userId, householdId);

  const { idempotencyKey, recipeId, ingredients } = req.body || {};
  if (typeof idempotencyKey !== 'string' || !/^[A-Za-z0-9_-]{8,100}$/.test(idempotencyKey)) {
    throw new ApiError(400, 'idempotencyKey must be 8-100 letters, digits, - or _.');
  }
  if (!/^\d+$/.test(String(recipeId))) throw new ApiError(400, 'Invalid recipe.');
  if (!Array.isArray(ingredients) || ingredients.length === 0 || ingredients.length > 40) {
    throw new ApiError(400, 'ingredients must list 1-40 inventory items.');
  }
  const rows = ingredients.map((ing) => ({
    inventoryItemId: String(ing && ing.inventoryItemId),
    ingredientId: ing && ing.ingredientId !== undefined && ing.ingredientId !== null ? String(ing.ingredientId) : null,
    plannedQuantity: ing && ing.plannedQuantity !== undefined && ing.plannedQuantity !== null ? Number(ing.plannedQuantity) : null,
    quantityUsed: Number(ing && ing.quantityUsed),
    selected: Boolean(ing && ing.selected),
  }));
  if (new Set(rows.map((r) => r.inventoryItemId)).size !== rows.length) {
    throw new ApiError(400, 'Each inventory item can only appear once — combine the amounts.');
  }
  for (const r of rows) {
    if (!/^\d+$/.test(r.inventoryItemId)) throw new ApiError(400, 'Invalid inventory item.');
    if (r.ingredientId !== null && !/^\d+$/.test(r.ingredientId)) throw new ApiError(400, 'Invalid recipe ingredient.');
    if (r.plannedQuantity !== null && !(Number.isFinite(r.plannedQuantity) && r.plannedQuantity >= 0)) r.plannedQuantity = null;
    // AC 6.3.3 — zero/negative rejected here; "more than available" is
    // checked against the locked rows below.
    if (r.selected && !(Number.isFinite(r.quantityUsed) && r.quantityUsed > 0)) {
      throw new ApiError(400, 'Each quantity used must be more than zero.');
    }
  }
  const selected = rows.filter((r) => r.selected);
  // AC 6.3.2 — deselected ingredients are recorded but never deducted.
  if (selected.length === 0) throw new ApiError(400, 'Select at least one ingredient that was used.');

  // AI recipes are stored inactive (kept out of the dataset search) but
  // are just as valid to cook from.
  const [recipeRows] = await pool.query(
    'SELECT recipe_id, title FROM recipes WHERE recipe_id = ? AND (is_active = 1 OR source_name LIKE ?)',
    [recipeId, `${AI_SOURCE_NAME}%`]
  );
  if (recipeRows.length === 0) throw new ApiError(404, 'Recipe not found.');
  const title = recipeRows[0].title;

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // AC 6.3.7 — claim (team, idempotency key) first. A retry, or a
    // double-tap racing the first request, hits the unique key and gets
    // the original result instead of deducting again.
    let sessionId;
    try {
      const [result] = await conn.query(
        `INSERT INTO recipe_cook_sessions (team_id, recipe_id, user_id, idempotency_key, status)
         VALUES (?, ?, ?, ?, 'DRAFT')`,
        [householdId, recipeId, req.userId, idempotencyKey]
      );
      sessionId = result.insertId;
    } catch (err) {
      if (!(err && (err.code === 'ER_DUP_ENTRY' || err.errno === 1062))) throw err;
      await conn.rollback();
      const [existing] = await pool.query(
        'SELECT session_id, recipe_id, status FROM recipe_cook_sessions WHERE team_id = ? AND idempotency_key = ?',
        [householdId, idempotencyKey]
      );
      if (existing.length === 0 || String(existing[0].recipe_id) !== String(recipeId) || existing[0].status !== 'CONFIRMED') {
        throw new ApiError(409, 'This update is already being processed. Please refresh and check your inventory.');
      }
      return res.json({ alreadyRecorded: true, sessionId: String(existing[0].session_id), updated: await confirmedSessionResult(existing[0].session_id) });
    }

    const [itemRows] = await conn.query(
      `SELECT ii.inventory_item_id, ii.team_id, ii.quantity, ii.unit, ii.status, p.product_name
       FROM inventory_items ii
       JOIN products p ON p.product_id = ii.product_id
       WHERE ii.inventory_item_id IN (?)
       FOR UPDATE`,
      [rows.map((r) => r.inventoryItemId)]
    );
    const itemsById = new Map(itemRows.map((r) => [String(r.inventory_item_id), r]));
    for (const r of rows) {
      const item = itemsById.get(r.inventoryItemId);
      if (!item || String(item.team_id) !== householdId) throw new ApiError(404, 'One of the ingredients is no longer in your inventory.');
    }

    const updated = [];
    for (const r of rows) {
      const item = itemsById.get(r.inventoryItemId);
      const unit = item.unit || 'pcs';
      if (!r.selected) {
        await conn.query(
          `INSERT INTO recipe_cook_session_items
             (session_id, inventory_item_id, ingredient_id, planned_quantity, used_quantity, unit, is_selected)
           VALUES (?, ?, ?, ?, 0, ?, 0)`,
          [sessionId, r.inventoryItemId, r.ingredientId, r.plannedQuantity, unit]
        );
        continue;
      }
      if (item.status !== 'IN_STOCK') {
        throw new ApiError(409, `${item.product_name} has already been used up or removed. Refresh and try again.`);
      }
      const available = Number(item.quantity);
      if (r.quantityUsed > available + 1e-9) {
        throw new ApiError(400, `You only have ${available} ${unit} of ${item.product_name}.`);
      }
      const remaining = round3(Math.max(0, available - r.quantityUsed));
      const fullyUsed = remaining <= FULLY_USED_THRESHOLD;
      const used = fullyUsed ? available : r.quantityUsed;

      if (fullyUsed) {
        // AC 6.3.4 — fully used: consumed (quantity left as it was, the
        // same as "Mark fully consumed" — quantity must stay > 0).
        await conn.query(
          "UPDATE inventory_items SET status = 'CONSUMED', checkout_date = NOW(), consumed_amount = 'full' WHERE inventory_item_id = ?",
          [r.inventoryItemId]
        );
        // AC 6.3.6 — reminders for fully consumed items are cancelled.
        await conn.query(
          `UPDATE reminders SET status = 'CANCELLED', cancelled_at = NOW()
           WHERE inventory_item_id = ? AND status IN ('PENDING', 'TRIGGERED')`,
          [r.inventoryItemId]
        );
      } else {
        // AC 6.3.4 — partly used: keep the remainder in stock.
        await conn.query(
          "UPDATE inventory_items SET quantity = ?, consumed_amount = 'partial' WHERE inventory_item_id = ?",
          [remaining, r.inventoryItemId]
        );
      }
      // AC 6.3.6 — consumption record (the audit trail the session points at).
      const [tx] = await conn.query(
        `INSERT INTO inventory_transactions (inventory_item_id, user_id, transaction_type, quantity, note)
         VALUES (?, ?, 'CONSUME', ?, ?)`,
        [r.inventoryItemId, req.userId, used,
          `Used in recipe: ${String(title).slice(0, 100)}${fullyUsed ? '' : ` — ${remaining} ${unit} left`}`]
      );
      await conn.query(
        `INSERT INTO recipe_cook_session_items
           (session_id, inventory_item_id, ingredient_id, planned_quantity, used_quantity, unit, is_selected, transaction_id)
         VALUES (?, ?, ?, ?, ?, ?, 1, ?)`,
        [sessionId, r.inventoryItemId, r.ingredientId, r.plannedQuantity, used, unit, tx.insertId]
      );
      updated.push({
        inventoryItemId: r.inventoryItemId,
        name: item.product_name,
        quantityUsed: used,
        remainingQuantity: fullyUsed ? 0 : remaining,
        unit,
        fullyUsed,
      });
    }

    await conn.query(
      "UPDATE recipe_cook_sessions SET status = 'CONFIRMED', cooked_at = NOW(), confirmed_at = NOW() WHERE session_id = ?",
      [sessionId]
    );
    await conn.commit();
    res.json({ alreadyRecorded: false, sessionId: String(sessionId), updated });
  } catch (err) {
    await conn.rollback().catch(() => {});
    throw err;
  } finally {
    conn.release();
  }
}));

// Clear message instead of a generic 500 if the Iteration 3 tables
// aren't in the database yet.
router.use((err, req, res, next) => {
  if (err && (err.code === 'ER_NO_SUCH_TABLE' || err.errno === 1146)) {
    console.error('Epic 6 table missing:', err.sqlMessage || err.message);
    return next(new ApiError(503, 'Recipe suggestions are not set up yet (database tables missing).'));
  }
  return next(err);
});

module.exports = router;
