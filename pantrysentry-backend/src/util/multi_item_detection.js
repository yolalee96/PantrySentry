// Epic 4 — "Scan several items": one photo of a table or trolley ->
// a list of food items for the user to review. Gemini proposes; this
// module validates everything before it reaches the app. Nothing is
// added to the inventory here — the app shows a review screen first.

const { CATEGORY_DART_NAMES } = require('./enums');
const { normaliseName } = require('./product_reference');

const MAX_ITEMS = 20;
const UNITS = ['pcs', 'pack', 'bottle', 'can', 'box', 'kg', 'g', 'L', 'mL'];
const CONFIDENCE = ['high', 'medium', 'low'];
// The app's 16 categories, by the names stored in product_categories.
const CATEGORY_NAMES = Object.keys(CATEGORY_DART_NAMES);

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    items: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          category: { type: 'STRING', enum: CATEGORY_NAMES },
          count: { type: 'NUMBER' },
          unit: { type: 'STRING', enum: UNITS },
          packaged: { type: 'BOOLEAN' },
          confidence: { type: 'STRING', enum: CONFIDENCE },
          box_2d: { type: 'ARRAY', items: { type: 'INTEGER' } },
        },
        required: ['name', 'category', 'count', 'unit', 'confidence'],
      },
    },
  },
  required: ['items'],
};

const SHAPE_HINT = JSON.stringify({
  items: [{ name: 'string', category: `one of: ${CATEGORY_NAMES.join(' | ')}`, count: 1, unit: UNITS.join(' | '),
    packaged: true, confidence: 'high | medium | low', box_2d: [0, 0, 1000, 1000] }],
});

function buildPrompt() {
  return [
    'You help a household log groceries. Look at this photo of food on a table, counter or in a shopping trolley.',
    `List every distinct FOOD or DRINK item you can see (at most ${MAX_ITEMS}). Ignore non-food things (bags, utensils, cleaning products, toiletries).`,
    'For each item:',
    '- name: what it is, as specific as the photo allows. Read brand and product names on packaging when legible',
    '  (e.g. "Gardenia wholemeal bread", "Dutch Lady full cream milk"); otherwise a plain food name ("banana", "red onion").',
    `- category: exactly one of: ${CATEGORY_NAMES.join(', ')}.`,
    '- count + unit: how many you can see, e.g. 3 pcs (loose items), 2 pack, 1 bottle, 4 can, 1 box. Group identical items',
    '  into one entry with a count. Only use kg/g/L/mL when the size is printed and clearly legible.',
    '- packaged: true if in a package, bottle, can or box.',
    '- confidence: high if clearly visible and identifiable, medium if partly hidden or unsure of the exact type, low if guessing.',
    '- box_2d: [ymin, xmin, ymax, xmax] around the item (or the group), scaled 0-1000.',
    'Do not invent items you cannot see. If there is no food in the photo, return an empty items list.',
  ].join('\n');
}

function cleanBox(box) {
  if (!Array.isArray(box) || box.length !== 4) return null;
  const v = box.map(Number);
  if (v.some((n) => !Number.isFinite(n))) return null;
  const [ymin, xmin, ymax, xmax] = v.map((n) => Math.max(0, Math.min(1000, Math.round(n))));
  if (ymax <= ymin || xmax <= xmin) return null;
  return [ymin, xmin, ymax, xmax];
}

/**
 * Validates Gemini's reply: unknown categories/units are dropped to safe
 * values, empty names removed, duplicates (same name + unit) merged into
 * one count, and the list capped. Returns plain items.
 */
function sanitiseDetections(raw) {
  const list = Array.isArray(raw && raw.items) ? raw.items : [];
  const merged = new Map();
  for (const it of list) {
    if (!it || typeof it !== 'object') continue;
    const name = typeof it.name === 'string' ? it.name.trim().replace(/\s+/g, ' ').slice(0, 100) : '';
    if (!name) continue;
    const unit = UNITS.includes(it.unit) ? it.unit : 'pcs';
    const count = Number(it.count);
    const quantity = Number.isFinite(count) && count > 0 ? Math.min(Math.round(count * 100) / 100, 999) : 1;
    const key = `${normaliseName(name)}|${unit}`;
    const box = cleanBox(it.box_2d);
    if (merged.has(key)) {
      const m = merged.get(key);
      m.quantity = Math.min(m.quantity + quantity, 999);
      if (box) m.boxes.push(box);
      // Keep the less certain rating — a merge shouldn't hide doubt.
      if (CONFIDENCE.indexOf(it.confidence) > CONFIDENCE.indexOf(m.confidence)) m.confidence = it.confidence;
      continue;
    }
    merged.set(key, {
      name,
      quantity,
      unit,
      categoryName: CATEGORY_NAMES.includes(it.category) ? it.category : null,
      packaged: Boolean(it.packaged),
      confidence: CONFIDENCE.includes(it.confidence) ? it.confidence : 'low',
      boxes: box ? [box] : [],
    });
    if (merged.size >= MAX_ITEMS) break;
  }
  return [...merged.values()];
}

/** Recognises JPEG / PNG / WebP from the first bytes (Gemini needs the type). */
function imageMimeType(buffer) {
  if (buffer[0] === 0xff && buffer[1] === 0xd8) return 'image/jpeg';
  if (buffer[0] === 0x89 && buffer[1] === 0x50) return 'image/png';
  if (buffer.slice(0, 4).toString() === 'RIFF' && buffer.slice(8, 12).toString() === 'WEBP') return 'image/webp';
  return null;
}

module.exports = { RESPONSE_SCHEMA, SHAPE_HINT, MAX_ITEMS, buildPrompt, sanitiseDetections, imageMimeType };
