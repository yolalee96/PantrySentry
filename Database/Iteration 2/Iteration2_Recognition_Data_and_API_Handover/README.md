# PantryBuddy Iteration 2 — Backend Recognition Specification

This document describes the dependencies and integration requirements for the Iteration 2 recognition feature. The backend team remains responsible for implementing the service in the existing PantryBuddy architecture.

## Files in this handover

- `README.md` — integration choices, dependencies and required behaviour.
- `LOCAL_VALIDATION.md` — what was deployed and tested locally before handover.
- `BACKUP_PLANS.md` — prioritised alternatives when the primary SigLIP service cannot be hosted for six months.
- `reference_recognition_service.py` — tested reference implementation that exposes SigLIP and Tesseract through private HTTP endpoints; adapt it rather than treating it as completed PantryBuddy backend code.
- `requirements-service.txt` — dependencies used by the reference recognition service.
- `verify_recognition_stack.py` — optional standalone checks that the backend developer can rerun; this is not application backend code.
- `requirements-test.txt` — dependencies used by the standalone test script.
- `visual_labels.csv` — English candidate labels for zero-shot image recognition.

## Required recognition routes

The backend should support four input paths:

1. Manual text: normalize the English item name and query the keyword-mapping table.
2. Photo: use an image model to suggest an item name/category, then query the mapping table.
3. OCR: extract English packaging text, then query the mapping table.
4. Barcode: decode the barcode in the web client, request product metadata from Open Food Facts, then map its category tags through the mapping table.

Every result must be shown to the user for confirmation. Recognition does not guarantee an expiry date.

## Image recognition — local model

- Model: `google/siglip-base-patch16-224`
- Task: zero-shot image classification
- Model page: https://huggingface.co/google/siglip-base-patch16-224
- Transformers documentation: https://huggingface.co/docs/transformers/tasks/zero_shot_image_classification
- Suggested runtime: Python 3.11, PyTorch, Transformers, Pillow and FastAPI/Flask if the Node backend calls a separate Python service.
- No model training is required for the prototype.
- The model compares one user-cropped food image with candidate English labels. It is not a multi-object detector and its scores are similarity scores, not food-safety confidence.

Use `visual_labels.csv` as the candidate-label input. The database mapping remains the authority for the final PantryBuddy category.

### Optional reference service

The supplied `reference_recognition_service.py` shows the tested API wrapper for the local model and OCR engine. It provides `/health`, `/warmup`, `/image`, `/ocr` and `/photo`. The backend team may reuse or rewrite it to suit its deployment architecture.

### Direct-Python deployment

