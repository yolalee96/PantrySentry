# Deploy Google Cloud Vision for PantryBuddy

This is the short deployment guide for the backend developer. Test evidence is stored separately in `cloud_vision_evaluation/TEST_REPORT.md`.

## What is being deployed

- Google Cloud Vision: `LABEL_DETECTION` only, for visual food suggestions.
- OCR: keep Tesseract/Tesseract.js; do not enable Google OCR.
- Barcode: keep ZXing + Open Food Facts/database lookup.
- The backend must combine these results and ask the user to confirm.

## Account required

Use a team-approved Google account and Google Cloud project that can remain active for at least six months. The owner needs:

- Project Owner or equivalent project administration access;
- Billing Account Administrator access, or help from the team's billing owner;
- a team-approved payment method attached to the Billing account.

Do not use Elva's local ADC login or the borrowed-card test account as the production identity.

The new-customer trial lasts 90 days. Before it expires, the Billing Account Administrator must upgrade the Billing account to paid pay-as-you-go by selecting `Activate`; otherwise the project service stops. Activation has no subscription fee by itself. At the time of this handover, the first 1,000 Label Detection units per month are free, but usage above the allowance, other Google services, or future pricing changes can create charges.

## Google Cloud setup

In the production Google Cloud project:

1. Attach the team Billing account.
2. Enable **Cloud Vision API** (`vision.googleapis.com`).
3. Create a service account for the PantryBuddy backend, for example `pantrybuddy-vision-backend`.
4. Allow that service account to consume the enabled API in this project using least privilege. Do not grant Owner to the service account.
5. Set a monthly budget alert and a conservative API quota.

If the backend runs on Oracle Cloud or another non-Google server, create one JSON key for that service account. Download it once, place it in a private server directory, and never upload it to GitHub or send it through the group chat. Set this server environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/private/path/pantrybuddy-vision.json
```

If the backend runs on Google Cloud, attach the service account to the runtime and use Application Default Credentials; do not create a JSON key.

## Deploy the supplied Python wrapper

Copy these files to the private backend/service directory:

- `google_vision_recognition_service.py`
- `requirements-google-vision.txt`

Install and start:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-google-vision.txt
export GOOGLE_APPLICATION_CREDENTIALS=/private/path/pantrybuddy-vision.json
export RECOGNITION_SERVICE_KEY='replace-with-a-long-random-private-value'
uvicorn google_vision_recognition_service:app --host 127.0.0.1 --port 8001
```

The Node backend calls this private endpoint; the browser must not call it directly:

```bash
curl -X POST http://127.0.0.1:8001/image-labels \
  -H "X-Service-Key: PRIVATE_VALUE" \
  -F "image=@food.jpg"
```

For production, run Uvicorn under the existing process manager/container and keep it private behind the Node backend. Configure request authentication, timeout, file-size checks and HTTPS at the public backend boundary.

## Required application flow

```text
photo
  -> browser barcode + OCR
  -> backend database/Open Food Facts lookup
  -> Google Label Detection for visual evidence
  -> combine candidates
  -> user confirmation
  -> save confirmed inventory item
```

If Google Vision fails or reaches quota, barcode, OCR and manual input must remain available.

Official references:

- https://cloud.google.com/vision/docs/authentication
- https://cloud.google.com/vision/docs/labels
- https://cloud.google.com/vision/pricing
- https://docs.cloud.google.com/free/docs/free-cloud-features

