// Epic 6 — matching household inventory to the recipe dataset
// (recipes / recipe_ingredients, Food.com + RecipeNLG, prepared by the
// data team). Pure functions here; the SQL lives in routes/recipes.js.

const { normaliseUnit } = require('./weight');
const { foldPlural } = require('./product_reference');

const EXPIRING_SOON_DAYS = 3; // AC 6.1.2 — "within the next three days"
const RESULT_LIMIT = 20;
const EPSILON = 1e-9;

// Basic staples almost every kitchen has. They are still listed as
// "not in inventory" (we never claim the user has them), but they don't
// count against a recipe when ranking, and a recipe that only matches a
// staple isn't suggested.
const STAPLES = new Set(['salt', 'water', 'pepper', 'black pepper', 'sugar', 'ice', 'ice cube', 'cold water', 'hot water', 'boiling water', 'warm water']);

// Mass and volume units seen in the recipe data. Cup/tbsp/tsp use the
// data team's assumed cooking conventions (quantity_conversions rows
// 1000003-1000005: cup = 240 mL, tbsp = 15 mL, tsp = 5 mL).
const MASS_TO_G = { kg: 1000, g: 1, mg: 0.001, oz: 28.349523125, lb: 453.59237 };
const VOLUME_TO_ML = { l: 1000, ml: 1, cup: 240, tbsp: 15, tsp: 5 };

