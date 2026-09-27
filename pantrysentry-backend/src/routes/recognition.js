const express = require('express');
const pool = require('../db');
const { ApiError, asyncHandler } = require('../util/errors');
const { CATEGORY_DART_NAMES } = require('../util/enums');
const vision = require('@google-cloud/vision');

const router = express.Router();

// ==================== Config ====================
// Set these in .env (local) AND the Vercel dashboard (deployed), same as
// every other env var this backend uses.
const OFF_USER_AGENT = process.env.OFF_USER_AGENT || 'PantryBuddy/Iteration2 (team-contact-placeholder)';

// ==================== Google Cloud Vision client ====================
// Per DEPLOY_GOOGLE_VISION.md: credentials stay server-side, LABEL_DETECTION
// only, never called directly from the browser. Deliberately NOT using the
// GOOGLE_APPLICATION_CREDENTIALS-file pattern from that doc, since Vercel's
// serverless functions have no persistent private disk to keep a key file
// on (that pattern is written for a VM). Instead, the service account JSON
// key's full contents are stored as one base64-encoded env var — the
// standard approach for GCP auth on serverless — and decoded at startup.
//
// Set GOOGLE_VISION_CREDENTIALS_B64 to: base64 of the whole downloaded
// service-account JSON key file. On the machine that has the key file:
//   base64 -i pantrybuddy-vision.json | tr -d '\n'
// then paste that single long string as the env var value in Vercel.
let visionClient = null;
function getVisionClient() {
  if (visionClient) return visionClient;
  const b64 = process.env.GOOGLE_VISION_CREDENTIALS_B64;
  if (!b64) return null;
  const credentials = JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
  visionClient = new vision.ImageAnnotatorClient({ credentials });
  return visionClient;
}

// ==================== Shared: keyword-mapping lookup ====================
// Verified against the real schema.sql — product_keyword_mapping,
// product_reference and product_categories column names below are exact.
//
// Ranks exact full-name matches above shorter phrase matches, per the
// README's acceptance checks. Returns candidates for user confirmation —
// never auto-assigns anything.
async function resolveByKeywords(keywords, matchType) {
  if (!keywords || keywords.length === 0) return [];
  const normalized = keywords
    .map((k) => k.trim().toLowerCase())
    .filter((k) => k.length > 0);
  if (normalized.length === 0) return [];

  const placeholders = normalized.map(() => '?').join(',');
  const [rows] = await pool.query(
    `SELECT
        pkm.normalized_keyword,
        pkm.keyword,
        pkm.source_name,
        pkm.source_url,
        pr.reference_id,
        pr.product_id,
        pr.product_name,
        pr.category_id,
        pc.category_name
      FROM product_keyword_mapping pkm
      JOIN product_reference pr ON pr.reference_id = pkm.reference_id
      JOIN product_categories pc ON pc.category_id = pr.category_id
      WHERE pkm.match_type = ?
        AND pkm.is_active = 1
        AND pkm.normalized_keyword IN (${placeholders})`,
    [matchType, ...normalized]
  );

  // Exact match on the longest input keyword ranks first (README: "Exact
  // full-name matches should rank above shorter phrase matches").
  const longestInput = normalized.reduce((a, b) => (b.length > a.length ? b : a), '');
  rows.sort((a, b) => {
    const aExact = a.normalized_keyword === longestInput ? 1 : 0;
    const bExact = b.normalized_keyword === longestInput ? 1 : 0;
    return bExact - aExact;
  });

  // De-dupe by reference_id (several keywords can point at the same one).
  const seen = new Set();
  const candidates = [];
  for (const row of rows) {
    if (seen.has(row.reference_id)) continue;
    seen.add(row.reference_id);
    candidates.push({
      referenceId: row.reference_id,
      productId: row.product_id,
      productName: row.product_name,
      categoryId: row.category_id,
      categoryName: row.category_name,
      // The frontend's ProductCategory enum name — null for the 2
      // categories intentionally absent from the 16-category set (see
      // enums.js), in which case the frontend leaves category unset.
      categoryDartName: CATEGORY_DART_NAMES[row.category_name] ?? null,
      matchedKeyword: row.keyword,
      sourceName: row.source_name,
      sourceUrl: row.source_url,
      requiresConfirmation: true,
    });
  }
  return candidates;
}

function normalizeText(text) {
  return text.trim().toLowerCase().replace(/\s+/g, ' ');
}

