# PantryBuddy Iteration 2 — Recognition Deployment Backup Plans

## Purpose

Use this document if the primary SigLIP and Tesseract service cannot be deployed on Oracle Cloud or another host with sufficient memory. The plans are ordered by functional completeness and practical feasibility.

The course requirement is that the implemented service remains available for at least six months. A temporary free trial must not be the only production dependency.

## Shared workflow in every plan

The application should present one photo workflow, but it may combine three separate recognition methods:

1. visual recognition for unpackaged or fresh food;
2. OCR for visible English packaging text;
3. barcode decoding and packaged-product metadata lookup.

All returned names or labels are matched against PantryBuddy's database:

```text
recognition terms
  -> product_keyword_mapping.normalized_keyword
  -> product_reference.reference_id
  -> product_categories.category_id
  -> user confirmation
```

Barcode metadata comes from Open Food Facts. Manual name entry and selection from the fixed 16 PantryBuddy categories are mandatory fallbacks in every plan.

## Primary plan — existing validated handover

### Components

- visual recognition: locally hosted `google/siglip-base-patch16-224`;
- OCR: locally hosted Tesseract English;
- barcode decoding: ZXing Browser in the web client;
- barcode metadata: Open Food Facts API v2;
- final category: PantryBuddy SQL keyword mapping;
- final decision: user confirmation.

### Status

This is the plan already supplied in the original handover. Local feasibility testing was completed for model loading, one food photograph, deterministic OCR text, one live barcode lookup, authentication and upload-size rejection. See `LOCAL_VALIDATION.md`.

### Hosting requirement

The SigLIP weight file is approximately 813 MB and its Hugging Face repository is approximately 1.63 GB. Runtime memory is higher because Python, PyTorch, model weights and inference tensors must coexist. A host with about 4 GB RAM may run a low-concurrency CPU prototype; more memory is safer. The team must verify the actual selected host and keep it available for six months.

Use this plan when a suitable long-lived host is available.

## Backup plan 1 — split browser and server processing

### Change from the primary plan

Move OCR from the Python service into the user's browser with Tesseract.js. Keep ZXing in the browser. The server hosts only SigLIP.

```text
Browser: ZXing barcode + Tesseract.js OCR
Server: SigLIP visual recognition
Backend: Open Food Facts + SQL mapping + result fusion
```

### Why this is first backup

- preserves automatic visual recognition for fresh and unpackaged food;
- removes Tesseract system installation and OCR processing from the model server;
- images used only for OCR do not need to be uploaded to the server;
- does not introduce a paid OCR API.

### Limitations

- it does not remove SigLIP's memory requirement;
- OCR speed depends on the user's device;
- the web client must package and test Tesseract.js and its English language assets;
- weak devices and difficult packaging may produce poor OCR results.

### Required validation before release

- test Tesseract.js in each supported desktop/mobile browser;
- verify first-load asset size and loading time;
- verify five representative English packages under normal lighting;
- confirm that image data is not retained after processing;
- rerun the existing SigLIP endpoint tests on the selected six-month host.

### Minimum implementation steps

1. Keep the existing SigLIP `/image` endpoint and deployment steps from `README.md`.
2. Add the browser packages to the existing web client:

```bash
npm install tesseract.js @zxing/browser
```

3. Create one reusable English Tesseract.js worker in the photo-entry page. Send only the extracted text to the authenticated backend text-resolution route.
4. Use ZXing Browser to decode a barcode from the camera or selected image. Send only the barcode digits to the authenticated backend barcode-resolution route.
5. Keep Open Food Facts requests and SQL keyword matching in the backend. Do not place database credentials or private service keys in browser code.
6. Merge visual, OCR and barcode candidates, then require the user to confirm the final name and category before creating an inventory item.

Official references:

- https://github.com/naptha/tesseract.js/
- https://github.com/zxing-js/browser

## Backup plan 2 — external vision API candidate

### Change from the primary plan

Replace only SigLIP visual inference with a hosted computer-vision API. Keep barcode decoding, Open Food Facts, SQL mapping, user confirmation and manual fallback unchanged. OCR can remain in Tesseract.js; alternatively, the same provider's OCR endpoint can be evaluated separately.

Current candidate: Google Cloud Vision Label Detection. Optional evaluation features are Text Detection and Object Localization.

```text
Browser: ZXing + optional Tesseract.js
External API: visual labels for the uploaded image
Backend: Open Food Facts + SQL mapping + result fusion
```

### Important status