/** Whole days from [today] to [dateStr], both 'YYYY-MM-DD'. */
function daysBetween(today, dateStr) {
  const a = Date.parse(`${today}T00:00:00Z`);
  const b = Date.parse(`${String(dateStr).slice(0, 10)}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

/**
 * AC 6.1.4 / 6.1.5 — the inventory a recipe may use: in stock, some
 * quantity left, and not past its expiry date. Items with no expiry date
 * are eligible but never "expiring soon".
 */
function eligibleItems(rows, today) {
  return rows
    .filter((r) => r.status === 'IN_STOCK' && Number(r.quantity) > 0)
    .map((r) => {
      const daysLeft = r.expiry_date ? daysBetween(today, r.expiry_date) : null;
      return {
        id: String(r.inventory_item_id),
        productId: String(r.product_id),
        name: r.product_name,
        quantity: Number(r.quantity),
        unit: r.unit || 'pcs',
        expiryDate: r.expiry_date ? String(r.expiry_date).slice(0, 10) : null,
        daysLeft,
      };
    })
    .filter((i) => i.daysLeft === null || i.daysLeft >= 0)
    .map((i) => ({ ...i, expiringSoon: i.daysLeft !== null && i.daysLeft <= EXPIRING_SOON_DAYS }));
}

function isStaple(normalisedName) {
  return STAPLES.has(foldPlural(normalisedName)) || STAPLES.has(normalisedName);
}

/**
 * Which eligible item (if any) a recipe ingredient line uses. A line
 * matches when its reference_id is one of the item's references, or its
 * plural-folded name equals one of the item's names. If several items
 * match (e.g. two packs of eggs), the one expiring soonest is used —
 * that's the one the household should use first.
 */
function matchIngredient(line, items, keysByItem) {
  const folded = foldPlural(line.normalized_ingredient_name || line.ingredient_name);
  const ref = line.reference_id === null || line.reference_id === undefined ? null : Number(line.reference_id);
  let best = null;
  for (const item of items) {
    const keys = keysByItem.get(item.id);
    if (!keys) continue;
    if ((ref !== null && keys.referenceIds.has(ref)) || keys.foldedNames.has(folded)) {
      const d = item.daysLeft === null ? Infinity : item.daysLeft;
      const bestD = best ? (best.daysLeft === null ? Infinity : best.daysLeft) : Infinity;
      if (!best || d < bestD) best = item;
    }
  }
  return best;
}

/** Expresses a quantity in a comparable base: grams, millilitres, or a
 * count of one specific unit (pcs, can, clove, ...). null if unusable. */
function toBase(quantity, unit) {
  const q = Number(quantity);
  if (quantity === null || quantity === undefined || !Number.isFinite(q) || q <= 0) return null;
  const u = normaliseUnit(unit);
  if (MASS_TO_G[u] !== undefined) return { dimension: 'mass', value: q * MASS_TO_G[u] };
  if (VOLUME_TO_ML[u] !== undefined) return { dimension: 'volume', value: q * VOLUME_TO_ML[u] };
  if (u === 'dozen') return { dimension: 'count:pcs', value: q * 12 };
  return { dimension: `count:${u}`, value: q };
}

function fromBase(base, unit) {
  const target = toBase(1, unit);
  if (!target || target.dimension !== base.dimension) return null;
  return base.value / target.value;
}

function round3(n) {
  return Math.round(n * 1000) / 1000;
}

/**
 * AC 6.2.2–6.2.4 — compares one ingredient line with the matched item.
 *   'missing'       — not in the household inventory
 *   'enough'        — comparable units, enough on hand
 *   'notEnough'     — comparable units, not enough on hand
 *   'checkQuantity' — can't compare reliably (no recipe quantity, or units
 *                     that don't convert, e.g. "2 cup" vs "300 g")
 * suggestedUseQuantity pre-fills "Update ingredients used", in the ITEM's
 * unit and capped at what's there, or null when it can't be worked out.
 */
function availabilityFor(line, item) {
  if (!item) return { status: 'missing', suggestedUseQuantity: null };
  const need = toBase(line.quantity, line.unit);
  const have = toBase(item.quantity, item.unit);
  if (!need || !have || need.dimension !== have.dimension) {
    return { status: 'checkQuantity', suggestedUseQuantity: null };
  }
  const neededInItemUnit = fromBase(need, item.unit);
  return {
    status: have.value + EPSILON >= need.value ? 'enough' : 'notEnough',
    suggestedUseQuantity: neededInItemUnit === null ? null : round3(Math.min(neededInItemUnit, item.quantity)),
  };
}

/**
 * Scores every candidate recipe from its ingredient lines.
 * [linesByRecipe]: Map(recipeId -> all ingredient rows of that recipe)
 * Returns ranked summaries (best first), recipes with no real match dropped.
 *
 * Ranking (AC 6.1.2, done here rather than trusting any source):
 *   1. uses at least one item expiring within 3 days
 *   2. more of those expiring items
 *   3. the soonest expiry among them
 *   4. higher share of (non-staple, non-optional) ingredients in stock
 *   5. more ingredients in stock
 */
function rankRecipes(linesByRecipe, items, keysByItem) {
  const scored = [];
  for (const [recipeId, lines] of linesByRecipe) {
    const counted = lines.filter((l) => !Number(l.is_optional));
    let matchedRequired = 0;
    let matchedNonStaple = 0;
    let missingNonStaple = 0;
    const expiring = new Map();
    for (const line of counted) {
      const staple = isStaple(line.normalized_ingredient_name || line.ingredient_name);
      const item = matchIngredient(line, items, keysByItem);
      if (item) {
        matchedRequired += 1;
        if (!staple) matchedNonStaple += 1;
        if (item.expiringSoon) expiring.set(item.id, item);
      } else if (!staple) {
        missingNonStaple += 1;
      }
    }
    if (matchedNonStaple === 0) continue;
    const soonest = expiring.size > 0 ? Math.min(...[...expiring.values()].map((i) => i.daysLeft)) : Infinity;
    scored.push({
      recipeId,
      expiringCount: expiring.size,
      soonest,
      coverage: matchedNonStaple / (matchedNonStaple + missingNonStaple),
      matchedRequired,
      missingNonStaple,
    });
  }
  scored.sort((a, b) =>
    (b.expiringCount > 0) - (a.expiringCount > 0) ||
    b.expiringCount - a.expiringCount ||
    a.soonest - b.soonest ||
    b.coverage - a.coverage ||
    b.matchedRequired - a.matchedRequired ||
    a.missingNonStaple - b.missingNonStaple ||
    Number(a.recipeId) - Number(b.recipeId));
  return scored;
}

/** Recipe row + its ingredient lines -> API shape, with live availability. */
function buildRecipe(recipe, lines, items, keysByItem) {
  const ingredients = [...lines]
    .sort((a, b) => Number(a.sort_order) - Number(b.sort_order))
    .map((line) => {
      const item = matchIngredient(line, items, keysByItem);
      const availability = availabilityFor(line, item);
      return {
        ingredientId: String(line.ingredient_id),
        name: line.ingredient_name,
        quantity: line.quantity === null ? null : Number(line.quantity),
        unit: line.unit || '',
        notes: line.notes || null,
        isOptional: Boolean(Number(line.is_optional)),
        isStaple: isStaple(line.normalized_ingredient_name || line.ingredient_name),
        status: availability.status,
        suggestedUseQuantity: availability.suggestedUseQuantity,
        inventoryItem: item
          ? { id: item.id, name: item.name, quantity: item.quantity, unit: item.unit, expiryDate: item.expiryDate, daysLeft: item.daysLeft }
          : null,
      };
    });

  // AC 6.1.3 — the matched items expiring soon, with their dates.
  const seen = new Set();
  const expiringMatches = [];
  for (const ing of ingredients) {
    const item = ing.inventoryItem && items.find((i) => i.id === ing.inventoryItem.id);
    if (item && item.expiringSoon && !seen.has(item.id)) {
      seen.add(item.id);
      expiringMatches.push({ inventoryItemId: item.id, name: item.name, expiryDate: item.expiryDate, daysLeft: item.daysLeft });
    }
  }
  expiringMatches.sort((a, b) => a.daysLeft - b.daysLeft);

  let steps = [];
  try {
    const parsed = typeof recipe.instructions_json === 'string' ? JSON.parse(recipe.instructions_json) : recipe.instructions_json;
    if (Array.isArray(parsed)) steps = parsed.map((s) => String(s).trim()).filter(Boolean);
  } catch {
    steps = [];
  }

  const required = ingredients.filter((i) => !i.isOptional);
  return {
    id: String(recipe.recipe_id),
    title: recipe.title,
    description: recipe.description || '',
    servings: recipe.servings === null ? null : Number(recipe.servings),
    servingUnit: recipe.serving_unit || null,
    prepMinutes: recipe.prep_time_minutes === null ? null : Number(recipe.prep_time_minutes),
    cookMinutes: recipe.cook_time_minutes === null ? null : Number(recipe.cook_time_minutes),
    totalMinutes: recipe.total_time_minutes === null ? null : Number(recipe.total_time_minutes),
    difficulty: recipe.difficulty || null,
    cuisine: recipe.cuisine || null,
    imageUrl: recipe.image_url || null,
    sourceName: recipe.source_name || null,
    sourceUrl: recipe.source_url || null,
    steps,
    ingredients,
    expiringMatches,
    usesExpiringSoon: expiringMatches.length > 0,
    matchedCount: required.filter((i) => i.inventoryItem).length,
    missingCount: required.filter((i) => !i.inventoryItem).length,
  };
}

module.exports = {
  EXPIRING_SOON_DAYS,
  RESULT_LIMIT,
  eligibleItems,
  availabilityFor,
  matchIngredient,
  rankRecipes,
  buildRecipe,
  isStaple,
  daysBetween,
  round3,
};
