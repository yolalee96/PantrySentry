// Epic 8 — the data team's emission-factor matching rules:
//
//   1. Match the product name against the distinct food_type values
//      (whole words / whole phrases, not raw substrings). If any match,
//      use the HIGHEST factor among them.
//   2. Only if step 1 finds nothing: match against factor_name. Each
//      factor_name ("Peaches - Other Fruit") belongs to a food_type and a
//      factor; if matches span several food types, use the HIGHEST factor.
//   3. (Ours) If neither matches, fall back to the factor of the item's
//      product reference, if it has one — e.g. a product linked through
//      the catalogue under a name that appears in neither field.
//   Otherwise the item is unavailable — never counted as zero.
//
// "Highest factor" is the project's conservative estimation rule: it
// does not confirm the exact identity of the product.
//
// Matching: text is normalised (trimmed, lowercase, repeated spaces
// collapsed), split into words, and simple plurals are folded per word
// ("beans" = "bean", "tomatoes" = "tomato", "berries" = "berry"). A match
// is a whole-phrase match: the food type's / factor name's words appear
// together in the product name ("Chicken eggs grade A" contains "eggs"),
// or the product name is the main food word(s) — the last words — of the
// longer name ("prawns" ends "... prawns"; but "butter" does NOT match
// "Butter beans", which are beans).

function normalise(text) {
  return String(text || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function foldWord(w) {
  if (w.length > 4 && w.endsWith('ies')) return `${w.slice(0, -3)}y`;
  if (w.length > 4 && w.endsWith('oes')) return w.slice(0, -2);
  if (w.length > 4 && /(ches|shes|sses|xes)$/.test(w)) return w.slice(0, -2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
  return w;
}

/** Words of a text, punctuation removed, plurals folded. */
function tokens(text) {
  return normalise(text).split(/[^a-z0-9]+/).filter(Boolean).map(foldWord);
}

/** True if [needle] appears as a contiguous run of words inside [hay]. */
function containsPhrase(hay, needle) {
  if (needle.length === 0 || needle.length > hay.length) return false;
  for (let i = 0; i + needle.length <= hay.length; i++) {
    if (needle.every((w, j) => hay[i + j] === w)) return true;
  }
  return false;
}

/** True if [needle] is the final run of words of [hay] — its main food word(s). */
function endsWithPhrase(hay, needle) {
  if (needle.length === 0 || needle.length > hay.length) return false;
  const offset = hay.length - needle.length;
  return needle.every((w, j) => hay[offset + j] === w);
}

/**
 * [item] = product name words, [target] = food_type / factor_name words.
 *  - The target inside the item: anywhere ("chicken eggs grade a" ~ "eggs").
 *  - The item inside a LONGER target: only as the target's last words, i.e.
 *    the food it names ("butter beans" are beans, so "butter" must not match
 *    it; "coffee milks" are milk, so "coffee" must not match it).
 */
function phraseMatch(item, target) {
  return containsPhrase(item, target) || endsWithPhrase(target, item);
}

/** Food types are short clean labels ("Onions & Leeks"), so the item may
 * match any whole word(s) of them. */
function foodTypeMatch(item, target) {
  return containsPhrase(item, target) || containsPhrase(target, item);
}

/**
 * "Peaches - Other Fruit" -> "Peaches" (the food_type part is step 1's job).
 * The food a name describes comes before "with" / "in": "Cheddar with
 * onions" is cheddar, "White beans in tomato sauce" is white beans.
 */
function factorNameProductPart(factorName) {
  let s = String(factorName || '');
  const i = s.lastIndexOf(' - ');
  if (i > 0) s = s.slice(0, i);
  const cut = s.search(/\s(with|in)\s/i);
  return cut > 0 ? s.slice(0, cut) : s;
}

/** Highest factor wins; ties go to the lowest factor_id so results are stable. */
function pickHighest(rows) {
  return rows.reduce((best, r) => {
    if (!best) return r;
    const d = Number(r.factor_kg_co2e_per_kg) - Number(best.factor_kg_co2e_per_kg);
    if (d > 0) return r;
    if (d === 0 && Number(r.factor_id) < Number(best.factor_id)) return r;
    return best;
  }, null);
}

/**
 * Builds the matcher from the active emission_factors rows valid on a date
 * (rows: factor_id, factor_name, food_type, factor_kg_co2e_per_kg,
 * source_name, source_version, reference_id, valid_from, valid_to).
 */
function buildFactorMatcher(rows) {
  const byFoodType = new Map();
  const nameIndex = [];
  for (const r of rows) {
    if (r.food_type) {
      const key = normalise(r.food_type);
      if (!byFoodType.has(key)) byFoodType.set(key, { tokens: tokens(r.food_type), rows: [] });
      byFoodType.get(key).rows.push(r);
    }
    nameIndex.push({ tokens: tokens(factorNameProductPart(r.factor_name)), row: r });
  }

  /** Returns { row, method } or null. */
  return function match(productName) {
    const item = tokens(productName);
    if (item.length === 0) return null;

    // Step 1 — food_type.
    const typeHits = [...byFoodType.values()].filter((t) => foodTypeMatch(item, t.tokens)).flatMap((t) => t.rows);
    if (typeHits.length > 0) return { row: pickHighest(typeHits), method: 'food_type' };

    // Step 2 — factor_name.
    const nameHits = nameIndex.filter((n) => phraseMatch(item, n.tokens)).map((n) => n.row);
    if (nameHits.length > 0) return { row: pickHighest(nameHits), method: 'factor_name' };
    return null;
  };
}

module.exports = { buildFactorMatcher, tokens, phraseMatch, factorNameProductPart };