This candidate has not been validated for PantryBuddy food accuracy and is not a confirmed replacement for SigLIP. Google Cloud Vision is a general vision service, not a PantryBuddy-specific or food-specific classifier.

The current public pricing page lists the first 1,000 units per feature per month as free, followed by usage charges. Billing setup, quotas, privacy terms and future price changes remain external dependencies. Do not promise permanent free availability.

### Acceptance test required before selection

Prepare a minimum evaluation set of 80 representative photographs: five for each of the 16 fixed categories. Include fresh food, packaged food, Malaysian products, varied lighting and difficult backgrounds.

For every image record:

```text
expected product name
expected PantryBuddy category
returned API labels
mapped category candidates
top result correct: yes/no
manual fallback required: yes/no
```

The team must define an acceptable top-result and fallback rate before calling this plan implemented. API credentials and billing controls must be held on the backend, never in browser code.

### Minimum implementation steps

1. Create a Google Cloud project, enable Cloud Vision API and configure billing/quota alerts.
2. Create a server-side service account with only the permissions needed to call Vision. Store its credentials in the backend secret configuration; never commit credentials or expose them to the browser.
3. Add the official Cloud Vision client library supported by the backend language, or call the authenticated REST API from the backend.
4. Send a resized image to Label Detection. OCR may remain in browser-based Tesseract.js; if Text Detection is also enabled, count and monitor it as a separate API feature.
5. Normalize returned English labels and resolve them through `product_keyword_mapping`. Do not insert Google labels directly as PantryBuddy categories.
6. Require user confirmation and fall back to barcode, OCR or manual input when labels are generic or no mapping is found.
7. Complete the 80-image evaluation and record monthly usage before enabling this plan for users.

Official references:

- https://cloud.google.com/vision/docs/labels
- https://cloud.google.com/vision/docs/ocr
- https://cloud.google.com/vision/pricing

## Backup plan 3 — resilient reduced-function workflow

### Change from the primary plan

Do not use an automatic visual model when no suitable host or evaluated API is available.

```text
Packaged food:
  barcode -> Open Food Facts -> SQL mapping
  or browser OCR -> SQL mapping
  or manual entry

Fresh/unpackaged food:
  manual English product name or category selection -> SQL mapping
```

### Why this is the final backup

- requires no model server and no paid vision API;
- barcode and OCR can run in the browser;
- database mapping and inventory entry remain operational;
- provides the strongest six-month continuity under a zero-budget constraint.

### Limitation

Automatic visual object recognition for both fresh and packaged food is unavailable. Packaged food may still be identified through barcode metadata or visible packaging text. The report and demonstration must describe SigLIP as a locally validated prototype deferred by hosting constraints, not as a deployed production feature.

### Minimum implementation steps

1. Add `tesseract.js` and `@zxing/browser` to the web client.
2. Keep the existing backend Open Food Facts lookup, SQL keyword-resolution route and inventory-save route.
3. Add a manual English product-name field and a fixed 16-category selector whenever barcode/OCR matching returns no confirmed result.
4. Cache permitted barcode metadata in the database to reduce external calls, while retaining source and retrieval date.
5. Test that a user can always complete inventory entry when the recognition service and Open Food Facts are unavailable.

## Priority and activation rule

| Priority | Plan | Activate when |
|---:|---|---|
| 1 | Primary | A six-month host with sufficient memory is available. |
| 2 | Backup 1 | SigLIP can be hosted, but the combined SigLIP/OCR service is too heavy or difficult to maintain. |
| 3 | Backup 2 | No suitable SigLIP host is available and the external API passes the PantryBuddy image evaluation, privacy and budget checks. |
| 4 | Backup 3 | Neither a model host nor an evaluated sustainable API is available. |

## What is already validated and what is not

| Item | Status |
|---|---|
| Primary SigLIP model load and single-photo inference | Locally validated |
| Primary Tesseract OCR | Locally validated |
| Open Food Facts live barcode lookup | Locally validated |
| SQL mapping datasets | Data-validated; final application integration remains with database/backend teams |
| Tesseract.js browser implementation | Proposed; backend/frontend integration test required |
| Google Cloud Vision food accuracy | Not validated; 80-image evaluation required |
| Six-month Oracle or alternative hosting | Not validated; infrastructure decision required |

## Handover rule

The backup designs can be handed over without pretending that they have all been deployed. Only the primary feasibility prototype is supported by the existing local test evidence. The backend team must validate the chosen backup in its real web application, credentials, browser matrix and hosting environment before release.
