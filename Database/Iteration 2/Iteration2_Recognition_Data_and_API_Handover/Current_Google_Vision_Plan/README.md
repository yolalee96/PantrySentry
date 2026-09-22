# Current Recognition Plan — Google Cloud Vision

This is the current PantryBuddy recognition plan after the self-hosted SigLIP deployment was found infeasible on the available Oracle host.

## Backend developer: read in this order

1. `README.md` — this architecture and responsibility summary.
2. `DEPLOY_GOOGLE_VISION.md` — Google account, billing, credentials and Oracle deployment steps.
3. `google_vision_recognition_service.py` and `requirements-google-vision.txt` — reference implementation for Label Detection.
4. `TEST_RESULTS/TEST_REPORT.md` — validated results and API usage.

## Complete recognition workflow

The user takes or uploads one photograph. Three methods may process that same input:

```text
Barcode (ZXing in client)
  -> backend Open Food Facts / internal database lookup

OCR (Tesseract.js in client or Tesseract on server)
  -> extracted package text
  -> backend product_keyword_mapping lookup

Image recognition (Google Cloud Vision Label Detection)
  -> English visual labels
  -> backend product/category mapping

Backend combines evidence
  -> user confirms or corrects product and category
  -> confirmed inventory item is saved
```

## Important division of responsibility

- The supplied Python service implements only the Google Vision Label Detection request.
- OCR is not Google OCR and does not consume Google Vision units. The application should use Tesseract/Tesseract.js.
- Barcode decoding should use ZXing in the client. The backend performs the product lookup.
- Hank must integrate these paths into the existing backend and database schema; the supplied file is a reference microservice, not a replacement for the PantryBuddy backend.
- Google credentials remain server-side. Never call Google Vision directly from the browser.
- All uncertain results require user confirmation, and manual entry remains available.

## Current evidence

- Google Vision connectivity and all attempted API requests succeeded technically.
- Visually reviewed fresh seafood retest: 4/5 mapped to Seafood (whole fish, crab, mussels and squid succeeded; peeled raw shrimp was unmapped).
- Adjusted small-sample overall mapping: 38/61 (62.30%).
- Current measured test usage: 67 Label Detection units.
- Results support using Vision as a suggestion source, not as an automatic category authority.
- OCR and barcode are particularly important for packaged products.

## Account and service duration

The present test account has a 90-day new-customer trial. Production must use a team-approved Google Cloud project, Billing owner, payment method and server service account. To run beyond 90 days, the Billing account must be upgraded to paid pay-as-you-go before the trial expires. Under the pricing listed during testing, the first 1,000 Label Detection units per month are free; overage, other services or later pricing changes can be charged.

See `DEPLOY_GOOGLE_VISION.md` for the exact deployment steps and safeguards.

