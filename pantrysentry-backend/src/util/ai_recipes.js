// Epic 6 — turns Gemini's proposed recipes into normal rows in the data
// team's recipes / recipe_ingredients tables, so they can be shown,
// matched, ranked and recorded (recipe_cook_sessions has a foreign key to
// recipes) exactly like dataset recipes.
//
// AI recipes are saved with is_active = FALSE and source_name =
// AI_SOURCE_NAME: inactive keeps them out of the dataset search (and away
// from other households), while the cook-session foreign key still works.
// recipe_ai_generations (migrations/epic6_ai_recipe_generations.sql)
// remembers which recipes were generated for which household, so Gemini
// is only called again when it's worth it.

const { normaliseName } = require('./product_reference');

const AI_SOURCE_NAME = 'Gemini (AI-generated)';

function cleanString(v, max) {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}

/**
 * Drops anything malformed rather than trusting it:
 *  - an inventoryItemId that wasn't offered becomes "not in inventory", so
 *    a made-up ingredient can never show up as something the user has;
 *  - a recipe with no title, no steps, or no ingredient from the inventory
 *    is dropped (it isn't "matched to your inventory").
 */
function sanitiseAiRecipes(raw, items, limit) {
  const byId = new Map(items.map((i) => [i.id, i]));
  const out = [];
  for (const r of Array.isArray(raw) ? raw : []) {
    if (!r || typeof r !== 'object') continue;
    const title = cleanString(r.title, 255);
    const steps = (Array.isArray(r.steps) ? r.steps : []).map((s) => cleanString(s, 1000)).filter(Boolean).slice(0, 25);
    const ingredients = (Array.isArray(r.ingredients) ? r.ingredients : []).slice(0, 25).map((ing) => {
      const q = Number(ing && ing.quantity);
      const id = ing && ing.inventoryItemId !== null && ing.inventoryItemId !== undefined ? String(ing.inventoryItemId) : null;
      return {
        name: cleanString(ing && ing.name, 255),
        quantity: ing && ing.quantity !== null && Number.isFinite(q) && q > 0 ? Math.round(q * 1000) / 1000 : null,
        unit: cleanString(ing && ing.unit, 20) || null,
        item: id && byId.has(id) ? byId.get(id) : null,
      };
    }).filter((i) => i.name);
    if (!title || steps.length === 0 || !ingredients.some((i) => i.item)) continue;
    const servings = Number(r.servings);
    const minutes = Number(r.prepMinutes);
    out.push({
      title,
      description: cleanString(r.description, 1000) || null,
      servings: Number.isFinite(servings) && servings > 0 && servings <= 50 ? Math.round(servings) : 1,
      totalMinutes: Number.isFinite(minutes) && minutes > 0 && minutes <= 1440 ? Math.round(minutes) : null,
      steps,
      ingredients,
    });
    if (out.length >= limit) break;
  }
  return out;
}

/**
 * Saves sanitised recipes in one transaction and returns their recipe_ids.
 * An ingredient Gemini linked to an inventory item gets that item's name
 * as its normalized_ingredient_name — the matcher then links it to the
 * same item, the same way dataset ingredients are matched by name.
 */
async function saveAiRecipes(conn, recipes, { teamId, userId, model, inputItemIds }) {
  const ids = [];
  for (const recipe of recipes) {
    const [result] = await conn.query(
      `INSERT INTO recipes (title, description, servings, total_time_minutes, instructions_json, source_name, is_active)
       VALUES (?, ?, ?, ?, ?, ?, 0)`,
      [recipe.title, recipe.description, recipe.servings, recipe.totalMinutes, JSON.stringify(recipe.steps), `${AI_SOURCE_NAME} — ${model}`.slice(0, 255)]
    );
    const recipeId = result.insertId;
    ids.push(recipeId);
    let order = 1;
    for (const ing of recipe.ingredients) {
      await conn.query(
        `INSERT INTO recipe_ingredients
           (recipe_id, ingredient_name, normalized_ingredient_name, quantity, unit, sort_order, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [recipeId, ing.name, normaliseName(ing.item ? ing.item.name : ing.name), ing.quantity, ing.unit, order++,
          ing.item ? `AI-linked to inventory item ${ing.item.id}` : null]
      );
    }
  }
  await conn.query(
    `INSERT INTO recipe_ai_generations (team_id, model, input_item_ids, recipe_ids, created_by)
     VALUES (?, ?, ?, ?, ?)`,
    [teamId, model.slice(0, 100), JSON.stringify(inputItemIds), JSON.stringify(ids), userId]
  );
  return ids;
}

module.exports = { AI_SOURCE_NAME, sanitiseAiRecipes, saveAiRecipes };
