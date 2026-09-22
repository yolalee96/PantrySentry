# PantryBuddy Google Cloud Vision Handover

## Decision and scope

The self-hosted SigLIP plan could not be deployed on the available host, so the current implementation candidate is Backup Plan 2.

Google Cloud Vision is used for **Label Detection only**, primarily to suggest names/categories for fresh or unpackaged food. It does not replace the other recognition paths:

```text
one user photo
  -> barcode in browser (ZXing) -> Open Food Facts / internal barcode data
  -> OCR in browser/server (Tesseract.js or Tesseract) -> product_keyword_mapping
  -> Google Vision Label Detection -> product_keyword_mapping / 16-category evidence
  -> backend combines candidates -> user confirms -> inventory item is saved
```

Do not enable Google Text Detection for the current plan. OCR does not consume Google Vision units because it runs through Tesseract/Tesseract.js.

## Files to deploy or review

- `google_vision_recognition_service.py`: backend-only FastAPI reference wrapper.
- `requirements-google-vision.txt`: pinned Python dependencies.
- `cloud_vision_evaluation/TEST_REPORT.md`: test conclusion and measured usage.
- `cloud_vision_evaluation/cloud_vision_test_results_revised.csv`: authoritative returned labels and adjusted mapping results.
- `cloud_vision_evaluation/cloud_vision_test_summary.json`: machine-readable summary.
- `cloud_vision_evaluation/evaluate_cloud_vision.py`: reproducible evaluation logic.
- `product_keyword_mapping.csv` is supplied separately in the Iteration 2 classification/database handover and remains the database authority.

## Backend behaviour

1. Keep Google credentials on the server only.
2. Validate authentication, MIME type and file size before calling Vision.
3. Call only `LABEL_DETECTION`, with a result limit such as 20.
4. Normalise returned English labels and resolve them through `product_keyword_mapping` and the fixed `product_categories.category_id` values.
5. Combine this result with barcode and OCR evidence. Recommended precedence is exact barcode match, strong OCR database match, then visual-label suggestion.
6. Always return `CONFIRM` to the client. Do not automatically persist a Vision-only result.
7. If Vision is unavailable, timed out, quota-limited or unmapped, allow manual name/category entry.
8. Do not store the uploaded image unless the consent and retention requirements explicitly allow it.

## Local deployment test

Use Python 3.11 or a backend-supported current Python version:

```bash
python -m venv .venv
pip install -r requirements-google-vision.txt
```

Authentication options:

- Local developer testing: `gcloud auth application-default login`, followed by `gcloud auth application-default set-quota-project PROJECT_ID`.
- VM/Oracle deployment: create a least-privilege service account for the project, grant only the required Vision permission, store its JSON credential outside Git/GitHub, and set `GOOGLE_APPLICATION_CREDENTIALS` to its absolute server path.
- Google Cloud runtime: prefer the runtime service account / Application Default Credentials instead of downloading a JSON key.

Set an internal service key and start the reference wrapper:

```bash
export RECOGNITION_SERVICE_KEY='a-long-private-random-value'
uvicorn google_vision_recognition_service:app --host 127.0.0.1 --port 8001
```

Windows PowerShell uses `$env:RECOGNITION_SERVICE_KEY = "..."` before the same `uvicorn` command.

Test from the backend host:

```bash
curl http://127.0.0.1:8001/health
curl -X POST http://127.0.0.1:8001/image-labels -H "X-Service-Key: PRIVATE_VALUE" -F "image=@food.jpg"
```

If the existing backend is Node.js, Hank may either call this private Python endpoint or implement the same single Vision request using Google's Node client. Do not make Vision requests directly from the browser because credentials would be exposed.

## Production credentials and ownership

The current project `pantrybuddy-vision-test` and borrowed payment card are suitable only for evaluation. Before production:

1. agree on a team-owned Google Cloud project and responsible billing owner;
2. attach a team-approved payment method;
3. enable `vision.googleapis.com`;
4. create the production server identity/service account;
5. set restrictive IAM, API quotas and budget alerts;
6. keep every credential file and secret out of GitHub;
7. test the manual fallback before release.

## Trial, monthly allowance and six-month availability

- The displayed 90 days refers to the new-customer USD 300 trial credit.
- If the account is not upgraded, the trial billing account closes when the trial expires and the service stops.
- To continue beyond 90 days, a Billing Account Administrator must select `Activate` and upgrade to a paid pay-as-you-go billing account.
- Upgrading does not itself create a subscription fee. Under the pricing listed at the time of this handover, the first 1,000 Label Detection units each month are free; usage above that allowance is chargeable.
- A billing method remains required, and other Google Cloud resources or future pricing changes can create charges.
- A budget is an alert unless Google explicitly offers spend-cap enforcement for the selected service; it is not automatically a hard cap.

For predictable operation, configure an API quota below the agreed monthly ceiling, monitor usage, and fall back to barcode/OCR/manual entry when quota is unavailable.

Official references:

- Free trial and upgrade rules: https://docs.cloud.google.com/free/docs/free-cloud-features
- Cloud Vision pricing: https://cloud.google.com/vision/pricing
- Vision authentication: https://cloud.google.com/vision/docs/authentication
- Vision Label Detection: https://cloud.google.com/vision/docs/labels

## Validation result and known limitation

The evaluation made 61 successful main Label Detection calls, one connectivity call and five fresh-seafood replacement calls. Total measured usage was 67 Label Detection units. Reclassification from saved responses used zero additional units.

After removing an invalid generic `food` mapping token and replacing the invalid seafood sample, simple label-to-category mapping produced an adjusted 38 correct results from 61 images (62.30%). Fresh-food results included Meat 100%, Vegetables 80%, Fruits 80%, Seafood 80%, and Eggs 80% in this small test. The revised seafood set contained visually reviewed whole uncooked fish, peeled raw shrimp, whole crab, whole mussels and whole fresh squid; four mapped to Seafood, while the peeled shrimp remained unmapped. This is evidence of technical feasibility, not production accuracy. Three categories lacked test coverage and some categories have only five examples.

Accordingly, this API is approved only as a **candidate/suggestion source with user confirmation**, not as an automatic category authority.