1. Install Python 3.11 and create a virtual environment:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
```

On macOS/Linux use `python3.11 -m venv .venv` followed by `source .venv/bin/activate`.

2. Install the tested CPU build of PyTorch and the supplied service dependencies:

```bash
pip install torch==2.7.0 --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-service.txt
```

The current PyTorch installation selector and hardware-specific commands are available at https://pytorch.org/get-started/locally/. A GPU is not required for the tested prototype.

3. Install Tesseract with English language data. Official installation guidance is at https://tesseract-ocr.github.io/tessdoc/Installation.html and downloads guidance is at https://tesseract-ocr.github.io/tessdoc/Downloads.html.

Ubuntu/Debian example:

```bash
sudo apt update
sudo apt install tesseract-ocr tesseract-ocr-eng
```

For Windows, use the Windows installer linked by the official Tesseract documentation and add its installation directory to `PATH`. Verify the installation on any platform with:

```bash
tesseract --version
```

4. Set a private service key and start the reference service.

Windows PowerShell:

```powershell
$env:RECOGNITION_SERVICE_KEY = "replace-with-a-private-random-value"
uvicorn reference_recognition_service:app --host 127.0.0.1 --port 8001
```

macOS/Linux:

```bash
export RECOGNITION_SERVICE_KEY='replace-with-a-private-random-value'
uvicorn reference_recognition_service:app --host 127.0.0.1 --port 8001
```

The first `/warmup` or image request automatically downloads the pinned model from https://huggingface.co/google/siglip-base-patch16-224. Later requests reuse the local Hugging Face cache. The Node backend should send the private value in the `X-Service-Key` header. Do not expose this internal service directly to the browser.

5. Verify the running service:

```powershell
curl.exe http://127.0.0.1:8001/health
curl.exe -X POST http://127.0.0.1:8001/warmup -H "X-Service-Key: replace-with-a-private-random-value"
curl.exe -X POST http://127.0.0.1:8001/image -H "X-Service-Key: replace-with-a-private-random-value" -H "Content-Type: image/jpeg" --data-binary "@food.jpg"
curl.exe -X POST http://127.0.0.1:8001/ocr -H "X-Service-Key: replace-with-a-private-random-value" -H "Content-Type: image/jpeg" --data-binary "@package.jpg"
```

Use ordinary `curl` instead of `curl.exe` on macOS/Linux.

## OCR — local library

- Recommended library: Tesseract OCR with English language data
- Project page: https://github.com/tesseract-ocr/tesseract
- Python wrapper: https://github.com/madmaze/pytesseract
- Purpose: extract product names and printed date text from packaging.
- OCR reads text only. The backend must not treat an OCR date as verified without user confirmation.

PaddleOCR is an acceptable alternative if it is already supported by the deployment environment: https://www.paddleocr.ai/

## Barcode recognition and product lookup

- Web barcode scanner: ZXing browser library — https://github.com/zxing-js/browser
- Alternative client scanner: BarcodeDetector API where supported — https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector
- Product metadata provider: Open Food Facts API v2 — https://openfoodfacts.github.io/openfoodfacts-server/api/
- Example lookup: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
- No API key is required for public product lookup.

The browser scanner only returns barcode digits. The server should call Open Food Facts, read the product name and exact `categories_tags`, and match those tags against `product_keyword_mapping`. Send a descriptive `User-Agent`, apply a timeout and caching, and keep manual input available when the product is missing or the provider is unavailable. Keep uncached product lookups below the published provider limit; the proposed application-side ceiling is 12 per minute per backend instance. Official Open Food Facts guidance currently documents 15 product-read requests per minute per IP and requires an identifiable custom User-Agent.

Example provider check:

```bash
curl -H "User-Agent: PantryBuddy/Iteration2 (team-contact)" "https://world.openfoodfacts.org/api/v2/product/3017620422003.json?fields=code,product_name,brands,categories_tags"
```

The Open Food Facts request does not require an API key for read-only product lookup. The backend team must replace `team-contact` with an appropriate project contact and must not call the provider directly from secret-bearing server code in the browser.

## Database lookup

Normalize input by lower-casing, trimming whitespace and normalising punctuation. Query `product_keyword_mapping.normalized_keyword`, then join:

`product_keyword_mapping.reference_id -> product_reference.reference_id -> product_categories.category_id`

Return one or more candidates containing:

- reference ID
- nullable product ID
- canonical product name
- category ID and category name
- matched keyword
- source name and source URL
- a `requiresConfirmation` flag

Exact full-name matches should rank above shorter phrase matches. Do not map ingredient-list words independently, because this can misclassify packaged products. Do not assign a product-level shelf-life rule when `product_id` is NULL.

## Suggested API behaviour

| Function | Suggested input | Expected result |
|---|---|---|
| Resolve text | English text, 1–500 characters | Ranked mapping candidates |
| Resolve barcode | Barcode digits | Open Food Facts metadata plus mapping candidates |
| Resolve image | JPEG/PNG/WebP, one cropped item | Image labels plus mapping candidates |
| Resolve OCR | Packaging image | OCR text plus mapping candidates |

Use the existing authentication and household-authorisation middleware. Limit image size and decoded pixel count. Do not store uploaded images by default. Keep manual name/category entry available for model, OCR and external-API failures.

## Minimum dependencies

Choose versions compatible with the team's environment and lock them in the backend repository:

- Python 3.11
- `torch`
- `transformers`
- `sentencepiece`
- `Pillow`
- `pytesseract` plus the Tesseract system package
- `FastAPI` and `uvicorn`, only if recognition runs as a separate Python HTTP service
- Node's existing HTTP client or `fetch` for Open Food Facts
- `@zxing/browser` in the web client if BarcodeDetector is not used

Docker is optional. It is useful for packaging Python, Tesseract and model dependencies consistently, but the same service can run in a Python virtual environment. Production hosting must expose the recognition service to the deployed Node backend; a cloud backend cannot call a model running only on a developer's `localhost`.

The reference service does not include the Open Food Facts barcode route because that lookup belongs in the existing Node backend. Its request is a normal server-side HTTP GET to `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`; the returned exact category tags are resolved through the database mapping table.

## Reproducing the feasibility checks

Create a Python 3.11 virtual environment, install Tesseract English on the operating system, and then run:

```bash
pip install torch==2.7.0 --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-test.txt
python verify_recognition_stack.py --image path/to/one-food-photo.jpg
python verify_recognition_stack.py --ocr-image path/to/package-photo.jpg
python verify_recognition_stack.py --barcode 3017620422003
```

The first image-model run downloads the pinned Hugging Face model and can be slow. The model is cached locally afterwards. These commands only verify the selected components; the backend developer must implement the authenticated application routes, database queries, error handling and deployment configuration.

## Acceptance checks

- Manual text maps known English terms to the correct existing category.
- A single-item photo returns suggestions and requires confirmation.
- OCR extracts visible English text and requires confirmation for names/dates.
- A known barcode returns Open Food Facts metadata and mapped candidates.
- Unknown input always offers manual entry.
- Generic category mappings never inherit an unrelated specific `product_id`.
- Recognition never presents shelf life as a safety guarantee.
