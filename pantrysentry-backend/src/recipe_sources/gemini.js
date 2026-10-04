// Epic 6 — AI recipe ideas from Gemini (Google AI Studio free tier),
// shown alongside the recipe dataset's suggestions. This file only
// proposes recipes; util/ai_recipes.js validates them against the real
// inventory and saves them into the recipes tables, after which they are
// matched, ranked and recorded exactly like dataset recipes.
//
//   suggestRecipes(items) -> Promise<Array<{
//     title, description, servings, prepMinutes,
//     ingredients: [{ name, quantity, unit, inventoryItemId }],
//     steps: [string]
//   }>>
//
// Config (Vercel environment variables):
//   GEMINI_API_KEY  required — from Google AI Studio. Never sent to the app.
//   GEMINI_MODEL    optional — defaults to the gemini-flash-latest alias,
//                   which tracks the current Flash model (Gemini 2.5 is
//                   being shut down on 16 Oct 2026, so don't pin it).

const { ApiError } = require('../util/errors');

const DEFAULT_MODEL = 'gemini-flash-latest';
// Two attempts must fit inside the Vercel function time limit together.
const ATTEMPT_TIMEOUT_MS = 25000;
const RETRY_DELAY_MS = 1500;

// The JSON shape spelled out for the schema-less retry.
const SHAPE_EXAMPLE = JSON.stringify({
  recipes: [{
    title: 'string', description: 'string', servings: 2, prepMinutes: 20,
    ingredients: [{ name: 'string', quantity: 1.5, unit: 'string', inventoryItemId: 'id from the inventory, or null' }],
    steps: ['string'],
  }],
});
const AI_RECIPE_LIMIT = 3; // a few ideas next to the dataset's recipes, not a replacement

// Constrains the reply to valid JSON of exactly this shape (Gemini's
// structured output), so we never have to scrape recipes out of prose.
function modelName() {
  return process.env.GEMINI_MODEL || DEFAULT_MODEL;
}

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    recipes: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          title: { type: 'STRING' },
          description: { type: 'STRING' },
          servings: { type: 'INTEGER' },
          prepMinutes: { type: 'INTEGER' },
          ingredients: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                name: { type: 'STRING' },
                quantity: { type: 'NUMBER', nullable: true },
                unit: { type: 'STRING' },
                inventoryItemId: { type: 'STRING', nullable: true },
              },
              required: ['name', 'unit'],
            },
          },
          steps: { type: 'ARRAY', items: { type: 'STRING' } },
        },
        required: ['title', 'servings', 'ingredients', 'steps'],
      },
    },
  },
  required: ['recipes'],
};

function buildPrompt(items) {
  const inventory = items.map((i) => ({
    id: i.id,
    name: i.name,
    category: i.category,
    quantity: i.quantity,
    unit: i.unit,
    daysUntilExpiry: i.daysLeft, // null = no expiry date recorded
  }));
  return [
    'You suggest home-cooking recipes that use up food a household already has, to reduce food waste.',
    '',
    `Suggest up to ${AI_RECIPE_LIMIT} different, realistic recipes using the household inventory below.`,
    'Rules:',
    '- Prioritise items with the smallest daysUntilExpiry (0-3 days is urgent). Try to use every urgent item in at least one recipe.',
    '- Every recipe must use at least one inventory item.',
    '- For each ingredient that comes from the inventory, set inventoryItemId to that item\'s exact id. Never invent ids.',
    '- For ingredients the household does not have (including basic staples like salt, oil or water), set inventoryItemId to null.',
    '- Keep missing ingredients to a minimum.',
    '- Give each ingredient a numeric quantity and a unit. For inventory items, use the same unit as the inventory where sensible',
    '  (g, kg, mL, L, pcs, pack, ...), and do not use more than the quantity available. Use null quantity only for "to taste" amounts.',
    '- Steps must be clear, safe, and in order. Cook meat, poultry, seafood and eggs thoroughly.',
    '- servings is the number of people the recipe serves; prepMinutes is total preparation and cooking time.',
    '- If no sensible recipe can be made, return an empty recipes list. Do not force odd combinations.',
    '',
    'Household inventory (JSON):',
    JSON.stringify(inventory),
  ].join('\n');
}

