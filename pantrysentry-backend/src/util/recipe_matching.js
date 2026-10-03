// Epic 6 — everything about recipe suggestions that does NOT depend on
// where the recipes come from. The recipe source (Gemini now, the recipe
// dataset later) only proposes recipes; this module decides what counts
// as available, validates the proposal against the real inventory,
// ranks, and works out ingredient availability. Pure functions, so they
// can be tested without a database or an LLM.

const { normaliseUnit } = require('./weight');

const EXPIRING_SOON_DAYS = 3; // AC 6.1.2 — "within the next three days"
const MAX_RECIPES = 8;
const EPSILON = 1e-9;

const MASS_TO_G = { kg: 1000, g: 1, mg: 0.001 };
const VOLUME_TO_ML = { l: 1000, ml: 1 };

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
 *
 * rows: { inventory_item_id, product_name, category, quantity, unit,
 *         expiry_date, status }
 */
function eligibleItems(rows, today) {
  return rows
    .filter((r) => r.status === 'IN_STOCK' && Number(r.quantity) > 0)
    .map((r) => {
      const daysLeft = r.expiry_date ? daysBetween(today, r.expiry_date) : null;
      return {
        id: String(r.inventory_item_id),
        name: r.product_name,
        category: r.category,
        quantity: Number(r.quantity),
        unit: r.unit || 'pcs',
        expiryDate: r.expiry_date ? String(r.expiry_date).slice(0, 10) : null,
        daysLeft,
      };
    })
    .filter((i) => i.daysLeft === null || i.daysLeft >= 0)
    .map((i) => ({ ...i, expiringSoon: i.daysLeft !== null && i.daysLeft <= EXPIRING_SOON_DAYS }));
}

/** Expresses a quantity in a comparable base: grams, millilitres, or a
 * count of one specific unit (pcs, pack, ...). null if not a number. */
function toBase(quantity, unit) {
  const q = Number(quantity);
  if (quantity === null || quantity === undefined || !Number.isFinite(q) || q < 0) return null;
  const u = normaliseUnit(unit);
  if (MASS_TO_G[u] !== undefined) return { dimension: 'mass', value: q * MASS_TO_G[u] };
  if (VOLUME_TO_ML[u] !== undefined) return { dimension: 'volume', value: q * VOLUME_TO_ML[u] };
  if (u === 'dozen') return { dimension: 'count:pcs', value: q * 12 };
  return { dimension: `count:${u}`, value: q };
}

/** Converts a base value back into [unit], or null if incompatible. */
function fromBase(base, unit) {
  const target = toBase(1, unit);
  if (!target || target.dimension !== base.dimension) return null;
  return base.value / target.value;
}

function round3(n) {
  return Math.round(n * 1000) / 1000;
}

/**
 * AC 6.2.2–6.2.4 — compares one recipe ingredient with the matched
 * inventory item.
 *   'missing'       — not in the household inventory
 *   'enough'        — comparable units, enough on hand
 *   'notEnough'     — comparable units, not enough on hand
 *   'checkQuantity' — can't compare reliably (no recipe quantity, or
 *                     units that don't convert, e.g. "2 pcs" vs "300 g")
 * Also returns how much of the item to pre-fill in the "Update
 * ingredients used" review (in the ITEM's unit, capped at what's there),
 * or null when it can't be worked out — the user then enters it.
 */