// ==================== 1. Manual text ====================
// POST /recognize/text  { text }
router.post('/recognize/text', asyncHandler(async (req, res) => {
  const { text } = req.body;
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    throw new ApiError(400, 'text is required.');
  }
  if (text.length > 500) {
    throw new ApiError(400, 'text must be 500 characters or fewer.');
  }
  const candidates = await resolveByKeywords([normalizeText(text)], 'TEXT');
  res.json({ candidates });
}));

// ==================== Shared: Open Food Facts lookup ====================
// Throws on a genuine network/server failure (distinct from "not found",
// which returns null) — callers that want to tolerate failures for one
// item among many (e.g. receipt parsing) should catch around this
// themselves rather than this function silently swallowing errors.
async function lookupOpenFoodFacts(barcode) {
  const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode)}.json?fields=product_name,product_name_en,categories_tags,brands`;
  let offResponse;
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    offResponse = await fetch(url, {
      headers: { 'User-Agent': OFF_USER_AGENT },
      signal: controller.signal,
    });
    clearTimeout(timeout);
  } catch (e) {
    throw new ApiError(502, 'Could not reach the product database.');
  }
  // Some Open Food Facts deployments return 404 for an unknown barcode
  // instead of 200+status:0 — treat both the same way (see chat history).
  if (offResponse.status === 404) return null;
  if (!offResponse.ok) throw new ApiError(502, `Product lookup failed (upstream returned ${offResponse.status}).`);

  const body = await offResponse.json();
  if (body.status !== 1 || !body.product) return null;
  const product = body.product;
  return {
    name: (product.product_name_en || product.product_name || '').trim() || null,
    brand: (product.brands || '').split(',')[0]?.trim() || null,
    categoriesTags: Array.isArray(product.categories_tags) ? product.categories_tags : [],
  };
}

// ==================== 2. Barcode -> Open Food Facts -> mapping ====================
// POST /recognize/barcode  { barcode }
router.post('/recognize/barcode', asyncHandler(async (req, res) => {
  const { barcode } = req.body;
  if (!barcode || typeof barcode !== 'string') {
    throw new ApiError(400, 'barcode is required.');
  }

  const product = await lookupOpenFoodFacts(barcode);
  if (!product) {
    return res.json({ product: null, candidates: [] });
  }

  const candidates = await resolveByKeywords(product.categoriesTags, 'OFF_TAG');
  res.json({ product, candidates });
}));

function decodeImageBody(req) {
  const { imageBase64 } = req.body;
  if (!imageBase64 || typeof imageBase64 !== 'string') {
    throw new ApiError(400, 'imageBase64 is required.');
  }
  const buffer = Buffer.from(imageBase64, 'base64');
  // Keep this in sync with whatever the Flutter client compresses to —
  // large uploads risk hitting the platform's request-body size limit.
  const maxBytes = 6 * 1024 * 1024;
  if (buffer.length === 0 || buffer.length > maxBytes) {
    throw new ApiError(400, 'Image must be a non-empty JPEG under 6MB.');
  }
  return buffer;
}

// ==================== 3. Photo -> Google Vision Label Detection -> mapping ====================
// POST /recognize/image  { imageBase64 }
//
// Route contract (request/response shape) is UNCHANGED from the earlier
// Oracle/SigLIP version — only what happens inside changed. The Flutter
// side (photo_scan_screen.dart) needed no changes because of this.
//
// Per the team's evaluation (TEST_REPORT.md): 62.3% overall category-match
// rate, strong for fresh whole items (Meat 100%, Seafood/Vegetables/
// Fruits/Baked Goods/Eggs 80%), weak for packaged/processed goods (Baby
// Food 20%, Dairy/Snacks/Frozen/Condiments 40%). This is exactly why
// candidates here are suggestions requiring confirmation, never
// auto-applied — same as every other recognition path in this file.
router.post('/recognize/image', asyncHandler(async (req, res) => {
  const buffer = decodeImageBody(req);
  const client = getVisionClient();
  if (!client) {
    throw new ApiError(500, 'Google Vision is not configured on this backend yet (missing GOOGLE_VISION_CREDENTIALS_B64).');
  }

  let result;
  try {
    [result] = await client.labelDetection({ image: { content: buffer }, maxResults: 20 });
  } catch (e) {
    throw new ApiError(502, `Google Vision request failed: ${e.message}`);
  }

  // Vision returns labels sorted by its own confidence, highest first.
  // Previously all labels were matched in one batch, which surfaced
  // near-duplicate results (e.g. "Banana", "Bananas", "Fruits" all at
  // once, from three different keyword rows). Now: walk labels in
  // confidence order and stop at the first one that resolves to
  // anything, returning only its single best match — one clean answer,
  // not a redundant list.
  const labels = (result.labelAnnotations || []).map((a) => ({ label: a.description, score: a.score }));
  let candidates = [];
  for (const l of labels) {
    candidates = await resolveByKeywords([l.label], 'TEXT');
    if (candidates.length > 0) break;
  }
  const best = candidates.length > 0 ? [candidates[0]] : [];
  res.json({ labels, candidates: best });
}));

// ==================== OCR is intentionally NOT a server route ====================
// Per the team's plan: OCR stays client-side (Tesseract.js in the browser,
// see BrowserOcrService in Flutter) — it does not use Google Vision's OCR
// and never did use the old Oracle path either way. Once text is
// extracted client-side, it's resolved via POST /recognize/text above
// (already generic — no dedicated /recognize/ocr route needed).

// ==================== 5. Receipt (Jaya Grocer format) -> items ====================
//
// Rewritten against a real failing sample (see chat — a 9-item receipt
// where only 3 items were being picked up). Root cause: the previous
// version demanded barcode + unit + qty + unitPrice + TOTAL all on one
// physical OCR line. Real Tesseract output on this receipt read the
// right-hand "total" column as a totally separate block, nowhere near
// its row — so that single-line match could barely ever fire at all.
//
// Fixed design:
//   1. A line is "this item exists" the moment it has a barcode + a unit
//      word on it — nothing else required. This alone is what makes an
//      item show up at all, which was the main failure.
//   2. totalPrice is never read from OCR — it's quantity * unitPrice,
//      computed in code. Removes the single biggest point of failure
//      (the separated right column) entirely.
//   3. quantity/unitPrice is a best-effort search in a small window
//      around the barcode line (bounded by the neighbouring barcode
//      lines either side, so a qty line can never get stolen across an
//      item boundary) — if genuinely not found, the item still gets
//      added with quantity defaulted to 1 rather than disappearing.
//      A wrong quantity is a quick manual fix in the review screen; a
//      vanished item might go unnoticed entirely.
//   4. Name extraction tolerates ONE skipped qty/discount line between
//      the name and the barcode (observed: the qty line sometimes lands
//      between them instead of after the barcode), and checks exactly
//      one more line further back for a wrapped second name line
//      (observed: "PRISTINE ROLLED OATS" / "750G *1" on two lines).
//
// Known remaining limitation: on a receipt where OCR's column order is
// badly scrambled, quantity/price can still occasionally get paired
// with the wrong neighbouring item — flattened text alone doesn't always
// disambiguate this. The robust fix would read Tesseract's word-position
// (bounding box) data and reconstruct rows by actual Y-coordinate rather
// than by line order — a browser_ocr_service.dart change, not this file.
const RECEIPT_BARCODE_LINE = /^(\d{12,14})\s+([A-Za-z]{1,6})\b/;
// Tolerant of a stray space after the decimal point (observed:
// "0. 472x25.60" from real OCR output).
const RECEIPT_QTY_PRICE = /(\d+(?:\.\s?\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)/;
const RECEIPT_UNIT_MAP = { KG: 'kg', G: 'g', UNIT: 'pcs', PKT: 'pack', PCS: 'pcs', L: 'L', ML: 'mL' };
const RECEIPT_BOILERPLATE = /^(invoice|item\s*\d|qty\s|saving|subtotal|spec\.?disc|rounding|total|change|approcode|thank you|we sell|if you are|member|grab)/i;
// A discount-code line ("03"), a bare price ("7.90"), a date/time stamp —
// none of these are ever a usable product name.
const RECEIPT_NUMERIC_ONLY = /^[\d.\-\s:/]+$/;

function isNameCandidate(line) {
  if (!line) return false;
  if (RECEIPT_BARCODE_LINE.test(line)) return false;
  if (RECEIPT_QTY_PRICE.test(line)) return false;
  if (RECEIPT_BOILERPLATE.test(line)) return false;
  if (RECEIPT_NUMERIC_ONLY.test(line)) return false;
  return true;
}

function parseJayaGrocerReceipt(rawText) {
  const lines = rawText.split('\n').map((l) => l.trim()).filter(Boolean);

  const barcodeIdx = [];
  for (let i = 0; i < lines.length; i++) {
    if (RECEIPT_BARCODE_LINE.test(lines[i])) barcodeIdx.push(i);
  }

  const parsed = [];
  const claimedQtyLines = new Set();

  for (let k = 0; k < barcodeIdx.length; k++) {
    const i = barcodeIdx[k];
    const [, barcode, unitToken] = lines[i].match(RECEIPT_BARCODE_LINE);

    // ---- Name ----
    // Nearest usable line above, allowing ONE skipped qty/discount line,
    // then one more line further back for a wrapped continuation.
    let name = null;
    let firstNameIdx = null;
    for (let j = i - 1, tries = 0; j >= 0 && tries < 3; j--, tries++) {
      if (RECEIPT_BARCODE_LINE.test(lines[j])) break; // previous item's territory
      if (isNameCandidate(lines[j])) {
        name = lines[j];
        firstNameIdx = j;
        break;
      }
    }
    if (name !== null && firstNameIdx > 0) {
      const prev = lines[firstNameIdx - 1];
      if (isNameCandidate(prev)) name = `${prev} ${name}`;
    }
    if (!name) continue; // genuinely nothing usable above — skip rather than guess

    name = name.replace(/\s*\*\d+\s*$/, '').trim();

    // ---- Quantity / unit price ----
    // Bounded by the neighbouring barcode lines so a qty line is never
    // pulled across an item boundary.
    const lowerBound = k > 0 ? barcodeIdx[k - 1] : -1;
    const upperBound = k < barcodeIdx.length - 1 ? barcodeIdx[k + 1] : lines.length;
    let quantity = 1;
    let unitPrice = null;
    outer: for (let dist = 0; dist <= 4; dist++) {
      for (const j of [i + dist, i - dist]) {
        if (j <= lowerBound || j >= upperBound) continue;
        if (claimedQtyLines.has(j)) continue;
        const qm = lines[j].match(RECEIPT_QTY_PRICE);
        if (qm) {
          quantity = parseFloat(qm[1].replace(/\s+/g, '')) || 1;
          unitPrice = parseFloat(qm[2]);
          claimedQtyLines.add(j);
          break outer;
        }
      }
    }

    parsed.push({
      rawName: name,
      barcode,
      unit: RECEIPT_UNIT_MAP[unitToken.toUpperCase()] ?? 'pcs',
      quantity,
      unitPrice,
      totalPrice: unitPrice !== null ? Math.round(quantity * unitPrice * 100) / 100 : null,
    });
  }
  return parsed;
}

// Strips a trailing size/weight suffix (e.g. "...130.2G", "...360G") to
// try a second, simpler match if the full product name doesn't hit —
// receipt names are often more specific than what's in the keyword table.
function simplifyProductName(name) {
  return name.replace(/\s*\d+(\.\d+)?\s*(G|KG|ML|L)\s*$/i, '').trim();
}

// POST /recognize/receipt  { text }
// Deliberately does NOT auto-decide "food vs not food" by silently
// dropping unmatched lines — every parsed line is returned, but ones
// with zero resolved candidates are flagged (matched: false) so the
// review screen can make that visible rather than losing an item the
// person actually paid for without them knowing.
router.post('/recognize/receipt', asyncHandler(async (req, res) => {
  const { text } = req.body;
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    throw new ApiError(400, 'text is required.');
  }
  if (text.length > 8000) {
    throw new ApiError(400, 'text is too long — is this really a single receipt?');
  }

  const rawItems = parseJayaGrocerReceipt(text);
  const items = [];
  for (const raw of rawItems) {
    let candidates = await resolveByKeywords([raw.rawName, simplifyProductName(raw.rawName)], 'TEXT');

    // Fall back to the barcode via Open Food Facts if the name-based
    // match came up empty — a second, independent channel to identify
    // the same line item. A failure here (network, OFF down) shouldn't
    // fail the whole receipt, so it's caught per-item.
    if (candidates.length === 0) {
      try {
        const offProduct = await lookupOpenFoodFacts(raw.barcode);
        if (offProduct) {
          candidates = await resolveByKeywords(offProduct.categoriesTags, 'OFF_TAG');
        }
      } catch (e) {
        // swallow — this item just stays unmatched, not a hard failure
      }
    }

    items.push({ ...raw, candidates, matched: candidates.length > 0 });
  }

  res.json({ items });
}));

module.exports = router;