/**
 * One call to Gemini. With [strictSchema] the reply is constrained to
 * RESPONSE_SCHEMA; without it, Gemini is only asked for JSON and the
 * shape comes from the prompt (the reply is validated by
 * util/ai_recipes.js either way).
 * Returns { ok: true, recipes } or { ok: false, status, body }.
 */
async function callGemini(apiKey, model, items, strictSchema) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const generationConfig = { responseMimeType: 'application/json', temperature: 0.7 };
  if (strictSchema) generationConfig.responseSchema = RESPONSE_SCHEMA;
  const prompt = strictSchema
    ? buildPrompt(items)
    : `${buildPrompt(items)}\n\nReply with JSON only, in exactly this shape:\n${SHAPE_EXAMPLE}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS);
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }], generationConfig }),
      signal: controller.signal,
    });
  } catch (err) {
    throw new ApiError(502, err.name === 'AbortError'
      ? 'The recipe service took too long to respond. Please try again.'
      : 'Could not reach the recipe service. Please try again.');
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    return { ok: false, status: response.status, body: await response.text().catch(() => '') };
  }
  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
  try {
    // Tolerate a ```json fence in the schema-less reply.
    const parsed = JSON.parse(text.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ''));
    return { ok: true, recipes: Array.isArray(parsed?.recipes) ? parsed.recipes : [] };
  } catch {
    console.error('Gemini returned non-JSON output', text.slice(0, 500));
    throw new ApiError(502, 'The recipe service returned an unexpected response. Please try again.');
  }
}

/** Turns a failed Gemini reply into a clear, safe message for the app. */
function errorFor(status, body, model) {
  let message = '';
  try {
    message = String(JSON.parse(body)?.error?.message || '');
  } catch {
    message = '';
  }
  if (status === 429) {
    return new ApiError(503, 'AI recipe ideas are busy right now (free-tier limit reached). Please try again later.');
  }
  if (status === 400 && /api key/i.test(message)) {
    return new ApiError(503, 'AI recipe ideas aren\'t set up correctly: the Gemini API key was rejected.');
  }
  if (status === 401 || status === 403) {
    return new ApiError(503, 'AI recipe ideas aren\'t set up correctly: the API key isn\'t allowed to use Gemini.');
  }
  if (status === 404) {
    return new ApiError(503, `AI recipe ideas aren't set up correctly: the Gemini model "${model}" isn't available. Set GEMINI_MODEL to a current model.`);
  }
  if (status >= 500) {
    return new ApiError(502, 'Gemini is having problems right now. Please try again later.');
  }
  return new ApiError(502, `The recipe service returned an error (${status}). Please try again.`);
}

async function suggestRecipes(items) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new ApiError(503, 'AI recipe ideas are not set up yet (missing GEMINI_API_KEY).');
  }
  const model = modelName();

  // Attempt 1: strict JSON schema.
  let result = await callGemini(apiKey, model, items, true);
  if (result.ok) return result.recipes;
  console.error('Gemini error', result.status, result.body);

  // A 5xx is either a busy model (a retry a moment later usually works) or
  // Gemini failing on the strict schema itself (it then fails every time).
  // One retry, after a short pause, without the strict schema covers both.
  if (result.status >= 500) {
    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    result = await callGemini(apiKey, model, items, false);
    if (result.ok) return result.recipes;
    console.error('Gemini error (retry without schema)', result.status, result.body);
  }
  throw errorFor(result.status, result.body, model);
}

module.exports = { suggestRecipes, modelName, AI_RECIPE_LIMIT, _buildPrompt: buildPrompt };