function availabilityFor(ingredient, item) {
  if (!item) return { status: 'missing', suggestedUseQuantity: null };
  const need = toBase(ingredient.quantity, ingredient.unit);
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

function cleanString(v, max) {
  if (typeof v !== 'string') return '';
  return v.trim().slice(0, max);
}

/**
 * Validates whatever the recipe source returned against the real
 * inventory. Anything malformed is dropped rather than trusted:
 *  - an inventoryItemId that wasn't offered becomes "not matched", so a
 *    made-up ingredient can never show up as something you have;
 *  - a recipe with no title, no steps, or no ingredient matched to the
 *    inventory is dropped (it isn't "matched to your inventory").
 * Returns plain recipe objects (no availability yet — see buildResponse,
 * which recomputes that against the CURRENT inventory every time).
 */
function sanitiseRecipes(raw, offeredIds) {
  const list = Array.isArray(raw) ? raw : [];
  const out = [];
  for (const r of list) {
    if (!r || typeof r !== 'object') continue;
    const title = cleanString(r.title, 120);
    const steps = (Array.isArray(r.steps) ? r.steps : []).map((s) => cleanString(s, 600)).filter(Boolean).slice(0, 20);
    const ingredients = (Array.isArray(r.ingredients) ? r.ingredients : [])
      .slice(0, 25)
      .map((ing) => {
        const name = cleanString(ing && ing.name, 80);
        const q = Number(ing && ing.quantity);
        const id = ing && ing.inventoryItemId !== null && ing.inventoryItemId !== undefined ? String(ing.inventoryItemId) : null;
        return {
          name,
          quantity: ing && ing.quantity !== null && Number.isFinite(q) && q > 0 ? round3(q) : null,
          unit: cleanString(ing && ing.unit, 20),
          inventoryItemId: id && offeredIds.has(id) ? id : null,
        };
      })
      .filter((ing) => ing.name);
    if (!title || steps.length === 0 || !ingredients.some((i) => i.inventoryItemId)) continue;
    const servings = Number(r.servings);
    const prepMinutes = Number(r.prepMinutes);
    out.push({
      title,
      description: cleanString(r.description, 300),
      servings: Number.isInteger(servings) && servings > 0 && servings <= 50 ? servings : null,
      prepMinutes: Number.isFinite(prepMinutes) && prepMinutes > 0 && prepMinutes <= 1440 ? Math.round(prepMinutes) : null,
      ingredients,
      steps,
    });
    if (out.length >= MAX_RECIPES) break;
  }
  return out;
}

/**
 * Attaches live availability to stored recipes and ranks them.
 * [recipes] come from the cache (sanitised when generated); [items] is
 * the CURRENT eligible inventory, so an item used up or expired since
 * the recipes were generated is treated as missing — never as available
 * (AC 6.1.4 / 6.1.5). Recipes left with nothing matched are dropped.
 *
 * Ranking (AC 6.1.2) is done here, not by the recipe source: recipes
 * using an item that expires within 3 days come first; then more such
 * items, the soonest expiry, more matched items, fewer missing.
 */
function buildRecipes(recipes, items, setId) {
  const byId = new Map(items.map((i) => [i.id, i]));
  const built = [];
  recipes.forEach((recipe, index) => {
    const ingredients = recipe.ingredients.map((ing) => {
      const item = ing.inventoryItemId ? byId.get(ing.inventoryItemId) : null;
      const availability = availabilityFor(ing, item);
      return {
        name: ing.name,
        quantity: ing.quantity,
        unit: ing.unit,
        inventoryItemId: item ? item.id : null,
        status: availability.status,
        suggestedUseQuantity: availability.suggestedUseQuantity,
        inventoryItem: item
          ? { id: item.id, name: item.name, quantity: item.quantity, unit: item.unit, expiryDate: item.expiryDate, daysLeft: item.daysLeft }
          : null,
      };
    });
    const matched = ingredients.filter((i) => i.inventoryItem);
    if (matched.length === 0) return;

    // AC 6.1.3 — which matched items are expiring soon, with their dates.
    const expiringMatches = [];
    const seen = new Set();
    for (const ing of matched) {
      const item = byId.get(ing.inventoryItemId);
      if (item.expiringSoon && !seen.has(item.id)) {
        seen.add(item.id);
        expiringMatches.push({ inventoryItemId: item.id, name: item.name, expiryDate: item.expiryDate, daysLeft: item.daysLeft });
      }
    }
    expiringMatches.sort((a, b) => a.daysLeft - b.daysLeft);

    built.push({
      id: `${setId}-${index}`,
      title: recipe.title,
      description: recipe.description,
      servings: recipe.servings,
      prepMinutes: recipe.prepMinutes,
      steps: recipe.steps,
      ingredients,
      expiringMatches,
      usesExpiringSoon: expiringMatches.length > 0,
      matchedCount: matched.length,
      missingCount: ingredients.length - matched.length,
    });
  });

  built.sort((a, b) => {
    if (a.usesExpiringSoon !== b.usesExpiringSoon) return a.usesExpiringSoon ? -1 : 1;
    if (a.expiringMatches.length !== b.expiringMatches.length) return b.expiringMatches.length - a.expiringMatches.length;
    const soonestA = a.expiringMatches.length ? a.expiringMatches[0].daysLeft : Infinity;
    const soonestB = b.expiringMatches.length ? b.expiringMatches[0].daysLeft : Infinity;
    if (soonestA !== soonestB) return soonestA - soonestB;
    if (a.matchedCount !== b.matchedCount) return b.matchedCount - a.matchedCount;
    return a.missingCount - b.missingCount;
  });
  return built;
}

module.exports = {
  EXPIRING_SOON_DAYS,
  MAX_RECIPES,
  eligibleItems,
  availabilityFor,
  sanitiseRecipes,
  buildRecipes,
  daysBetween,
  round3,
};
